import Foundation

/// The complete observable state of the fixed dungeon at one point in a run.
///
/// Value semantics with deterministic, replayable content: the same world
/// plus the same event sequence always produces the same resulting state.
/// Room identifiers are stable strings defined by the fixed room graph
/// (`RuleTables`); nothing here is randomly generated.
///
/// Durable encoding rule: persisted snapshots MUST be produced through
/// `WorldCodec.canonical` (sorted members + `.sortedKeys`). The synthesized
/// `Codable` conformance is kept for convenience/compat but `Set` member
/// order in `JSONEncoder` output is unspecified, so it is never byte-stable.
public struct WorldState: Equatable, Codable, Sendable {
    /// Rooms the hero has entered at least once.
    public var visitedRooms: Set<String>

    /// Toggle-style puzzle elements currently "on" (lit braziers, thrown
    /// levers, pressed tiles). Membership is the whole truth.
    public var flags: Set<String>

    /// Key items currently in the hero's possession.
    public var keys: Set<String>

    /// Locks the hero has opened (with a matching key). Opening is
    /// permanent within a run.
    public var unlockedLocks: Set<String>

    /// Content discovery identifiers already recorded (journal entries,
    /// lore, quest hooks). Membership is the whole truth.
    public var discoveries: Set<String>

    /// Number of successful `visit` moves so far. Patrol positions derive
    /// from this count and the (fixed, versioned) patrol cycles, so the
    /// whole world stays a pure function of the event sequence.
    public var patrolStep: Int

    /// The room the hero currently occupies, i.e. the target of the last
    /// accepted `visit`. Nil before the run's first room entry.
    public var currentRoom: String?

    /// The run ended in death; gameplay events no longer mutate the world.
    public var isDead: Bool

    /// The run ended in a deliberate retreat; gameplay events no longer
    /// mutate the world.
    public var retreated: Bool

    public init(
        visitedRooms: Set<String> = [],
        flags: Set<String> = [],
        keys: Set<String> = [],
        unlockedLocks: Set<String> = [],
        discoveries: Set<String> = [],
        patrolStep: Int = 0,
        currentRoom: String? = nil,
        isDead: Bool = false,
        retreated: Bool = false
    ) {
        self.visitedRooms = visitedRooms
        self.flags = flags
        self.keys = keys
        self.unlockedLocks = unlockedLocks
        self.discoveries = discoveries
        self.patrolStep = patrolStep
        self.currentRoom = currentRoom
        self.isDead = isDead
        self.retreated = retreated
    }

    /// True once the run has ended (death or retreat); no further gameplay
    /// events apply.
    public var isTerminal: Bool { isDead || retreated }

    private enum CodingKeys: String, CodingKey {
        case visitedRooms, flags, keys, unlockedLocks, discoveries
        case patrolStep, currentRoom, isDead, retreated
    }

    /// Lenient decoding: every field is optional and defaults to its blank
    /// value. This keeps earlier persisted snapshots (M1 wrote only the
    /// original three sets, e.g. the committed DelveStore `v1.sqlite`
    /// fixture) forward-compatible without a migration.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visitedRooms = try container.decodeIfPresent(Set<String>.self, forKey: .visitedRooms) ?? []
        flags = try container.decodeIfPresent(Set<String>.self, forKey: .flags) ?? []
        keys = try container.decodeIfPresent(Set<String>.self, forKey: .keys) ?? []
        unlockedLocks = try container.decodeIfPresent(Set<String>.self, forKey: .unlockedLocks) ?? []
        discoveries = try container.decodeIfPresent(Set<String>.self, forKey: .discoveries) ?? []
        patrolStep = try container.decodeIfPresent(Int.self, forKey: .patrolStep) ?? 0
        currentRoom = try container.decodeIfPresent(String.self, forKey: .currentRoom)
        isDead = try container.decodeIfPresent(Bool.self, forKey: .isDead) ?? false
        retreated = try container.decodeIfPresent(Bool.self, forKey: .retreated) ?? false
    }

    /// Explicit encoding: every key is always present (optionals encode
    /// their nil as an explicit null). The synthesized form omits nil
    /// keys, and this decoder's leniency would then erase a `nil`
    /// `currentRoom` distinction on round-trip — the lenient path must
    /// round-trip losslessly for the snapshot contract, so keys never drop.
    /// Byte stability still comes exclusively from `WorldCodec.canonical`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visitedRooms, forKey: .visitedRooms)
        try container.encode(flags, forKey: .flags)
        try container.encode(keys, forKey: .keys)
        try container.encode(unlockedLocks, forKey: .unlockedLocks)
        try container.encode(discoveries, forKey: .discoveries)
        try container.encode(patrolStep, forKey: .patrolStep)
        try container.encode(currentRoom, forKey: .currentRoom)
        try container.encode(isDead, forKey: .isDead)
        try container.encode(retreated, forKey: .retreated)
    }
}
