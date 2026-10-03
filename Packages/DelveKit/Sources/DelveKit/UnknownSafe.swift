import Foundation

/// Unknown-safe scalar helpers.
///
/// Dungeon content may legitimately not know something yet (a room's loot
/// table not yet rolled, a counter that has never been incremented). An
/// "unknown" value must stay distinct from zero/false through arithmetic,
/// comparisons, Codable round-trips, and display — collapsing unknown to a
/// concrete value would silently corrupt ledger reasoning and save files.
public enum Maybe<Value: Equatable & Sendable>: Equatable, Sendable {
    case unknown
    case known(Value)

    /// Strict map: `unknown` stays `unknown` regardless of `transform`.
    public func map<T: Equatable & Sendable>(_ transform: (Value) -> T) -> Maybe<T> {
        switch self {
        case .unknown: return .unknown
        case .known(let value): return .known(transform(value))
        }
    }

    /// Strict flatMap: unknown chains stay unknown; a nested `.unknown`
    /// result is preserved, never flattened to a default.
    public func flatMap<T: Equatable & Sendable>(_ transform: (Value) -> Maybe<T>) -> Maybe<T> {
        switch self {
        case .unknown: return .unknown
        case .known(let value): return transform(value)
        }
    }

    /// Resolves only with an explicit fallback the caller chooses; there is
    /// no implicit "or zero" convenience anywhere in this file.
    public func unwrap(or fallback: Value) -> Value {
        switch self {
        case .unknown: return fallback
        case .known(let value): return value
        }
    }

    public var isKnown: Bool {
        if case .known = self { return true }
        return false
    }
}

// Codable: encoded as `{"known": <value>}` or `{}` — a round-trip through
// JSON can never manufacture a known value from an unknown one.
extension Maybe: Codable where Value: Codable {
    private enum CodingKeys: String, CodingKey { case known }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.known) {
            self = .known(try container.decode(Value.self, forKey: .known))
        } else {
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unknown: break
        case .known(let value): try container.encode(value, forKey: .known)
        }
    }
}

/// An unknown-safe integer counter: `increment` on unknown yields unknown,
/// not 1; `value(or:)` is the only way to collapse it.
public struct UnknownSafeCounter: Equatable, Sendable {
    private(set) public var count: Maybe<Int>

    public init(_ count: Maybe<Int> = .unknown) {
        self.count = count
    }

    public mutating func increment() {
        count = count.map { $0 + 1 }
    }

    /// Adds `delta`, preserving unknown.
    public mutating func add(_ delta: Int) {
        count = count.map { $0 + delta }
    }

    /// Explicit collapse — caller picks the fallback; nothing defaults it.
    public func value(or fallback: Int) -> Int { count.unwrap(or: fallback) }

    /// True only for `.known(0)`; unknown is explicitly NOT zero.
    public var isExactlyZero: Bool { count == .known(0) }
}
