import Foundation

/// Deterministic step function: `step(world, event, tables) -> world'`.
///
/// Every behavior is a plain function of its inputs (world + event + the
/// frozen versioned `RuleTables`): no date, no randomness, no environment
/// reads, no iteration-order dependence. Replaying the same event sequence
/// against the same tables always lands on a byte-identical state (see
/// `WorldCodec`).
///
/// Rule enforcement invariants (the ledger only ever contains events the
/// rules accepted, so every ledgered row is faithful history):
/// - `action` payloads must name exactly the table's effects for the
///   element; the table — not the payload — decides what applies.
/// - Patrol contact is the only cause of death in M2, and it is mandatory:
///   while the hero shares a room with a patrol, only `death` is accepted,
///   and `death` is accepted only when in contact. A replayed ledger can
///   therefore never survive a contact or die without one.
/// - Terminal runs: once `isDead` or `retreated`, every event is rejected.
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
        case .sessionStart:
            guard !world.isTerminal, !inPatrolContact(world, tables: tables) else {
                return StepResult(world: world, accepted: false)
            }
            // Session boundaries are ledger facts, not dungeon movement.
        case .death:
            // Contact is the only death in M2: required, and terminal.
            guard !world.isTerminal, inPatrolContact(world, tables: tables) else {
                return StepResult(world: world, accepted: false)
            }
            next.isDead = true

        case .retreat:
            guard !world.isTerminal, world.currentRoom != nil,
                  !inPatrolContact(world, tables: tables) else {
                return StepResult(world: world, accepted: false)
            }
            next.retreated = true

        case .visit(let room):
            guard !world.isTerminal, !inPatrolContact(world, tables: tables) else {
                return StepResult(world: world, accepted: false)
            }
            guard tables.graph.room(room) != nil else {
                return StepResult(world: world, accepted: false)
            }
            if let here = world.currentRoom {
                guard let door = tables.graph.door(between: here, and: room) else {
                    return StepResult(world: world, accepted: false)
                }
                if let lock = door.lock, !world.unlockedLocks.contains(lock) {
                    guard let key = tables.lockKeys[lock], world.keys.contains(key) else {
                        return StepResult(world: world, accepted: false) // locked: travel impossible
                    }
                    guard (tables.lockFlags?[lock] ?? []).allSatisfy(world.flags.contains) else {
                        return StepResult(world: world, accepted: false)
                    }
                    next.unlockedLocks.insert(lock) // unlocking with the key is permanent
                }
            } else {
                // The run begins at the table's fixed spawn room only —
                // a run can never spawn inside (or behind) a locked room.
                guard room == tables.spawnRoom else {
                    return StepResult(world: world, accepted: false)
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

        case .action(let element, let effects):
            // An element lives in a room: acting before entering the
            // dungeon is impossible.
            guard !world.isTerminal, world.currentRoom != nil,
                  !inPatrolContact(world, tables: tables) else {
                return StepResult(world: world, accepted: false)
            }
            // The recorded payload must agree with the frozen table; the
            // table alone decides which effects apply.
            guard let tableEffects = tables.switchEffects[element], effects == tableEffects else {
                return StepResult(world: world, accepted: false)
            }
            if let switchRooms = tables.switchRooms {
                guard switchRooms[element] == world.currentRoom else {
                    return StepResult(world: world, accepted: false)
                }
            }
            for effect in tableEffects {
                if next.flags.contains(effect) {
                    next.flags.remove(effect)
                } else {
                    next.flags.insert(effect)
                }
            }

        case .discovery(let id):
            guard !world.isTerminal, !inPatrolContact(world, tables: tables) else {
                return StepResult(world: world, accepted: false)
            }
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
    /// world's current patrol step. While true, only `.death` is accepted
    /// (see the rule invariants above), and replay reproduces the contact
    /// death exactly.
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

    /// Recomputes the exact world state of a run from its ledger — and
    /// proves the ledger is faithful: every row is replayed through the
    /// rule-checked `stepResult`, and a row the rules would reject (an
    /// out-of-contact death, action after patrol contact, post-terminal
    /// tail, ...) throws instead of being silently skipped. A restored
    /// ledger therefore always recomputes exactly what an append-built
    /// ledger recomputes, or the restore is rejected outright.
    /// The caller's tables must match the ledger's pinned
    /// `contentVersion` AND content fingerprint; a mismatch throws
    /// rather than silently reinterpreting history.
    public static func resume(tables: RuleTables, ledger: RunLedger) throws -> WorldState {
        try ledger.validate(tables)
        var world = WorldState()
        for entry in ledger.entries {
            let result = stepResult(world, entry.event, tables: tables)
            guard result.accepted else {
                throw RunLedger.LedgerError.rejected(entry.event)
            }
            world = result.world
        }
        return world
    }
}
