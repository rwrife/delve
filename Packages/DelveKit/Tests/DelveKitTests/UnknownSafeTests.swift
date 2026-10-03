import Foundation
import Testing

@testable import DelveKit

@Suite("Unknown-safe helpers")
struct UnknownSafeTests {
    @Test("unknown survives map/flatMap without collapsing to a value")
    func unknownStaysUnknown() {
        let u: Maybe<Int> = .unknown
        #expect(u.map { $0 + 1 } == .unknown)
        #expect(u.flatMap { .known($0 * 2) } == .unknown)
        // A flatMap that itself returns unknown must stay unknown.
        #expect(Maybe<Int>.known(3).flatMap { _ in Maybe<Int>.unknown } == .unknown)
        #expect(!u.isKnown)
    }

    @Test("known values map normally; collapse requires an explicit fallback")
    func knownPaths() {
        let k: Maybe<Int> = .known(41)
        #expect(k.map { $0 + 1 } == .known(42))
        #expect(k.flatMap { .known($0 * 2) } == .known(82))
        #expect(k.unwrap(or: 0) == 41)
        #expect(Maybe<Int>.unknown.unwrap(or: -1) == -1) // explicit, never implicit
    }

    @Test("counter: unknown increments stay unknown, known increments stay known")
    func counterUnknown() {
        var counter = UnknownSafeCounter()
        counter.increment()
        counter.increment()
        counter.add(5)
        #expect(counter.count == .unknown)
        #expect(!counter.isExactlyZero) // unknown is NOT zero
        #expect(counter.value(or: 99) == 99) // caller-chosen collapse only

        var counted = UnknownSafeCounter(.known(0))
        counted.increment()
        counted.increment()
        #expect(counted.count == .known(2))
        #expect(counted.value(or: -1) == 2)
        #expect(UnknownSafeCounter(.known(0)).isExactlyZero)
    }

    @Test("Codable round-trips preserve the unknown/known distinction")
    func codableRoundTrip() throws {
        let pairs: [Maybe<Int>] = [.known(7), .unknown]
        for value in pairs {
            let data = try JSONEncoder().encode(value)
            #expect(try JSONDecoder().decode(Maybe<Int>.self, from: data) == value)
        }
        // Malformed payloads never silently become `.known`: an empty or
        // wrong-key object decodes to `.unknown` (no known key present).
        #expect(try JSONDecoder().decode(Maybe<Int>.self, from: Data("{}".utf8)) == .unknown)
        // A wrong-typed `known` value throws rather than collapsing.
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Maybe<Int>.self, from: Data(#"{"known":"seven"}"#.utf8))
        }
    }

    @Test("unknown never equals a concrete value")
    func unknownIsDistinct() {
        #expect(Maybe<Int>.unknown != .known(0))
        #expect(Maybe<Int>.unknown != .known(-1))
        #expect(Maybe<String>.unknown != .known(""))
        #expect(Maybe<Bool>.unknown != .known(false))
    }
}
