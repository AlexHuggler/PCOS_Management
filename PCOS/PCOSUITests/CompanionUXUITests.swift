import XCTest

@MainActor
final class CompanionUXUITests: XCTestCase {
    private func launch(theme: String = "calm", onboarding: Bool = true, largeText: Bool = false, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITestMode", "-onboarding.hasCompletedOnboarding", onboarding ? "YES" : "NO", "-onboarding.startPhase", "journey_5", "-appearance.themeOption", theme, "-app.language", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launchArguments += ["-appearance.colorMode", theme == "lunarCalm" ? "dark" : "light"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }

    func testSkipHealthWithoutPermissionsAndNoInventedCheckIn() {
        let app = launch(onboarding: false)
        // A7 Apple Health is optional: Skip goes straight to Today with nothing recorded.
        let skip = app.buttons["onboarding.finish"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()
        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        checkIn.tap()
        let save = app.buttons["symptom_log.save_button"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["Not recorded"].firstMatch.exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
    }

    func testNativeTabsAndCustomizationAcrossPresets() {
        for theme in ["calm", "lunarCalm", "botanicalJournal"] {
            let app = launch(theme: theme)
            let personalize = app.buttons["today.personalization"]
            XCTAssertTrue(personalize.waitForExistence(timeout: 10))
            XCTAssertEqual(app.tabBars.buttons.count, 5)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Today-\(theme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            personalize.tap()
            XCTAssertTrue(app.navigationBars["Make it yours"].waitForExistence(timeout: 5))
            app.buttons["Done"].tap()
            app.tabBars.buttons["Calendar"].tap()
            XCTAssertTrue(app.segmentedControls["calendar.view_mode"].waitForExistence(timeout: 5))
            app.segmentedControls["calendar.view_mode"].buttons["List"].tap()
            XCTAssertTrue(app.staticTexts["No records this month"].waitForExistence(timeout: 5))
            app.tabBars.buttons["Track"].tap()
            XCTAssertFalse(app.buttons["tracking.card.meal_scan"].exists)
            app.terminate()
        }
    }

    func testLargeTypeCheckInRemainsReachable() {
        let app = launch(largeText: true)
        let button = app.buttons["today.checkin"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue(app.buttons["symptom_log.save_button"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Check-in-large-type"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTodayAndCheckInAcrossSupportedLanguages() {
        for language in ["en", "de", "fr", "it", "ja", "ko", "nl"] {
            let app = launch(language: language)
            let button = app.buttons["today.checkin"]
            XCTAssertTrue(button.waitForExistence(timeout: 10), language)
            XCTAssertEqual(app.tabBars.buttons.count, 5, language)
            button.tap()
            let save = app.buttons["symptom_log.save_button"]
            XCTAssertTrue(save.waitForExistence(timeout: 5), language)
            XCTAssertFalse(save.isEnabled, language)
            XCTAssertTrue(app.buttons["symptom_log.mood"].exists, language)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Check-in-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
