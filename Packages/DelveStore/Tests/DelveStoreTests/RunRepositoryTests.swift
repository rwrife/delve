import Foundation
import GRDB
import DelveKit
import Testing
@testable import DelveStore

@Test func replayIgnoresSnapshotAndSurvivesReopen() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: path) }
    let tables = try RuleTables.wingOne()
    let store = try DelveStore.atPath(path)
    let start = try store.start(tables: tables)
    let moved = try store.advance(start, event: .visit(room: "brazier-hall"), tables: tables)
    let acted = try store.advance(moved, event: .action(element: "brazier-left", effects: ["brazier-left"]), tables: tables)
    try store.save(acted, tables: tables)
    try store.db.write { try $0.execute(sql: "UPDATE runs SET world_json='{}' WHERE id=?", arguments: [acted.id]) }
    let reopened = try DelveStore.atPath(path)
    #expect(try reopened.activeRun(tables: tables) == acted)
    #expect(acted.world.flags == ["brazier-left"])
}

@Test func transactionFailureAndFailedStartRetainPreviousRun() throws {
    let store = try DelveStore.inMemory()
    let tables = try RuleTables.wingOne()
    let run = try store.start(tables: tables)
    try store.db.write { db in
        try db.execute(sql: "CREATE TRIGGER fail_snapshot BEFORE UPDATE ON runs BEGIN SELECT RAISE(ABORT, 'test disk failure'); END")
    }
    #expect(throws: (any Error).self) { try store.advance(run, event: .visit(room: "brazier-hall"), tables: tables) }
    #expect(try store.activeRun(tables: tables) == run)
    #expect(try store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM ledger_events") } == 2)
    #expect(throws: (any Error).self) { try store.start(tables: tables) }
    #expect(try store.activeRun(tables: tables) == run)
    #expect(try store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM runs") } == 1)
    #expect(throws: (any Error).self) { try store.save(run, tables: tables) }
}

@Test func terminalHistoryIsPreservedAndImmutable() throws {
    let store = try DelveStore.inMemory()
    let tables = try RuleTables.wingOne()
    let initial = try store.start(tables: tables)
    let ended = try store.advance(initial, event: .retreat, tables: tables)
    #expect(try store.activeRun(tables: tables) == nil)
    let next = try store.start(tables: tables)
    #expect(try store.run(ended.id, tables: tables) == ended)
    #expect(try store.history(tables: tables) == [ended])
    #expect(try store.activeRun(tables: tables) == next)
    for sql in ["UPDATE runs SET world_json='{}' WHERE id=?", "DELETE FROM runs WHERE id=?", "UPDATE run_metadata SET terminal=0 WHERE run_id=?", "DELETE FROM run_metadata WHERE run_id=?"] {
        #expect(throws: (any Error).self) { try store.db.write { try $0.execute(sql: sql, arguments: [ended.id]) } }
    }
    #expect(throws: (any Error).self) { try store.advance(ended, event: .visit(room: "brazier-hall"), tables: tables) }
}

@Test func actualPatrolContactCommitsDeathWithMovement() throws {
    let store = try DelveStore.inMemory()
    let tables = try RuleTables.wingOne()
    var run = try store.start(tables: tables)
    for room in ["brazier-hall", "sealed-vault", "dust-corridor", "fork", "blind-crypt", "ossuary", "blind-crypt", "ossuary", "blind-crypt", "ossuary", "blind-crypt"] {
        run = try store.advance(run, event: .visit(room: room), tables: tables)
    }
    let beforeContact = run
    try store.db.write { db in
        try db.execute(sql: "CREATE TRIGGER fail_death BEFORE INSERT ON ledger_events WHEN NEW.kind='death' BEGIN SELECT RAISE(ABORT, 'test terminal failure'); END")
    }
    #expect(throws: (any Error).self) { try store.advance(beforeContact, event: .visit(room: "ossuary"), tables: tables) }
    #expect(try store.activeRun(tables: tables) == beforeContact)
    try store.db.write { try $0.execute(sql: "DROP TRIGGER fail_death") }
    run = try store.advance(beforeContact, event: .visit(room: "ossuary"), tables: tables)
    #expect(run.world.isDead)
    #expect(run.ledger.entries.last?.event == .death)
    #expect(try store.activeRun(tables: tables) == nil)
    #expect(try store.run(run.id, tables: tables) == run)
}

@Test func invalidAndUnknownLedgerEventsFailResume() throws {
    let tables = try RuleTables.wingOne()
    for payload in ["{\"teleport\":{}}", String(decoding: try EventCodec.canonical(.visit(room: "missing-room")), as: UTF8.self), String(decoding: try EventCodec.canonical(.death), as: UTF8.self)] {
        let store = try DelveStore.inMemory()
        let run = try store.start(tables: tables)
        try store.db.write { db in
            try db.execute(sql: "INSERT INTO ledger_events(run_id,kind,detail_json,occurred_at) VALUES (?,'visit',?,0)", arguments: [run.id, payload])
        }
        #expect(throws: (any Error).self) { try store.activeRun(tables: tables) }
    }
}

@Test func staleAndRejectedCommandsDoNotWrite() throws {
    let store = try DelveStore.inMemory()
    let tables = try RuleTables.wingOne()
    let run = try store.start(tables: tables)
    #expect(throws: (any Error).self) { try store.advance(run, event: .death, tables: tables) }
    #expect(throws: (any Error).self) { try store.advance(run, event: .visit(room: "heart-chamber"), tables: tables) }
    let moved = try store.advance(run, event: .visit(room: "brazier-hall"), tables: tables)
    #expect(throws: (any Error).self) { try store.advance(run, event: .discovery(id: "lore-threshold"), tables: tables) }
    #expect(try store.activeRun(tables: tables) == moved)
    #expect(throws: (any Error).self) { try store.run(run.id, tables: .current) }
}
