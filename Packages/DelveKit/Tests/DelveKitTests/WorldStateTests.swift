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
    }

    @Test("world round-trips through Codable with stable equality")
    func codableRoundTrip() throws {
        let world = WorldState(
            visitedRooms: ["entrance", "brazier-hall"],
            flags: ["brazier-left"],
            keys: ["bronze-key"]
        )
        let data = try JSONEncoder().encode(world)
        let decoded = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(decoded == world)
    }
}

@Suite("RuleEngine determinism")
struct RuleEngineTests {
    @Test("step stubs apply pure transitions")
    func stubTransitions() {
        let start = WorldState()
        let moved = RuleEngine.step(start, .move(to: "entrance"))
        #expect(moved.visitedRooms == ["entrance"])

        let lit = RuleEngine.step(moved, .toggle(switchID: "brazier-left"))
        #expect(lit.flags == ["brazier-left"])

        let unlit = RuleEngine.step(lit, .toggle(switchID: "brazier-left"))
        #expect(unlit.flags.isEmpty)
        #expect(unlit.visitedRooms == moved.visitedRooms)

        let armed = RuleEngine.step(unlit, .pickUp(key: "bronze-key"))
        #expect(armed.keys == ["bronze-key"])
    }

    @Test("identical replays produce identical state and canonical bytes")
    func replayIsDeterministic() throws {
        let commands: [Command] = [
            .move(to: "entrance"),
            .toggle(switchID: "brazier-left"),
            .move(to: "brazier-hall"),
            .pickUp(key: "bronze-key"),
            .toggle(switchID: "idol-plinth"),
            .move(to: "sealed-door"),
            .toggle(switchID: "brazier-left"),
        ]
        let first = RuleEngine.replay(WorldState(), commands)
        let second = RuleEngine.replay(WorldState(), commands)
        #expect(first == second)

        // Canonical serialization: JSONEncoder lays out Set members in
        // hash order, which Swift seeds per process, so raw encode bytes of
        // two equal states may differ across runs. The canonical form
        // (sorted members) must be byte-identical — that is the durable
        // determinism contract the ledger and save files rely on.
        func canonical(_ world: WorldState) -> Data {
            let payload: [String: [String]] = [
                "visitedRooms": world.visitedRooms.sorted(),
                "flags": world.flags.sorted(),
                "keys": world.keys.sorted(),
            ]
            // Dictionary key order in JSONEncoder output is unspecified and
            // platform-dependent (observed to differ between two equal
            // payloads within one process on the macOS/Darwin runtime while
            // the Linux runtime happened to agree). .sortedKeys is the
            // documented deterministic formatting — the same guarantee the
            // ledger and save files will rely on.
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return (try? encoder.encode(payload)) ?? Data()
        }
        #expect(canonical(first) == canonical(second))
    }
}
