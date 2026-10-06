import XCTest

final class DelveLaunchTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func tap(_ id: String, in app: XCUIApplication) {
        let button = app.buttons[id]
        if !button.isHittable {
            for _ in 0..<4 { app.swipeDown() }
        }
        for _ in 0..<12 {
            if button.exists && button.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), id)
        XCTAssertTrue(button.isHittable, id)
        button.tap()
    }

    @MainActor
    func testMovementInteractionPauseQuitResumeAndRetreat() {
        let app = XCUIApplication()
        app.launch()
        let newRun = app.buttons["entrance.new"]
        XCTAssertTrue(newRun.waitForExistence(timeout: 10))
        // Hit targets and VoiceOver labels on the primary control.
        XCTAssertGreaterThanOrEqual(newRun.frame.height, 56)
        XCTAssertEqual(newRun.label, "New delve")
        newRun.tap()
        let pause = app.buttons["exploration.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(pause.frame.height, 56)
        XCTAssertEqual(pause.label, "Pause")
        tap("discover.lore-threshold", in: app)
        tap("move.brazier-hall", in: app)
        XCTAssertEqual(app.staticTexts["room.title"].label, "Brazier Hall")
        tap("interact.brazier-left", in: app)
        XCTAssertTrue(app.buttons["interact.brazier-left"].label.contains("On"))
        tap("exploration.pause", in: app)
        XCTAssertTrue(app.staticTexts["exploration.paused"].exists)
        XCTAssertFalse(app.buttons["move.sealed-vault"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["entrance.resume"].waitForExistence(timeout: 10))
        tap("entrance.resume", in: app)
        XCTAssertEqual(app.staticTexts["room.title"].label, "Brazier Hall")
        XCTAssertTrue(app.buttons["interact.brazier-left"].label.contains("On"))
        tap("exploration.pause", in: app)
        tap("pause.entrance", in: app)
        tap("entrance.resume", in: app)
        tap("exploration.retreat", in: app)
        XCTAssertTrue(app.buttons["entrance.new"].exists)
        XCTAssertFalse(app.buttons["entrance.resume"].exists)
        XCTAssertTrue(app.staticTexts["run.ending"].label.contains("retreated"))
    }

    @MainActor
    func testBackgroundSaveCapturesLatestActionWithoutManualPause() {
        let app = XCUIApplication()
        app.launch()
        tap("entrance.new", in: app)
        tap("move.brazier-hall", in: app)
        tap("interact.brazier-left", in: app)
        // Background without manual pause, then prove the lifecycle pause.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["exploration.paused"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["entrance.resume"].waitForExistence(timeout: 10))
        tap("entrance.resume", in: app)
        XCTAssertEqual(app.staticTexts["room.title"].label, "Brazier Hall")
        XCTAssertTrue(app.buttons["interact.brazier-left"].label.contains("On"))
    }

    @MainActor
    func testActualPatrolDeathReturnsToEntrance() {
        let app = XCUIApplication()
        app.launch()
        tap("entrance.new", in: app)
        // Spawn is step 1; the alternating crypt route first contacts
        // the watcher in Ossuary at step 13.
        for room in ["brazier-hall", "sealed-vault", "dust-corridor", "fork", "blind-crypt", "ossuary", "blind-crypt", "ossuary", "blind-crypt", "ossuary", "blind-crypt", "ossuary"] {
            tap("move.\(room)", in: app)
        }
        XCTAssertTrue(app.buttons["entrance.new"].exists)
        XCTAssertFalse(app.buttons["entrance.resume"].exists)
        XCTAssertTrue(app.staticTexts["run.ending"].label.contains("patrol"))
    }

    @MainActor
    func testKeyPickupAndLockedDoorJourney() {
        let app = XCUIApplication()
        app.launch()
        tap("entrance.new", in: app)
        for room in ["brazier-hall", "sealed-vault", "dust-corridor", "fork"] { tap("move.\(room)", in: app) }
        XCTAssertFalse(app.buttons["move.sentinel-arch"].isEnabled)
        tap("move.amber-alcove", in: app)
        XCTAssertTrue(app.staticTexts["Collected Bronze Key"].exists)
        tap("move.fork", in: app)
        XCTAssertTrue(app.buttons["move.sentinel-arch"].isEnabled)
        tap("move.sentinel-arch", in: app)
        tap("exploration.retreat", in: app)
    }
}
