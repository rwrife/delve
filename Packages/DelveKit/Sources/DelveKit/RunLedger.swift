import Foundation

/// An append-only record of everything that happened in one run.
///
/// The ledger is the run's source of truth: `WorldState` is always
/// recomputable from the events via `RuleEngine.resume`. Rows carry a
/// monotonic, gap-free `sequence`, and the ledger is pinned to the
/// `contentVersion` of the `RuleTables` it was created for — appending or
/// resuming against a different table version is a hard error, so an old
/// ledger can never be silently reinterpreted by new content.
///
/// Every initializer path (including `Codable` decoding) validates the
/// sequence is exactly `0..<entries.count`; there is no unvalidated route
/// into a ledger's entries. Events encode through `EventCodec.canonical`
/// so a persisted ledger replays to byte-identical states.
///
/// This in-memory value type is what DelveStore persists (the `runs` +
/// append-only `ledger_events` tables); persistence stays out of DelveKit
/// to keep the package pure and Linux-testable.
public struct RunLedger: Equatable, Codable, Sendable {
    /// One ledger row: the event plus its monotonic sequence number.
    public struct Entry: Equatable, Codable, Sendable {
        public var sequence: Int
        public var event: GameEvent

        public init(sequence: Int, event: GameEvent) {
            self.sequence = sequence
            self.event = event
        }
    }

    public enum LedgerError: Error, Equatable {
        /// The rules rejected the event (illegal movement, locked door,
        /// unknown ids, payload/table disagreement, out-of-contact death,
        /// post-terminal). Rejected events must never be ledgered — every
        /// ledgered row must replay to state changes.
        case rejected(GameEvent)
        /// A decoded/stored ledger had a gap, duplicate, or out-of-order
        /// sequence; trusting it would corrupt the ordering contract.
        case nonMonotonicSequence(expected: Int, found: Int)
        /// The ledger was created for a different `RuleTables` content
        /// version than the one supplied; replay semantics could differ.
        case contentVersionMismatch(ledger: Int, tables: Int)
    }

    public private(set) var entries: [Entry]

    /// The `RuleTables.contentVersion` this ledger's events are valid for.
    public let contentVersion: Int

    /// Sequence the next `append` will assign (monotonic, starts at 0).
    public var nextSequence: Int { entries.count }

    /// The one initializer for all paths (fresh ledgers, decoded ledgers,
    /// test fixtures). Throws unless `entries` form a contiguous sequence
    /// `0..<entries.count` — there is deliberately no unvalidated init.
    public init(
        entries: [Entry] = [],
        contentVersion: Int = RuleTables.current.contentVersion
    ) throws {
        for (index, entry) in entries.enumerated() where entry.sequence != index {
            throw LedgerError.nonMonotonicSequence(expected: index, found: entry.sequence)
        }
        self.entries = entries
        self.contentVersion = contentVersion
    }

    /// The world state implied by the ledger so far (resume from source of
    /// truth; no cached snapshot to go stale). Requires the matching table
    /// version.
    public func world(tables: RuleTables) throws -> WorldState {
        guard tables.contentVersion == contentVersion else {
            throw LedgerError.contentVersionMismatch(ledger: contentVersion, tables: tables.contentVersion)
        }
        // Version already validated above; replay directly to keep the
        // guard single-sourced (resume re-checks it defensively).
        return RuleEngine.replay(WorldState(), entries.map(\.event), tables: tables)
    }

    /// Appends an event after validating the rules accept it against the
    /// current ledger-derived world. Returns the new entry.
    @discardableResult
    public mutating func append(
        _ event: GameEvent,
        tables: RuleTables
    ) throws -> Entry {
        guard tables.contentVersion == contentVersion else {
            throw LedgerError.contentVersionMismatch(ledger: contentVersion, tables: tables.contentVersion)
        }
        let result = RuleEngine.stepResult(try world(tables: tables), event, tables: tables)
        guard result.accepted else { throw LedgerError.rejected(event) }
        let entry = Entry(sequence: nextSequence, event: event)
        entries.append(entry)
        return entry
    }

    private enum CodingKeys: String, CodingKey {
        case contentVersion, entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .contentVersion)
        let rows = try container.decode([Entry].self, forKey: .entries)
        // Routes through the validating initializer — decoding can never
        // bypass the sequence contract.
        try self.init(entries: rows, contentVersion: version)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentVersion, forKey: .contentVersion)
        try container.encode(entries, forKey: .entries)
    }
}
