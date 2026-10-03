import Foundation

/// An append-only record of everything that happened in one run.
///
/// The ledger is the run's source of truth: `WorldState` is always
/// recomputable from the events via `RuleEngine.resume`. Rows carry a
/// monotonic, gap-free `sequence`, and the ledger is pinned to the exact
/// `RuleTables` it was built for — both its `contentVersion` AND its
/// content `fingerprint`. Appending or resuming against any other table
/// set is a hard error, so a ledger can never be silently reinterpreted,
/// not even by same-version tables whose contents drifted.
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
    public struct Entry: Equatable, Sendable {
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
        /// The supplied tables carry the ledger's `contentVersion` but
        /// different content (fingerprint mismatch) — replaying them
        /// would silently reinterpret the run's history.
        case tablesFingerprintMismatch(ledger: String, tables: String)
    }

    public private(set) var entries: [Entry]

    /// The `RuleTables.contentVersion` this ledger's events are valid for.
    public let contentVersion: Int

    /// The content fingerprint (`RuleTables.fingerprint`) of the exact
    /// table set this ledger was built against.
    public let tablesFingerprint: String

    /// Sequence the next `append` will assign (monotonic, starts at 0).
    public var nextSequence: Int { entries.count }

    /// The one initializer for all paths (fresh ledgers, decoded ledgers,
    /// test fixtures). Throws unless `entries` form a contiguous sequence
    /// `0..<entries.count` — there is deliberately no unvalidated init.
    public init(
        entries: [Entry] = [],
        tables: RuleTables = .current
    ) throws {
        for (index, entry) in entries.enumerated() where entry.sequence != index {
            throw LedgerError.nonMonotonicSequence(expected: index, found: entry.sequence)
        }
        self.entries = entries
        self.contentVersion = tables.contentVersion
        self.tablesFingerprint = tables.fingerprint
    }

    /// Verifies the supplied tables are the exact table set this ledger
    /// was pinned to (version AND content fingerprint).
    func validate(_ tables: RuleTables) throws {
        guard tables.contentVersion == contentVersion else {
            throw LedgerError.contentVersionMismatch(ledger: contentVersion, tables: tables.contentVersion)
        }
        guard tables.fingerprint == tablesFingerprint else {
            throw LedgerError.tablesFingerprintMismatch(ledger: tablesFingerprint, tables: tables.fingerprint)
        }
    }

    /// The world state implied by the ledger so far (resume from source of
    /// truth; no cached snapshot to go stale). Requires the exact pinned
    /// tables and a rule-faithful ledger (see `RuleEngine.resume`).
    public func world(tables: RuleTables) throws -> WorldState {
        try RuleEngine.resume(tables: tables, ledger: self)
    }

    /// Appends an event after validating the rules accept it against the
    /// current ledger-derived world. Returns the new entry.
    @discardableResult
    public mutating func append(
        _ event: GameEvent,
        tables: RuleTables
    ) throws -> Entry {
        try validate(tables)
        let result = RuleEngine.stepResult(try world(tables: tables), event, tables: tables)
        guard result.accepted else { throw LedgerError.rejected(event) }
        let entry = Entry(sequence: nextSequence, event: event)
        entries.append(entry)
        return entry
    }

    private enum CodingKeys: String, CodingKey {
        case contentVersion, tablesFingerprint, entries
    }

    /// Canonical persisted form for one row: sequence + canonical event
    /// bytes as base64. Decoding runs the bytes back through
    /// `EventCodec.decode`, so ledger JSON that is not a canonical event
    /// encoding (field drift, reordered members, extra keys) is rejected
    /// at the boundary instead of silently loading.
    private struct EntryWire: Codable {
        var sequence: Int
        var eventBase64: String
    }

    private struct LedgerWire: Codable {
        var contentVersion: Int
        var tablesFingerprint: String
        var entries: [EntryWire]
    }

    public init(from decoder: Decoder) throws {
        // Decodes through the wire shape, then re-runs every row through
        // the strict event codec and the validating sequence contract.
        let wire = try LedgerWire(from: decoder)
        self.contentVersion = wire.contentVersion
        self.tablesFingerprint = wire.tablesFingerprint
        var rows: [Entry] = []
        rows.reserveCapacity(wire.entries.count)
        for row in wire.entries {
            guard let bytes = Data(base64Encoded: row.eventBase64) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "ledger event bytes are not valid base64"
                    )
                )
            }
            rows.append(Entry(sequence: row.sequence, event: try EventCodec.decode(bytes)))
        }
        for (index, entry) in rows.enumerated() where entry.sequence != index {
            throw LedgerError.nonMonotonicSequence(expected: index, found: entry.sequence)
        }
        self.entries = rows
    }

    public func encode(to encoder: Encoder) throws {
        let wire = LedgerWire(
            contentVersion: contentVersion,
            tablesFingerprint: tablesFingerprint,
            entries: try entries.map { entry in
                EntryWire(
                    sequence: entry.sequence,
                    eventBase64: try EventCodec.canonical(entry.event).base64EncodedString()
                )
            }
        )
        try wire.encode(to: encoder)
    }
}
