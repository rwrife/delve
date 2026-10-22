import Foundation
import Testing
@testable import DelveKit

@Test func fullDungeonIsVersionedAndSolvable() throws {
    let old = try RuleTables.wingOne()
    let tables = try RuleTables.fullDungeon() // load() runs exhaustive no-softlock proof.
    let quest = try QuestEngine.fullDungeon(tables: tables)
    #expect(old.contentVersion == 2)
    #expect(old.graph.rooms.count == 15)
    #expect(tables.contentVersion == 3)
    #expect(tables.graph.rooms.count == 45)
    #expect(tables.graph.wings.count == 3)
    #expect(tables.graph.rooms.filter { $0.wing == "wing-2" }.count == 15)
    #expect(tables.graph.rooms.filter { $0.wing == "wing-3" }.count == 15)
    #expect(tables.graph.rooms.allSatisfy { !$0.id.isEmpty })
    #expect(tables.goalRoom == "dawn-well")
    #expect(quest.goals.count == 6)
    #expect(tables.fingerprint != old.fingerprint)
}

@Test func crossWingBacktrackAndFinishAreLedgerFacts() throws {
    let tables = try RuleTables.fullDungeon()
    let quest = try QuestEngine.fullDungeon(tables: tables)
    // Patrol-free for a deterministic puzzle proof; the bundled validator
    // separately proves all reachable states can still reach the entrance/goal.
    let puzzle = RuleTables(contentVersion: tables.contentVersion, graph: tables.graph,
        spawnRoom: tables.spawnRoom, switchEffects: tables.switchEffects,
        lockKeys: tables.lockKeys, keySpawns: tables.keySpawns,
        discoverySpawns: tables.discoverySpawns, patrolCycles: [:],
        switchRooms: tables.switchRooms, lockFlags: tables.lockFlags, goalRoom: tables.goalRoom)
    var ledger = try RunLedger(tables: puzzle)
    func visit(_ rooms: [String]) throws {
        for room in rooms { try ledger.append(.visit(room: room), tables: puzzle) }
    }
    try visit(["entrance", "brazier-hall", "sealed-vault", "dust-corridor", "fork", "amber-alcove", "fork", "west-gallery", "bell-niche"])
    try ledger.append(.action(element: "resonant-bell", effects: ["bell-lit"]), tables: puzzle)
    try visit(["west-gallery", "fork", "sentinel-arch", "echo-steps", "stair-landing", "reliquary", "heart-chamber", "ash-threshold", "ink-gallery", "chronicle-aisle"])
    try ledger.append(.discovery(id: "lore-ink"), tables: puzzle)
    try visit(["quiet-stacks", "tide-landing", "lantern-bridge", "slate-crossing", "underkeep-bridge", "night-gate", "basalt-foyer", "moth-court", "glass-corridor", "ember-walk", "spiral-steps"])
    #expect(!RuleEngine.stepResult(try ledger.world(tables: puzzle), .visit(room: "star-anteroom"), tables: puzzle).accepted)
    try visit(["ember-walk", "glass-corridor", "moth-court", "basalt-foyer", "prism-chapel"])
    try ledger.append(.discovery(id: "lore-prism"), tables: puzzle)
    #expect(try quest.progress(for: "borrowed-light", ledger: ledger, tables: puzzle) == .inProgress)
    try visit(["basalt-foyer", "night-gate", "underkeep-bridge", "slate-crossing", "lantern-bridge", "tide-landing", "quiet-stacks", "chronicle-aisle", "memory-seat"])
    try ledger.append(.action(element: "memory-latch", effects: ["memory-lit"]), tables: puzzle)
    #expect(try quest.progress(for: "borrowed-light", ledger: ledger, tables: puzzle) == .achieved)
    try visit(["chronicle-aisle", "quiet-stacks", "tide-landing", "lantern-bridge", "slate-crossing", "underkeep-bridge", "night-gate", "basalt-foyer", "moth-court", "glass-corridor", "ember-walk", "spiral-steps", "star-anteroom", "last-aperture"])
    #expect(!RuleEngine.stepResult(try ledger.world(tables: puzzle), .visit(room: "dawn-well"), tables: puzzle).accepted)
    try visit(["star-anteroom", "spiral-steps", "broken-orbit"])
    try ledger.append(.action(element: "orrery-lens", effects: ["star-lit"]), tables: puzzle)
    try visit(["spiral-steps", "star-anteroom", "last-aperture", "dawn-well"])
    try ledger.append(.discovery(id: "lore-dawn"), tables: puzzle)
    #expect(try quest.progress(for: "dawn", ledger: ledger, tables: puzzle) == .achieved)
    #expect(try ledger.world(tables: puzzle).currentRoom == "dawn-well")
    #expect(try RuleEngine.resume(tables: puzzle, ledger: ledger) == ledger.world(tables: puzzle))
}

@Test func finishOnlyAtGoalInV3AndIsTerminal() throws {
    let v3 = try RuleTables.fullDungeon()
    let puzzle = RuleTables(contentVersion: v3.contentVersion, graph: v3.graph,
        spawnRoom: v3.spawnRoom, switchEffects: v3.switchEffects,
        lockKeys: v3.lockKeys, keySpawns: v3.keySpawns,
        discoverySpawns: v3.discoverySpawns, patrolCycles: [:],
        switchRooms: v3.switchRooms, lockFlags: v3.lockFlags, goalRoom: v3.goalRoom)
    var ledger = try RunLedger(tables: puzzle)
    try ledger.append(.visit(room: "entrance"), tables: puzzle)
    #expect(throws: RunLedger.LedgerError.self) { try ledger.append(.finish, tables: puzzle) }
    // v2 can never finish, even if its goal room were reached.
    let v2 = try RuleTables.wingOne()
    var old = try RunLedger(tables: v2)
    try old.append(.visit(room: "entrance"), tables: v2)
    #expect(throws: RunLedger.LedgerError.self) { try old.append(.finish, tables: v2) }
    #expect(try RuleTables.bundledVersions().map(\.contentVersion) == [3, 2])
    #expect(WorldState(finished: true).isTerminal)
}
