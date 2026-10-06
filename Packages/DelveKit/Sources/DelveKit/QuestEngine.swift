import Foundation

/// Vague, layered goals whose progress is derived only from validated
/// append-only events. Never infer progress from a room snapshot or UI state.
public struct QuestEngine: Sendable {
    public enum Progress: String, Codable, Sendable {
        case unknown, inProgress = "in_progress", achieved
    }

    public struct Evidence: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case visit, discovery, action }
        public let kind: Kind
        public let id: String

        func matches(_ event: GameEvent) -> Bool {
            switch (kind, event) {
            case (.visit, .visit(let room)): return room == id
            case (.discovery, .discovery(let discovery)): return discovery == id
            case (.action, .action(let element, _)): return element == id
            default: return false
            }
        }
    }

    public struct Goal: Codable, Equatable, Sendable {
        public let id: String
        public let text: String
        public let firstEvidence: Evidence
        public let completionEvidence: Evidence
    }

    public enum QuestError: Error, Equatable {
        case invalidDefinition(String)
    }

    public let goals: [Goal]
    public let contentVersion: Int

    private struct Definition: Decodable {
        let contentVersion: Int
        let goals: [Goal]
    }

    public init(data: Data, tables: RuleTables) throws {
        let definition = try JSONDecoder().decode(Definition.self, from: data)
        guard definition.contentVersion == tables.contentVersion,
              !definition.goals.isEmpty,
              Set(definition.goals.map(\.id)).count == definition.goals.count else {
            throw QuestError.invalidDefinition("version or goal ids")
        }
        for goal in definition.goals {
            guard !goal.text.isEmpty, !goal.id.isEmpty,
                  [goal.firstEvidence, goal.completionEvidence].allSatisfy({ evidence in
                      switch evidence.kind {
                      case .visit: tables.graph.room(evidence.id) != nil
                      case .discovery: tables.discoverySpawns[evidence.id] != nil
                      case .action: tables.switchEffects[evidence.id] != nil
                      }
                  }) else { throw QuestError.invalidDefinition(goal.id) }
        }
        goals = definition.goals
        contentVersion = definition.contentVersion
    }

    public static func wingOne(tables: RuleTables) throws -> QuestEngine {
        guard let url = Bundle.module.url(forResource: "quest-v2", withExtension: "json") else {
            throw QuestError.invalidDefinition("missing quest-v2.json")
        }
        return try QuestEngine(data: Data(contentsOf: url), tables: tables)
    }

    /// Rejects foreign or rule-invalid ledgers before granting any progress.
    public func progress(for goalID: String, ledger: RunLedger, tables: RuleTables) throws -> Progress {
        guard let goal = goals.first(where: { $0.id == goalID }),
              tables.contentVersion == contentVersion else {
            throw QuestError.invalidDefinition(goalID)
        }
        _ = try RuleEngine.resume(tables: tables, ledger: ledger)
        var state: Progress = .unknown
        for entry in ledger.entries {
            if goal.firstEvidence.matches(entry.event), state == .unknown {
                state = .inProgress
            } else if goal.completionEvidence.matches(entry.event), state == .inProgress {
                state = .achieved
            }
        }
        return state
    }
}
