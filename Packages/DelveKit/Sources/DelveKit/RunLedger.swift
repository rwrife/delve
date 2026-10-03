import Foundation

/// An append-only record of everything that happened in one run.
///
/// The ledger is the run's source of truth: `WorldState` is always
/// recomputable from the events via `RuleEngine.resume`. Rows carry a
/// monotonic, gap-free `sequence` assigned by `append`, and events encode
/// through `EventCodec.canonical` so a persisted ledger replays to
/// byte-identical states.
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

    public private(set) var entries: [Entry]

    /// Sequence the next `append` will assign (monotonic, starts at 0).
    public var nextSequence: Int { entries.count }

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public enum LedgerError: Error, Equatable {
        /// The rules rejected the event (illegal movement, locked door,
        /// unknown ids, post-terminal). Rejected events must never be
        /// ledgered — every ledgered row must replay to state changes.
        case rejected(GameEvent)
        /// A decoded/stored ledger had a gap, duplicate, or out-of-order
        /// sequence; trusting it would corrupt the ordering contract.
        case nonMonotonicSequence(expected: Int, found: Int)
    }

    /// The world state implied by the ledger so far (resume from source of
    /// truth; no cached snapshot to go stale).
    public func world(tables: RuleTables) -> WorldState {
        RuleEngine.resume(tables: tables, ledger: self)
    }

    /// Appends an event after validating the rules accept it against the
    /// current ledger-derived world. Returns the new entry.
    @discardableResult
    public mutating func append(
        _ event: GameEvent,
        tables: RuleTables
    ) throws -> Entry {
        let result = RuleEngine.stepResult(world(tables: tables), event, tables: tables)
        guard result.accepted else { throw LedgerError.rejected(event) }
        let entry = Entry(sequence: nextSequence, event: event)
        entries.append(entry)
        return entry
    }

    /// Strict initializer for decoded ledgers: verifies the sequence field
    /// is exactly 0..<entries.count before trusting it.
    public init(validated entries: [Entry]) throws {
        for (index, entry) in entries.enumerated() where entry.sequence != index {
            throw LedgerError.nonMonotonicSequence(expected: index, found: entry.sequence)
        }
        self.entries = entries
    }
}
