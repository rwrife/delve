import DelveKit
import SwiftUI

@main
struct DelveApp: App {
    init() {
        // Fail fast on corrupted bundled dungeon data before a run can start.
        do {
            let tables = try RuleTables.wingOne()
            _ = try QuestEngine.wingOne(tables: tables)
        }
        catch { fatalError("Bundled wing-1 validation failed: \(error)") }
    }
    var body: some Scene {
        WindowGroup {
            BootstrapHomeView()
        }
    }
}
