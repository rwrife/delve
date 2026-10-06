import Foundation
import Testing
@testable import DelveKit

@Suite("Wing 1 content and puzzle proof")
struct WingOneTests {
    private func tables() throws -> RuleTables { try RuleTables.wingOne() }

    private func copy(_ t: RuleTables, graph: RoomGraph? = nil,
                      keySpawns: [String: String]? = nil,
                      switchRooms: [String: String]? = nil,
                      lockFlags: [String: [String]]? = nil) -> RuleTables {
        RuleTables(contentVersion: t.contentVersion, graph: graph ?? t.graph,
            spawnRoom: t.spawnRoom, switchEffects: t.switchEffects,
            lockKeys: t.lockKeys, keySpawns: keySpawns ?? t.keySpawns,
            discoverySpawns: t.discoverySpawns, patrolCycles: t.patrolCycles,
            switchRooms: switchRooms ?? t.switchRooms,
            lockFlags: lockFlags ?? t.lockFlags, goalRoom: t.goalRoom)
    }

    @Test("v2 is bundled and exhaustively validated; v1 remains pinned")
    func bundledAndPinned() throws {
        let t = try tables()
        #expect(t.graph.rooms.count == 15)
        #expect(t.contentVersion == 2)
        #expect(t.graph.schemaVersion == 2)
        #expect(t.graph.rooms.allSatisfy { $0.wing == "wing-1" })
        #expect(t.goalRoom == "heart-chamber")
        try GraphValidator.validate(t)
        let old = try RuleTables.load(from: #require(Bundle.module.url(forResource: "content-v1", withExtension: "json")))
        #expect(old == .current)
        #expect(old.fingerprint == RuleTables.current.fingerprint)
        #expect(old.fingerprint != t.fingerprint)
    }

    @Test("blind route has no prize; backtracking to key and bell is required")
    func chain() throws {
        let t = try tables()
        var ledger = try RunLedger(tables: t)
        for room in ["entrance", "brazier-hall", "sealed-vault", "dust-corridor", "fork"] {
            try ledger.append(.visit(room: room), tables: t)
        }
        #expect(throws: RunLedger.LedgerError.rejected(.visit(room: "sentinel-arch"))) {
            try ledger.append(.visit(room: "sentinel-arch"), tables: t)
        }
        // A four-visit detour shifts the patrol phase: the false crypt
        // becomes safe to explore, then the only exit is back through fork.
        for room in ["amber-alcove", "fork", "west-gallery", "fork", "blind-crypt", "ossuary"] {
            try ledger.append(.visit(room: room), tables: t)
        }
        #expect(try ledger.world(tables: t).keys.contains("bronze-key"))
        #expect(t.graph.connections(from: "ossuary").map(\.neighbor) == ["blind-crypt"])
        try ledger.append(.discovery(id: "lore-silence"), tables: t)
        for room in ["blind-crypt", "fork", "west-gallery", "bell-niche"] {
            try ledger.append(.visit(room: room), tables: t)
        }
        try ledger.append(.action(element: "resonant-bell", effects: ["bell-lit"]), tables: t)
        for room in ["west-gallery", "fork", "sentinel-arch", "echo-steps", "stair-landing", "reliquary"] {
            try ledger.append(.visit(room: room), tables: t)
        }
        try ledger.append(.discovery(id: "lore-echo"), tables: t)
        try ledger.append(.visit(room: "heart-chamber"), tables: t)
        let quest = try QuestEngine.wingOne(tables: t)
        for goal in quest.goals {
            #expect(try quest.progress(for: goal.id, ledger: ledger, tables: t) == .achieved)
        }
        #expect(try ledger.world(tables: t).unlockedLocks == ["arch-door", "heart-door"])
        #expect(try ledger.world(tables: t).currentRoom == "heart-chamber")
        // The permanent door latch makes returning to the entrance safe even
        // after the bell is toggled off on a subsequent pass.
        for room in ["reliquary", "stair-landing", "echo-steps", "sentinel-arch", "fork", "dust-corridor", "sealed-vault", "brazier-hall", "entrance"] {
            try ledger.append(.visit(room: room), tables: t)
        }
        #expect(try ledger.world(tables: t).currentRoom == "entrance")
    }

