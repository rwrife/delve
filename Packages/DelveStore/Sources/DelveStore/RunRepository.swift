import Foundation
import GRDB
import DelveKit

public struct StoredRun: Equatable, Sendable {
    public let id: String
    public let ledger: RunLedger
    public let world: WorldState
}

public enum RunStoreError: Error, Equatable {
    case missingRun, staleRun, invalidLedgerKind, emptyRun
}

extension DelveStore {
    /// All reads replay canonical ledger events; snapshots are only a cache.
    public func activeRun(tables: RuleTables) throws -> StoredRun? {
        try db.read { db in
            guard let id = try String.fetchOne(db, sql: "SELECT run_id FROM active_run WHERE slot=1") else { return nil }
            return try readRun(id, tables: tables, db: db)
        }
    }

    public func run(_ id: String, tables: RuleTables) throws -> StoredRun {
        try db.read { try readRun(id, tables: tables, db: $0) }
    }

    public func history(tables: RuleTables) throws -> [StoredRun] {
        try db.read { db in
            try String.fetchAll(db, sql: "SELECT run_id FROM run_metadata WHERE terminal=1 ORDER BY run_id")
                .map { try readRun($0, tables: tables, db: db) }
        }
    }

    /// A failed new start never removes the previous active run.
    public func start(tables: RuleTables, id: String = UUID().uuidString) throws -> StoredRun {
        var ledger = try RunLedger(tables: tables)
        let header = try JSONEncoder().encode(ledger)
        try ledger.append(.sessionStart, tables: tables)
        try ledger.append(.visit(room: tables.spawnRoom), tables: tables)
        if RuleEngine.inPatrolContact(try ledger.world(tables: tables), tables: tables) {
            try ledger.append(.death, tables: tables)
        }
        let result = StoredRun(id: id, ledger: ledger, world: try ledger.world(tables: tables))
        try db.write { db in
            let now = Date().timeIntervalSince1970
            try db.execute(sql: "INSERT INTO runs VALUES (?,?,?,?,?)", arguments: [id, "Delver", String(decoding: WorldCodec.canonical(result.world), as: UTF8.self), now, now])
            try db.execute(sql: "INSERT INTO run_metadata(run_id,ledger_header) VALUES (?,?)", arguments: [id, header])
            try insert(ledger.entries, id: id, db: db)
            try db.execute(sql: "INSERT INTO active_run VALUES (1,?) ON CONFLICT(slot) DO UPDATE SET run_id=excluded.run_id", arguments: [id])
            try finish(result, db: db)
        }
        return result
    }

    /// Validate and commit a candidate before the caller publishes it to UI.
    public func advance(_ previous: StoredRun, event: GameEvent, tables: RuleTables) throws -> StoredRun {
        var ledger = previous.ledger
        try ledger.append(event, tables: tables)
        if RuleEngine.inPatrolContact(try ledger.world(tables: tables), tables: tables) {
            try ledger.append(.death, tables: tables)
        }
        let next = StoredRun(id: previous.id, ledger: ledger, world: try ledger.world(tables: tables))
        try db.write { db in
            try requireCurrent(previous, tables: tables, db: db)
            try insert(Array(ledger.entries.dropFirst(previous.ledger.entries.count)), id: previous.id, db: db)
            try finish(next, db: db)
        }
        return next
    }

    /// Record a real resume boundary, atomically, before publishing the run.
    public func resumeSession(_ previous: StoredRun, tables: RuleTables) throws -> StoredRun {
        try advance(previous, event: .sessionStart, tables: tables)
    }

    public func save(_ run: StoredRun, tables: RuleTables) throws {
        try db.write { db in
            try requireCurrent(run, tables: tables, db: db)
            try finish(run, db: db)
        }
    }

    private func requireCurrent(_ run: StoredRun, tables: RuleTables, db: Database) throws {
        guard try String.fetchOne(db, sql: "SELECT run_id FROM active_run WHERE slot=1") == run.id,
              try readRun(run.id, tables: tables, db: db) == run else { throw RunStoreError.staleRun }
    }

    private func readRun(_ id: String, tables: RuleTables, db: Database) throws -> StoredRun {
        guard let header = try Data.fetchOne(db, sql: "SELECT ledger_header FROM run_metadata WHERE run_id=?", arguments: [id]) else { throw RunStoreError.missingRun }
        let headerLedger = try JSONDecoder().decode(RunLedger.self, from: header)
        // Verify the persisted content identity before rebuilding with these tables.
        _ = try headerLedger.world(tables: tables)
        guard headerLedger.entries.isEmpty else { throw RunStoreError.invalidLedgerKind }
        let rows = try Row.fetchAll(db, sql: "SELECT kind,detail_json FROM ledger_events WHERE run_id=? ORDER BY id", arguments: [id])
        let entries = try rows.enumerated().map { index, row in
            let json: String = row["detail_json"]
            let event = try EventCodec.decode(Data(json.utf8))
            let kind: String = row["kind"]
            guard kind == eventKind(event) else { throw RunStoreError.invalidLedgerKind }
            return RunLedger.Entry(sequence: index, event: event)
        }
        guard !entries.isEmpty else { throw RunStoreError.emptyRun }
        let ledger = try RunLedger(entries: entries, tables: tables)
        // One strict replay validates every event without quadratic prefix replays.
        return StoredRun(id: id, ledger: ledger, world: try ledger.world(tables: tables))
    }

    private func insert(_ entries: [RunLedger.Entry], id: String, db: Database) throws {
        for entry in entries {
            try db.execute(sql: "INSERT INTO ledger_events(run_id,kind,detail_json,occurred_at) VALUES (?,?,?,?)", arguments: [id, eventKind(entry.event), String(decoding: try EventCodec.canonical(entry.event), as: UTF8.self), Date().timeIntervalSince1970])
        }
    }

    private func finish(_ run: StoredRun, db: Database) throws {
        try db.execute(sql: "UPDATE runs SET world_json=?,updated_at=? WHERE id=?", arguments: [String(decoding: try WorldCodec.canonical(run.world), as: UTF8.self), Date().timeIntervalSince1970, run.id])
        if run.world.isTerminal {
            try db.execute(sql: "UPDATE run_metadata SET terminal=1 WHERE run_id=?", arguments: [run.id])
            try db.execute(sql: "DELETE FROM active_run WHERE run_id=?", arguments: [run.id])
        }
    }

    private func eventKind(_ event: GameEvent) -> String {
        switch event {
        case .visit: "visit"
        case .action: "action"
        case .discovery: "discovery"
        case .sessionStart: "session"
        case .death: "death"
        case .retreat: "retreat"
        }
    }
}
