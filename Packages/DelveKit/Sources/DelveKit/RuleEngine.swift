/// A player-intent command fed to the deterministic rule engine.
///
/// M1 defines the vocabulary the UI and ledger will speak; M2 extends the
/// engine (not the vocabulary) with real rule tables keyed by these inputs.
public enum Command: Equatable, Codable, Sendable {
    /// The hero moves into a named room (topology is validated in M2/M3).
    case move(to: String)

    /// The hero picks up a named key item.
    case pickUp(key: String)

    /// The hero toggles a named puzzle element (lever, brazier, tile).
    case toggle(switchID: String)
}

/// Deterministic step function: `step(world, command) -> world'`.
///
/// The M1 stub implements only the pure state transitions below — no rule
/// tables, no topology validation, no enemy patrols. It exists so the app,
/// the ledger, and the CI lanes can already be wired against the final
/// shape. Every behavior here is a plain function of its inputs: no date,
/// no randomness, no environment reads.
public enum RuleEngine {
    public static func step(_ world: WorldState, _ command: Command) -> WorldState {
        var next = world
        switch command {
        case .move(let room):
            next.visitedRooms.insert(room)
        case .pickUp(let key):
            next.keys.insert(key)
        case .toggle(let switchID):
            if next.flags.contains(switchID) {
                next.flags.remove(switchID)
            } else {
                next.flags.insert(switchID)
            }
        }
        return next
    }

    /// Deterministically replays a command sequence from an initial state.
    public static func replay(_ world: WorldState, _ commands: [Command]) -> WorldState {
        commands.reduce(world) { step($0, $1) }
    }
}
