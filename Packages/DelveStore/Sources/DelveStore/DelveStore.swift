import Foundation
import GRDB
import DelveKit

/// Version one is immutable. Add a new migration for future schema changes.
///
/// The v1 schema carries the skeleton persistence shape the milestones
/// build on: one save slot per run with the serialized `WorldState`, and an
/// append-only event ledger (a BEFORE UPDATE / BEFORE DELETE trigger pair
/// rejects in-place mutation or erasure of ledger rows — history is corrected
/// by appending compensating events, never by rewriting).
public enum DelveStoreSchema {
    public static let migrationIdentifiers = ["v1", "v2", "v3"]

    public static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE runs (
                  id TEXT PRIMARY KEY NOT NULL,
                  hero_name TEXT NOT NULL,
                  world_json TEXT NOT NULL,
                  started_at REAL NOT NULL,
                  updated_at REAL NOT NULL
                );
                CREATE TABLE ledger_events (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
                  kind TEXT NOT NULL CHECK (
                    kind IN ('visit', 'action', 'discovery', 'death', 'retreat')
                  ),
                  detail_json TEXT NOT NULL,
                  occurred_at REAL NOT NULL
                );
                CREATE INDEX ledger_events_run_occurred
                  ON ledger_events(run_id, occurred_at, id);
                CREATE TRIGGER ledger_events_no_update
                  BEFORE UPDATE ON ledger_events
                BEGIN
                  SELECT RAISE(ABORT, 'ledger events are append-only');
                END;
                -- Direct DELETE of ledger rows is forbidden: history is
                -- append-only. The WHEN guard lets foreign-key CASCADE
                -- through: deleting a run (the parent row) removes its
                -- events; deleting an event directly while its run still
                -- exists is rejected.
                CREATE TRIGGER ledger_events_no_direct_delete
                  BEFORE DELETE ON ledger_events
                WHEN EXISTS(SELECT 1 FROM runs WHERE id = OLD.run_id)
                BEGIN
                  SELECT RAISE(ABORT, 'ledger events are append-only; delete the run to remove its history');
                END;
                """)
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: """
                CREATE TABLE run_metadata (
                  run_id TEXT PRIMARY KEY NOT NULL REFERENCES runs(id),
                  ledger_header BLOB NOT NULL,
                  terminal INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE active_run (
                  slot INTEGER PRIMARY KEY CHECK(slot = 1),
                  run_id TEXT NOT NULL REFERENCES run_metadata(run_id)
                );
                CREATE TRIGGER terminal_run_no_update BEFORE UPDATE ON runs
                WHEN EXISTS(SELECT 1 FROM run_metadata WHERE run_id = OLD.id AND terminal = 1)
                BEGIN SELECT RAISE(ABORT, 'terminal run is immutable'); END;
                CREATE TRIGGER recorded_run_no_delete BEFORE DELETE ON runs
                WHEN EXISTS(SELECT 1 FROM run_metadata WHERE run_id = OLD.id)
                BEGIN SELECT RAISE(ABORT, 'recorded run is immutable history'); END;
                CREATE TRIGGER terminal_ledger_no_insert BEFORE INSERT ON ledger_events
                WHEN EXISTS(SELECT 1 FROM run_metadata WHERE run_id = NEW.run_id AND terminal = 1)
                BEGIN SELECT RAISE(ABORT, 'terminal ledger is immutable'); END;
                CREATE TRIGGER terminal_metadata_no_update BEFORE UPDATE ON run_metadata
                WHEN OLD.terminal = 1
                BEGIN SELECT RAISE(ABORT, 'terminal metadata is immutable'); END;
                CREATE TRIGGER recorded_metadata_no_delete BEFORE DELETE ON run_metadata
                BEGIN SELECT RAISE(ABORT, 'recorded metadata is immutable'); END;
                """)
        }
        migrator.registerMigration("v3") { db in
            // Extend the CHECK without mutating v1/v2 or rewriting event bytes.
            try db.execute(sql: """
                CREATE TABLE ledger_events_v3 (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
                  kind TEXT NOT NULL CHECK(kind IN ('visit','action','discovery','death','retreat','session')),
                  detail_json TEXT NOT NULL,
                  occurred_at REAL NOT NULL
                );
                INSERT INTO ledger_events_v3 SELECT * FROM ledger_events;
                DROP TABLE ledger_events;
                ALTER TABLE ledger_events_v3 RENAME TO ledger_events;
                CREATE INDEX ledger_events_run_occurred ON ledger_events(run_id, occurred_at, id);
                CREATE TRIGGER ledger_events_no_update BEFORE UPDATE ON ledger_events
                BEGIN SELECT RAISE(ABORT, 'ledger events are append-only'); END;
                CREATE TRIGGER ledger_events_no_direct_delete BEFORE DELETE ON ledger_events
                WHEN EXISTS(SELECT 1 FROM runs WHERE id = OLD.run_id)
                BEGIN SELECT RAISE(ABORT, 'ledger events are append-only; delete the run to remove its history'); END;
                CREATE TRIGGER terminal_ledger_no_insert BEFORE INSERT ON ledger_events
                WHEN EXISTS(SELECT 1 FROM run_metadata WHERE run_id = NEW.run_id AND terminal = 1)
                BEGIN SELECT RAISE(ABORT, 'terminal ledger is immutable'); END;
                CREATE TABLE room_notes (
                  run_id TEXT NOT NULL REFERENCES run_metadata(run_id),
                  room_id TEXT NOT NULL,
                  text TEXT NOT NULL CHECK(length(text) <= 10000),
                  PRIMARY KEY(run_id, room_id)
                );
                CREATE TABLE quest_marks (
                  run_id TEXT NOT NULL REFERENCES run_metadata(run_id),
                  goal_id TEXT NOT NULL,
                  PRIMARY KEY(run_id, goal_id)
                );
                """)
        }
        return migrator
    }()
}

/// Opens and migrates Delve's local SQLite store. GRDB is a purely local
/// storage engine — this package performs no networking of any kind.
public struct DelveStore: Sendable {
    public let db: any DatabaseWriter

    public init(db: any DatabaseWriter) throws {
        try DelveStoreSchema.migrator.migrate(db)
        self.db = db
    }

    public static func inMemory() throws -> DelveStore {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try DelveStore(db: DatabaseQueue(configuration: configuration))
    }

    public static func atPath(_ path: String) throws -> DelveStore {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try DelveStore(db: DatabaseQueue(path: path, configuration: configuration))
    }
}
