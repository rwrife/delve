import Foundation
import Testing

@testable import DelveKit

@Suite("RuleEngine rules")
struct RuleEngineTests {
    @Test("graph is versioned data: file loads and equals the in-code tables")
    func graphLoadableAsData() throws {
        // The committed data file is the source of truth; the in-code
        // constant must match it exactly (drift = build stays honest via
        // this test) and it round-trips through Codable (M3 loads bundled
        // files with the identical shape).
        let url = try #require(Bundle.module.url(forResource: "content-v1", withExtension: "json"))
        let loaded = try RuleTables.load(from: url)
        #expect(loaded == .current)
        #expect(loaded.graph.room("sealed-vault")?.wing == "wing-1")
        #expect(loaded.graph.door(between: "brazier-hall", and: "sealed-vault")?.lock == "vault-door")
        #expect(loaded.graph.door(between: "entrance", and: "brazier-hall")?.lock == nil)
        #expect(loaded.graph.door(between: "entrance", and: "sealed-vault") == nil)
    }

    @Test("loader rejects dangling cross-references")
    func loaderRejectsDanglingRefs() {
        #expect(throws: RuleTables.TablesError.danglingReference("door a->ghost")) {
            _ = try RuleTables.load(contentsOf: Data(#"{"contentVersion":9,"spawnRoom":"a","graph":{"schemaVersion":1,"rooms":[{"id":"a","wing":"w"}],"doors":[{"from":"a","to":"ghost","lock":null}],"wings":[{"id":"w"}]},"switchEffects":{},"lockKeys":{},"keySpawns":{},"discoverySpawns":{},"patrolCycles":{}}"#.utf8))
        }
        // Lock without a key binding is dangling too.
        #expect(throws: RuleTables.TablesError.danglingReference("lock nope")) {
            _ = try RuleTables.load(contentsOf: Data(#"{"contentVersion":9,"spawnRoom":"a","graph":{"schemaVersion":1,"rooms":[{"id":"a","wing":"w"},{"id":"b","wing":"w"}],"doors":[{"from":"a","to":"b","lock":"nope"}],"wings":[{"id":"w"}]},"switchEffects":{},"lockKeys":{},"keySpawns":{},"discoverySpawns":{},"patrolCycles":{}}"#.utf8))
        }
        // A spawn room that isn't a real room is dangling too.
        #expect(throws: RuleTables.TablesError.danglingReference("spawnRoom nowhere")) {
            _ = try RuleTables.load(contentsOf: Data(#"{"contentVersion":9,"spawnRoom":"nowhere","graph":{"schemaVersion":1,"rooms":[{"id":"a","wing":"w"}],"doors":[],"wings":[{"id":"w"}]},"switchEffects":{},"lockKeys":{},"keySpawns":{},"discoverySpawns":{},"patrolCycles":{}}"#.utf8))
        }
    }

    @Test("switch effects toggle membership; payload must equal the table")
    func switchEffects() {
        let lit = RuleEngine.step(WorldState(), .action(element: "brazier-left", effects: ["brazier-left"]), tables: .current)
        #expect(lit.flags == ["brazier-left"])
        let unlit = RuleEngine.step(lit, .action(element: "brazier-left", effects: ["brazier-left"]), tables: .current)
        #expect(unlit.flags.isEmpty)

        // A payload that disagrees with the frozen table is rejected —
        // the table alone decides which effects apply.
        let world = WorldState(flags: ["brazier-left"])
        let tampered = RuleEngine.stepResult(world, .action(element: "brazier-left", effects: []), tables: .current)
        #expect(!tampered.accepted)
        #expect(tampered.world == world)
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

    @Test("run spawns only at the table spawn room; unknown rooms rejected")
    func spawnAndUnknownRooms() {
        let start = RuleEngine.step(WorldState(), .visit(room: "entrance"), tables: .current)
        #expect(start.currentRoom == "entrance")
        // First visit anywhere else is rejected — no spawning past the lock.
        let wrongSpawn = RuleEngine.stepResult(WorldState(), .visit(room: "sealed-vault"), tables: .current)
        #expect(!wrongSpawn.accepted)
        let ghost = RuleEngine.stepResult(WorldState(), .visit(room: "ghost-room"), tables: .current)
        #expect(!ghost.accepted)
    }

    @Test("patrol positions derive from patrolStep with wrap-around")
    func patrolDerivation() {
        let rooms0 = RuleEngine.patrolRooms(atStep: 0, tables: .current)
        #expect(rooms0["guard-post"] == "brazier-hall")
        #expect(RuleEngine.patrolRooms(atStep: 1, tables: .current)["guard-post"] == "sealed-vault")
        #expect(RuleEngine.patrolRooms(atStep: 2, tables: .current)["guard-post"] == "entrance")
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

    @Test("contact locks the run down to death: no travel/action/retreat survives contact")
    func contactForcesDeath() {
        // patrolStep 2 puts the guard in `entrance`; stand there via spawn.
        let contact = WorldState(visitedRooms: ["entrance"], patrolStep: 2, currentRoom: "entrance")
        #expect(RuleEngine.inPatrolContact(contact, tables: .current))
        for event in [
            GameEvent.visit(room: "brazier-hall"),
            .action(element: "brazier-left", effects: ["brazier-left"]),
            .discovery(id: "lore-threshold"),
            .retreat,
        ] {
            let result = RuleEngine.stepResult(contact, event, tables: .current)
            #expect(!result.accepted, "\(event) survived contact")
            #expect(result.world == contact)
        }
        // Only death is accepted, and death without contact is rejected.
        let dead = RuleEngine.stepResult(contact, .death, tables: .current)
        #expect(dead.accepted)
        #expect(dead.world.isDead)
        let safe = WorldState(visitedRooms: ["entrance"], patrolStep: 1, currentRoom: "entrance")
        #expect(!RuleEngine.inPatrolContact(safe, tables: .current))
        #expect(!RuleEngine.stepResult(safe, .death, tables: .current).accepted)
        // ...and retreat is accepted when safe.
        #expect(RuleEngine.stepResult(safe, .retreat, tables: .current).accepted)
    }

    @Test("retreat is terminal: further gameplay is rejected")
    func terminalStates() {
        var world = RuleEngine.step(WorldState(), .visit(room: "entrance"), tables: .current)
        world = RuleEngine.step(world, .retreat, tables: .current)
        #expect(world.isTerminal)
        for event in [
            GameEvent.visit(room: "brazier-hall"),
            .action(element: "brazier-left", effects: ["brazier-left"]),
            .discovery(id: "lore-threshold"),
            .retreat,
            .death,
        ] {
            let result = RuleEngine.stepResult(world, event, tables: .current)
            #expect(!result.accepted, "\(event) applied after terminal")
            #expect(result.world == world)
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
        let events: [GameEvent] = [
            .visit(room: "entrance"),
            .discovery(id: "lore-threshold"),
            .action(element: "brazier-left", effects: ["brazier-left"]),
            .visit(room: "brazier-hall"),
            .visit(room: "sealed-vault"),
            .retreat,
        ]
        var ledger = try RunLedger()
        for event in events {
            #expect(try ledger.append(event, tables: .current).sequence == ledger.nextSequence - 1)
        }
        let stepped = RuleEngine.replay(WorldState(), events, tables: .current)
        let resumed = try RuleEngine.resume(tables: .current, ledger: ledger)
        #expect(resumed == stepped)
        #expect(try canonical(resumed) == canonical(stepped))
        #expect(resumed.retreated)
        #expect(resumed.patrolStep == 3)
        #expect(resumed.unlockedLocks == ["vault-door"])
    }

    @Test("ledger append rejects rule-illegal events and keeps sequence gaps impossible")
    func appendRejectsIllegal() throws {
        var ledger = try RunLedger()
        #expect(try ledger.append(.visit(room: "entrance"), tables: .current).sequence == 0)
        // Non-adjacent + locked travel is never ledgered.
        #expect(throws: RunLedger.LedgerError.rejected(.visit(room: "sealed-vault"))) {
            try ledger.append(.visit(room: "sealed-vault"), tables: .current)
        }
        // Payload disagreement with the table is never ledgered.
        #expect(throws: RunLedger.LedgerError.rejected(.action(element: "brazier-left", effects: []))) {
            try ledger.append(.action(element: "brazier-left", effects: []), tables: .current)
        }
        // Death without patrol contact is never ledgered.
        #expect(throws: RunLedger.LedgerError.rejected(.death)) {
            try ledger.append(.death, tables: .current)
        }
        #expect(try ledger.append(.visit(room: "brazier-hall"), tables: .current).sequence == 1)
        #expect(try ledger.append(.retreat, tables: .current).sequence == 2)
        // Post-terminal appends are rejected too.
        #expect(throws: RunLedger.LedgerError.rejected(.visit(room: "entrance"))) {
            try ledger.append(.visit(room: "entrance"), tables: .current)
        }
        #expect(ledger.entries.map(\.sequence) == [0, 1, 2])
    }

    @Test("every ledger initializer path enforces monotonic sequence 0..<count")
    func sequenceValidation() throws {
        let gap = [
            RunLedger.Entry(sequence: 0, event: .visit(room: "entrance")),
            RunLedger.Entry(sequence: 2, event: .visit(room: "entrance")),
        ]
        #expect(throws: RunLedger.LedgerError.nonMonotonicSequence(expected: 1, found: 2)) {
            _ = try RunLedger(entries: gap)
        }
        // Decoded ledgers route through the same validation: wire JSON
        // (canonical eventBase64 rows) with a sequence gap must throw.
        let visitB64 = try EventCodec.canonical(GameEvent.visit(room: "entrance")).base64EncodedString()
        let visitJSON = "{\"eventBase64\":\"\(visitB64)\","
        let badJSON =
            "{\"contentVersion\":1,\"entries\":["
            + visitJSON + "\"sequence\":0},"
            + visitJSON + "\"sequence\":2}]}"
        #expect(throws: RunLedger.LedgerError.nonMonotonicSequence(expected: 1, found: 2)) {
            _ = try JSONDecoder().decode(RunLedger.self, from: Data(badJSON.utf8))
        }
        let ok = [
            RunLedger.Entry(sequence: 0, event: .visit(room: "entrance")),
            RunLedger.Entry(sequence: 1, event: .visit(room: "entrance")),
        ]
        #expect(try RunLedger(entries: ok).entries.count == 2)
    }

