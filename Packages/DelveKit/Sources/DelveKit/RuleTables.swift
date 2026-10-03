import Foundation

/// The frozen, versioned rule tables that drive the deterministic engine.
///
/// Everything the engine knows about the dungeon — topology, switch
/// effects, key/lock bindings, patrol cycles, spawn rooms — lives here as
/// plain data. `step` reads only these tables plus the incoming world and
/// event; there are no hidden inputs, no randomness, no environment reads.
/// Bumping `contentVersion` is a content change: old ledgers replay
/// against the version they were recorded with (persisted with the run),
/// never against the latest table silently.
public struct RuleTables: Equatable, Codable, Sendable {
    public var contentVersion: Int
    public var graph: RoomGraph

    /// element id -> ordered effect ids. Toggle semantics: effects listed
    /// here flip when the element is acted on.
    public var switchEffects: [String: [String]]

    /// lock id -> the key id that opens it.
    public var lockKeys: [String: String]

    /// key item id -> room where it starts (M2 fixed placement; a key is
    /// acquired by visiting its room).
    public var keySpawns: [String: String]

    /// discovery id -> room where it is found.
    public var discoverySpawns: [String: String]

    /// patrol id -> ordered room cycle. The patrol occupies
    /// `cycle[world.patrolStep % cycle.count]` — patrol positions are a
    /// pure function of the successful-visit count, so replays land the
    /// hero and the patrols in the same room at the same moment.
    public var patrolCycles: [String: [String]]

    public init(
        contentVersion: Int,
        graph: RoomGraph,
        switchEffects: [String: [String]],
        lockKeys: [String: String],
        keySpawns: [String: String],
        discoverySpawns: [String: String],
        patrolCycles: [String: [String]]
    ) {
        self.contentVersion = contentVersion
        self.graph = graph
        self.switchEffects = switchEffects
        self.lockKeys = lockKeys
        self.keySpawns = keySpawns
        self.discoverySpawns = discoverySpawns
        self.patrolCycles = patrolCycles
    }

    /// The M2 table set: one two-room prologue pair plus a locked brazier
    /// hall, one brazier switch, one key/lock pair, one patrol. These exact
    /// ids are the contract the M1 committed DelveStore fixture already
    /// references (`brazier-left`, `bronze-key`, `entrance`,
    /// `brazier-hall`).
    ///
    /// The source of truth is the versioned data file
    /// `Resources/content-v1.json`, loaded through `load(contentsOf:)`;
    /// the test suite asserts this constant equals the decoded file, so
    /// callers get zero I/O while drift between code and data file is
    /// impossible to merge unnoticed.
    public static let current = RuleTables(
        contentVersion: 1,
        graph: RoomGraph(
            schemaVersion: 1,
            rooms: [
                RoomGraph.Room(id: "entrance", wing: "wing-1"),
                RoomGraph.Room(id: "brazier-hall", wing: "wing-1"),
                RoomGraph.Room(id: "sealed-vault", wing: "wing-1"),
            ],
            doors: [
                RoomGraph.Door(from: "entrance", to: "brazier-hall"),
                RoomGraph.Door(from: "brazier-hall", to: "sealed-vault", lock: "vault-door"),
            ],
            wings: [RoomGraph.Wing(id: "wing-1")]
        ),
        switchEffects: [
            "brazier-left": ["brazier-left"],
            "idol-plinth": ["idol-plinth"],
        ],
        lockKeys: [
            "vault-door": "bronze-key",
        ],
        keySpawns: [
            "bronze-key": "brazier-hall",
        ],
        discoverySpawns: [
            "lore-threshold": "entrance",
        ],
        patrolCycles: [
            // Guard on a 3-room cycle. With the hero's canonical opener
            // (entrance -> brazier-hall -> sealed-vault) the guard is never
            // in the hero's room, but a 5th visit back to `entrance`
            // (patrolStep 5 -> "entrance") is a contact death: the tables
            // support both survival and death runs, each fully replayable.
            "guard-post": ["brazier-hall", "sealed-vault", "entrance"],
        ]
    )

    /// Room the patrol `patrolID` occupies after `step` successful visits.
    public func patrolRoom(_ patrolID: String, atStep step: Int) -> String? {
        guard let cycle = patrolCycles[patrolID], !cycle.isEmpty else { return nil }
        return cycle[step % cycle.count]
    }

    public enum TablesError: Error, Equatable {
        /// A data file decoded fine but references ids that do not exist
        /// (door to unknown room, lock with no key entry, key spawn in an
        /// unknown room, patrol cycle through an unknown room, ...). The
        /// full graph validator lands in M3; this covers cross-reference
        /// integrity, which is what makes replay sound.
        case danglingReference(String)
    }

    /// Loads tables from versioned data file contents (the shape of
    /// `Resources/content-v1.json`) and checks cross-reference integrity.
    public static func load(contentsOf data: Data) throws -> RuleTables {
        let tables = try JSONDecoder().decode(RuleTables.self, from: data)
        let roomIDs = Set(tables.graph.rooms.map(\.id))
        for door in tables.graph.doors {
            guard roomIDs.contains(door.from), roomIDs.contains(door.to) else {
                throw TablesError.danglingReference("door \(door.from)->\(door.to)")
            }
            if let lock = door.lock {
                guard tables.lockKeys[lock] != nil else {
                    throw TablesError.danglingReference("lock \(lock)")
                }
            }
        }
        for (key, room) in tables.keySpawns where !roomIDs.contains(room) {
            throw TablesError.danglingReference("key \(key) spawn \(room)")
        }
        for (id, room) in tables.discoverySpawns where !roomIDs.contains(room) {
            throw TablesError.danglingReference("discovery \(id) spawn \(room)")
        }
        for (patrol, cycle) in tables.patrolCycles {
            guard !cycle.isEmpty else {
                throw TablesError.danglingReference("patrol \(patrol) empty cycle")
            }
            for room in cycle where !roomIDs.contains(room) {
                throw TablesError.danglingReference("patrol \(patrol) room \(room)")
            }
        }
        return tables
    }

    /// Loads tables from a data file URL on disk.
    public static func load(from url: URL) throws -> RuleTables {
        try load(contentsOf: Data(contentsOf: url))
    }
}
