import Foundation

/// The complete observable state of the fixed dungeon at one point in a run.
///
/// Value semantics with deterministic, replayable content: the same world
/// plus the same command sequence always produces the same resulting state.
/// Room identifiers are stable strings defined by the (M3) fixed room graph;
/// nothing here is randomly generated.
public struct WorldState: Equatable, Codable, Sendable {
    /// Rooms the hero has entered at least once.
    public var visitedRooms: Set<String>

    /// Toggle-style puzzle elements currently "on" (lit braziers, thrown
    /// levers, pressed tiles). Membership is the whole truth.
    public var flags: Set<String>

    /// Key items currently in the hero's possession.
    public var keys: Set<String>

    public init(
        visitedRooms: Set<String> = [],
        flags: Set<String> = [],
        keys: Set<String> = []
    ) {
        self.visitedRooms = visitedRooms
        self.flags = flags
        self.keys = keys
    }
}