    @Test("ledger is pinned to its content version; tables cannot be mutated")
    func contentVersionPinning() throws {
        var ledger = try RunLedger()
        try ledger.append(.visit(room: "entrance"), tables: .current)
        // A different-version table set (constructed the only way content
        // releases can: the full initializer) is refused for both append
        // and resume. RuleTables properties are private(set), so silent
        // in-place reinterpretation of an existing ledger is impossible.
        let future = RuleTables(
            contentVersion: 999,
            graph: RuleTables.current.graph,
            spawnRoom: RuleTables.current.spawnRoom,
            switchEffects: RuleTables.current.switchEffects,
            lockKeys: RuleTables.current.lockKeys,
            keySpawns: RuleTables.current.keySpawns,
            discoverySpawns: RuleTables.current.discoverySpawns,
            patrolCycles: RuleTables.current.patrolCycles
        )
        #expect(throws: RunLedger.LedgerError.contentVersionMismatch(ledger: 1, tables: 999)) {
            try ledger.append(.visit(room: "brazier-hall"), tables: future)
        }
        #expect(throws: RunLedger.LedgerError.contentVersionMismatch(ledger: 1, tables: 999)) {
            _ = try RuleEngine.resume(tables: future, ledger: ledger)
        }
        // Same events against matching version still work.
        #expect(try ledger.append(.visit(room: "brazier-hall"), tables: .current).sequence == 1)
    }

    @Test("restoring a hand-built ledger with rule-illegal events throws")
    func restoredLedgersAreRuleValidated() throws {
        struct Row: Encodable {
            var eventBase64: String
            var sequence: Int
        }
        struct LedgerWire: Encodable {
            var contentVersion: Int
            var entries: [Row]
        }
        func ledgerJSON(rows: [Row]) throws -> Data {
            try JSONEncoder().encode(LedgerWire(contentVersion: 1, entries: rows))
        }
        func row(_ event: GameEvent, _ sequence: Int) throws -> Row {
            Row(eventBase64: try EventCodec.canonical(event).base64EncodedString(), sequence: sequence)
        }

        // A ledger whose first event is a no-contact death decodes (the
        // event itself is well-formed) but resume must reject it — never
        // silently skip it.
        let restored = try JSONDecoder().decode(
            RunLedger.self,
            from: ledgerJSON(rows: [row(.death, 0)])
        )
        #expect(throws: RunLedger.LedgerError.rejected(.death)) {
            _ = try RuleEngine.resume(tables: .current, ledger: restored)
        }
        // A post-terminal tail is rejected on restore too.
        let tailLedger = try JSONDecoder().decode(
            RunLedger.self,
            from: ledgerJSON(rows: [
                try row(.visit(room: "entrance"), 0),
                try row(.retreat, 1),
                try row(.visit(room: "brazier-hall"), 2),
            ])
        )
        #expect(throws: RunLedger.LedgerError.rejected(.visit(room: "brazier-hall"))) {
            _ = try RuleEngine.resume(tables: .current, ledger: tailLedger)
        }
        // Non-canonical event payloads inside ledger JSON are rejected at
        // the decode boundary (extra key present).
        let nonCanonicalRow = Row(
            eventBase64: Data(#"{"visit":{"room":"entrance"},"extra":true}"#.utf8).base64EncodedString(),
            sequence: 0
        )
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(RunLedger.self, from: ledgerJSON(rows: [nonCanonicalRow]))
        }
    }

    @Test("ledger Codable round-trips through validated decoding")
    func ledgerCodableRoundTrip() throws {
        var ledger = try RunLedger()
        try ledger.append(.visit(room: "entrance"), tables: .current)
        try ledger.append(.retreat, tables: .current)
        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(RunLedger.self, from: data)
        #expect(decoded == ledger)
        #expect(decoded.contentVersion == RuleTables.current.contentVersion)
    }

    @Test("event canonical bytes round-trip, stay stable, and reject drift")
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
        // Garbage and non-canonical bytes never decode silently.
        #expect(throws: (any Error).self) {
            try EventCodec.decode(Data(#"{"kind":"teleport"}"#.utf8))
        }
        // A canonical event with an extra key carries the same value but is
        // not canonical bytes => rejected.
        #expect(throws: EventCodec.EventDecodingError.nonCanonical) {
            try EventCodec.decode(Data(#"{"visit":{"room":"entrance"},"extra":true}"#.utf8))
        }
    }

    @Test("death run replays byte-identically through the ledger")
    func deathRunReplays() throws {
        var ledger = try RunLedger()
        for room in ["entrance", "brazier-hall", "sealed-vault", "brazier-hall", "entrance"] {
            try ledger.append(.visit(room: room), tables: .current)
        }
        var world = try RuleEngine.resume(tables: .current, ledger: ledger)
        #expect(RuleEngine.inPatrolContact(world, tables: .current))
        try ledger.append(.death, tables: .current)
        world = try RuleEngine.resume(tables: .current, ledger: ledger)
        #expect(world.isDead)

        // Independent step-by-step replay of the same ledger events.
        let replayed = RuleEngine.replay(WorldState(), ledger.entries.map(\.event), tables: .current)
        #expect(replayed == world)
        #expect(try canonical(replayed) == canonical(world))
    }
}
