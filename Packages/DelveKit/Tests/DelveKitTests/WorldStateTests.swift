import Foundation
import Testing

@testable import DelveKit

@Suite("WorldState contract")
struct WorldStateTests {
    @Test("empty world starts blank")
    func emptyWorld() {
        let world = WorldState()
        #expect(world.visitedRooms.isEmpty)
        #expect(world.flags.isEmpty)
        #expect(world.keys.isEmpty)
        #expect(world.unlockedLocks.isEmpty)
        #expect(world.discoveries.isEmpty)
        #expect(world.patrolStep == 0)
        #expect(world.currentRoom == nil)
        #expect(!world.isTerminal)
    }

    @Test("legacy M1 snapshot JSON decodes forward-compatibly")
    func legacySnapshotDecodes() throws {
        // Exactly what M1's synthesized encoder produced (the committed
        // DelveStore v1.sqlite fixture stores this shape) — the three
        // original sets and nothing else.
        let legacy = Data(
            #"{"visitedRooms":["entrance","brazier-hall"],"flags":["brazier-left"],"keys":["bronze-key"]}"#
                .utf8
        )
        let world = try JSONDecoder().decode(WorldState.self, from: legacy)
        #expect(world.flags == ["brazier-left"])
        #expect(world.visitedRooms == ["entrance", "brazier-hall"])
        #expect(world.keys == ["bronze-key"])
        #expect(world.unlockedLocks.isEmpty)
        #expect(world.discoveries.isEmpty)
        #expect(world.patrolStep == 0)
        #expect(world.currentRoom == nil)
        #expect(!world.isTerminal)
    }

    @Test("canonical codec round-trips and survives legacy field absence")
    func canonicalRoundTrip() throws {
        let world = WorldState(
            visitedRooms: ["entrance", "brazier-hall"],
            flags: ["brazier-left"],
            keys: ["bronze-key"],
            unlockedLocks: ["vault-door"],
            discoveries: ["lore-threshold"],
            patrolStep: 3,
            currentRoom: "sealed-vault",
            isDead: false,
            retreated: true
        )
        let data = try WorldCodec.canonical(world)
        let decoded = try WorldCodec.decode(data)
        #expect(decoded == world)

        // Canonical bytes must also decode through the lenient synthesized
        // path (extra sorted-array fields are set-compatible).
        let lenient = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(lenient == world)
    }
}

@Suite("WorldCodec determinism")
struct WorldCodecTests {
    @Test("equal states encode to byte-identical canonical bytes")
    func equalStatesSameBytes() throws {
        var a = WorldState()
        var b = WorldState()
        // Build two equal worlds via different insertion orders so any
        // residual Set-order leakage would surface in the bytes.
        let events1: [GameEvent] = [
            .visit(room: "entrance"),
            .action(element: "brazier-left", effects: ["brazier-left"]),
            .visit(room: "brazier-hall"),
            .discovery(id: "lore-threshold"),
        ]
        let events2: [GameEvent] = [
            .visit(room: "entrance"),
            .discovery(id: "lore-threshold"),
            .action(element: "brazier-left", effects: ["brazier-left"]),
            .visit(room: "brazier-hall"),
        ]
        a = RuleEngine.replay(a, events1, tables: .current)
        b = RuleEngine.replay(b, events2, tables: .current)
        #expect(a == b)
        #expect(try WorldCodec.canonical(a) == WorldCodec.canonical(b))

        // Repeated encodes of the same state are identical (100x to defeat
        // per-process hash seeding variance).
        let first = try WorldCodec.canonical(a)
        for _ in 0..<100 {
            #expect(try WorldCodec.canonical(a) == first)
        }
    }

    @Test("canonical key order is fixed regardless of dictionary layout")
    func canonicalKeysSorted() throws {
        let world = WorldState(flags: ["brazier-left"], patrolStep: 1, currentRoom: "entrance")
        let bytes = try #require(String(data: try WorldCodec.canonical(world), encoding: .utf8))
        // Field order must be alphabetical (.sortedKeys).
        let fieldNames = ["currentRoom", "discoveries", "flags", "isDead", "keys",
                          "patrolStep", "retreated", "unlockedLocks", "visitedRooms"]
        var lastIndex = bytes.startIndex
        for field in fieldNames {
            guard let found = bytes.range(of: "\"\(field)\""), found.lowerBound >= lastIndex else {
                Issue.record("canonical JSON missing field \(field) in sorted order: \(bytes)")
                return
            }
            lastIndex = found.upperBound
        }
    }
}