    @Test("actions are location-bound; flag and key both gate the final door")
    func gate() throws {
        let t = try tables()
        let start = RuleEngine.step(WorldState(), .visit(room: "entrance"), tables: t)
        #expect(!RuleEngine.stepResult(start, .action(element: "resonant-bell", effects: ["bell-lit"]), tables: t).accepted)
        let atDoor = WorldState(visitedRooms: ["reliquary"], keys: ["bronze-key"],
            unlockedLocks: ["arch-door"], currentRoom: "reliquary")
        #expect(!RuleEngine.stepResult(atDoor, .visit(room: "heart-chamber"), tables: t).accepted)
        let lit = WorldState(visitedRooms: ["reliquary"], flags: ["bell-lit"],
            unlockedLocks: ["arch-door"], currentRoom: "reliquary")
        #expect(!RuleEngine.stepResult(lit, .visit(room: "heart-chamber"), tables: t).accepted)
        let ready = WorldState(visitedRooms: ["reliquary"], flags: ["bell-lit"], keys: ["bronze-key"],
            unlockedLocks: ["arch-door"], currentRoom: "reliquary")
        #expect(RuleEngine.stepResult(ready, .visit(room: "heart-chamber"), tables: t).accepted)
    }

    @Test("broken content fails the bundled loader's graph proof")
    func rejectsBrokenContent() throws {
        let t = try tables()
        let disconnected = RoomGraph(schemaVersion: 2, rooms: t.graph.rooms,
            doors: t.graph.doors.filter { $0.to != "amber-alcove" }, wings: t.graph.wings)
        #expect(throws: GraphValidator.ValidationError.disconnected("amber-alcove")) {
            try GraphValidator.validate(copy(t, graph: disconnected))
        }
        #expect(throws: GraphValidator.ValidationError.unreachable("echo-steps")) {
            try GraphValidator.validate(copy(t, keySpawns: ["bronze-key": "heart-chamber"]))
        }
        #expect(throws: GraphValidator.ValidationError.unreachable("heart-chamber")) {
            try GraphValidator.validate(copy(t, switchRooms: ["brazier-left": "brazier-hall", "resonant-bell": "heart-chamber"]))
        }
        let duplicate = RoomGraph(schemaVersion: 2, rooms: t.graph.rooms + [t.graph.rooms[0]], doors: t.graph.doors, wings: t.graph.wings)
        #expect(throws: GraphValidator.ValidationError.malformed("duplicate/missing rooms or wings, or invalid version")) {
            try GraphValidator.validate(copy(t, graph: duplicate))
        }
        // load() invokes the same validator, not just tests.
        let data = try JSONEncoder().encode(copy(t, keySpawns: ["bronze-key": "heart-chamber"]))
        #expect(throws: GraphValidator.ValidationError.unreachable("echo-steps")) {
            _ = try RuleTables.load(contentsOf: data)
        }
    }

    @Test("patrol cycle is deterministic; contact forces death, alternate timing survives")
    func patrol() throws {
        let t = try tables()
        #expect((0..<7).map { t.patrolRoom("crypt-watcher", atStep: $0) } ==
                ["blind-crypt", "ossuary", "blind-crypt", "ossuary", "blind-crypt", "ossuary", "ossuary"])
        var world = WorldState()
        for room in ["entrance", "brazier-hall", "sealed-vault", "dust-corridor", "fork",
                     "amber-alcove", "fork", "west-gallery", "bell-niche", "west-gallery",
                     "fork", "blind-crypt", "ossuary"] {
            let result = RuleEngine.stepResult(world, .visit(room: room), tables: t)
            #expect(result.accepted)
            world = result.world
        }
        #expect(RuleEngine.inPatrolContact(world, tables: t))
        #expect(!RuleEngine.stepResult(world, .visit(room: "blind-crypt"), tables: t).accepted)
        #expect(RuleEngine.stepResult(world, .death, tables: t).world.isDead)
        var direct = WorldState()
        for room in ["entrance", "brazier-hall", "sealed-vault", "dust-corridor", "fork",
                     "blind-crypt", "ossuary", "blind-crypt", "fork"] {
            let result = RuleEngine.stepResult(direct, .visit(room: room), tables: t)
            #expect(result.accepted)
            direct = result.world
            #expect(!RuleEngine.inPatrolContact(direct, tables: t))
        }
        #expect(direct.currentRoom == "fork")
    }
}

