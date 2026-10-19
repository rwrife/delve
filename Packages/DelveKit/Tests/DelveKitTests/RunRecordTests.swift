import Foundation
import Testing
@testable import DelveKit

@Test func emptyLedgerProducesUnknownRunRecord() throws {
    let ledger = try RunLedger(entries: [], tables: .current)
    let record = try RunRecord.derive(from: ledger, tables: .current)
    #expect(record.roomsVisited == .unknown)
    #expect(record.steps == .unknown)
    #expect(record.sessions == .unknown)
    #expect(record.discoveries == .unknown)
    #expect(RunRecord.display(record.steps) == "unknown")
}

@Test func legacyLedgerWithoutSessionMarkersHasUnknownSessionCount() throws {
    let tables = try RuleTables.wingOne()
    var ledger = try RunLedger(tables: tables)
    try ledger.append(.visit(room: "entrance"), tables: tables)
    try ledger.append(.visit(room: "brazier-hall"), tables: tables)
    let record = try RunRecord.derive(from: ledger, tables: tables)
    #expect(record.roomsVisited == .known(2))
    #expect(record.steps == .known(2))
    #expect(record.sessions == .unknown)
    #expect(RunRecord.display(record.sessions) == "unknown")
    #expect(record.discoveries == .known([]))
}

@Test func modernLedgerWithSessionMarkersCountsSessionsAccurately() throws {
    let tables = try RuleTables.wingOne()
    var ledger = try RunLedger(tables: tables)
    try ledger.append(.sessionStart, tables: tables)
    try ledger.append(.visit(room: "entrance"), tables: tables)
    try ledger.append(.discovery(id: "lore-threshold"), tables: tables)
    try ledger.append(.visit(room: "brazier-hall"), tables: tables)
    try ledger.append(.sessionStart, tables: tables)
    let record = try RunRecord.derive(from: ledger, tables: tables)
    #expect(record.roomsVisited == .known(2))
    #expect(record.steps == .known(2))
    #expect(record.sessions == .known(2))
    #expect(record.discoveries == .known(["lore-threshold"]))
}
