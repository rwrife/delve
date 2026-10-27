import XCTest
@testable import DelveKit

final class BackupCodecTests: XCTestCase {
    private func archive(_ tables: RuleTables) throws -> BackupArchive {
        var ledger = try RunLedger(tables: tables)
        try ledger.append(.sessionStart, tables: tables)
        try ledger.append(.visit(room: tables.spawnRoom), tables: tables)
        return BackupArchive(runs: [BackupRun(id: "run", ledger: ledger, notes: [tables.spawnRoom: "A, \"quote\"\r\n雪 👩🏽‍🚀"])], activeRunID: "run", settings: .init(confirmNewRun: false))
    }

    func testVersionAndContentMatrix() throws {
        let versions = try [.current] + RuleTables.bundledVersions()
        for tables in versions {
            let original = try archive(tables)
            let data = try BackupCodec.encode(original, versions: versions)
            XCTAssertEqual(try BackupCodec.decode(data, versions: versions), original)
            XCTAssertEqual(try BackupCodec.encode(BackupCodec.decode(data, versions: versions), versions: versions), data)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            json["version"] = 1
            json.removeValue(forKey: "settings")
            let migrated = try BackupCodec.decode(JSONSerialization.data(withJSONObject: json), versions: versions)
            XCTAssertEqual(migrated.version, 2)
            XCTAssertEqual(migrated.runs, original.runs)
            XCTAssertEqual(migrated.settings, BackupSettings())
            for invalid in [-1, 0, 3, 999] {
                json["version"] = invalid
                XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: json), versions: versions)) {
                    XCTAssertEqual($0 as? BackupError, .unsupportedVersion(invalid))
                }
            }
        }
    }

    func testRejectsInvalidArchives() throws {
        let tables = try RuleTables.fullDungeon()
        let versions = [tables]
        let original = try archive(tables)
        var invalid = original
        invalid.runs.append(invalid.runs[0])
        XCTAssertThrowsError(try BackupCodec.encode(invalid, versions: versions))
        invalid = original; invalid.activeRunID = "missing"
        XCTAssertThrowsError(try BackupCodec.encode(invalid, versions: versions))
        invalid = original; invalid.runs[0].notes = ["not-visited": "note"]
        XCTAssertThrowsError(try BackupCodec.encode(invalid, versions: versions))
        invalid = original; invalid.runs[0].notes = [tables.spawnRoom: String(repeating: "x", count: 10001)]
        XCTAssertThrowsError(try BackupCodec.encode(invalid, versions: versions))
        invalid = original; invalid.runs[0].markedGoals = ["invented"]
        XCTAssertThrowsError(try BackupCodec.encode(invalid, versions: versions))
        invalid = original
        try invalid.runs[0].ledger.append(.retreat, tables: tables)
        XCTAssertThrowsError(try BackupCodec.encode(invalid, versions: versions))
        XCTAssertThrowsError(try BackupCodec.decode(Data("{}".utf8), versions: versions))
        XCTAssertThrowsError(try BackupCodec.decode(Data(repeating: 32, count: BackupCodec.maximumBytes + 1), versions: versions))
        let bytes = try BackupCodec.encode(original, versions: versions)
        XCTAssertThrowsError(try BackupCodec.decode(bytes.dropLast(), versions: versions))
        XCTAssertThrowsError(try BackupCodec.decode(bytes, versions: []))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        json.removeValue(forKey: "settings") // v2 must not silently default corrupted settings
        XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: json), versions: versions))
    }

    func testRejectsCorruptLedgerSequenceFingerprintAndEvents() throws {
        let tables = try RuleTables.fullDungeon()
        let data = try BackupCodec.encode(archive(tables), versions: [tables])
        for corruption in ["sequence", "fingerprint", "event", "illegal-event"] {
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var runs = root["runs"] as! [[String: Any]]
            var ledger = runs[0]["ledger"] as! [String: Any]
            if corruption == "fingerprint" { ledger["tablesFingerprint"] = "bad" }
            else {
                var entries = ledger["entries"] as! [[String: Any]]
                if corruption == "sequence" { entries[0]["sequence"] = 7 }
                else if corruption == "illegal-event" {
                    entries[0]["eventBase64"] = try EventCodec.canonical(.visit(room: "nonexistent")).base64EncodedString()
                } else { entries[0]["eventBase64"] = Data("invalid".utf8).base64EncodedString() }
                ledger["entries"] = entries
            }
            runs[0]["ledger"] = ledger; root["runs"] = runs
            XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: root), versions: [tables]))
        }
    }

    func testCSVQuotingUnicodeFormulaSafetyAndDerivedProgress() throws {
        let tables = try RuleTables.fullDungeon()
        var archive = try archive(tables)
        let quest = try QuestEngine.bundledFor(tables: tables)
        archive.runs[0].markedGoals = [quest.goals[0].id]
        let csv = String(decoding: try JournalCSV.export(archive, versions: [tables]), as: UTF8.self)
        XCTAssertTrue(csv.contains("\"A, \"\"quote\"\"\r\n雪 👩🏽‍🚀\""))
        XCTAssertTrue(csv.contains("\"quest\""))
        XCTAssertTrue(csv.contains("\"true\""))
        XCTAssertTrue(csv.contains("\"\(try quest.progress(for: quest.goals[0].id, ledger: archive.runs[0].ledger, tables: tables).rawValue)\""))
        for formula in ["=SUM(1,2)", "  +3", "-1", "@cmd", "\tformula"] {
            archive.runs[0].notes[tables.spawnRoom] = formula
            let result = String(decoding: try JournalCSV.export(archive, versions: [tables]), as: UTF8.self)
            XCTAssertTrue(result.contains("\"'\(formula)\""))
        }
    }
}
