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

@Test func activeRunResolvesPinnedContentVersion() throws {
    let versions = try RuleTables.bundledVersions()
    let store = try DelveStore.inMemory()
    let v2 = try RuleTables.wingOne()
    let old = try store.start(tables: v2)
    let matched = try store.activeRun(matching: versions)
    #expect(matched?.run == old)
    #expect(matched?.tables.fingerprint == v2.fingerprint)
    // A v2 run is never reinterpreted by the v3 tables.
    #expect(throws: (any Error).self) { try store.activeRun(tables: try RuleTables.fullDungeon()) }
    let v3 = try RuleTables.fullDungeon()
    let ended = try store.advance(old, event: .retreat, tables: v2)
    let fresh = try store.start(tables: v3)
    let nowMatched = try store.activeRun(matching: versions)
    #expect(nowMatched?.run == fresh)
    #expect(nowMatched?.tables.contentVersion == 3)
    #expect(try store.run(ended.id, tables: v2) == ended)
}

@Test func finishEventPersistsTerminalizesAndSurvivesReopen() throws {
    let v3 = try RuleTables.fullDungeon()
    // Patrol-free twin of the shipped tables (same fingerprint-relevant
    // puzzle data) so the legal route stays deterministic in the store lane.
    let tables = RuleTables(contentVersion: v3.contentVersion, graph: v3.graph,
        spawnRoom: v3.spawnRoom, switchEffects: v3.switchEffects,
        lockKeys: v3.lockKeys, keySpawns: v3.keySpawns,
        discoverySpawns: v3.discoverySpawns, patrolCycles: [:],
        switchRooms: v3.switchRooms, lockFlags: v3.lockFlags, goalRoom: v3.goalRoom)
    var ledger = try RunLedger(tables: tables)
    try ledger.append(.sessionStart, tables: tables)
    for room in ["entrance", "brazier-hall", "sealed-vault", "dust-corridor", "fork", "amber-alcove", "fork", "west-gallery", "bell-niche"] {
        try ledger.append(.visit(room: room), tables: tables)
    }
    try ledger.append(.action(element: "resonant-bell", effects: ["bell-lit"]), tables: tables)
    for room in ["west-gallery", "fork", "sentinel-arch", "echo-steps", "stair-landing", "reliquary", "heart-chamber", "ash-threshold", "ink-gallery", "chronicle-aisle"] {
        try ledger.append(.visit(room: room), tables: tables)
    }
    try ledger.append(.discovery(id: "lore-ink"), tables: tables)
    for room in ["quiet-stacks", "tide-landing", "lantern-bridge", "slate-crossing", "underkeep-bridge", "night-gate", "basalt-foyer", "moth-court", "glass-corridor", "ember-walk", "spiral-steps"] {
        try ledger.append(.visit(room: room), tables: tables)
    }
    #expect(!RuleEngine.stepResult(try ledger.world(tables: tables), .visit(room: "star-anteroom"), tables: tables).accepted)
    for room in ["ember-walk", "glass-corridor", "moth-court", "basalt-foyer", "prism-chapel"] {
        try ledger.append(.visit(room: room), tables: tables)
    }
    try ledger.append(.discovery(id: "lore-prism"), tables: tables)
    for room in ["basalt-foyer", "night-gate", "underkeep-bridge", "slate-crossing", "lantern-bridge", "tide-landing", "quiet-stacks", "chronicle-aisle", "memory-seat"] {
        try ledger.append(.visit(room: room), tables: tables)
    }
    try ledger.append(.action(element: "memory-latch", effects: ["memory-lit"]), tables: tables)
    for room in ["chronicle-aisle", "quiet-stacks", "tide-landing", "lantern-bridge", "slate-crossing", "underkeep-bridge", "night-gate", "basalt-foyer", "moth-court", "glass-corridor", "ember-walk", "spiral-steps", "star-anteroom"] {
        try ledger.append(.visit(room: room), tables: tables)
    }
    #expect(try ledger.world(tables: tables).unlockedLocks.contains("memory-door"))
    try ledger.append(.visit(room: "last-aperture"), tables: tables)
    #expect(!RuleEngine.stepResult(try ledger.world(tables: tables), .visit(room: "dawn-well"), tables: tables).accepted)
    for room in ["star-anteroom", "spiral-steps", "broken-orbit"] {
        try ledger.append(.visit(room: room), tables: tables)
    }
    try ledger.append(.action(element: "orrery-lens", effects: ["star-lit"]), tables: tables)
    for room in ["spiral-steps", "star-anteroom", "last-aperture", "dawn-well"] {
        try ledger.append(.visit(room: room), tables: tables)
    }

    let id = UUID().uuidString
    let store = try DelveStore.inMemory()
    let header = try JSONEncoder().encode(RunLedger(tables: tables))
    try store.db.write { db in
        let now = Date().timeIntervalSince1970
        try db.execute(sql: "INSERT INTO runs VALUES (?,?,?,?,?)", arguments: [id, "Delver", String(decoding: WorldCodec.canonical(ledger.entries.isEmpty ? WorldState() : ledger.world(tables: tables)), as: UTF8.self), now, now])
        try db.execute(sql: "INSERT INTO run_metadata(run_id,ledger_header) VALUES (?,?)", arguments: [id, header])
        for entry in ledger.entries {
            var kind: String {
                switch entry.event {
                case .visit: "visit"
                case .action: "action"
                case .discovery: "discovery"
                case .sessionStart: "session"
                case .death: "death"
                case .retreat: "retreat"
                case .finish: "finish"
                }
            }
            try db.execute(sql: "INSERT INTO ledger_events(run_id,kind,detail_json,occurred_at) VALUES (?,?,?,?)", arguments: [id, kind, String(decoding: try EventCodec.canonical(entry.event), as: UTF8.self), now])
        }
        try db.execute(sql: "INSERT INTO active_run VALUES (1,?)", arguments: [id])
    }
    var run = try store.run(id, tables: tables)
    #expect(run.world.currentRoom == "dawn-well" && !run.world.isTerminal)
    let done = try store.advance(run, event: .finish, tables: tables)
    #expect(done.world.finished && done.world.isTerminal)
    #expect(done.ledger.entries.last?.event == .finish)
    #expect(try store.activeRun(matching: [tables]) == nil)
    #expect(try store.history(tables: tables).map(\.id) == [id])
    let reopened = try store.run(id, tables: tables)
    #expect(reopened == done)
    run = reopened
    #expect(throws: (any Error).self) { try store.advance(run, event: .retreat, tables: tables) }
}
