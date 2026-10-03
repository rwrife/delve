import Foundation

/// The fixed dungeon topology: rooms connected by doors, grouped into wings.
///
/// Value types loaded from versioned data (`RuleTables.graph`). The graph is
/// data, not code: M3 introduces external file loading with a validator; M2
/// freezes the in-code source of truth behind the same API so the loader
/// only swaps where `current` comes from.
public struct RoomGraph: Equatable, Codable, Sendable {
    public struct Room: Equatable, Codable, Sendable, Hashable {
        public var id: String
        public var wing: String
        public init(id: String, wing: String) {
            self.id = id
            self.wing = wing
        }
    }

    /// A one-way traversable connection between two rooms. `lock` names the
    /// puzzle element gating the door (nil = plain door).
    public struct Door: Equatable, Codable, Sendable, Hashable {
        public var from: String
        public var to: String
        public var lock: String?
        public init(from: String, to: String, lock: String? = nil) {
            self.from = from
            self.to = to
            self.lock = lock
        }
    }

    /// A named, ordered group of rooms (content-release unit).
    public struct Wing: Equatable, Codable, Sendable, Hashable {
        public var id: String
        public init(id: String) {
            self.id = id
        }
    }

    public var schemaVersion: Int
    public var rooms: [Room]
    public var doors: [Door]
    public var wings: [Wing]

    public init(schemaVersion: Int, rooms: [Room], doors: [Door], wings: [Wing]) {
        self.schemaVersion = schemaVersion
        self.rooms = rooms
        self.doors = doors
        self.wings = wings
    }

    public func room(_ id: String) -> Room? {
        rooms.first { $0.id == id }
    }

    /// Doors leaving `roomID` in either direction with their gate lock
    /// (nil for an ungated door). Bidirectional pairs appear once per edge.
    public func connections(from roomID: String) -> [(neighbor: String, lock: String?)] {
        doors.compactMap { door in
            if door.from == roomID { return (door.to, door.lock) }
            if door.to == roomID { return (door.from, door.lock) }
            return nil
        }
    }

    /// The door directly connecting two rooms (traversable either way), or
    /// nil when no such door exists. Callers read `door?.lock` to gate
    /// movement: a door with `lock == nil` is always passable.
    public func door(between a: String, and b: String) -> Door? {
        doors.first { door in
            (door.from == a && door.to == b) || (door.from == b && door.to == a)
        }
    }
}
