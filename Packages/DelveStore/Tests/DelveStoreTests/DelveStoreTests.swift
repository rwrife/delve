import Foundation
import GRDB
import DelveKit
import Testing

@testable import DelveStore

@Test func emptyDatabaseMigratesThroughV2() throws {
    let store = try DelveStore.inMemory()
    let tables = try store.db.read { db in
        try Set(String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name IN ('runs', 'ledger_events', 'grdb_migrations')
            """))
    }
    #expect(tables == ["grdb_migrations", "ledger_events", "runs"])
    #expect(try store.db.read { db in try DelveStoreSchema.migrator.appliedMigrations(db) } == ["v1", "v2"])
}

@Test func runAndLedgerRoundTripThroughStore() throws {
    let store = try DelveStore.inMemory()
    let runID = "00000000-0000-0000-0000-000000000001"
    try store.db.write { db in
        try db.execute(
            sql: "INSERT INTO runs (id, hero_name, world_json, started_at, updated_at) VALUES (?,?,?,?,?)",
            arguments: [runID, "Delver", "{}", 100.0, 101.0]
        )
        try db.execute(
            sql: "INSERT INTO ledger_events (run_id, kind, detail_json, occurred_at) VALUES (?,?,?,?)",
            arguments: [runID, "visit", "{\"room\":\"entrance\"}", 100.0]
        )
    }
    let kinds = try store.db.read { db in
        try String.fetchAll(db, sql: "SELECT kind FROM ledger_events WHERE run_id = ? ORDER BY occurred_at, id", arguments: [runID])
    }
    #expect(kinds == ["visit"])
}

@Test func ledgerRowsRejectInPlaceUpdatesAndDirectDeletes() throws {
    let store = try DelveStore.inMemory()
    let runID = "00000000-0000-0000-0000-000000000001"
    try store.db.write { db in
        try db.execute(
            sql: "INSERT INTO runs (id, hero_name, world_json, started_at, updated_at) VALUES (?,?,?,?,?)",
            arguments: [runID, "Delver", "{}", 100.0, 101.0]
        )
        try db.execute(
            sql: "INSERT INTO ledger_events (run_id, kind, detail_json, occurred_at) VALUES (?,?,?,?)",
            arguments: [runID, "visit", "{\"room\":\"entrance\"}", 100.0]
        )
    }
    #expect(throws: (any Error).self) {
        try store.db.write { db in
            try db.execute(sql: "UPDATE ledger_events SET kind='discovery' WHERE run_id=?", arguments: [runID])
        }
    }
    #expect(throws: (any Error).self) {
        try store.db.write { db in
            try db.execute(sql: "DELETE FROM ledger_events WHERE run_id=?", arguments: [runID])
        }
    }
    let count = try store.db.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledger_events")
    }
    #expect(count == 1)
}

@Test func deletingRunCascadesLedgerEvents() throws {
    let store = try DelveStore.inMemory()
    let runID = "00000000-0000-0000-0000-000000000001"
    try store.db.write { db in
        try db.execute(
            sql: "INSERT INTO runs (id, hero_name, world_json, started_at, updated_at) VALUES (?,?,?,?,?)",
            arguments: [runID, "Delver", "{}", 100.0, 101.0]
        )
        try db.execute(
            sql: "INSERT INTO ledger_events (run_id, kind, detail_json, occurred_at) VALUES (?,?,?,?)",
            arguments: [runID, "visit", "{\"room\":\"entrance\"}", 100.0]
        )
        try db.execute(sql: "DELETE FROM runs WHERE id = ?", arguments: [runID])
    }
    let count = try store.db.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledger_events")
    }
    #expect(count == 0)
}

@Test func ledgerKindCheckRejectsUnknownKinds() throws {
    let store = try DelveStore.inMemory()
    let runID = "00000000-0000-0000-0000-000000000001"
    #expect(throws: (any Error).self) {
        try store.db.write { db in
            try db.execute(
                sql: "INSERT INTO runs (id, hero_name, world_json, started_at, updated_at) VALUES (?,?,?,?,?)",
                arguments: [runID, "Delver", "{}", 100.0, 101.0]
            )
            try db.execute(
                sql: "INSERT INTO ledger_events (run_id, kind, detail_json, occurred_at) VALUES (?,?,?,?)",
                arguments: [runID, "teleport", "{}", 100.0]
            )
        }
    }
}

@Test func committedV1FixtureMigratesAndReadsSeedRows() throws {
    let source = try #require(Bundle.module.url(forResource: "v1", withExtension: "sqlite"))
    let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    defer { try? FileManager.default.removeItem(at: target) }
    try FileManager.default.copyItem(at: source, to: target)
    let store = try DelveStore.atPath(target.path)
    #expect(try store.db.read { db in try DelveStoreSchema.migrator.appliedMigrations(db) } == ["v1", "v2"])
    let hero = try store.db.read { db in
        try String.fetchOne(db, sql: "SELECT hero_name FROM runs WHERE id = ?", arguments: ["00000000-0000-0000-0000-000000000001"])
    }
    #expect(hero == "Delver")
    let kinds = try store.db.read { db in
        try String.fetchAll(db, sql: "SELECT kind FROM ledger_events ORDER BY occurred_at, id")
    }
    #expect(kinds == ["visit", "action", "visit"])
    let worldJSON = try store.db.read { db in
        try String.fetchOne(db, sql: "SELECT world_json FROM runs WHERE id = ?", arguments: ["00000000-0000-0000-0000-000000000001"])
    }
    let data = try #require(worldJSON?.data(using: .utf8))
    let world = try JSONDecoder().decode(WorldState.self, from: data)
    #expect(world.flags == ["brazier-left"])
    #expect(world.visitedRooms == ["entrance", "brazier-hall"])
    #expect(world.keys == ["bronze-key"])
}
