import Foundation
import GRDB
import DelveKit

public struct RestoreDiff: Equatable, Sendable {
    public let added: [String]
    public let removed: [String]
    public let changed: [String]
    public let unchanged: [String]
    public let notesBefore: Int
    public let notesAfter: Int
    public let marksBefore: Int
    public let marksAfter: Int
    public let eventsBefore: Int
    public let eventsAfter: Int
    public let activeBefore: String?
    public let activeAfter: String?
    public let settingsChanged: Bool
    public let settingsBefore: BackupSettings
    public let settingsAfter: BackupSettings
}

/// Only the store can mint a preview. Its immutable baseline prevents restoring
/// over edits made while the confirmation UI was open.
public struct RestorePreview: Sendable {
    public let diff: RestoreDiff
    fileprivate let baseline: BackupArchive
    fileprivate let replacement: BackupArchive
}

extension DelveStore {
    public func backup(versions: [RuleTables]) throws -> BackupArchive {
        try db.read { try backup(versions: versions, db: $0) }
    }

    private func backup(versions: [RuleTables], db: Database) throws -> BackupArchive {
        guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM runs WHERE id NOT IN (SELECT run_id FROM run_metadata)") == 0 else {
            throw BackupError.invalid("Legacy runs without pinned ledger identity cannot be safely backed up or replaced")
        }
        let ids = try String.fetchAll(db, sql: "SELECT run_id FROM run_metadata ORDER BY run_id")
        let runs = try ids.map { id in
            let header = try Data.fetchOne(db, sql: "SELECT ledger_header FROM run_metadata WHERE run_id=?", arguments: [id])!
            let identity = try JSONDecoder().decode(RunLedger.self, from: header)
            let tables = try BackupCodec.tables(for: identity, versions: versions)
            let run = try readRun(id, tables: tables, db: db)
            let notes = try Row.fetchAll(db, sql: "SELECT room_id,text FROM room_notes WHERE run_id=?", arguments: [id])
            return BackupRun(id: id, ledger: run.ledger,
                             notes: Dictionary(uniqueKeysWithValues: notes.map { ($0["room_id"] as String, $0["text"] as String) }),
                             markedGoals: try String.fetchAll(db, sql: "SELECT goal_id FROM quest_marks WHERE run_id=? ORDER BY goal_id", arguments: [id]))
        }
        let settings = try Data.fetchOne(db, sql: "SELECT json FROM backup_settings WHERE slot=1")
        let archive = BackupArchive(runs: runs,
                                    activeRunID: try String.fetchOne(db, sql: "SELECT run_id FROM active_run WHERE slot=1"),
                                    settings: try settings.map { try JSONDecoder().decode(BackupSettings.self, from: $0) } ?? .init())
        try BackupCodec.validate(archive, versions: versions)
        return archive
    }

    public func setSettings(_ settings: BackupSettings) throws {
        let data = try JSONEncoder().encode(settings)
        try db.write { try $0.execute(sql: "INSERT INTO backup_settings VALUES (1,?) ON CONFLICT(slot) DO UPDATE SET json=excluded.json", arguments: [data]) }
    }

    public func previewRestore(_ data: Data, versions: [RuleTables]) throws -> RestorePreview {
        let replacement = try BackupCodec.decode(data, versions: versions)
        let baseline = try backup(versions: versions)
        let before = Dictionary(uniqueKeysWithValues: baseline.runs.map { ($0.id, $0) })
        let after = Dictionary(uniqueKeysWithValues: replacement.runs.map { ($0.id, $0) })
        let shared = Set(before.keys).intersection(after.keys)
        return RestorePreview(diff: RestoreDiff(
            added: Set(after.keys).subtracting(before.keys).sorted(), removed: Set(before.keys).subtracting(after.keys).sorted(),
            changed: shared.filter { before[$0] != after[$0] }.sorted(), unchanged: shared.filter { before[$0] == after[$0] }.sorted(),
            notesBefore: baseline.runs.reduce(0) { $0 + $1.notes.count }, notesAfter: replacement.runs.reduce(0) { $0 + $1.notes.count },
            marksBefore: baseline.runs.reduce(0) { $0 + $1.markedGoals.count }, marksAfter: replacement.runs.reduce(0) { $0 + $1.markedGoals.count },
            eventsBefore: baseline.runs.reduce(0) { $0 + $1.ledger.entries.count }, eventsAfter: replacement.runs.reduce(0) { $0 + $1.ledger.entries.count },
            activeBefore: baseline.activeRunID, activeAfter: replacement.activeRunID,
            settingsChanged: baseline.settings != replacement.settings,
            settingsBefore: baseline.settings, settingsAfter: replacement.settings), baseline: baseline, replacement: replacement)
    }

    public func restore(_ preview: RestorePreview, confirmed: Bool, versions: [RuleTables]) throws {
        guard confirmed else { throw BackupError.confirmationRequired }
        try BackupCodec.validate(preview.replacement, versions: versions)
        try db.write { db in
            guard try backup(versions: versions, db: db) == preview.baseline else { throw BackupError.stalePreview }
            // Replacement is the sole authorized exception to immutable history.
            // DDL is transactional in SQLite: all guards and data roll back on any failure.
            let guards = try Row.fetchAll(db, sql: "SELECT name,sql FROM sqlite_master WHERE type='trigger' AND name IN ('ledger_events_no_update','ledger_events_no_direct_delete','terminal_run_no_update','recorded_run_no_delete','terminal_ledger_no_insert','terminal_metadata_no_update','recorded_metadata_no_delete')")
            for row in guards {
                let name: String = row["name"]
                try db.execute(sql: "DROP TRIGGER \"\(name.replacingOccurrences(of: "\"", with: "\"\""))\"")
            }
            try db.execute(sql: "DELETE FROM active_run; DELETE FROM room_notes; DELETE FROM quest_marks; DELETE FROM run_metadata; DELETE FROM runs; DELETE FROM backup_settings;")
            for run in preview.replacement.runs {
                let tables = try BackupCodec.tables(for: run.ledger, versions: versions)
                let world = try run.ledger.world(tables: tables)
                let header = try JSONEncoder().encode(RunLedger(tables: tables))
                try db.execute(sql: "INSERT INTO runs VALUES (?,?,?,?,?)", arguments: [run.id, "Delver", String(decoding: WorldCodec.canonical(world), as: UTF8.self), 0, 0])
                try db.execute(sql: "INSERT INTO run_metadata VALUES (?,?,?)", arguments: [run.id, header, world.isTerminal])
                try insert(run.ledger.entries, id: run.id, db: db)
                for (room, text) in run.notes { try db.execute(sql: "INSERT INTO room_notes VALUES (?,?,?)", arguments: [run.id, room, text]) }
                for goal in run.markedGoals { try db.execute(sql: "INSERT INTO quest_marks VALUES (?,?)", arguments: [run.id, goal]) }
            }
            if let id = preview.replacement.activeRunID { try db.execute(sql: "INSERT INTO active_run VALUES (1,?)", arguments: [id]) }
            try db.execute(sql: "INSERT INTO backup_settings VALUES (1,?)", arguments: [JSONEncoder().encode(preview.replacement.settings)])
            for row in guards { let sql: String = row["sql"]; try db.execute(sql: sql) }
        }
    }
}
