import Foundation

/// Deterministic step function: `step(world, event, tables) -> world'`.
///
/// Every behavior is a plain function of its inputs (world + event + the
/// frozen versioned `RuleTables`): no date, no randomness, no environment
/// reads, no iteration-order dependence. Replaying the same event sequence
/// against the same tables always lands on a byte-identical state (see
/// `WorldCodec`).
///
/// Terminal runs: once `isDead` or `retreated`, gameplay events no longer
/// mutate the world (idempotent no-ops), which keeps stray post-end ledger
/// rows from desyncing replays.
public enum RuleEngine {
    /// The result of one step: the next world plus whether the event was
    /// accepted by the rules. Rejected events leave the world untouched and
    /// must never enter the ledger — `RunLedger.append` enforces this.
    public struct StepResult: Equatable, Sendable {
        public var world: WorldState
        public var accepted: Bool
    }

    /// Full rule-checked advance. Callers that persist events to a ledger
    /// must use `accepted`; callers that only need the state (replay of an
    /// already-validated ledger) can use `step`.
    public static func stepResult(
        _ world: WorldState,
        _ event: GameEvent,
        tables: RuleTables
    ) -> StepResult {
        var next = world
        switch event {
        case .death:
            guard !world.isTerminal else { return StepResult(world: world, accepted: false) }
            next.isDead = true

        case .retreat:
            guard !world.isTerminal else { return StepResult(world: world, accepted: false) }
            next.retreated = true

        case .visit(let room):
            guard !world.isTerminal else { return StepResult(world: world, accepted: false) }
            guard tables.graph.room(room) != nil else { return StepResult(world: world, accepted: false) }
            if let here = world.currentRoom {
                guard let door = tables.graph.door(between: here, and: room) else {
                    return StepResult(world: world, accepted: false)
                }
                if let lock = door.lock, !world.unlockedLocks.contains(lock) {
                    guard let key = tables.lockKeys[lock], world.keys.contains(key) else {
                        return StepResult(world: world, accepted: false) // locked: travel impossible
                    }
                    next.unlockedLocks.insert(lock) // unlocking with the key is permanent
                }
            }
            next.currentRoom = room
            next.visitedRooms.insert(room)
            next.patrolStep += 1
            // Fixed key placement: entering a room acquires any key that
            // starts there (data-driven, sorted iteration for stability).
            for key in tables.keySpawns.keys.sorted() where tables.keySpawns[key] == room {
                next.keys.insert(key)
            }

        case .action(let element, _):
            guard !world.isTerminal else { return StepResult(world: world, accepted: false) }
            guard let effects = tables.switchEffects[element] else {
                return StepResult(world: world, accepted: false)
            }
            for effect in effects {
                if next.flags.contains(effect) {
                    next.flags.remove(effect)
                } else {
                    next.flags.insert(effect)
                }
            }

        case .discovery(let id):
            guard !world.isTerminal else { return StepResult(world: world, accepted: false) }
            guard let spawnRoom = tables.discoverySpawns[id] else {
                return StepResult(world: world, accepted: false)
            }
            guard world.visitedRooms.contains(spawnRoom) else {
                return StepResult(world: world, accepted: false)
            }
            next.discoveries.insert(id) // idempotent: repeat is accepted, no change
        }
        return StepResult(world: next, accepted: true)
    }

    /// State-only advance (rejected events are no-ops). This is the pure
    /// transition function the determinism contract is stated against.
    public static func step(
        _ world: WorldState,
        _ event: GameEvent,
        tables: RuleTables
    ) -> WorldState {
        stepResult(world, event, tables: tables).world
    }

    /// Rooms occupied by every patrol after `patrolStep` successful visits,
    /// derived purely from the versioned cycles. Patrol positions are a
    /// function of world state, never stored in it, so they can never
    /// desync from a replay.
    public static func patrolRooms(atStep patrolStep: Int, tables: RuleTables) -> [String: String] {
        var rooms: [String: String] = [:]
        for patrolID in tables.patrolCycles.keys.sorted() {
            guard let cycle = tables.patrolCycles[patrolID], !cycle.isEmpty else { continue }
            rooms[patrolID] = cycle[patrolStep % cycle.count]
        }
        return rooms
    }

    /// True when the hero's current room is occupied by a patrol at the
    /// world's current patrol step. The game session checks this after each
    /// accepted visit and records `.death` (a ledgered fact) on contact —
    /// replay then reproduces the death exactly.
    public static func inPatrolContact(_ world: WorldState, tables: RuleTables) -> Bool {
        guard let room = world.currentRoom, !world.isTerminal else { return false }
        return patrolRooms(atStep: world.patrolStep, tables: tables).values.contains(room)
    }

    /// Step-by-step replay of an event sequence from an initial state.
    public static func replay(
        _ world: WorldState,
        _ events: [GameEvent],
        tables: RuleTables
    ) -> WorldState {
        events.reduce(world) { step($0, $1, tables: tables) }
    }

    /// Recomputes the exact world state of a run from its ledger. Equal to
    /// `replay` over the ledger's events in sequence order — the ledger is
    /// the run's source of truth, so resume never trusts stored snapshots.
    public static func resume(tables: RuleTables, ledger: RunLedger) -> WorldState {
        replay(WorldState(), ledger.entries.map(\.event), tables: tables)
    }
}
