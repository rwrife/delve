import Foundation
import Testing

@testable import DelveKit

@Suite("RuleEngine rules")
struct RuleEngineTests {
    @Test("graph is versioned data: JSON round-trip preserves every field")
    func graphLoadableAsData() throws {
        // Proves the topology is plain versioned data (M3 loads the exact
        // same shapes from bundled files) — no code is baked into rooms.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(RuleTables.current.graph)
        let decoded = try JSONDecoder().decode(RoomGraph.self, from: data)
        #expect(decoded == RuleTables.current.graph)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.room("sealed-vault")?.wing == "wing-1")
        #expect(decoded.door(between: "brazier-hall", and: "sealed-vault")?.lock == "vault-door")
        #expect(decoded.door(between: "entrance", and: "brazier-hall")?.lock == nil)
        #expect(decoded.door(between: "entrance", and: "sealed-vault") == nil)
    }

    @Test("switch effects toggle membership")
    func switchEffects() {
        let lit = RuleEngine.step(WorldState(), .action(element: "brazier-left", effects: ["brazier-left"]), tables: .current)
        #expect(lit.flags == ["brazier-left"])
        let unlit = RuleEngine.step(lit, .action(element: "brazier-left", effects: ["brazier-left"]), tables: .current)
        #expect(unlit.flags.isEmpty)
    }

    @Test("unknown element is rejected and leaves state untouched")
    func unknownElementRejected() {
        let world = WorldState()
        let result = RuleEngine.stepResult(world, .action(element: "no-such-lever", effects: ["x"]), tables: .current)
        #expect(!result.accepted)
        #expect(result.world == world)
    }

    @Test("lock opens only with its key, permanently and ledgered once")
    func lockKeyBinding() {
        var world = RuleEngine.step(WorldState(), .visit(room: "entrance"), tables: .current)
        // Locked door: brazier-hall -> sealed-vault needs bronze-key via vault-door.
        world = RuleEngine.step(world, .visit(room: "brazier-hall"), tables: .current)
        #expect(world.keys.contains("bronze-key")) // picked up in brazier-hall

        let vault = RuleEngine.stepResult(world, .visit(room: "sealed-vault"), tables: .current)
        #expect(vault.accepted)
        #expect(vault.world.unlockedLocks == ["vault-door"])

        // Without the key the same travel is rejected.
        let noKey = WorldState(visitedRooms: ["brazier-hall"], patrolStep: 2, currentRoom: "brazier-hall")
        let blocked = RuleEngine.stepResult(noKey, .visit(room: "sealed-vault"), tables: .current)
        #expect(!blocked.accepted)
        #expect(blocked.world == noKey)
    }

    @Test("illegal travel between non-adjacent rooms is rejected")
    func illegalTravel() {
        let world = RuleEngine.step(WorldState(), .visit(room: "entrance"), tables: .current)
        let result = RuleEngine.stepResult(world, .visit(room: "sealed-vault"), tables: .current)
        #expect(!result.accepted)
        #expect(result.world == world)
    }

    @Test("first visit is legal anywhere (run spawn), unknown rooms rejected")
    func spawnAndUnknownRooms() {
        let start = RuleEngine.step(WorldState(), .visit(room: "brazier-hall"), tables: .current)
        #expect(start.currentRoom == "brazier-hall")
        let ghost = RuleEngine.stepResult(WorldState(), .visit(room: "ghost-room"), tables: .current)
        #expect(!ghost.accepted)
    }

    @Test("patrol positions derive from patrolStep with wrap-around")
    func patrolDerivation() {
        let rooms0 = RuleEngine.patrolRooms(atStep: 0, tables: .current)
        #expect(rooms0["guard-post"] == "brazier-hall")
        #expect(RuleEngine.patrolRooms(atStep: 1, tables: .current)["guard-post"] == "sealed-vault")
        #expect(RuleEngine.patrolRooms(atStep: 2, tables: .current)["guard-post"] == "entrance")
        // Same position at step n and n + cycle length (pure modulo cycle).
        #expect(RuleEngine.patrolRooms(atStep: 3, tables: .current) == rooms0)
        #expect(RuleEngine.patrolRooms(atStep: 102, tables: .current)["guard-post"] == "brazier-hall")
    }

