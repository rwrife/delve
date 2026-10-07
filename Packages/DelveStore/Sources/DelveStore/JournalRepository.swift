import Foundation
import GRDB
import DelveKit

public struct Journal: Equatable, Sendable {
    public let notes: [String: String]
    public let markedGoals: Set<String>
}

public enum JournalError: Error, Equatable {
    case unknownRoom, unknownGoal, noteTooLong
}

extension DelveStore {
    public func journal(runID: String, tables: RuleTables) throws -> Journal {
        // Validate content identity and run existence; never trust a UI snapshot.
        _ = try run(runID, tables: tables)
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT room_id,text FROM room_notes WHERE run_id=?", arguments: [runID])
            return Journal(
                notes: Dictionary(uniqueKeysWithValues: rows.map { ($0["room_id"] as String, $0["text"] as String) }),
                markedGoals: Set(try String.fetchAll(db, sql: "SELECT goal_id FROM quest_marks WHERE run_id=?", arguments: [runID]))
            )
        }
    }

    /// One pinned note per visited room per run. Empty text deletes the note.
    /// User annotations never change ledger facts or engine-derived progress.
    public func setNote(_ text: String, roomID: String, runID: String, tables: RuleTables) throws {
        let stored = try run(runID, tables: tables)
        guard stored.world.visitedRooms.contains(roomID) else { throw JournalError.unknownRoom }
        guard text.unicodeScalars.count <= 10000, !text.contains("\0") else { throw JournalError.noteTooLong }
        try db.write { db in
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try db.execute(sql: "DELETE FROM room_notes WHERE run_id=? AND room_id=?", arguments: [runID, roomID])
            } else {
                try db.execute(sql: "INSERT INTO room_notes VALUES (?,?,?) ON CONFLICT(run_id,room_id) DO UPDATE SET text=excluded.text", arguments: [runID, roomID, text])
            }
        }
    }

    public func setGoalMarked(_ marked: Bool, goalID: String, runID: String, quest: QuestEngine, tables: RuleTables) throws {
        _ = try run(runID, tables: tables)
        guard quest.contentVersion == tables.contentVersion, quest.goals.contains(where: { $0.id == goalID }) else {
            throw JournalError.unknownGoal
        }
        try db.write { db in
            if marked {
                try db.execute(sql: "INSERT OR IGNORE INTO quest_marks VALUES (?,?)", arguments: [runID, goalID])
            } else {
                try db.execute(sql: "DELETE FROM quest_marks WHERE run_id=? AND goal_id=?", arguments: [runID, goalID])
            }
        }
    }
}
