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
    func testJournalNotesQuestMarksAndRecordSurviveRelaunch() {
        let app = XCUIApplication()
        app.launch()
        tap("entrance.new", in: app)
        tap("journal.open", in: app)
        tap("journal.notes", in: app)
        tap("note.room.entrance", in: app)
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("A threshold clue")
        tap("note.save", in: app)
        XCTAssertTrue(app.staticTexts["note.status"].label.contains("saved"))
        app.terminate()
        app.launch()
        tap("entrance.resume", in: app)
        tap("journal.open", in: app)
        tap("journal.notes", in: app)
        XCTAssertTrue(app.staticTexts["A threshold clue"].waitForExistence(timeout: 5))
        app.navigationBars["Room notes"].buttons["Journal"].tap()
        tap("journal.quests", in: app)
        let mark = app.buttons["quest.mark.silence"]
        XCTAssertTrue(mark.waitForExistence(timeout: 5))
        XCTAssertTrue(mark.label.contains("Not marked by you"))
        mark.tap()
        XCTAssertTrue(mark.label.contains("Marked by you"))
        XCTAssertTrue(app.staticTexts["quest.engine.silence"].label.contains("Unknown"))
        app.navigationBars["Quest inscriptions"].buttons["Journal"].tap()
        tap("journal.record", in: app)
        XCTAssertTrue(app.staticTexts["record.sessions"].label.contains("2"))
        XCTAssertTrue(app.staticTexts["record.steps"].label.contains("1"))
    }

    @MainActor
    func testJournalAccessibilityAtDefaultAndLargestDynamicType() throws {
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", category]
            app.launchEnvironment["UIPreferredContentSizeCategoryName"] = category
            app.launch()
            tap("entrance.new", in: app)
            tap("journal.open", in: app)
            try app.performAccessibilityAudit()
            for (id, title) in [("journal.notes", "Room notes"), ("journal.quests", "Quest inscriptions"), ("journal.record", "Run record")] {
                tap(id, in: app)
                try app.performAccessibilityAudit()
                if id == "journal.notes" {
                    tap("note.room.entrance", in: app)
                    try app.performAccessibilityAudit()
                    let editor = app.textViews["note.editor"]
                    XCTAssertTrue(editor.waitForExistence(timeout: 5))
                    editor.tap()
                    editor.typeText("AX note")
                    tap("note.save", in: app)
                    try app.performAccessibilityAudit()
                    tap("note.delete", in: app)
                    try app.performAccessibilityAudit()
                    app.navigationBars["Entrance"].buttons["Room notes"].tap()
                }
                app.navigationBars[title].buttons["Journal"].tap()
            }
            app.terminate()
        }
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
