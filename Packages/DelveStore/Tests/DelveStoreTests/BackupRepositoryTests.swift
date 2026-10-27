import XCTest
import GRDB
import DelveKit
@testable import DelveStore

final class BackupRepositoryTests: XCTestCase {
    func testRoundTripHistoryJournalSettingsAndExplicitConfirmation() throws {
        let versions = try RuleTables.bundledVersions()
        let source = try DelveStore.inMemory()
        for tables in versions {
            let run = try source.start(tables: tables)
            try source.setNote("Note 雪", roomID: tables.spawnRoom, runID: run.id, tables: tables)
            let quest = try QuestEngine.bundledFor(tables: tables)
            try source.setGoalMarked(true, goalID: quest.goals[0].id, runID: run.id, quest: quest, tables: tables)
            _ = try source.advance(run, event: .retreat, tables: tables)
        }
        _ = try source.start(tables: versions[0], id: "active")
        try source.setSettings(.init(confirmNewRun: false))
        let archive = try source.backup(versions: versions)
        let target = try DelveStore.inMemory()
        _ = try target.start(tables: versions[0], id: "removed")
        let bytes = try BackupCodec.encode(archive, versions: versions)
        let before = try target.backup(versions: versions)
        let preview = try target.previewRestore(bytes, versions: versions)
        XCTAssertEqual(preview.diff.removed, ["removed"])
        XCTAssertEqual(preview.diff.added.count, 3)
        XCTAssertEqual(preview.diff.notesAfter, 2)
        XCTAssertEqual(preview.diff.marksAfter, 2)
        XCTAssertTrue(preview.diff.settingsChanged)
        XCTAssertThrowsError(try target.restore(preview, confirmed: false, versions: versions))
        XCTAssertEqual(try target.backup(versions: versions), before)
        try target.restore(preview, confirmed: true, versions: versions)
        XCTAssertEqual(try target.backup(versions: versions), archive)
        XCTAssertEqual(try target.activeRun(matching: versions)?.run.id, "active")
        XCTAssertThrowsError(try target.db.write { try $0.execute(sql: "UPDATE ledger_events SET kind='visit'") })
        XCTAssertThrowsError(try target.db.write { try $0.execute(sql: "DELETE FROM run_metadata") })
    }

    func testStalePreviewRejectsJournalSettingsAndLedgerChanges() throws {
        let tables = try RuleTables.fullDungeon()
        let versions = [tables]
        let store = try DelveStore.inMemory()
        var run = try store.start(tables: tables)
        let bytes = try BackupCodec.encode(store.backup(versions: versions), versions: versions)
        for change in 0..<3 {
            let preview = try store.previewRestore(bytes, versions: versions)
            if change == 0 { try store.setNote("changed", roomID: tables.spawnRoom, runID: run.id, tables: tables) }
            if change == 1 { try store.setSettings(.init(confirmNewRun: false)) }
            if change == 2 { run = try store.resumeSession(run, tables: tables) }
            let before = try store.backup(versions: versions)
            XCTAssertThrowsError(try store.restore(preview, confirmed: true, versions: versions)) {
                XCTAssertEqual($0 as? BackupError, .stalePreview)
            }
            XCTAssertEqual(try store.backup(versions: versions), before)
        }
    }

    func testMidRestoreFailureRollsBackDataAndGuards() throws {
        let tables = try RuleTables.fullDungeon()
        let versions = [tables]
        let store = try DelveStore.inMemory()
        let run = try store.start(tables: tables, id: "original")
        var replacement = try store.backup(versions: versions)
        replacement.runs[0].notes[tables.spawnRoom] = "fails"
        let preview = try store.previewRestore(BackupCodec.encode(replacement, versions: versions), versions: versions)
        let before = try store.backup(versions: versions)
        try store.db.write { try $0.execute(sql: "CREATE TRIGGER fail_restore BEFORE INSERT ON room_notes BEGIN SELECT RAISE(ABORT, 'injected disk failure'); END") }
        XCTAssertThrowsError(try store.restore(preview, confirmed: true, versions: versions))
        XCTAssertEqual(try store.backup(versions: versions), before)
        XCTAssertThrowsError(try store.db.write { try $0.execute(sql: "DELETE FROM ledger_events") })
        XCTAssertThrowsError(try store.db.write { try $0.execute(sql: "UPDATE ledger_events SET kind='visit'") })
        _ = try store.advance(run, event: .retreat, tables: tables)
        XCTAssertThrowsError(try store.db.write { try $0.execute(sql: "UPDATE runs SET hero_name='mutated'") })
    }

    func testPreviewChangedUnchangedEmptyRestore() throws {
        let tables = try RuleTables.fullDungeon()
        let versions = [tables]
        let store = try DelveStore.inMemory()
        let run = try store.start(tables: tables, id: "run")
        var archive = try store.backup(versions: versions)
        var preview = try store.previewRestore(BackupCodec.encode(archive, versions: versions), versions: versions)
        XCTAssertEqual(preview.diff.unchanged, [run.id])
        archive.runs[0].notes[tables.spawnRoom] = "new"
        preview = try store.previewRestore(BackupCodec.encode(archive, versions: versions), versions: versions)
        XCTAssertEqual(preview.diff.changed, [run.id])
        let empty = BackupArchive(runs: [], activeRunID: nil)
        preview = try store.previewRestore(BackupCodec.encode(empty, versions: versions), versions: versions)
        try store.restore(preview, confirmed: true, versions: versions)
        XCTAssertEqual(try store.backup(versions: versions), empty)
        XCTAssertNil(try store.activeRun(tables: tables))
    }
}

extension BackupRepositoryTests {
    func testRestoreSurvivesReopenAndV1ArchiveMigration() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }
        let tables = try RuleTables.wingOne()
        let versions = [tables]
        let source = try DelveStore.inMemory()
        let run = try source.start(tables: tables, id: "legacy-archive")
        try source.setNote("saved", roomID: tables.spawnRoom, runID: run.id, tables: tables)
        _ = try source.advance(run, event: .retreat, tables: tables)
        let archive = try source.backup(versions: versions)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupCodec.encode(archive, versions: versions)) as? [String: Any])
        json["version"] = 1; json.removeValue(forKey: "settings")
        do {
            let store = try DelveStore.atPath(path)
            let preview = try store.previewRestore(JSONSerialization.data(withJSONObject: json), versions: versions)
            try store.restore(preview, confirmed: true, versions: versions)
        }
        let reopened = try DelveStore.atPath(path)
        XCTAssertEqual(try reopened.backup(versions: versions), archive)
        XCTAssertEqual(try reopened.history(tables: tables).count, 1)
        XCTAssertThrowsError(try reopened.db.write { try $0.execute(sql: "DELETE FROM runs") })
    }

    func testCannotSilentlyDiscardUnpinnedLegacyRuns() throws {
        let store = try DelveStore.inMemory()
        try store.db.write { try $0.execute(sql: "INSERT INTO runs VALUES ('legacy','Delver','{}',0,0)") }
        XCTAssertThrowsError(try store.backup(versions: RuleTables.bundledVersions()))
    }
}
