import Foundation
import Testing
@testable import DelveKit

@Test func godotContentFingerprintsMatchNativeTables() throws {
    #expect(RuleTables.current.fingerprint == "e4a8d1f9e5749c8d")
    #expect(try RuleTables.wingOne().fingerprint == "2a4b4cc2b0d8ceb0")
    #expect(try RuleTables.fullDungeon().fingerprint == "d631b2c3c2665c0b")
}

@Test func godotEventEncodingMatchesNativeLedger() throws {
    let event = GameEvent.action(element: "resonant-bell", effects: ["bell-lit"])
    let encoded = String(decoding: try EventCodec.canonical(event), as: UTF8.self)
    #expect(encoded == #"{"action":{"effects":["bell-lit"],"element":"resonant-bell"}}"#)
}