@Suite("Ledger-only quest derivation")
struct WingQuestTests {
    @Test("completion without the preceding clue remains unknown, even after unrelated events")
    func missingPrerequisite() throws {
        let t = try RuleTables.wingOne()
        let quest = try QuestEngine.wingOne(tables: t)
        var ledger = try RunLedger(tables: t)
        for room in ["entrance", "brazier-hall", "sealed-vault", "dust-corridor", "fork",
                     "west-gallery", "bell-niche"] {
            try ledger.append(.visit(room: room), tables: t)
        }
        try ledger.append(.action(element: "resonant-bell", effects: ["bell-lit"]), tables: t)
        #expect(try quest.progress(for: "answer", ledger: ledger, tables: t) == .unknown)
        for room in ["west-gallery", "fork", "amber-alcove", "fork", "sentinel-arch",
                     "echo-steps", "stair-landing", "reliquary", "heart-chamber"] {
            try ledger.append(.visit(room: room), tables: t)
        }
        #expect(try quest.progress(for: "heart", ledger: ledger, tables: t) == .unknown)
        // Discovering the clue after the completion event cannot retroactively
        // certify the older event as completion of a layered goal.
        try ledger.append(.discovery(id: "lore-echo"), tables: t)
        #expect(try quest.progress(for: "heart", ledger: ledger, tables: t) == .inProgress)
    }

    @Test("missing evidence never becomes known, including after unrelated visits")
    func unknownIsUnknown() throws {
        let t = try RuleTables.wingOne()
        let quest = try QuestEngine.wingOne(tables: t)
        var ledger = try RunLedger(tables: t)
        for goal in quest.goals { #expect(try quest.progress(for: goal.id, ledger: ledger, tables: t) == .unknown) }
        for room in ["entrance", "brazier-hall", "sealed-vault", "dust-corridor", "fork"] {
            try ledger.append(.visit(room: room), tables: t)
        }
        #expect(try quest.progress(for: "silence", ledger: ledger, tables: t) == .inProgress)
        #expect(try quest.progress(for: "answer", ledger: ledger, tables: t) == .unknown)
        #expect(try quest.progress(for: "heart", ledger: ledger, tables: t) == .unknown)
        #expect(try JSONEncoder().encode(ledger).count > 0)
        let restored = try JSONDecoder().decode(RunLedger.self, from: JSONEncoder().encode(ledger))
        #expect(try quest.progress(for: "heart", ledger: restored, tables: t) == .unknown)
    }

    @Test("goal progress follows ledger events, not arbitrary world flags")
    func goalEvidence() throws {
        let t = try RuleTables.wingOne()
        let quest = try QuestEngine.wingOne(tables: t)
        var ledger = try RunLedger(tables: t)
        for room in ["entrance", "brazier-hall", "sealed-vault", "dust-corridor", "fork", "amber-alcove", "fork", "west-gallery", "fork", "blind-crypt", "ossuary"] {
            try ledger.append(.visit(room: room), tables: t)
        }
        #expect(try quest.progress(for: "silence", ledger: ledger, tables: t) == .inProgress)
        try ledger.append(.discovery(id: "lore-silence"), tables: t)
        #expect(try quest.progress(for: "silence", ledger: ledger, tables: t) == .achieved)
        #expect(try quest.progress(for: "answer", ledger: ledger, tables: t) == .inProgress)
        for room in ["blind-crypt", "fork", "west-gallery", "bell-niche"] {
            try ledger.append(.visit(room: room), tables: t)
        }
        try ledger.append(.action(element: "resonant-bell", effects: ["bell-lit"]), tables: t)
        #expect(try quest.progress(for: "answer", ledger: ledger, tables: t) == .achieved)
        #expect(try quest.progress(for: "heart", ledger: ledger, tables: t) == .unknown)
        #expect(throws: QuestEngine.QuestError.invalidDefinition("heart")) {
            _ = try quest.progress(for: "heart", ledger: ledger, tables: .current)
        }
    }
}
