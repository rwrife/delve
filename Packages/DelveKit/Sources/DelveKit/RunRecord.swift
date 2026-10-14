import Foundation

/// Ledger-derived run facts for the record screen.
///
/// Unknown-safety is the display contract: a value the ledger cannot prove
/// renders as "unknown", never as a fabricated zero.
///
/// - An empty ledger proves nothing: every field is unknown.
/// - `sessions` counts `sessionStart` markers. A run started before M5
///   introduced session tracking has no markers at all — that is missing
///   data, not zero sessions, so it stays unknown.
/// - `discoveries` is complete knowledge once the ledger has rows (the
///   engine records every discovery event), so an empty set is a true zero
///   rendered by the UI as "none recorded" — distinct from the unknown
///   empty-ledger case.
public struct RunRecord: Equatable, Sendable {
    public let roomsVisited: Maybe<Int>
    public let steps: Maybe<Int>
    public let sessions: Maybe<Int>
    public let discoveries: Maybe<[String]>

    public init(
        roomsVisited: Maybe<Int>,
        steps: Maybe<Int>,
        sessions: Maybe<Int>,
        discoveries: Maybe<[String]>
    ) {
        self.roomsVisited = roomsVisited
        self.steps = steps
        self.sessions = sessions
        self.discoveries = discoveries
    }

    /// Derives the record from a validated ledger replay. Throws exactly
    /// when the ledger is not rule-faithful for these tables.
    public static func derive(from ledger: RunLedger, tables: RuleTables) throws -> RunRecord {
        let world = try RuleEngine.resume(tables: tables, ledger: ledger)
        guard !ledger.entries.isEmpty else {
            return RunRecord(roomsVisited: .unknown, steps: .unknown, sessions: .unknown, discoveries: .unknown)
        }
        var sessionCount = 0
        for entry in ledger.entries {
            if case .sessionStart = entry.event { sessionCount += 1 }
        }
        return RunRecord(
            roomsVisited: .known(world.visitedRooms.count),
            steps: .known(world.patrolStep),
            sessions: ledger.entries.first?.event == .sessionStart ? .known(sessionCount) : .unknown,
            discoveries: .known(world.discoveries.sorted())
        )
    }

    /// The one unknown-safe rendering used by every record row.
    public static func display(_ value: Maybe<Int>) -> String {
        switch value {
        case .unknown: return "unknown"
        case .known(let count): return String(count)
        }
    }
}
