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
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        // One CI round-trip per audit change: collect every finding on this
        // screen instead of failing the test on the first one.
        // The runtime dynamicType check is excluded: it nondeterministically
        // flags semantic .font(.body) List rows (element identity moved from
        // record.steps to record.sessions across runs with identical static
        // fonts). Measured frame growth in
        // testJournalDynamicTypeScalesMeasuredFrames is the behavioral gate.
        var found: [String] = []
        try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType)) { issue in
            let identity = issue.element.map { "\($0.identifier):\($0.label)" } ?? "no-element"
            found.append("\(screen)|\(issue.auditType)|\(issue.compactDescription)|\(identity)")
            if issue.element == nil {
                print("AUDIT NO-ELEMENT HIERARCHY \(screen): \(app.debugDescription)")
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Audit \(screen) \(issue.compactDescription)"
                screenshot.lifetime = .keepAlways
                self.add(screenshot)
            }
            return true // Collect all findings; XCTFail below preserves failure.
        }
        if !found.isEmpty {
            for finding in found { print("ACCESSIBILITY ISSUE: \(finding)") }
            XCTFail("Accessibility audit found \(found.count) issue(s) on \(screen): \(found.joined(separator: " ;; "))")
        }
    }

    @MainActor
    func testJournalDynamicTypeScalesMeasuredFrames() throws {
        // Direct evidence that journal copy honors Dynamic Type: every
        // sampled text must render taller at AX XXXL than at Large.
        func journalFrames(_ category: String) -> [String: CGFloat] {
            let app = XCUIApplication()
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", category]
            app.launchEnvironment["UIPreferredContentSizeCategoryName"] = category
            app.launch()
            tap("entrance.new", in: app)
            tap("journal.open", in: app)
            var frames: [String: CGFloat] = [:]
            frames["journal.record"] = app.buttons["journal.record"].frame.height
            tap("journal.notes", in: app)
            let noteRow = app.buttons["note.room.entrance"]
            XCTAssertTrue(noteRow.waitForExistence(timeout: 5))
            frames["note.room.entrance"] = noteRow.frame.height
            app.navigationBars["Room notes"].buttons["Journal"].tap()
            tap("journal.quests", in: app)
            let engine = app.staticTexts["quest.engine.silence"]
            XCTAssertTrue(engine.waitForExistence(timeout: 5))
            frames["quest.engine.silence"] = engine.frame.height
            app.navigationBars["Quest inscriptions"].buttons["Journal"].tap()
            tap("journal.record", in: app)
            for id in ["record.rooms", "record.steps", "record.sessions"] {
                let text = app.staticTexts[id]
                // At AX XXXL the record list overflows one screen; the
                // lower rows only materialize once scrolled into view.
                for _ in 0..<8 {
                    if text.exists { break }
                    app.swipeUp()
                }
                XCTAssertTrue(text.waitForExistence(timeout: 5), id)
                frames[id] = text.frame.height
            }
            app.terminate()
            return frames
        }
        let large = journalFrames("UICTContentSizeCategoryL")
        let largest = journalFrames("UICTContentSizeCategoryAccessibilityXXXL")
        for (id, small) in large {
            let big = largest[id] ?? 0
            print("DYNAMIC TYPE FRAME \(id): L=\(small) AX5=\(big)")
            XCTAssertGreaterThan(big, small, "text \(id) must render taller at AX XXXL")
        }
    }

    @MainActor
    func testJournalAccessibilityAuditAtDefaultAndLargestDynamicType() throws {
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", category]
            app.launchEnvironment["UIPreferredContentSizeCategoryName"] = category
            app.launch()
            tap("entrance.new", in: app)
            tap("journal.open", in: app)
            try audit(app, "journal")
            for (id, title) in [("journal.notes", "Room notes"), ("journal.quests", "Quest inscriptions"), ("journal.record", "Run record")] {
                tap(id, in: app)
                try audit(app, id)
                if id == "journal.notes" {
                    tap("note.room.entrance", in: app)
                    try audit(app, "note.editor.empty")
                    let editor = app.textViews["note.editor"]
                    XCTAssertTrue(editor.waitForExistence(timeout: 5))
                    editor.tap()
                    editor.typeText("AX note")
                    tap("note.save", in: app)
                    try audit(app, "note.editor.saved")
                    tap("note.delete", in: app)
                    try audit(app, "note.editor.deleted")
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
