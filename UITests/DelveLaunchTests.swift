import XCTest

final class DelveLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBootstrapHomeLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.otherElements["bootstrap.home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Delve"].exists)
        XCTAssertTrue(app.staticTexts["Dungeon engine, quest journal, and room exploration arrive in the next milestones."].exists)
    }
}
