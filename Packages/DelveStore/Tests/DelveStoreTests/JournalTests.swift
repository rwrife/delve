import Foundation
import GRDB
import DelveKit
import Testing
@testable import DelveStore

@Test func notesRoundTripUpdateAndTrimToDelete() throws {
    let store = try DelveStore.inMemory()
    let tables = try RuleTables.wingOne()
    let quest = try QuestEngine.wingOne(tables: tables)
    let run = try store.start(tables: tables)
    let moved = try store.advance(run, event: .visit(room: "brazier-hall"), tables: tables)

    try store.setNote("Spotted two braziers and a locked vault door.", roomID: "brazier-hall", runID: run.id, tables: tables)
    var journal = try store.journal(runID: run.id, tables: tables)
    #expect(journal.notes["brazier-hall"] == "Spotted two braziers and a locked vault door.")

    // Update note in place.
    try store.setNote("Vault door needs bronze key.", roomID: "brazier-hall", runID: run.id, tables: tables)
    journal = try store.journal(runID: run.id, tables: tables)
    #expect(journal.notes["brazier-hall"] == "Vault door needs bronze key.")

    // Whitespace deletion.
    try store.setNote("   \n  ", roomID: "brazier-hall", runID: run.id, tables: tables)
    journal = try store.journal(runID: run.id, tables: tables)
    #expect(journal.notes["brazier-hall"] == nil)

    // Cannot write note for unvisited room.
    #expect(throws: JournalError.unknownRoom) {
        try store.setNote("Unseen depths", roomID: "heart-chamber", runID: run.id, tables: tables)
    }

    // Toggle user checkmarks independently of engine state.
    try store.setGoalMarked(true, goalID: "silence", runID: run.id, quest: quest, tables: tables)
    journal = try store.journal(runID: run.id, tables: tables)
    #expect(journal.markedGoals.contains("silence"))
    try store.setGoalMarked(false, goalID: "silence", runID: run.id, quest: quest, tables: tables)
    journal = try store.journal(runID: run.id, tables: tables)
    #expect(!journal.markedGoals.contains("silence"))

    // Invalid goal rejected.
    #expect(throws: JournalError.unknownGoal) {
        try store.setGoalMarked(true, goalID: "nonexistent", runID: run.id, quest: quest, tables: tables)
    }
    #expect(try store.run(run.id, tables: tables) == moved)
    #expect(try quest.progress(for: "silence", ledger: moved.ledger, tables: tables) == .unknown)
    let unicode = String(repeating: "e\u{301}", count: 5000)
    try store.setNote(unicode, roomID: "entrance", runID: run.id, tables: tables)
    #expect(throws: JournalError.noteTooLong) {
        try store.setNote(unicode + "e\u{301}", roomID: "entrance", runID: run.id, tables: tables)
    }
    #expect(throws: JournalError.noteTooLong) {
        try store.setNote("bad\0note", roomID: "entrance", runID: run.id, tables: tables)
    }
}

@Test func sessionMarkerAdvancesRecordAndSurvivesReopen() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: path) }
    let tables = try RuleTables.wingOne()
    let store = try DelveStore.atPath(path)
    let run = try store.start(tables: tables)
    let resumed = try store.resumeSession(run, tables: tables)
    let record = try RunRecord.derive(from: resumed.ledger, tables: tables)
    #expect(record.sessions == .known(2))

    let reopened = try DelveStore.atPath(path)
    let loaded = try #require(try reopened.activeRun(tables: tables))
    #expect(loaded == resumed)
}
