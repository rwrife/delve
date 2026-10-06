import Foundation

/// Exhaustive finite-state puzzle proof over the actual movement/action rules.
/// Patrol contact is intentionally excluded from this proof: contact is a
/// separate, explicit terminal death rule, not a puzzle lock or softlock.
public enum GraphValidator {
    public enum ValidationError: Error, Equatable {
        case malformed(String)
        case disconnected(String)
        case unreachable(String)
        case softlock(String)
        case tooManyStates
    }

    private struct Position: Hashable {
        let room: String
        let keys: Set<String>
        let flags: Set<String>
        let unlocked: Set<String>

        init(_ world: WorldState) {
            room = world.currentRoom ?? ""
            keys = world.keys
            flags = world.flags
            unlocked = world.unlockedLocks
        }

        func world() -> WorldState {
            WorldState(visitedRooms: [room], flags: flags, keys: keys,
                       unlockedLocks: unlocked, currentRoom: room)
        }
    }

    public static func validate(_ tables: RuleTables) throws {
        try RuleTables.validateReferences(tables)
        let graph = tables.graph
        let roomIDs = Set(graph.rooms.map(\.id))
        guard !roomIDs.isEmpty, roomIDs.count == graph.rooms.count,
              graph.wings.count == Set(graph.wings.map(\.id)).count,
              graph.rooms.allSatisfy({ graph.wings.contains(.init(id: $0.wing)) }),
              tables.contentVersion > 0, graph.schemaVersion == tables.contentVersion,
              (tables.contentVersion == 1 || (tables.goalRoom != nil && tables.switchRooms != nil)) else {
            throw ValidationError.malformed("duplicate/missing rooms or wings, or invalid version")
        }
        if let goal = tables.goalRoom, !roomIDs.contains(goal) {
            throw ValidationError.malformed("unknown goal room \(goal)")
        }
        var edges = Set<Set<String>>()
        for door in graph.doors {
            let pair = Set([door.from, door.to])
            guard pair.count == 2, edges.insert(pair).inserted else {
                throw ValidationError.malformed("loop or duplicate door \(door.from)-\(door.to)")
            }
        }
        if tables.contentVersion > 1 {
            for (id, cycle) in tables.patrolCycles {
                for index in cycle.indices {
                    let from = cycle[index]
                    let to = cycle[(index + 1) % cycle.count]
                    guard from == to || graph.door(between: from, and: to) != nil else {
                        throw ValidationError.malformed("patrol \(id) jumps \(from)-\(to)")
                    }
                }
            }
        }
        // Structural connectivity is independent of keys and switches.
        var connected = Set([tables.spawnRoom])
        var pending = [tables.spawnRoom]
        while let room = pending.popLast() {
            for edge in graph.connections(from: room) where connected.insert(edge.neighbor).inserted {
                pending.append(edge.neighbor)
            }
        }
        if let missing = roomIDs.subtracting(connected).sorted().first {
            throw ValidationError.disconnected(missing)
        }

        // A patrol-free copy uses the production RuleEngine, including
        // location-bound actions and permanent unlocking, without conflating
        // optional combat risk with logical puzzle reachability.
        let puzzle = RuleTables(contentVersion: tables.contentVersion, graph: graph,
            spawnRoom: tables.spawnRoom, switchEffects: tables.switchEffects,
            lockKeys: tables.lockKeys, keySpawns: tables.keySpawns,
            discoverySpawns: tables.discoverySpawns, patrolCycles: [:],
            switchRooms: tables.switchRooms, lockFlags: tables.lockFlags,
            goalRoom: tables.goalRoom)
        let start = RuleEngine.stepResult(WorldState(), .visit(room: tables.spawnRoom), tables: puzzle)
        guard start.accepted else { throw ValidationError.unreachable(tables.spawnRoom) }
        let root = Position(start.world)
        var seen: Set<Position> = [root]
        var queue = [root]
        var reverse: [Position: Set<Position>] = [:]
        var roomsReached = Set<String>()
        var index = 0
        while index < queue.count {
            let here = queue[index]
            index += 1
            roomsReached.insert(here.room)
            let actions: [GameEvent] = graph.connections(from: here.room).map { .visit(room: $0.neighbor) }
                + (tables.switchRooms ?? [:]).keys.sorted().compactMap { element in
                    guard tables.switchRooms?[element] == here.room,
                          let effects = tables.switchEffects[element] else { return nil }
                    return .action(element: element, effects: effects)
                }
            for action in actions {
                let result = RuleEngine.stepResult(here.world(), action, tables: puzzle)
                guard result.accepted else { continue }
                let there = Position(result.world)
                reverse[there, default: []].insert(here)
                if seen.insert(there).inserted {
                    queue.append(there)
                    if queue.count > 100_000 { throw ValidationError.tooManyStates }
                }
            }
        }
        if let missing = roomIDs.subtracting(roomsReached).sorted().first {
            throw ValidationError.unreachable(missing)
        }
        if let goal = tables.goalRoom {
            let canFinish = predecessors(of: Set(seen.filter { $0.room == goal }), reverse: reverse)
            if let trapped = seen.subtracting(canFinish).sorted(by: { $0.room < $1.room }).first {
                throw ValidationError.softlock("goal unreachable from \(trapped.room)")
            }
        }
        let canLeave = predecessors(of: Set(seen.filter { $0.room == tables.spawnRoom }), reverse: reverse)
        if let trapped = seen.subtracting(canLeave).sorted(by: { $0.room < $1.room }).first {
            throw ValidationError.softlock("entrance unreachable from \(trapped.room)")
        }
    }

    private static func predecessors(of targets: Set<Position>, reverse: [Position: Set<Position>]) -> Set<Position> {
        var reached = targets
        var queue = Array(targets)
        var index = 0
        while index < queue.count {
            let state = queue[index]
            index += 1
            for previous in reverse[state] ?? [] where reached.insert(previous).inserted {
                queue.append(previous)
            }
        }
        return reached
    }
}
