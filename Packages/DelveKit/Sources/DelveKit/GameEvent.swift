import Foundation

/// A gameplay event appended to a run's ledger and fed to `RuleEngine.step`.
///
/// M2 replaces the M1 `Command` vocabulary with ledger-shaped events: every
/// event is a fact a run has recorded, so a run can always be recomputed
/// from its ledger alone. Event payloads contain only stable string
/// identifiers and ordered string arrays — no sets, no dates, no
/// randomness — so canonical encoding is byte-stable.
///
/// Encoding rule: ledger rows persist events through `EventCodec.canonical`
/// (`.sortedKeys`). `JSONEncoder`'s default dictionary key layout is
/// unspecified and was observed to differ between two equal payloads within
/// one process on the Darwin runtime — the ledger contract cannot rely on
/// it.
public enum GameEvent: Equatable, Codable, Sendable {
    /// The hero visits a room. A visit to a room behind a locked door only
    /// succeeds once the hero holds the door's key; blocked visits never
    /// mutate the world and must not be ledgered.
    case visit(room: String)

    /// The hero acts on a named puzzle element. The engine resolves the
    /// effect list from `RuleTables.switchEffects`; the recorded payload
    /// keeps the raw intent plus the effect identifiers that were active at
    /// the time, so ledgers remain faithful historical records.
    case action(element: String, effects: [String])

    /// A content discovery was recorded (journal entry, lore fragment).
    /// Idempotent: re-discovering may be ledgered but only the first
    /// occurrence changes state.
    case discovery(id: String)

    /// The run ended in death (patrol contact or fatal trap).
    case death

    /// The run ended in a deliberate retreat.
    case retreat
}

/// Stable canonical serialization for persisted game events.
public enum EventCodec {
    /// Deterministic JSON bytes for an event: all dictionary keys sorted.
    public static func canonical(_ event: GameEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(event)
    }

    /// Strict decode: anything that is not a byte-faithful canonical event
    /// throws rather than collapsing into a wrong-but-valid event.
    public static func decode(_ data: Data) throws -> GameEvent {
        try JSONDecoder().decode(GameEvent.self, from: data)
    }
}
