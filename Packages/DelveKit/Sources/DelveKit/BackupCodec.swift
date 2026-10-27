import Foundation

public struct BackupSettings: Codable, Equatable, Sendable {
    public var confirmNewRun: Bool
    public init(confirmNewRun: Bool = true) { self.confirmNewRun = confirmNewRun }
}

public struct BackupRun: Codable, Equatable, Sendable {
    public var id: String
    public var ledger: RunLedger
    public var notes: [String: String]
    public var markedGoals: [String]
    public init(id: String, ledger: RunLedger, notes: [String: String] = [:], markedGoals: [String] = []) {
        self.id = id; self.ledger = ledger; self.notes = notes; self.markedGoals = markedGoals
    }
}

/// v1 contains runs and activeRunID. v2 adds settings (v1 migrates to defaults).
/// World snapshots are deliberately absent: the ledger is authoritative.
public struct BackupArchive: Codable, Equatable, Sendable {
    public let version: Int
    public var runs: [BackupRun]
    public var activeRunID: String?
    public var settings: BackupSettings
    public init(runs: [BackupRun], activeRunID: String?, settings: BackupSettings = .init()) {
        version = BackupCodec.currentVersion
        self.runs = runs; self.activeRunID = activeRunID; self.settings = settings
    }
}

public enum BackupError: Error, Equatable {
    case unsupportedVersion(Int), invalid(String), tooLarge, confirmationRequired, stalePreview
}

extension BackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Backup version \(version) is unsupported. Use a compatible Delve version."
        case .invalid(let reason): "Invalid backup: \(reason)."
        case .tooLarge: "Backup exceeds the 32 MiB limit."
        case .confirmationRequired: "Confirm the preview before restoring."
        case .stalePreview: "Local data changed after the preview. Preview the backup again."
        }
    }
}

public enum BackupCodec {
    public static let currentVersion = 2
    public static let maximumBytes = 32 * 1024 * 1024

    public static func decode(_ data: Data, versions: [RuleTables]) throws -> BackupArchive {
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        struct Version: Decodable { let version: Int }
        let version = try JSONDecoder().decode(Version.self, from: data).version
        let archive: BackupArchive
        switch version {
        case 1:
            struct V1: Decodable { let runs: [BackupRun]; let activeRunID: String? }
            let old = try JSONDecoder().decode(V1.self, from: data)
            archive = BackupArchive(runs: old.runs, activeRunID: old.activeRunID)
        case currentVersion: archive = try JSONDecoder().decode(BackupArchive.self, from: data)
        default: throw BackupError.unsupportedVersion(version)
        }
        try validate(archive, versions: versions)
        var normalized = archive
        normalized.runs.sort { $0.id < $1.id }
        for index in normalized.runs.indices { normalized.runs[index].markedGoals.sort() }
        return normalized
    }

    public static func encode(_ archive: BackupArchive, versions: [RuleTables]) throws -> Data {
        try validate(archive, versions: versions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        var ordered = archive
        ordered.runs.sort { $0.id < $1.id }
        for index in ordered.runs.indices { ordered.runs[index].markedGoals.sort() }
        let data = try encoder.encode(ordered)
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    public static func tables(for ledger: RunLedger, versions: [RuleTables]) throws -> RuleTables {
        guard let tables = versions.first(where: {
            $0.contentVersion == ledger.contentVersion && $0.fingerprint == ledger.tablesFingerprint
        }) else { throw BackupError.invalid("Unsupported dungeon content or fingerprint") }
        return tables
    }

    public static func validate(_ archive: BackupArchive, versions: [RuleTables]) throws {
        guard archive.version == currentVersion else { throw BackupError.unsupportedVersion(archive.version) }
        guard archive.runs.count <= 10000,
              Set(archive.runs.map(\.id)).count == archive.runs.count else { throw BackupError.invalid("Duplicate or excessive runs") }
        for run in archive.runs {
            guard !run.id.isEmpty, run.id.count <= 200, !run.id.contains("\0"), !run.ledger.entries.isEmpty else {
                throw BackupError.invalid("Invalid run identity or empty ledger")
            }
            let tables = try tables(for: run.ledger, versions: versions)
            let world = try run.ledger.world(tables: tables)
            for (room, text) in run.notes {
                guard world.visitedRooms.contains(room), text.count <= 10000, !text.contains("\0") else {
                    throw BackupError.invalid("Invalid room note")
                }
            }
            guard Set(run.markedGoals).count == run.markedGoals.count else { throw BackupError.invalid("Duplicate quest marks") }
            if !run.markedGoals.isEmpty {
                let quest = try QuestEngine.bundledFor(tables: tables)
                guard Set(run.markedGoals).isSubset(of: Set(quest.goals.map(\.id))) else { throw BackupError.invalid("Unknown quest mark") }
            }
            if run.id == archive.activeRunID, world.isTerminal { throw BackupError.invalid("Active run is terminal") }
        }
        if let active = archive.activeRunID, !archive.runs.contains(where: { $0.id == active }) {
            throw BackupError.invalid("Missing active run")
        }
    }
}

public enum JournalCSV {
    // RFC 4180 quoting, CRLF rows, plus spreadsheet formula neutralization.
    private static func field(_ value: String) -> String {
        let first = value.drop(while: { $0.isWhitespace }).first
        let safe = first.map { "=+-@".contains($0) } == true || value.first == "\t" || value.first == "\r" ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    public static func export(_ archive: BackupArchive, versions: [RuleTables]) throws -> Data {
        try BackupCodec.validate(archive, versions: versions)
        var rows = [["run_id", "content_version", "kind", "id", "text", "marked_by_player", "dungeon_progress"]]
        for run in archive.runs.sorted(by: { $0.id < $1.id }) {
            let tables = try BackupCodec.tables(for: run.ledger, versions: versions)
            for room in run.notes.keys.sorted() {
                rows.append([run.id, String(tables.contentVersion), "note", room, run.notes[room]!, "", ""])
            }
            // v1 had no quest definitions. Preserve that absence, never invent progress.
            if tables.contentVersion >= 2 {
                let quest = try QuestEngine.bundledFor(tables: tables)
                for goal in quest.goals {
                    rows.append([run.id, String(tables.contentVersion), "quest", goal.id, goal.text,
                                 String(run.markedGoals.contains(goal.id)),
                                 try quest.progress(for: goal.id, ledger: run.ledger, tables: tables).rawValue])
                }
            }
        }
        return Data((rows.map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n").utf8)
    }
}