    @Test("patrol contact is derived from world state, not stored in it")
    func patrolContact() {
        // Hero walks the 5-move death line: entrance, brazier-hall,
        // sealed-vault, brazier-hall, entrance. After the 5th visit
        // patrolStep == 5 and the guard's cycle lands on "entrance".
        var world = WorldState()
        for room in ["entrance", "brazier-hall", "sealed-vault", "brazier-hall", "entrance"] {
            let result = RuleEngine.stepResult(world, .visit(room: room), tables: .current)
            #expect(result.accepted, "unexpected rejection visiting \(room)")
            world = result.world
        }
        #expect(world.currentRoom == "entrance")
        #expect(world.patrolStep == 5)
        #expect(RuleEngine.inPatrolContact(world, tables: .current))
        // The world itself stores no patrol data — positions recompute.
        let killed = RuleEngine.step(world, .death, tables: .current)
        #expect(killed.isDead)
        #expect(!RuleEngine.inPatrolContact(killed, tables: .current)) // terminal: no contact
    }

    @Test("death and retreat are terminal: further gameplay is rejected")
    func terminalStates() {
        for end in [GameEvent.death, .retreat] {
            var world = RuleEngine.step(WorldState(), .visit(room: "entrance"), tables: .current)
            world = RuleEngine.step(world, end, tables: .current)
            #expect(world.isTerminal)
            let later = RuleEngine.stepResult(world, .visit(room: "brazier-hall"), tables: .current)
            #expect(!later.accepted)
            #expect(later.world == world)
            let endAgain = RuleEngine.stepResult(world, end, tables: .current)
            #expect(!endAgain.accepted)
        }
    }

    @Test("discovery requires the hero to have visited its room; repeat is no-change")
    func discoveryRules() {
        let fresh = RuleEngine.stepResult(WorldState(), .discovery(id: "lore-threshold"), tables: .current)
        #expect(!fresh.accepted) // not visited yet

        let visited = RuleEngine.step(WorldState(), .visit(room: "entrance"), tables: .current)
        let found = RuleEngine.stepResult(visited, .discovery(id: "lore-threshold"), tables: .current)
        #expect(found.accepted)
        #expect(found.world.discoveries == ["lore-threshold"])

        let again = RuleEngine.stepResult(found.world, .discovery(id: "lore-threshold"), tables: .current)
        #expect(again.accepted)
        #expect(again.world == found.world) // idempotent
    }
}

@Suite("RuleEngine determinism")
struct DeterminismTests {
    private func canonical(_ world: WorldState) throws -> Data {
        try WorldCodec.canonical(world)
    }

    @Test("identical event sequences produce byte-identical canonical state")
    func replayIsDeterministic() throws {
        let events: [GameEvent] = [
            .visit(room: "entrance"),
            .discovery(id: "lore-threshold"),
            .action(element: "brazier-left", effects: ["brazier-left"]),
            .visit(room: "brazier-hall"),
            .action(element: "idol-plinth", effects: ["idol-plinth"]),
            .visit(room: "sealed-vault"),
            .action(element: "brazier-left", effects: ["brazier-left"]),
        ]
        let first = RuleEngine.replay(WorldState(), events, tables: .current)
        let second = RuleEngine.replay(WorldState(), events, tables: .current)
        #expect(first == second)
        #expect(try canonical(first) == canonical(second))
    }

