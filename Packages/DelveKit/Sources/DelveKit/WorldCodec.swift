import Foundation

/// Stable canonical serialization for persisted `WorldState` snapshots.
///
/// The synthesized `Codable` conformance on `WorldState` is NOT byte-stable:
/// `JSONEncoder` lays `Set` members out in hash order, which Swift seeds per
/// process and per platform. Anything that persists or compares world state
/// across time/processes (the run ledger, save files, golden fixtures) must
/// go through this codec: set members become sorted arrays and dictionary
/// keys are sorted, yielding identical bytes for identical states.
public enum WorldCodec {
    private struct Canonical: Codable, Equatable {
        var visitedRooms: [String]
        var flags: [String]
        var keys: [String]
        var unlockedLocks: [String]
        var discoveries: [String]
        var patrolStep: Int
        var currentRoom: String?
        var isDead: Bool
        var retreated: Bool
    }

    public static func canonical(_ world: WorldState) throws -> Data {
        let payload = Canonical(
            visitedRooms: world.visitedRooms.sorted(),
            flags: world.flags.sorted(),
            keys: world.keys.sorted(),
            unlockedLocks: world.unlockedLocks.sorted(),
            discoveries: world.discoveries.sorted(),
            patrolStep: world.patrolStep,
            currentRoom: world.currentRoom,
            isDead: world.isDead,
            retreated: world.retreated
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    /// Round-trips `canonical`. Lenient `WorldState` decoding is unaffected;
    /// canonical payloads always carry every field.
    public static func decode(_ data: Data) throws -> WorldState {
        let payload = try JSONDecoder().decode(Canonical.self, from: data)
        return WorldState(
            visitedRooms: Set(payload.visitedRooms),
            flags: Set(payload.flags),
            keys: Set(payload.keys),
            unlockedLocks: Set(payload.unlockedLocks),
            discoveries: Set(payload.discoveries),
            patrolStep: payload.patrolStep,
            currentRoom: payload.currentRoom,
            isDead: payload.isDead,
            retreated: payload.retreated
        )
    }
}