    @Test("ledger resume equals step-by-step replay exactly")
    func resumeEqualsReplay() throws {
        var ledger = RunLedger()
        let events: [GameEvent] = [
            .visit(room: "entrance"),
            .discovery(id: "lore-threshold"),
            .action(element: "brazier-left", effects: ["brazier-left"]),
            .visit(room: "brazier-hall"),
            .visit(room: "sealed-vault"),
            .retreat,
        ]
        for event in events {
            #expect(try ledger.append(event, tables: .current).sequence == ledger.nextSequence - 1)
        }
        let stepped = RuleEngine.replay(WorldState(), events, tables: .current)
        let resumed = RuleEngine.resume(tables: .current, ledger: ledger)
        #expect(resumed == stepped)
        #expect(try canonical(resumed) == canonical(stepped))
        #expect(resumed.retreated)
        #expect(resumed.patrolStep == 3)
        #expect(resumed.unlockedLocks == ["vault-door"])
    }

    @Test("ledger append rejects rule-illegal events and keeps sequence gaps impossible")
    func appendRejectsIllegal() throws {
        var ledger = RunLedger()
        #expect(try ledger.append(.visit(room: "entrance"), tables: .current).sequence == 0)
        // Non-adjacent + locked travel is never ledgered.
        #expect(throws: RunLedger.LedgerError.rejected(.visit(room: "sealed-vault"))) {
            try ledger.append(.visit(room: "sealed-vault"), tables: .current)
        }
        // Post-terminal appends are rejected too.
        #expect(try ledger.append(.visit(room: "brazier-hall"), tables: .current).sequence == 1)
        #expect(try ledger.append(.death, tables: .current).sequence == 2)
        #expect(throws: RunLedger.LedgerError.rejected(.visit(room: "entrance"))) {
            try ledger.append(.visit(room: "entrance"), tables: .current)
        }
        #expect(ledger.entries.map(\.sequence) == [0, 1, 2])
    }

    @Test("validated init enforces monotonic sequence 0..<count")
    func sequenceValidation() throws {
        let gap = [
            RunLedger.Entry(sequence: 0, event: .visit(room: "entrance")),
            RunLedger.Entry(sequence: 2, event: .visit(room: "entrance")),
        ]
        #expect(throws: RunLedger.LedgerError.nonMonotonicSequence(expected: 1, found: 2)) {
            _ = try RunLedger(validated: gap)
        }
        let ok = [
            RunLedger.Entry(sequence: 0, event: .visit(room: "entrance")),
            RunLedger.Entry(sequence: 1, event: .visit(room: "entrance")),
        ]
        #expect(try RunLedger(validated: ok).entries.count == 2)
    }

    @Test("event canonical bytes round-trip and stay stable")
    func eventCodecStability() throws {
        let events: [GameEvent] = [
            .visit(room: "entrance"),
            .action(element: "brazier-left", effects: ["brazier-left", "idol-plinth"]),
            .discovery(id: "lore-threshold"),
            .death,
            .retreat,
        ]
        for event in events {
            let bytes = try EventCodec.canonical(event)
            #expect(try EventCodec.decode(bytes) == event)
            for _ in 0..<50 {
                #expect(try EventCodec.canonical(event) == bytes)
            }
        }
        // Garbage never decodes.
        #expect(throws: (any Error).self) {
            try EventCodec.decode(Data(#"{"kind":"teleport"}"#.utf8))
        }
    }

    @Test("death run replays byte-identically through the ledger")
    func deathRunReplays() throws {
        var ledger = RunLedger()
        for room in ["entrance", "brazier-hall", "sealed-vault", "brazier-hall", "entrance"] {
            try ledger.append(.visit(room: room), tables: .current)
        }
        var world = RuleEngine.resume(tables: .current, ledger: ledger)
        #expect(RuleEngine.inPatrolContact(world, tables: .current))
        try ledger.append(.death, tables: .current)
        world = RuleEngine.resume(tables: .current, ledger: ledger)
        #expect(world.isDead)

        // Independent step-by-step replay of the same ledger events.
        let replayed = RuleEngine.replay(WorldState(), ledger.entries.map(\.event), tables: .current)
        #expect(replayed == world)
        #expect(try canonical(replayed) == canonical(world))
    }
}
