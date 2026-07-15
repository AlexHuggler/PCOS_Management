//
//  PCOSUITests.swift
//  PCOSUITests
//
//  Created by Alex Huggler on 3/6/26.
//

import XCTest

final class PCOSUITests: XCTestCase {
    @MainActor
    private func makeApp(
        language: String? = nil,
        locale: String? = nil,
        onboardingCompleted: Bool,
        appLanguage: String? = nil,
        fontOption: String? = nil,
        themeOption: String? = nil,
        onboardingStartPhase: String? = nil,
        demoScenario: String? = nil,
        contentSizeCategory: String? = nil,
        csvImportFixture: String? = nil,
        jsonImportFixture: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = [
            "UITestMode",
            "-onboarding.hasCompletedOnboarding", onboardingCompleted ? "YES" : "NO",
            "-onboarding.hasCompletedWelcome", onboardingCompleted ? "YES" : "NO",
            "-onboarding.hasCompletedQuestionnaire", onboardingCompleted ? "YES" : "NO",
            "-onboarding.hasCompletedGuidedAction", onboardingCompleted ? "YES" : "NO",
        ]
        if !onboardingCompleted {
            launchArguments += [
                "-onboarding.hasPromptedForReview", "NO",
                "-onboarding.primaryGoal", "__unset__",
                "-onboarding.pcosExperience", "__unset__",
                "-onboarding.symptomFocusAreas", "__unset__",
                "-onboarding.preferredName", "__unset__",
            ]
        }
        if let language, let locale {
            launchArguments += [
                "-AppleLanguages", "(\(language))",
                "-AppleLocale", locale,
            ]
        }
        if let appLanguage {
            launchArguments += ["-app.language", appLanguage]
        }
        if let fontOption {
            launchArguments += ["-appearance.fontOption", fontOption]
        }
        if let themeOption {
            launchArguments += ["-appearance.themeOption", themeOption]
        }
        if let onboardingStartPhase {
            launchArguments += ["-onboarding.startPhase", onboardingStartPhase]
        }
        if let demoScenario {
            launchArguments += ["-uiTest.demoScenario", demoScenario]
        }
        if let contentSizeCategory {
            launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
        if let csvImportFixture {
            launchArguments += ["-settings.csvImportFixture", csvImportFixture]
        }
        if let jsonImportFixture {
            launchArguments += ["-settings.jsonImportFixture", jsonImportFixture]
        }
        app.launchArguments += launchArguments
        return app
    }

    @MainActor
    private func advanceWelcomeFlow(in app: XCUIApplication) {
        let questionnaireSkip = app.buttons["onboarding.questionnaire.skip"]
        let welcomePrimary = app.buttons["onboarding.welcome.primary"]

        XCTAssertTrue(welcomePrimary.waitForExistence(timeout: 5))

        for _ in 0..<4 where !questionnaireSkip.exists {
            welcomePrimary.tap()
            if questionnaireSkip.waitForExistence(timeout: 2) {
                break
            }
        }
    }

    @MainActor
    private func openSettingsTab(in app: XCUIApplication) {
        tapMainTab(.settings, in: app)
    }

    @MainActor
    private func screenElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func openCalendarTab(in app: XCUIApplication) {
        tapMainTab(.calendar, in: app)
    }

    @MainActor
    private func openTrackTab(in app: XCUIApplication) {
        tapMainTab(.track, in: app)
    }

    @MainActor
    private func openSymptomLogFromTrackHub(in app: XCUIApplication) {
        openTrackTab(in: app)

        let symptomCard = app.buttons["tracking.card.symptoms"]
        scrollToElement(symptomCard, in: app)
        symptomCard.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.symptom_log").waitForExistence(timeout: 5))
    }

    @MainActor
    private func openPeriodLogFromTrackHub(in app: XCUIApplication) {
        openTrackTab(in: app)

        let periodCard = app.buttons["tracking.card.period"]
        scrollToElement(periodCard, in: app)
        periodCard.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.cycle_log").waitForExistence(timeout: 5))
    }

    @MainActor
    private func openMealLogFromTrackHub(in app: XCUIApplication) {
        openTrackTab(in: app)

        let mealCard = app.buttons["tracking.card.meal"]
        scrollToElement(mealCard, in: app)
        mealCard.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.meal_log").waitForExistence(timeout: 5))
    }

    @MainActor
    private func openMealScanFromMealLog(in app: XCUIApplication) {
        let currentButton = app.buttons["meal_log.photo_estimate_button"]
        let legacyPremiumButton = app.buttons["meal_log.lunar.ai_meal_scan_primary"]
        let legacyStandardButton = app.buttons["meal_log.ai_meal_estimate_button"]
        let mealEstimateButton = currentButton.waitForExistence(timeout: 2)
            ? currentButton
            : (legacyPremiumButton.waitForExistence(timeout: 1) ? legacyPremiumButton : legacyStandardButton)

        scrollToElement(mealEstimateButton, in: app)
        mealEstimateButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.meal_scan").waitForExistence(timeout: 5))
    }

    @MainActor
    private func openOvulationLogFromTrackHub(in app: XCUIApplication) {
        openTrackTab(in: app)

        let ovulationCard = app.buttons["tracking.card.ovulation"]
        scrollToElement(ovulationCard, in: app)
        ovulationCard.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.ovulation_log").waitForExistence(timeout: 5))
    }

    @MainActor
    private func openBloodSugarLogFromTrackHub(in app: XCUIApplication) {
        openTrackTab(in: app)

        let bloodSugarCard = app.buttons["tracking.card.blood_sugar"]
        scrollToElement(bloodSugarCard, in: app)
        bloodSugarCard.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.blood_sugar_log").waitForExistence(timeout: 5))
    }

    @MainActor
    private func performSymptomSelectionStress(in app: XCUIApplication) {
        let tapPoints = [
            CGVector(dx: 105, dy: 410),
            CGVector(dx: 296, dy: 410),
            CGVector(dx: 105, dy: 555),
            CGVector(dx: 296, dy: 555),
            CGVector(dx: 105, dy: 410),
            CGVector(dx: 296, dy: 410),
            CGVector(dx: 105, dy: 555),
            CGVector(dx: 296, dy: 555),
            CGVector(dx: 105, dy: 410),
            CGVector(dx: 296, dy: 410),
        ]
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))

        for point in tapPoints {
            origin.withOffset(point).tap()
        }
    }

    @MainActor
    private func openInsightsTab(in app: XCUIApplication) {
        tapMainTab(.insights, in: app)
    }

    @MainActor
    private func openTodayTab(in app: XCUIApplication) {
        tapMainTab(.today, in: app)
    }

    @MainActor
    private func assertCalendarScreen(
        in app: XCUIApplication,
        localizedTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.otherElements["calendar.grid"].waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.staticTexts[localizedTitle].waitForExistence(timeout: 5),
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertNoPlaceholderTokensVisible(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let forbiddenTokens = ["トークン", "GETTONE", "JETON", "TOKEN_", "__", "토큰"]

        for token in forbiddenTokens {
            let predicate = NSPredicate(format: "label CONTAINS %@", token)
            let matches = app.staticTexts.matching(predicate)
            XCTAssertEqual(
                matches.count,
                0,
                "Found token placeholder text containing '\(token)' in the visible UI: \(matches.firstMatch.label)",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func scrollToElement(
        _ element: XCUIElement,
        in container: XCUIElement,
        maxSwipes: Int = 16,
        requireHittable: Bool = true,
        requireSafeTapZone: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if isReadyForScrollTarget(element, in: container, requireHittable: requireHittable, requireSafeTapZone: requireSafeTapZone) {
            return
        }

        _ = element.waitForExistence(timeout: 1)

        for _ in 0..<maxSwipes {
            if isReadyForScrollTarget(element, in: container, requireHittable: requireHittable, requireSafeTapZone: requireSafeTapZone) {
                return
            }
            container.swipeUp()
        }

        for _ in 0..<maxSwipes {
            if isReadyForScrollTarget(element, in: container, requireHittable: requireHittable, requireSafeTapZone: requireSafeTapZone) {
                return
            }
            container.swipeDown()
        }

        XCTAssertTrue(element.waitForExistence(timeout: 2), file: file, line: line)
        if requireHittable {
            XCTAssertTrue(element.isHittable, file: file, line: line)
        }
        if requireSafeTapZone {
            XCTAssertTrue(isInSafeTapZone(element, in: container), file: file, line: line)
        }
    }

    @MainActor
    private func isReadyForScrollTarget(
        _ element: XCUIElement,
        in container: XCUIElement,
        requireHittable: Bool,
        requireSafeTapZone: Bool
    ) -> Bool {
        element.exists
            && (!requireHittable || element.isHittable)
            && (!requireSafeTapZone || isInSafeTapZone(element, in: container))
    }

    @MainActor
    private func waitForInsightsContent(in app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        let screen = app.collectionViews["screen.insights"]
        if screen.waitForExistence(timeout: timeout / 3) {
            return true
        }

        let list = app.descendants(matching: .any).matching(identifier: "insights.list").firstMatch
        if list.waitForExistence(timeout: timeout / 2) {
            return true
        }

        let disclosureButton = firstVisibleInsightDisclosureButton(in: app, maxSwipes: 10)
        if disclosureButton.waitForExistence(timeout: timeout / 2) {
            return true
        }

        let card = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "insights.card.")
        ).firstMatch
        return card.waitForExistence(timeout: timeout / 2)
    }

    @MainActor
    private func isInSafeTapZone(_ element: XCUIElement, in container: XCUIElement) -> Bool {
        let bottomSafeInset: CGFloat = 80
        return element.frame.maxY <= container.frame.maxY - bottomSafeInset
    }

    @MainActor
    private func waitForNonEmptyFrame(
        of element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGRect {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)

        let deadline = Date().addingTimeInterval(timeout)
        var frame = element.frame

        while frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            frame = element.frame
        }

        XCTAssertFalse(frame.isEmpty, "Expected a non-empty frame for \(element).", file: file, line: line)
        return frame
    }

    @MainActor
    private func scrollToVisibleFrame(
        _ element: XCUIElement,
        in container: XCUIElement,
        bottomSafeInset: CGFloat = 80,
        maxSwipes: Int = 16,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGRect {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)

        var frame = waitForNonEmptyFrame(of: element, timeout: 5, file: file, line: line)
        for _ in 0..<maxSwipes where frame.maxY > container.frame.maxY - bottomSafeInset {
            container.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            frame = waitForNonEmptyFrame(of: element, timeout: 2, file: file, line: line)
        }

        XCTAssertLessThanOrEqual(frame.maxY, container.frame.maxY - bottomSafeInset, file: file, line: line)
        return frame
    }

    @MainActor
    private func saveScreenshotArtifact(named filename: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = filename
        attachment.lifetime = .keepAlways
        add(attachment)

        let directoryURL: URL
        if filename.hasPrefix("task-2-") {
            directoryURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".superpowers/sdd/task-2-screenshots", isDirectory: true)
        } else if let artifactDirectory = ProcessInfo.processInfo.environment["BOTANICAL_UI_ARTIFACT_DIR"] {
            directoryURL = URL(fileURLWithPath: artifactDirectory, isDirectory: true)
        } else {
            directoryURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Artifacts", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let screenshotURL = directoryURL.appendingPathComponent(filename)
        try screenshot.pngRepresentation.write(to: screenshotURL, options: .atomic)
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testSymptomLogPerformanceSmokeWithDemoData() throws {
        measure(metrics: [XCTClockMetric()]) {
            let app = makeApp(
                language: "en",
                locale: "en_US",
                onboardingCompleted: true,
                appLanguage: "system",
                demoScenario: "symptomManagement"
            )
            app.launch()

            openSymptomLogFromTrackHub(in: app)
            performSymptomSelectionStress(in: app)

            let saveButton = app.buttons["symptom_log.save_button"]
            XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
            XCTAssertTrue(saveButton.isEnabled)
            XCTAssertEqual(app.state, .runningForeground)

            app.terminate()
        }
    }

    @MainActor
    func testMealLogOpensFromTrackHubWithDemoData() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal",
            demoScenario: "symptomManagement"
        )
        app.launchArguments += ["-reports.resetPolicy", "YES"]
        app.launch()

        openTrackTab(in: app)

        let mealCard = app.buttons["tracking.card.meal"]
        scrollToElement(mealCard, in: app)
        mealCard.tap()

        XCTAssertTrue(app.textFields["meal_log.description"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_log.history_button"].waitForExistence(timeout: 5))

        let scanBarcodeButton = app.buttons["meal_log.scan_barcode_button"]
        scrollToElement(scanBarcodeButton, in: app)
        XCTAssertTrue(scanBarcodeButton.waitForExistence(timeout: 5))
        scanBarcodeButton.tap()

        let consentButton = app.buttons["meal_log.barcode_consent_continue"]
        if consentButton.waitForExistence(timeout: 2) {
            consentButton.tap()
        }
        XCTAssertTrue(app.textFields["meal_log.manual_barcode_field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_log.lookup_barcode_button"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
    }

    @MainActor
    func testOvulationLogOpensFromTrackHubWithDemoData() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal",
            demoScenario: "symptomManagement"
        )
        app.launch()

        openTrackTab(in: app)

        let ovulationCard = app.buttons["tracking.card.ovulation"]
        scrollToElement(ovulationCard, in: app)
        ovulationCard.tap()

        XCTAssertTrue(app.datePickers["ovulationLog.date"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["ovulationLog.temperature"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ovulationLog.save"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMealLogOpensFromTodayMealSummaryWithDemoData() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            demoScenario: "symptomManagement"
        )
        app.launch()

        let mealSummary = app.buttons["today.meal_summary.open_log"]
        scrollToElement(mealSummary, in: app)
        mealSummary.tap()

        XCTAssertTrue(app.textFields["meal_log.description"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_log.history_button"].waitForExistence(timeout: 5))

        // The scan tile lives in a lazy grid below the fold; scroll it into
        // existence like testMealLogOpensFromTrackHubWithDemoData does.
        let scanBarcodeButton = app.buttons["meal_log.scan_barcode_button"]
        scrollToElement(scanBarcodeButton, in: app)
        XCTAssertTrue(scanBarcodeButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testTodayHeroResolvesToSingleCurrentCycleCardWithoutOverlap() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            demoScenario: "symptomManagement"
        )
        app.launch()

        let todayScreen = app.otherElements["screen.today"]
        XCTAssertTrue(todayScreen.waitForExistence(timeout: 10))

        let heroContainer = app.otherElements["today.hero.container"]
        let currentCycleLabel = app.staticTexts["today.hero.current_cycle_label"]
        let welcomeTitle = app.staticTexts["today.hero.welcome_title"]
        let quickPeriodLogRow = app.otherElements["today.quick_period_log"]

        let heroFrame = waitForNonEmptyFrame(of: heroContainer)
        let quickLogFrame = waitForNonEmptyFrame(of: quickPeriodLogRow)

        XCTAssertTrue(currentCycleLabel.waitForExistence(timeout: 5))
        XCTAssertFalse(welcomeTitle.exists)
        XCTAssertLessThanOrEqual(
            heroFrame.maxY,
            quickLogFrame.minY,
            "Expected the Today hero card to finish above the quick period log row."
        )
    }

    @MainActor
    func testMarkPeriodEndFlowWithDemoData() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            demoScenario: "symptomManagement"
        )
        app.launch()

        openTodayTab(in: app)

        let periodEndButton = app.buttons["today.period_end_button"]
        scrollToElement(periodEndButton, in: app)
        periodEndButton.tap()

        let saveButton = app.buttons["period_end.save_button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let periodEndStatus = app.descendants(matching: .any)["today.period_end_status"]
        XCTAssertTrue(periodEndStatus.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Edit Period End Date"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testInsightsDisclosureSheetAndFooterAreVisibleWithDemoData() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal",
            demoScenario: "symptomManagement"
        )
        app.launch()

        openInsightsTab(in: app)

        let footer = app.staticTexts["insights.footer.disclaimer"]
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForInsightsContent(in: app))
        let sharedIntroCard = app.descendants(matching: .any)["insights.shared_intro_card"]
        scrollToElement(sharedIntroCard, in: app)
        XCTAssertTrue(sharedIntroCard.waitForExistence(timeout: 5))

        let disclosureButton = firstVisibleInsightDisclosureButton(in: app, timeout: 0.5, maxSwipes: 3)
        if disclosureButton.exists {
            disclosureButton.tap()

            XCTAssertTrue(app.otherElements["evidence_disclosure.sheet"].waitForExistence(timeout: 5))
            XCTAssertTrue(screenElement(in: app, identifier: "evidence_disclosure.specific_explanation").waitForExistence(timeout: 5))
            XCTAssertTrue(screenElement(in: app, identifier: "evidence_disclosure.evidence_summary").waitForExistence(timeout: 5))

            app.buttons["evidence_disclosure.done_button"].tap()
            XCTAssertFalse(app.otherElements["evidence_disclosure.sheet"].exists)
        }
    }

    @MainActor
    func testSupplementCatalogSourcesAreShownOnlyForCatalogSelections() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            demoScenario: "symptomManagement"
        )
        app.launch()

        openTrackTab(in: app)

        let supplementCard = app.buttons["tracking.card.supplements"]
        scrollToElement(supplementCard, in: app)
        supplementCard.tap()

        XCTAssertTrue(app.buttons["supplement_log.inline_history_button"].waitForExistence(timeout: 5))

        let addButton = app.buttons["supplement_log.add_button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let searchField = app.textFields["supplement_log.add_sheet.search_field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        let inositolResult = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Inositol")
        ).firstMatch
        XCTAssertTrue(inositolResult.waitForExistence(timeout: 5))
        inositolResult.tap()

        let sourcesButton = app.buttons["supplement_log.catalog.inositol.sources_button"]
        XCTAssertTrue(sourcesButton.waitForExistence(timeout: 5))
        sourcesButton.tap()

        XCTAssertTrue(app.otherElements["evidence_disclosure.sheet"].waitForExistence(timeout: 5))
        let referencesToggle = app.descendants(matching: .any)["evidence_disclosure.references_toggle"]
        scrollToElement(referencesToggle, in: app)
        XCTAssertTrue(referencesToggle.waitForExistence(timeout: 5))
        app.buttons["evidence_disclosure.done_button"].tap()

        let addSheetCancelButton = app.buttons["supplement_log.add_sheet.cancel_button"]
        XCTAssertTrue(addSheetCancelButton.waitForExistence(timeout: 5))
        addSheetCancelButton.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["Discard"].tap()

        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Custom Blend")

        let sourcesButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "supplement_log.catalog.")
        )
        XCTAssertEqual(sourcesButtons.count, 0)
    }

    @MainActor
    func testLunarCalmSupplementLogAddSheetAndHistoryOpenFromTrackHub() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openTrackTab(in: app)

        let supplementCard = app.buttons["tracking.card.supplements"]
        scrollToElement(supplementCard, in: app)
        supplementCard.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.supplement_log").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "supplement_log.lunar.header"), timeout: 10)
        XCTAssertTrue(app.buttons["supplement_log.inline_history_button"].waitForExistence(timeout: 5))

        let addButton = app.buttons["supplement_log.add_button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-supplement-log.png")

        addButton.tap()
        XCTAssertTrue(screenElement(in: app, identifier: "supplement_log.add_sheet").waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["supplement_log.add_sheet.search_field"].waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-supplement-add-sheet.png")

        app.buttons["supplement_log.add_sheet.cancel_button"].tap()
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))

        let historyButton = app.buttons["supplement_log.inline_history_button"]
        scrollToElement(historyButton, in: app)
        historyButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.supplement_history").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "supplement_history.lunar.adherence"), timeout: 10)
        try saveScreenshotArtifact(named: "lunar-calm-supplement-history.png")
    }

    @MainActor
    func testFruitGroveSupplementLogAndHistoryUsePremiumShell() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "fruitGrove",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        openTrackTab(in: app)

        let supplementCard = app.buttons["tracking.card.supplements"]
        scrollToElement(supplementCard, in: app)
        supplementCard.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.supplement_log").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "supplement_log.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["supplement_log.inline_history_button"].waitForExistence(timeout: 5))

        let addButton = app.buttons["supplement_log.add_button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        XCTAssertTrue(screenElement(in: app, identifier: "supplement_log.add_sheet").waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["supplement_log.add_sheet.search_field"].waitForExistence(timeout: 5))
        app.buttons["supplement_log.add_sheet.cancel_button"].tap()

        let historyButton = app.buttons["supplement_log.inline_history_button"]
        scrollToElement(historyButton, in: app)
        historyButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.supplement_history").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "supplement_history.lunar.adherence").waitForExistence(timeout: 5))
    }

    @MainActor
    func testPhotoComparisonOpensFromPhotoJournalWithDemoData() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            demoScenario: "symptomManagement"
        )
        app.launch()

        openTrackTab(in: app)

        let photoCard = app.buttons["tracking.card.photo"]
        scrollToElement(photoCard, in: app)
        photoCard.tap()

        XCTAssertTrue(app.otherElements["screen.photo_journal"].waitForExistence(timeout: 5))

        let compareButton = app.buttons["photo_journal.compare_button"]
        XCTAssertTrue(compareButton.waitForExistence(timeout: 5))
        compareButton.tap()

        XCTAssertTrue(app.staticTexts["Before"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["After"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLunarCalmPhotoJournalAndComparisonOpenFromTrackHub() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openTrackTab(in: app)

        let photoCard = app.buttons["tracking.card.photo"]
        scrollToElement(photoCard, in: app)
        photoCard.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.photo_journal").waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-photo-journal.png")
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "photo_journal.lunar.header"), timeout: 10)
        XCTAssertTrue(app.staticTexts["Private progress photos"].waitForExistence(timeout: 5))

        let compareButton = app.buttons["photo_journal.compare_button"]
        XCTAssertTrue(compareButton.waitForExistence(timeout: 5))

        compareButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.photo_comparison").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "photo_comparison.lunar.content"), timeout: 10)
        XCTAssertTrue(app.staticTexts["Before"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["After"].waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-photo-comparison.png")
    }

    @MainActor
    func testFruitGrovePhotoJournalCaptureAndComparisonUsePremiumShell() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "fruitGrove",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        openTrackTab(in: app)

        let photoCard = app.buttons["tracking.card.photo"]
        scrollToElement(photoCard, in: app)
        photoCard.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.photo_journal").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "photo_journal.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Private progress photos"].waitForExistence(timeout: 5))

        let addButton = app.buttons["photo_journal.add_button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.photo_capture").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "photo_capture.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "photo_capture.lunar.type").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "photo_capture.lunar.photo_section").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "photo_capture.lunar.save_button").waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.photo_journal").waitForExistence(timeout: 5))
        let compareButton = app.buttons["photo_journal.compare_button"]
        XCTAssertTrue(compareButton.waitForExistence(timeout: 5))
        compareButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.photo_comparison").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "photo_comparison.lunar.content").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Before"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["After"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLunarCalmPhotoDetailOpensFromPhotoJournal() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openTrackTab(in: app)

        let photoCard = app.buttons["tracking.card.photo"]
        scrollToElement(photoCard, in: app)
        photoCard.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.photo_journal").waitForExistence(timeout: 5))

        let photoTile = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "photo_journal.lunar.photo."))
            .firstMatch
        XCTAssertTrue(photoTile.waitForExistence(timeout: 5))
        photoTile.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.photo_detail").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "photo_detail.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "photo_detail.lunar.metadata").waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-photo-detail.png")
    }

    @MainActor
    func testLunarCalmPhotoCaptureOpensFromPhotoJournal() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openTrackTab(in: app)

        let photoCard = app.buttons["tracking.card.photo"]
        scrollToElement(photoCard, in: app)
        photoCard.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.photo_journal").waitForExistence(timeout: 5))
        let addButton = app.buttons["photo_journal.add_button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.photo_capture").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "photo_capture.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "photo_capture.lunar.photo_section").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "photo_capture.lunar.notes").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "photo_capture.lunar.date").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["photo_capture.lunar.save_button"].waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-photo-capture.png")
    }

    @MainActor
    func testBotanicalJournalCalendarAndTrackBottomContentClearsCustomTabBar() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal",
            demoScenario: "symptomManagement"
        )
        app.launch()

        openTodayTab(in: app)
        XCTAssertTrue(screenElement(in: app, identifier: "screen.today").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "today.lunar.header").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "today.hero.container").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "today.lunar.snapshot").waitForExistence(timeout: 10))
        try saveScreenshotArtifact(named: "botanical-today-shell.png")
        let mealSummary = app.buttons["today.meal_summary.open_log"]
        _ = scrollToVisibleFrame(mealSummary, in: app)
        try saveScreenshotArtifact(named: "botanical-today-bottom-clearance.png")

        openCalendarTab(in: app)
        XCTAssertTrue(app.otherElements["screen.calendar"].waitForExistence(timeout: 10))
        let cycleDetailsCard = app.descendants(matching: .any)["calendar.cycle_details.card"]
        scrollToElement(cycleDetailsCard, in: app)
        XCTAssertTrue(cycleDetailsCard.isHittable)
        try saveScreenshotArtifact(named: "botanical-calendar-bottom-clearance.png")

        openTrackTab(in: app)
        let photoJournalCard = app.buttons["tracking.card.photo"]
        scrollToElement(photoJournalCard, in: app)
        XCTAssertTrue(photoJournalCard.isHittable)
        try saveScreenshotArtifact(named: "botanical-track-bottom-clearance.png")

        openInsightsTab(in: app)
        XCTAssertTrue(waitForInsightsContent(in: app))
        let insightsFooter = app.staticTexts["insights.footer.disclaimer"]
        let insightsFooterFrame = waitForNonEmptyFrame(of: insightsFooter, timeout: 10)
        XCTAssertLessThanOrEqual(insightsFooterFrame.maxY, app.frame.maxY - 80)
        try saveScreenshotArtifact(named: "botanical-insights-bottom-clearance.png")

        openSettingsTab(in: app)
        let settingsScreen = screenElement(in: app, identifier: "screen.settings")
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 10))
        let deleteAllDataButton = app.buttons["settings.delete_all_data"]
        scrollToElement(deleteAllDataButton, in: settingsScreen)
        XCTAssertTrue(deleteAllDataButton.isHittable)
        try saveScreenshotArtifact(named: "botanical-settings-bottom-clearance.png")
    }

    @MainActor
    func testBotanicalJournalAccessibilityTextSizeKeepsNavigationAndCTAsReachable() throws {
        let accessibilityTextSize = "UICTContentSizeCategoryAccessibilityXXXL"
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal",
            demoScenario: "symptomManagement",
            contentSizeCategory: accessibilityTextSize
        )
        app.launch()

        XCTAssertTrue(app.otherElements["botanical.tab_bar"].waitForExistence(timeout: 10))
        assertMainTabShellPresent(in: app)

        openCalendarTab(in: app)
        XCTAssertTrue(app.otherElements["calendar.grid"].waitForExistence(timeout: 10))
        let cycleDetailsCard = app.descendants(matching: .any)["calendar.cycle_details.card"]
        scrollToElement(cycleDetailsCard, in: app)
        XCTAssertTrue(cycleDetailsCard.isHittable)

        openSettingsTab(in: app)
        let settingsScreen = screenElement(in: app, identifier: "screen.settings")
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 10))
        let deleteAllDataButton = app.buttons["settings.delete_all_data"]
        scrollToElement(deleteAllDataButton, in: settingsScreen)
        XCTAssertTrue(deleteAllDataButton.isHittable)
        app.terminate()

        let onboardingApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: false,
            appLanguage: "system",
            themeOption: "botanicalJournal",
            onboardingStartPhase: "all_set",
            contentSizeCategory: accessibilityTextSize
        )
        onboardingApp.launch()

        XCTAssertTrue(screenElement(in: onboardingApp, identifier: "screen.onboarding.completion").waitForExistence(timeout: 10))
        let finishButton = onboardingApp.buttons["onboarding.completion.finish"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 10))
        XCTAssertTrue(finishButton.isHittable)
    }

    @MainActor
    func testOnboardingResultsAccessibilityTextSizeKeepsActionsReachable() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: false,
            appLanguage: "system",
            themeOption: "botanicalJournal",
            onboardingStartPhase: "results",
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        app.launch()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.onboarding.results").waitForExistence(timeout: 10))
        let continueButton = app.buttons["onboarding.results.continue"]
        let skipButton = app.buttons["onboarding.results.skip"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        XCTAssertTrue(skipButton.waitForExistence(timeout: 10))
        XCTAssertTrue(continueButton.isHittable)
        XCTAssertTrue(skipButton.isHittable)
    }

    @MainActor
    func testLunarCalmThemeLaunchesCustomTabsAndPilotSurfaces() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["today.hero.container"].waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "today.lunar.header").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "today.lunar.snapshot").waitForExistence(timeout: 10))
        try saveScreenshotArtifact(named: "lunar-calm-today-shell.png")

        openInsightsTab(in: app)
        let lunarDashboard = app.otherElements["insights.lunar_dashboard"]
        _ = waitForNonEmptyFrame(of: lunarDashboard, timeout: 10)
        try saveScreenshotArtifact(named: "lunar-calm-insights-dashboard.png")

        openTrackTab(in: app)
        let lunarTrackHeader = screenElement(in: app, identifier: "tracking.lunar.header")
        _ = waitForNonEmptyFrame(of: lunarTrackHeader, timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "tracking.lunar.quick_rail").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "tracking.lunar.card_cluster").waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-track-hub.png")

        let symptomCard = app.buttons["tracking.card.symptoms"]
        scrollToElement(symptomCard, in: app)
        XCTAssertTrue(symptomCard.isHittable)

        openSettingsTab(in: app)
        let lunarSettingsOverview = screenElement(in: app, identifier: "settings.lunar.support_overview")
        _ = waitForNonEmptyFrame(of: lunarSettingsOverview, timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "settings.lunar.reminders").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "settings.lunar.daily_checkin").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "settings.lunar.support_card").waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["settings.lunar.reminder.symptoms"].waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-settings-support.png")

        let lunarCalmPreview = app.descendants(matching: .any)["settings.display.theme_preview"]
        scrollToElement(lunarCalmPreview, in: app)
        XCTAssertTrue(lunarCalmPreview.exists)

        openCalendarTab(in: app)
        XCTAssertTrue(app.otherElements["screen.calendar"].waitForExistence(timeout: 10))
        let lunarCalendarPanel = screenElement(in: app, identifier: "calendar.lunar.panel")
        _ = waitForNonEmptyFrame(of: lunarCalendarPanel, timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "calendar.lunar.header").waitForExistence(timeout: 10))

        let lunarTimeline = screenElement(in: app, identifier: "calendar.lunar.timeline")
        let timelineFrame = waitForNonEmptyFrame(of: lunarTimeline, timeout: 10)
        XCTAssertLessThanOrEqual(timelineFrame.maxY, app.frame.maxY - 80)
        try saveScreenshotArtifact(named: "lunar-calm-calendar.png")

        try saveScreenshotArtifact(named: "lunar-calm-pilot-surfaces.png")
    }

    @MainActor
    func testLunarCalmAppearsInSettingsThemePickerForInternalReview() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            demoScenario: "symptomManagement"
        )
        app.launch()

        openSettingsTab(in: app)
        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))

        let themePicker = screenElement(in: app, identifier: "settings.display.theme")
        scrollToElement(themePicker, in: settingsScreen)
        XCTAssertTrue(screenElement(in: app, identifier: "settings.display.experimental_themes").exists)
        themePicker.tap()

        let lunarCalmButton = app.buttons["Lunar Calm"]
        let lunarCalmText = app.staticTexts["Lunar Calm"]
        XCTAssertTrue(
            lunarCalmButton.waitForExistence(timeout: 3) || lunarCalmText.waitForExistence(timeout: 3)
        )
        try saveScreenshotArtifact(named: "lunar-calm-settings-picker.png")
    }

    @MainActor
    func testLunarCalmTodaySymptomLogUsesFullScreenPresentation() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openTodayTab(in: app)
        let logSymptomsButton = app.buttons["Log Symptoms"]
        scrollToElement(logSymptomsButton, in: app)
        logSymptomsButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.symptom_log").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "symptom_log.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "symptom_log.lunar.mood_section").waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-today-symptom-log.png")
    }

    @MainActor
    func testLunarCalmPregnancyModeUsesFullScreenPresentation() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))

        let pregnancyButton = app.buttons["settings.pregnancy.enter"]
        scrollToElement(pregnancyButton, in: settingsScreen)
        pregnancyButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.pregnancy_activation").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "pregnancy_activation.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "pregnancy_activation.lunar.mode_card").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "pregnancy_activation.lunar.start_card").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "pregnancy_activation.lunar.due_date_card").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pregnancy_activation.lunar.submit"].waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-pregnancy-activation.png")
    }

    @MainActor
    func testFruitGrovePregnancyModeUsesPremiumActivationShell() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "fruitGrove",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))

        let pregnancyButton = app.buttons["settings.pregnancy.enter"]
        scrollToElement(pregnancyButton, in: settingsScreen)
        pregnancyButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.pregnancy_activation").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "pregnancy_activation.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "pregnancy_activation.lunar.mode_card").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "pregnancy_activation.lunar.start_card").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "pregnancy_activation.lunar.due_date_card").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pregnancy_activation.lunar.submit"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLunarCalmSettingsSecondarySurfaces() throws {
        let languageApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        languageApp.launch()
        openSettingsTab(in: languageApp)
        let languageSettingsScreen = languageApp.collectionViews["screen.settings"]
        XCTAssertTrue(languageSettingsScreen.waitForExistence(timeout: 5))
        let appLanguageRow = languageApp.buttons["settings.app_language.row"]
        scrollToElement(appLanguageRow, in: languageSettingsScreen)
        appLanguageRow.tap()
        XCTAssertTrue(screenElement(in: languageApp, identifier: "screen.settings.app_language").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: languageApp, identifier: "settings.app_language.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(languageApp.buttons["settings.app_language.option.system"].waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-settings-language.png")
        languageApp.terminate()

        let notificationsApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        notificationsApp.launch()
        openSettingsTab(in: notificationsApp)
        let notificationSettingsScreen = notificationsApp.collectionViews["screen.settings"]
        XCTAssertTrue(notificationSettingsScreen.waitForExistence(timeout: 5))
        let notificationsRow = notificationsApp.buttons["settings.notifications.row"]
        scrollToElement(notificationsRow, in: notificationSettingsScreen)
        notificationsRow.tap()
        XCTAssertTrue(screenElement(in: notificationsApp, identifier: "screen.settings.notifications").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: notificationsApp, identifier: "settings.notifications.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: notificationsApp, identifier: "settings.notifications.lunar.authorization").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: notificationsApp, identifier: "settings.notifications.lunar.reminders").waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-settings-notifications.png")
        notificationsApp.terminate()

        let csvGuideApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        csvGuideApp.launch()
        openSettingsTab(in: csvGuideApp)
        let csvGuideSettingsScreen = csvGuideApp.collectionViews["screen.settings"]
        XCTAssertTrue(csvGuideSettingsScreen.waitForExistence(timeout: 5))
        let guideButton = csvGuideApp.buttons["settings.csv_import_guide"]
        scrollToElement(guideButton, in: csvGuideSettingsScreen)
        guideButton.tap()
        XCTAssertTrue(screenElement(in: csvGuideApp, identifier: "screen.settings.csv_import_guide").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: csvGuideApp, identifier: "settings.csv_guide.lunar.intro").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: csvGuideApp, identifier: "settings.csv_guide.lunar.types").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: csvGuideApp, identifier: "settings.csv_guide.lunar.rules").waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-settings-csv-guide.png")
        csvGuideApp.terminate()

        let importResultApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement",
            csvImportFixture: "invalid"
        )
        importResultApp.launch()
        openSettingsTab(in: importResultApp)
        let importSettingsScreen = importResultApp.collectionViews["screen.settings"]
        XCTAssertTrue(importSettingsScreen.waitForExistence(timeout: 5))
        let importButton = importResultApp.buttons["settings.import_external_csv"]
        scrollToElement(importButton, in: importSettingsScreen)
        importButton.tap()
        XCTAssertTrue(screenElement(in: importResultApp, identifier: "screen.settings.import_result").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: importResultApp, identifier: "settings.import_result.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: importResultApp, identifier: "settings.import_result.lunar.counts").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: importResultApp, identifier: "settings.import_result.lunar.issues").waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-settings-import-result.png")
    }

    @MainActor
    func testLunarCalmReportConfigOpensFromInsights() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openInsightsTab(in: app)
        XCTAssertTrue(screenElement(in: app, identifier: "screen.insights").waitForExistence(timeout: 10))
        try saveScreenshotArtifact(named: "lunar-calm-insights-report-entry.png")

        let reportExportButton = app.buttons["insights.lunar_dashboard.report_button"]
        scrollToElement(reportExportButton, in: app)
        XCTAssertTrue(reportExportButton.waitForExistence(timeout: 5))
        let reportIconButton = app.buttons["insights.lunar_dashboard.report_icon_button"]
        scrollToElement(reportIconButton, in: app)
        XCTAssertTrue(reportIconButton.waitForExistence(timeout: 5))
        reportIconButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.report_config").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "report.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "report.lunar.range").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "report.lunar.presets").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "report.lunar.sections").waitForExistence(timeout: 5))
        let exportCard = screenElement(in: app, identifier: "report.lunar.export")
        XCTAssertTrue(exportCard.waitForExistence(timeout: 5))
        scrollToElement(exportCard, in: app, maxSwipes: 8)
        try saveScreenshotArtifact(named: "lunar-calm-report-config.png")
    }

    @MainActor
    func testLunarCalmEvidenceDisclosureUsesFullScreenPresentation() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openInsightsTab(in: app)
        XCTAssertTrue(waitForInsightsContent(in: app))

        let disclosureButton = firstVisibleInsightDisclosureButton(in: app, timeout: 1, maxSwipes: 8)
        XCTAssertTrue(disclosureButton.waitForExistence(timeout: 5))
        disclosureButton.tap()

        XCTAssertTrue(app.otherElements["evidence_disclosure.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "screen.evidence_disclosure").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "evidence_disclosure.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "evidence_disclosure.lunar.specific_explanation").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "evidence_disclosure.lunar.evidence_summary").waitForExistence(timeout: 5))

        let referencesToggle = app.buttons["evidence_disclosure.references_toggle"]
        for _ in 0..<3 where !referencesToggle.exists {
            app.swipeUp()
        }
        if referencesToggle.waitForExistence(timeout: 2) {
            referencesToggle.tap()
            XCTAssertTrue(screenElement(in: app, identifier: "evidence_disclosure.references_content").waitForExistence(timeout: 5))
        }

        try saveScreenshotArtifact(named: "lunar-calm-evidence-disclosure.png")

        app.buttons["evidence_disclosure.done_button"].tap()
        XCTAssertFalse(app.otherElements["evidence_disclosure.sheet"].exists)
    }

    @MainActor
    func testFruitGroveTrustSurfacesUsePremiumShell() throws {
        let reportApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "fruitGrove",
            demoScenario: "symptomManagement"
        )
        reportApp.launch()

        XCTAssertTrue(reportApp.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        openInsightsTab(in: reportApp)
        XCTAssertTrue(waitForInsightsContent(in: reportApp))

        let reportExportButton = reportApp.buttons["insights.lunar_dashboard.report_button"]
        scrollToElement(reportExportButton, in: reportApp)
        XCTAssertTrue(reportExportButton.waitForExistence(timeout: 5))
        let reportIconButton = reportApp.buttons["insights.lunar_dashboard.report_icon_button"]
        scrollToElement(reportIconButton, in: reportApp)
        XCTAssertTrue(reportIconButton.waitForExistence(timeout: 5))
        reportIconButton.tap()

        XCTAssertTrue(screenElement(in: reportApp, identifier: "screen.report_config").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: reportApp, identifier: "report.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: reportApp, identifier: "report.lunar.range").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: reportApp, identifier: "report.lunar.export").waitForExistence(timeout: 5))
        reportApp.terminate()

        let evidenceApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "fruitGrove",
            demoScenario: "symptomManagement"
        )
        evidenceApp.launch()

        XCTAssertTrue(evidenceApp.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        openInsightsTab(in: evidenceApp)
        XCTAssertTrue(waitForInsightsContent(in: evidenceApp))

        let disclosureButton = firstVisibleInsightDisclosureButton(in: evidenceApp, timeout: 1, maxSwipes: 8)
        XCTAssertTrue(disclosureButton.waitForExistence(timeout: 5))
        disclosureButton.tap()

        XCTAssertTrue(evidenceApp.otherElements["evidence_disclosure.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: evidenceApp, identifier: "screen.evidence_disclosure").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: evidenceApp, identifier: "evidence_disclosure.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: evidenceApp, identifier: "evidence_disclosure.lunar.specific_explanation").waitForExistence(timeout: 5))
        evidenceApp.terminate()

        let notificationsApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "fruitGrove",
            demoScenario: "symptomManagement"
        )
        notificationsApp.launch()

        XCTAssertTrue(notificationsApp.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        openSettingsTab(in: notificationsApp)
        let settingsScreen = notificationsApp.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))

        let notificationsRow = notificationsApp.buttons["settings.notifications.row"]
        scrollToElement(notificationsRow, in: settingsScreen)
        notificationsRow.tap()

        XCTAssertTrue(screenElement(in: notificationsApp, identifier: "screen.settings.notifications").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: notificationsApp, identifier: "settings.notifications.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: notificationsApp, identifier: "settings.notifications.lunar.authorization").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: notificationsApp, identifier: "settings.notifications.lunar.reminders").waitForExistence(timeout: 5))
    }

    @MainActor
    func testLunarCalmSymptomLogOpensFromTrackHub() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openSymptomLogFromTrackHub(in: app)

        XCTAssertTrue(screenElement(in: app, identifier: "symptom_log.lunar.header").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "symptom_log.lunar.date_strip").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "symptom_log.lunar.mood_section").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "symptom_log.lunar.symptom_chips").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "symptom_log.lunar.slider.flow").waitForExistence(timeout: 5))

        let crampsChip = screenElement(in: app, identifier: "symptom_log.lunar.chip.cramps")
        scrollToElement(crampsChip, in: app)
        XCTAssertTrue(crampsChip.isHittable)
        crampsChip.tap()

        let saveButton = app.buttons["symptom_log.save_button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(saveButton.isEnabled)

        try saveScreenshotArtifact(named: "lunar-calm-symptom-log.png")
    }

    @MainActor
    func testLunarCalmPeriodLogOpensFromTrackHub() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openPeriodLogFromTrackHub(in: app)

        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "cycle_log.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "cycle_log.lunar.mode").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "cycle_log.lunar.date_card").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "cycle_log.lunar.flow_picker").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "cycle_log.lunar.notes").waitForExistence(timeout: 5))

        let lightFlow = screenElement(in: app, identifier: "cycle_log.lunar.flow.light")
        XCTAssertTrue(lightFlow.waitForExistence(timeout: 5))
        lightFlow.tap()

        try saveScreenshotArtifact(named: "lunar-calm-period-log.png")
    }

    @MainActor
    func testLunarCalmOvulationLogOpensFromTrackHub() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openOvulationLogFromTrackHub(in: app)

        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "ovulation_log.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "ovulation_log.lunar.date_card").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "ovulation_log.lunar.clue_grid").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "ovulation_log.lunar.temperature").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "ovulation_log.lunar.notes").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "ovulation_log.lunar.save_button").waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers["ovulationLog.date"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["ovulationLog.temperature"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ovulationLog.save"].waitForExistence(timeout: 5))

        let peakLH = screenElement(in: app, identifier: "ovulation_log.lunar.lh.peak")
        scrollToElement(peakLH, in: app)
        XCTAssertTrue(peakLH.isHittable)
        peakLH.tap()

        try saveScreenshotArtifact(named: "lunar-calm-ovulation-log.png")
    }

    @MainActor
    func testLunarCalmMealLogOpensFromTrackHub() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openMealLogFromTrackHub(in: app)
        try saveScreenshotArtifact(named: "lunar-calm-meal-log.png")

        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "meal_log.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "meal_log.lunar.meal_type").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_log.lunar.description").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_log.lunar.quick_actions").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_log.lunar.glycemic_impact").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_log.lunar.macros").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_log.history_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_log.scan_barcode_button"].waitForExistence(timeout: 5))

        let descriptionField = app.textFields["meal_log.description"]
        XCTAssertTrue(descriptionField.waitForExistence(timeout: 5))
        descriptionField.tap()
        descriptionField.typeText("Lentil bowl")
        if app.buttons["Done"].waitForExistence(timeout: 2) {
            app.buttons["Done"].tap()
        }

        let saveButton = app.buttons["meal_log.save_button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(saveButton.isEnabled)
    }

    @MainActor
    func testLunarCalmAddNutritionShowsEveryEntryPath() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData"]
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openMealLogFromTrackHub(in: app)

        let addNutritionCard = screenElement(in: app, identifier: "meal_log.lunar.quick_actions")
        scrollToElement(addNutritionCard, in: app, maxSwipes: 10)

        let photoButton = app.buttons["meal_log.photo_estimate_button"]
        let barcodeButton = app.buttons["meal_log.scan_barcode_button"]
        let manualButton = app.buttons["meal_log.manual_nutrition_button"]
        XCTAssertTrue(photoButton.waitForExistence(timeout: 5))
        XCTAssertTrue(barcodeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(manualButton.waitForExistence(timeout: 5))
        XCTAssertTrue(photoButton.isHittable)
        XCTAssertTrue(barcodeButton.isHittable)
        XCTAssertTrue(manualButton.isHittable)
        try saveScreenshotArtifact(named: "lunar-calm-add-nutrition.png")
    }

    @MainActor
    func testLunarCalmMealHistoryOpensFromLog() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openMealLogFromTrackHub(in: app)

        let historyButton = app.buttons["meal_log.history_button"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.meal_history").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "meal_history.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "meal_history.lunar.dashboard").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_history.lunar.gi_chart").waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-meal-history.png")
    }

    @MainActor
    func testLunarCalmMealDetailOpensFromMealHistory() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openMealLogFromTrackHub(in: app)

        let historyButton = app.buttons["meal_log.history_button"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.meal_history").waitForExistence(timeout: 5))
        let firstMealRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal_history.lunar.row."))
            .firstMatch
        scrollToElement(firstMealRow, in: app, maxSwipes: 10)
        firstMealRow.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.meal_detail").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "meal_detail.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "meal_detail.lunar.glycemic").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_detail.lunar.macros").waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-meal-detail.png")
    }

    @MainActor
    func testLunarCalmMealScanEntryOpensFromMealLog() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData"]
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openMealLogFromTrackHub(in: app)

        openMealScanFromMealLog(in: app)

        XCTAssertTrue(screenElement(in: app, identifier: "screen.meal_scan").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "meal_scan.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.privacy").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.actions").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_scan.scan_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_scan.manual_button"].waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-meal-scan-entry.png")
    }

    @MainActor
    func testMealScanRemoteConsentNamesGoogleAndKeepsFallbacksVisible() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData", "-enableGeminiMealScan"]
        app.launchEnvironment["MEAL_SCAN_PROXY_BASE_URL"] = "https://meal-scan-ui-test.invalid"
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openMealLogFromTrackHub(in: app)
        openMealScanFromMealLog(in: app)

        let scanButton = app.buttons["meal_scan.scan_button"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5))
        scanButton.tap()

        let sampleButton = app.buttons["meal_scan.mock_photo_button"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
        sampleButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.remote_consent").waitForExistence(timeout: 8))
        let sendButton = app.buttons["meal_scan.remote_consent.continue"]
        let manualButton = app.buttons["meal_scan.remote_consent.manual"]
        let retakeButton = app.buttons["meal_scan.remote_consent.retake"]
        let retentionDisclosure = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "up to 55 days"))
            .firstMatch
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        XCTAssertEqual(sendButton.label, "Send to Google Gemini")
        XCTAssertTrue(retentionDisclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(manualButton.waitForExistence(timeout: 5))
        XCTAssertTrue(retakeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.frame.intersects(retentionDisclosure.frame))
        XCTAssertTrue(sendButton.isHittable)
        XCTAssertTrue(manualButton.isHittable)
        XCTAssertTrue(retakeButton.isHittable)
        try saveScreenshotArtifact(named: "lunar-calm-meal-scan-consent.png")
    }

    @MainActor
    func testMealScanReviewKeepsFoodEditsAndSaveVisible() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData"]
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openMealLogFromTrackHub(in: app)
        openMealScanFromMealLog(in: app)

        let scanButton = app.buttons["meal_scan.scan_button"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5))
        scanButton.tap()

        let sampleButton = app.buttons["meal_scan.mock_photo_button"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
        sampleButton.tap()

        XCTAssertTrue(app.textFields["meal_scan.meal_name"].waitForExistence(timeout: 8))
        let editableFood = app.buttons.matching(identifier: "meal_scan.edit_food_item").firstMatch
        XCTAssertTrue(editableFood.waitForExistence(timeout: 5))
        scrollToElement(editableFood, in: app.collectionViews.firstMatch, maxSwipes: 4)
        XCTAssertTrue(editableFood.isHittable)
        editableFood.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["meal_scan.edit_food.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["meal_scan.edit_food.grams"].waitForExistence(timeout: 5))
        app.buttons["meal_scan.edit_food.cancel"].tap()

        let saveButton = app.buttons["meal_scan.save_button"]
        scrollToElement(saveButton, in: app.collectionViews.firstMatch, maxSwipes: 12)
        XCTAssertTrue(saveButton.isHittable)
        XCTAssertTrue(app.buttons["Edit Portions"].waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-meal-estimate-review.png")
    }

    @MainActor
    func testRepeatMealSuggestionSupportsReuseAtAccessibilityTextSize() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement",
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        )
        app.launchArguments += [
            "-enableMealScanV2",
            "-enableMockMealScanData",
            "-enableRepeatMealSuggestions",
            "SeedRepeatMealSuggestion",
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openMealLogFromTrackHub(in: app)

        openMealScanFromMealLog(in: app)

        let scanButton = app.buttons["meal_scan.scan_button"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5))
        scanButton.tap()

        let sampleButton = app.buttons["meal_scan.mock_photo_button"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
        sampleButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.repeat_suggestion").waitForExistence(timeout: 8))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.repeat_suggestion.summary").waitForExistence(timeout: 5))
        let usePreviousButton = app.buttons["meal_scan.repeat_suggestion.use_previous"]
        let scanAsNewButton = app.buttons["meal_scan.repeat_suggestion.scan_as_new"]
        XCTAssertTrue(usePreviousButton.waitForExistence(timeout: 5))
        XCTAssertTrue(scanAsNewButton.waitForExistence(timeout: 5))

        XCTAssertTrue(usePreviousButton.isHittable)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        try saveScreenshotArtifact(named: "lunar-calm-repeat-meal-accessibility-xxxl-actions.png")
        usePreviousButton.tap()

        XCTAssertTrue(app.textFields["meal_scan.meal_name"].waitForExistence(timeout: 5))
        let reuseSaveButton = app.buttons["meal_scan.save_button"]
        scrollToElement(reuseSaveButton, in: app.collectionViews.firstMatch, maxSwipes: 12)
        XCTAssertTrue(reuseSaveButton.isHittable)
    }

    @MainActor
    func testBotanicalRepeatMealSuggestionCanScanAsNew() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal",
            demoScenario: "symptomManagement"
        )
        app.launchArguments += [
            "-enableMealScanV2",
            "-enableMockMealScanData",
            "-enableRepeatMealSuggestions",
            "SeedRepeatMealSuggestion",
        ]
        app.launch()

        openMealLogFromTrackHub(in: app)
        openMealScanFromMealLog(in: app)

        let scanButton = app.buttons["meal_scan.scan_button"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5))
        scanButton.tap()

        let sampleButton = app.buttons["meal_scan.mock_photo_button"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
        sampleButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.repeat_suggestion").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["meal_scan.repeat_suggestion.use_previous"].waitForExistence(timeout: 5))
        let scanAsNewButton = app.buttons["meal_scan.repeat_suggestion.scan_as_new"]
        XCTAssertTrue(scanAsNewButton.waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "botanical-repeat-meal-standard-text.png")

        scanAsNewButton.tap()

        XCTAssertTrue(app.textFields["meal_scan.meal_name"].waitForExistence(timeout: 8))
        let freshScanSaveButton = app.buttons["meal_scan.save_button"]
        scrollToElement(freshScanSaveButton, in: app.collectionViews.firstMatch, maxSwipes: 12)
        XCTAssertTrue(freshScanSaveButton.isHittable)
    }

    @MainActor
    func testFruitGroveMealScanEntryUsesPremiumShell() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "fruitGrove",
            demoScenario: "symptomManagement"
        )
        app.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData"]
        app.launch()

        XCTAssertTrue(app.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        openMealLogFromTrackHub(in: app)

        openMealScanFromMealLog(in: app)

        XCTAssertTrue(screenElement(in: app, identifier: "screen.meal_scan").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.privacy").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.actions").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_scan.scan_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_scan.manual_button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMealScanReleasePhaseMatrixAcrossAllThemes() throws {
        let themes = [
            (option: "lunarCalm", artifact: "lunar-calm"),
            (option: "botanicalJournal", artifact: "botanical-journal"),
            (option: "fruitGrove", artifact: "fruit-grove"),
            (option: "highContrast", artifact: "high-contrast"),
        ]

        for theme in themes {
            let app = makeApp(
                language: "en",
                locale: "en_US",
                onboardingCompleted: true,
                appLanguage: "system",
                themeOption: theme.option,
                demoScenario: "symptomManagement"
            )
            app.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData"]
            app.launch()

            openMealLogFromTrackHub(in: app)
            openMealScanFromMealLog(in: app)
            XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.entry").waitForExistence(timeout: 5))
            try saveScreenshotArtifact(named: "task-2-\(theme.artifact)-meal-scan-entry.png")

            let scanButton = app.buttons["meal_scan.scan_button"]
            XCTAssertTrue(scanButton.waitForExistence(timeout: 5))
            scanButton.tap()
            let sampleButton = app.buttons["meal_scan.mock_photo_button"]
            XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
            sampleButton.tap()

            XCTAssertTrue(app.textFields["meal_scan.meal_name"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons.matching(identifier: "meal_scan.edit_food_item").firstMatch.waitForExistence(timeout: 5))
            try saveScreenshotArtifact(named: "task-2-\(theme.artifact)-meal-scan-review.png")

            let scrollContainer = app.scrollViews.firstMatch
            let saveButton = app.buttons["meal_scan.save_button"]
            scrollToElement(saveButton, in: scrollContainer, maxSwipes: 16)
            saveButton.tap()

            XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.saved").waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["meal_scan.saved.view_meal"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["meal_scan.saved.add_context"].waitForExistence(timeout: 5))
            let shareButton = app.buttons["meal_scan.saved.share"]
            XCTAssertTrue(shareButton.waitForExistence(timeout: 5))
            try saveScreenshotArtifact(named: "task-2-\(theme.artifact)-meal-scan-saved.png")

            scrollToElement(shareButton, in: scrollContainer, maxSwipes: 8)
            shareButton.tap()
            XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.share.preview").waitForExistence(timeout: 8))
            XCTAssertTrue(app.switches["Include food names"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.switches["Include meal photo"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.switches["Include nutrition macros"].waitForExistence(timeout: 5))
            try saveScreenshotArtifact(named: "task-2-\(theme.artifact)-meal-scan-share.png")
            app.terminate()
        }
    }

    @MainActor
    func testMealScanAddContextUpdatesSavedMealIdentityInPlace() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData"]
        app.launch()

        openMealLogFromTrackHub(in: app)
        openMealScanFromMealLog(in: app)
        app.buttons["meal_scan.scan_button"].tap()
        let sampleButton = app.buttons["meal_scan.mock_photo_button"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
        sampleButton.tap()
        XCTAssertTrue(app.textFields["meal_scan.meal_name"].waitForExistence(timeout: 8))

        let saveButton = app.buttons["meal_scan.save_button"]
        scrollToElement(saveButton, in: app.scrollViews.firstMatch, maxSwipes: 16)
        saveButton.tap()
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.saved").waitForExistence(timeout: 8))

        app.buttons["meal_scan.saved.view_meal"].tap()
        let savedFoodRow = screenElement(in: app, identifier: "meal_scan.food_item_row")
        XCTAssertTrue(savedFoodRow.waitForExistence(timeout: 5))
        XCTAssertTrue(savedFoodRow.label.localizedCaseInsensitiveContains("g"))
        XCTAssertTrue(savedFoodRow.label.localizedCaseInsensitiveContains("kcal"))
        XCTAssertTrue(savedFoodRow.label.localizedCaseInsensitiveContains("confidence"))
        app.buttons["meal_scan.phase.close"].firstMatch.tap()
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.saved").waitForExistence(timeout: 5))

        let addContext = app.buttons["meal_scan.saved.add_context"]
        XCTAssertTrue(addContext.waitForExistence(timeout: 5))
        addContext.tap()
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.saved_context").waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["meal_scan.context.meal_name"].label, "Chicken rice bowl")

        let glucoseButton = app.buttons["meal_scan.context.log_glucose"]
        XCTAssertTrue(glucoseButton.waitForExistence(timeout: 5))
        glucoseButton.tap()
        XCTAssertTrue(screenElement(in: app, identifier: "screen.blood_sugar_log").waitForExistence(timeout: 5))
        let visibleCancel = try XCTUnwrap(
            app.buttons
                .matching(NSPredicate(format: "label == %@", "Cancel"))
                .allElementsBoundByIndex
                .first(where: { $0.isHittable })
        )
        visibleCancel.tap()
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.saved_context").waitForExistence(timeout: 5))

        let severity = app.buttons["meal_scan.context.severity.4"]
        XCTAssertTrue(severity.waitForExistence(timeout: 5))
        severity.tap()
        let note = app.textFields["meal_scan.context.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("Steady energy and comfortable digestion")
        app.buttons["meal_scan.context.save"].tap()

        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.saved").waitForExistence(timeout: 5))
        app.buttons["meal_scan.saved.add_context"].tap()
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.saved_context").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_scan.context.severity.4"].isSelected)
        XCTAssertEqual(
            app.textFields["meal_scan.context.note"].value as? String,
            "Steady energy and comfortable digestion"
        )
    }

    @MainActor
    func testMealScanConsentMatrixAcrossAllThemes() throws {
        let themes = [
            (option: "lunarCalm", artifact: "lunar-calm"),
            (option: "botanicalJournal", artifact: "botanical-journal"),
            (option: "fruitGrove", artifact: "fruit-grove"),
            (option: "highContrast", artifact: "high-contrast"),
        ]

        for theme in themes {
            let app = makeApp(
                language: "en",
                locale: "en_US",
                onboardingCompleted: true,
                appLanguage: "system",
                themeOption: theme.option,
                demoScenario: "symptomManagement"
            )
            app.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData", "-enableGeminiMealScan"]
            app.launchEnvironment["MEAL_SCAN_PROXY_BASE_URL"] = "https://meal-scan-ui-test.invalid"
            app.launch()

            openMealLogFromTrackHub(in: app)
            openMealScanFromMealLog(in: app)
            app.buttons["meal_scan.scan_button"].tap()
            let sampleButton = app.buttons["meal_scan.mock_photo_button"]
            XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
            sampleButton.tap()

            XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.remote_consent").waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["meal_scan.remote_consent.continue"].waitForExistence(timeout: 5))
            try saveScreenshotArtifact(named: "task-2-\(theme.artifact)-meal-scan-consent.png")
            app.terminate()
        }
    }

    @MainActor
    func testMealScanSmallestPhoneAccessibilityXXXLFlow() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "highContrast",
            demoScenario: "symptomManagement",
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        )
        app.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData"]
        app.launch()

        openMealLogFromTrackHub(in: app)
        openMealScanFromMealLog(in: app)
        let entryScroll = app.scrollViews.firstMatch
        let scanButton = app.buttons["meal_scan.scan_button"]
        scrollToElement(scanButton, in: entryScroll, maxSwipes: 12)
        scanButton.tap()
        let sampleButton = app.buttons["meal_scan.mock_photo_button"]
        scrollToElement(sampleButton, in: app.scrollViews.firstMatch, maxSwipes: 12)
        sampleButton.tap()

        XCTAssertTrue(app.textFields["meal_scan.meal_name"].waitForExistence(timeout: 8))
        let saveButton = app.buttons["meal_scan.save_button"]
        scrollToElement(saveButton, in: app.scrollViews.firstMatch, maxSwipes: 20)
        XCTAssertTrue(saveButton.isHittable)
        try saveScreenshotArtifact(named: "task-2-smallest-high-contrast-axxxl-review.png")
        saveButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.saved").waitForExistence(timeout: 8))
        let shareButton = app.buttons["meal_scan.saved.share"]
        scrollToElement(shareButton, in: app.scrollViews.firstMatch, maxSwipes: 12)
        XCTAssertTrue(shareButton.isHittable)
        try saveScreenshotArtifact(named: "task-2-smallest-high-contrast-axxxl-saved.png")
    }

    @MainActor
    func testMealScanSevenLanguageSavedShareSmoke() throws {
        let localizations = [
            (language: "en", locale: "en_US", artifact: "en"),
            (language: "de", locale: "de_DE", artifact: "de"),
            (language: "fr", locale: "fr_FR", artifact: "fr"),
            (language: "it", locale: "it_IT", artifact: "it"),
            (language: "ja", locale: "ja_JP", artifact: "ja"),
            (language: "ko", locale: "ko_KR", artifact: "ko"),
            (language: "nl", locale: "nl_NL", artifact: "nl"),
        ]

        for localization in localizations {
            let app = makeApp(
                language: localization.language,
                locale: localization.locale,
                onboardingCompleted: true,
                appLanguage: "system",
                themeOption: "lunarCalm",
                demoScenario: "symptomManagement"
            )
            app.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData"]
            app.launch()

            openMealLogFromTrackHub(in: app)
            openMealScanFromMealLog(in: app)
            XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.entry").waitForExistence(timeout: 5))
            let scanButton = app.buttons["meal_scan.scan_button"]
            XCTAssertTrue(scanButton.waitForExistence(timeout: 5))
            scanButton.tap()
            let sampleButton = app.buttons["meal_scan.mock_photo_button"]
            XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
            sampleButton.tap()

            XCTAssertTrue(app.textFields["meal_scan.meal_name"].waitForExistence(timeout: 8))
            let saveButton = app.buttons["meal_scan.save_button"]
            scrollToElement(saveButton, in: app.scrollViews.firstMatch, maxSwipes: 16)
            saveButton.tap()
            XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.saved").waitForExistence(timeout: 8))
            let shareButton = app.buttons["meal_scan.saved.share"]
            scrollToElement(shareButton, in: app.scrollViews.firstMatch, maxSwipes: 8)
            shareButton.tap()
            XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.share.preview").waitForExistence(timeout: 8))
            try saveScreenshotArtifact(named: "task-2-language-\(localization.artifact)-meal-scan-share.png")
            app.terminate()
        }
    }

    @MainActor
    func testMealScanLightAndDarkAppearanceSmoke() throws {
        let appearances = [
            (theme: "fruitGrove", artifact: "light"),
            (theme: "lunarCalm", artifact: "dark"),
        ]

        for appearance in appearances {
            let app = makeApp(
                language: "en",
                locale: "en_US",
                onboardingCompleted: true,
                appLanguage: "system",
                themeOption: appearance.theme,
                demoScenario: "symptomManagement"
            )
            app.launchArguments += [
                "-enableMealScanV2",
                "-enableMockMealScanData",
            ]
            app.launch()

            openMealLogFromTrackHub(in: app)
            openMealScanFromMealLog(in: app)
            XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.entry").waitForExistence(timeout: 5))
            try saveScreenshotArtifact(named: "task-2-appearance-\(appearance.artifact)-meal-scan-entry.png")
            app.terminate()
        }
    }

    @MainActor
    func testMealScanCameraProcessingAndRecoveryPhaseFixtures() throws {
        let cameraApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        cameraApp.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData"]
        cameraApp.launch()
        openMealLogFromTrackHub(in: cameraApp)
        openMealScanFromMealLog(in: cameraApp)
        cameraApp.buttons["meal_scan.scan_button"].tap()
        XCTAssertTrue(screenElement(in: cameraApp, identifier: "meal_scan.camera.permission").waitForExistence(timeout: 5))
        XCTAssertTrue(cameraApp.buttons["meal_scan.import_photo_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(cameraApp.buttons["meal_scan.take_photo_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(cameraApp.buttons["meal_scan.camera.barcode"].waitForExistence(timeout: 5))
        XCTAssertTrue(cameraApp.buttons["meal_scan.camera.manual"].waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "task-2-lunar-calm-meal-scan-camera.png")
        cameraApp.terminate()

        let processingApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        processingApp.launchArguments += ["-enableMealScanV2", "SeedMealScanProcessingPhase"]
        processingApp.launch()
        openMealLogFromTrackHub(in: processingApp)
        openMealScanFromMealLog(in: processingApp)
        XCTAssertTrue(screenElement(in: processingApp, identifier: "meal_scan.lunar.processing").waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "task-2-lunar-calm-meal-scan-processing.png")
        processingApp.terminate()

        let fallbackApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        fallbackApp.launchArguments += ["-enableMealScanV2", "SeedMealScanManualFallbackPhase"]
        fallbackApp.launch()
        openMealLogFromTrackHub(in: fallbackApp)
        openMealScanFromMealLog(in: fallbackApp)
        XCTAssertTrue(screenElement(in: fallbackApp, identifier: "meal_scan.lunar.manual_fallback").waitForExistence(timeout: 5))
        let fallbackTitle = fallbackApp.staticTexts["meal_scan.phase.title"]
        let fallbackClose = fallbackApp.buttons["meal_scan.phase.close"]
        XCTAssertEqual(fallbackTitle.label, "Photo analysis unavailable")
        XCTAssertTrue(fallbackClose.waitForExistence(timeout: 5))
        let fallbackManualButton = fallbackApp.buttons["Enter nutrition manually"]
        let fallbackBarcodeButton = fallbackApp.buttons["Scan a barcode"]
        let retakeButton = fallbackApp.buttons["Retake photo"]
        scrollToElement(retakeButton, in: fallbackApp.scrollViews.firstMatch, maxSwipes: 8)
        XCTAssertTrue(fallbackManualButton.exists)
        XCTAssertTrue(fallbackBarcodeButton.exists)
        XCTAssertTrue(retakeButton.exists)
        XCTAssertTrue(retakeButton.isHittable)
        XCTAssertTrue(fallbackTitle.exists)
        XCTAssertTrue(fallbackClose.isHittable)
        try saveScreenshotArtifact(named: "task-2-lunar-calm-meal-scan-fallback.png")
        retakeButton.tap()
        XCTAssertTrue(screenElement(in: fallbackApp, identifier: "meal_scan.camera.permission").waitForExistence(timeout: 5))
        fallbackApp.terminate()

        let ambiguousApp = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        ambiguousApp.launchArguments += ["-enableMealScanV2", "SeedMealScanAmbiguousOutcomePhase"]
        ambiguousApp.launch()
        openMealLogFromTrackHub(in: ambiguousApp)
        openMealScanFromMealLog(in: ambiguousApp)
        XCTAssertTrue(screenElement(in: ambiguousApp, identifier: "meal_scan.unknown_outcome").waitForExistence(timeout: 5))
        let ambiguousTitle = ambiguousApp.staticTexts["meal_scan.phase.title"]
        let ambiguousClose = ambiguousApp.buttons["meal_scan.phase.close"]
        XCTAssertEqual(ambiguousTitle.label, "Analysis status unknown")
        XCTAssertTrue(ambiguousClose.waitForExistence(timeout: 5))
        let requestNewButton = ambiguousApp.buttons["Consider a new analysis"]
        XCTAssertTrue(requestNewButton.waitForExistence(timeout: 5))
        scrollToElement(requestNewButton, in: ambiguousApp.scrollViews.firstMatch, maxSwipes: 8)
        XCTAssertTrue(requestNewButton.isHittable)
        XCTAssertTrue(ambiguousTitle.exists)
        XCTAssertTrue(ambiguousClose.isHittable)
        try saveScreenshotArtifact(named: "task-2-lunar-calm-meal-scan-ambiguous.png")
        requestNewButton.tap()
        XCTAssertTrue(screenElement(in: ambiguousApp, identifier: "meal_scan.new_attempt_confirmation").waitForExistence(timeout: 5))
        let confirmNewButton = ambiguousApp.buttons["Start a new billable analysis"]
        XCTAssertTrue(confirmNewButton.waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "task-2-lunar-calm-meal-scan-new-attempt.png")
        let goBackButton = ambiguousApp.buttons["Go back"]
        XCTAssertTrue(goBackButton.waitForExistence(timeout: 5))
        scrollToElement(goBackButton, in: ambiguousApp.scrollViews.firstMatch, maxSwipes: 8)
        XCTAssertTrue(goBackButton.isHittable)
        goBackButton.tap()
        XCTAssertTrue(screenElement(in: ambiguousApp, identifier: "meal_scan.unknown_outcome").waitForExistence(timeout: 5))
        ambiguousApp.terminate()
    }

    @MainActor
    func testMealScanIncreaseContrastRuntimeSmoke() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "highContrast",
            demoScenario: "symptomManagement"
        )
        app.launchArguments += ["-enableMealScanV2", "-enableMockMealScanData"]
        app.launch()

        openMealLogFromTrackHub(in: app)
        openMealScanFromMealLog(in: app)
        XCTAssertTrue(screenElement(in: app, identifier: "meal_scan.lunar.entry").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_scan.scan_button"].waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "task-2-increase-contrast-high-contrast-entry.png")
    }

    @MainActor
    func testBloodSugarLogOpensFromTrackHubWithDemoData() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal",
            demoScenario: "symptomManagement"
        )
        app.launch()

        openBloodSugarLogFromTrackHub(in: app)

        XCTAssertTrue(app.textFields["blood_sugar_log.glucose_value"].waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.inline_history_button").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.reading_type").waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["blood_sugar_log.meal_context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers["blood_sugar_log.date"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLunarCalmBloodSugarLogOpensFromTrackHub() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openBloodSugarLogFromTrackHub(in: app)

        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "blood_sugar_log.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.lunar.history").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.lunar.glucose").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.lunar.reading_type").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.lunar.meal_context").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.lunar.date").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.lunar.save_button").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.inline_history_button").waitForExistence(timeout: 5))
        try saveScreenshotArtifact(named: "lunar-calm-blood-sugar-log.png")

        let glucoseField = app.textFields["blood_sugar_log.glucose_value"]
        XCTAssertTrue(glucoseField.waitForExistence(timeout: 5))
        glucoseField.tap()
        glucoseField.typeText("112")
        if app.buttons["Done"].waitForExistence(timeout: 2) {
            app.buttons["Done"].tap()
        }

        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.save_ready").waitForExistence(timeout: 5))
    }

    @MainActor
    func testLunarCalmBloodSugarHistoryOpensFromLog() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "lunarCalm",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["lunar.tab_bar"].waitForExistence(timeout: 10))
        openBloodSugarLogFromTrackHub(in: app)

        let historyButton = screenElement(in: app, identifier: "blood_sugar_log.inline_history_button")
        scrollToElement(historyButton, in: app)
        historyButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.blood_sugar_history").waitForExistence(timeout: 5))
        _ = waitForNonEmptyFrame(of: screenElement(in: app, identifier: "blood_sugar_history.lunar.header"), timeout: 10)
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_history.lunar.dashboard").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_history.lunar.daily_chart").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_history.lunar.trend").waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        try saveScreenshotArtifact(named: "lunar-calm-blood-sugar-history.png")

        let recentReadings = screenElement(in: app, identifier: "blood_sugar_history.lunar.recent_readings")
        for _ in 0..<8 where !recentReadings.exists {
            app.swipeUp()
        }
        XCTAssertTrue(recentReadings.waitForExistence(timeout: 2))
    }

    @MainActor
    func testFruitGroveBloodSugarHistoryUsesPremiumDashboard() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "fruitGrove",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        openBloodSugarLogFromTrackHub(in: app)

        let historyButton = screenElement(in: app, identifier: "blood_sugar_log.inline_history_button")
        scrollToElement(historyButton, in: app)
        historyButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.blood_sugar_history").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_history.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_history.lunar.dashboard").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_history.lunar.daily_chart").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_history.lunar.trend").waitForExistence(timeout: 5))
    }

    @MainActor
    func testFrenchMainTabsSettingsAndAlertSmoke() throws {
        let app = makeApp(
            language: "fr",
            locale: "fr_FR",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal"
        )
        app.launch()

        assertMainTabShellPresent(in: app)

        assertMainTabLabel(.calendar, equals: "Calendrier", in: app)
        tapMainTab(.calendar, in: app)
        XCTAssertTrue(app.otherElements["calendar.grid"].waitForExistence(timeout: 5))

        assertMainTabLabel(.settings, equals: "Paramètres", in: app)
        tapMainTab(.settings, in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let appLanguageRow = app.buttons["settings.app_language.row"]
        scrollToElement(appLanguageRow, in: settingsScreen)
        let deleteButton = app.buttons["settings.delete_all_data"]
        scrollToElement(deleteButton, in: settingsScreen)
        deleteButton.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testJapaneseOnboardingAndCalendarSmoke() throws {
        let app = makeApp(
            language: "ja",
            locale: "ja_JP",
            onboardingCompleted: false,
            appLanguage: "system",
            onboardingStartPhase: "completion"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["screen.onboarding.completion"].waitForExistence(timeout: 5))
        let completionFinish = app.buttons["onboarding.completion.finish"]
        XCTAssertTrue(completionFinish.waitForExistence(timeout: 5))
        completionFinish.tap()

        assertMainTabShellPresent(in: app)
        assertMainTabLabel(.calendar, equals: "カレンダー", in: app)
        assertMainTabLabel(.settings, equals: "設定", in: app)
        assertNoPlaceholderTokensVisible(in: app)
    }

    @MainActor
    func testEnglishSystemLaunchUsesEnglishTabLabels() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal"
        )
        app.launch()

        assertMainTabLabel(.settings, equals: "Settings", in: app)
        XCTAssertFalse(mainTabShellContainsLabel("Einstellungen", in: app))
    }

    @MainActor
    func testFontLaunchOverrideKeepsMainTabsAccessible() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            fontOption: "rounded",
            themeOption: "fruitGrove"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        assertMainTabShellPresent(in: app)

        let todayTitle = app.staticTexts["Today"]
        XCTAssertTrue(todayTitle.waitForExistence(timeout: 10))

        openInsightsTab(in: app)
        XCTAssertTrue(app.buttons["Log Period"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Log Symptoms"].exists)

        openSettingsTab(in: app)
        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))

        let themePicker = screenElement(in: app, identifier: "settings.display.theme")
        scrollToElement(themePicker, in: settingsScreen)
        XCTAssertTrue(themePicker.exists)
        XCTAssertTrue(app.staticTexts["Fruit Grove"].exists)
        let themeSwatch = app.otherElements["settings.display.theme_swatch"]
        scrollToElement(themeSwatch, in: settingsScreen)
        XCTAssertTrue(themeSwatch.exists)

        let fontPicker = screenElement(in: app, identifier: "settings.display.font")
        scrollToElement(fontPicker, in: settingsScreen)
        XCTAssertTrue(fontPicker.exists)

        assertMainTabLabel(.today, equals: "Today", in: app)
        assertMainTabLabel(.insights, equals: "Insights", in: app)
        assertMainTabLabel(.settings, equals: "Settings", in: app)
    }

    @MainActor
    func testFruitGroveTodayAndCalendarUsePremiumDailyShell() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "fruitGrove",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "screen.today").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "today.lunar.header").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "today.hero.container").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "today.lunar.snapshot").waitForExistence(timeout: 10))
        try saveScreenshotArtifact(named: "fruit-grove-today-shell.png")

        openCalendarTab(in: app)
        XCTAssertTrue(screenElement(in: app, identifier: "screen.calendar").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "calendar.lunar.header").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "calendar.lunar.panel").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "calendar.lunar.timeline").waitForExistence(timeout: 10))
        try saveScreenshotArtifact(named: "fruit-grove-calendar-shell.png")

        openSettingsTab(in: app)
        XCTAssertTrue(screenElement(in: app, identifier: "screen.settings").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "settings.lunar.support_overview").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "settings.lunar.reminders").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "settings.lunar.daily_checkin").waitForExistence(timeout: 10))
    }

    @MainActor
    func testHighContrastTodayUsesPremiumDailyShell() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "highContrast",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "screen.today").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "today.lunar.header").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "today.hero.container").waitForExistence(timeout: 10))
        XCTAssertTrue(screenElement(in: app, identifier: "today.lunar.snapshot").waitForExistence(timeout: 10))
        try saveScreenshotArtifact(named: "high-contrast-today-shell.png")
    }

    @MainActor
    func testFruitGroveTrackHubUsesPremiumLogEditors() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "fruitGrove",
            demoScenario: "symptomManagement"
        )
        app.launch()

        XCTAssertTrue(app.otherElements["themed.tab_bar"].waitForExistence(timeout: 10))
        openSymptomLogFromTrackHub(in: app)
        XCTAssertTrue(screenElement(in: app, identifier: "symptom_log.lunar.date_strip").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "symptom_log.lunar.mood_section").waitForExistence(timeout: 5))

        let symptomCancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(symptomCancel.waitForExistence(timeout: 5))
        symptomCancel.tap()

        openPeriodLogFromTrackHub(in: app)
        XCTAssertTrue(screenElement(in: app, identifier: "cycle_log.lunar.mode").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "cycle_log.lunar.flow_picker").waitForExistence(timeout: 5))

        let periodCancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(periodCancel.waitForExistence(timeout: 5))
        periodCancel.tap()

        openOvulationLogFromTrackHub(in: app)
        XCTAssertTrue(screenElement(in: app, identifier: "ovulation_log.lunar.date_card").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "ovulation_log.lunar.clue_grid").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "ovulation_log.lunar.temperature").waitForExistence(timeout: 5))

        let ovulationCancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(ovulationCancel.waitForExistence(timeout: 5))
        ovulationCancel.tap()

        openBloodSugarLogFromTrackHub(in: app)
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.lunar.glucose").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.lunar.reading_type").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "blood_sugar_log.lunar.meal_context").waitForExistence(timeout: 5))

        let bloodSugarCancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(bloodSugarCancel.waitForExistence(timeout: 5))
        bloodSugarCancel.tap()

        openMealLogFromTrackHub(in: app)
        XCTAssertTrue(screenElement(in: app, identifier: "meal_log.lunar.meal_type").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_log.lunar.description").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_log.lunar.glycemic_impact").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_log.lunar.macros").waitForExistence(timeout: 5))

        let historyButton = app.buttons["meal_log.history_button"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.meal_history").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_history.lunar.dashboard").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_history.lunar.gi_chart").waitForExistence(timeout: 5))

        let firstMealRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal_history.lunar.row."))
            .firstMatch
        scrollToElement(firstMealRow, in: app, maxSwipes: 10)
        firstMealRow.tap()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.meal_detail").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_detail.lunar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(screenElement(in: app, identifier: "meal_detail.lunar.glycemic").waitForExistence(timeout: 5))
    }

    @MainActor
    func testRoundedFontAndFruitGroveThemeCoverOnboardingPhases() throws {
        let phases: [(launchValue: String, screenIdentifier: String)] = [
            ("welcome_language", "screen.onboarding.welcome_language"),
            ("theme", "screen.onboarding.theme"),
            ("name", "screen.onboarding.name"),
            ("quiz", "screen.onboarding.questionnaire"),
            ("results", "screen.onboarding.results"),
            ("how_app_helps", "screen.onboarding.how_app_helps"),
            ("permissions", "screen.onboarding.permissions"),
            ("health_context", "screen.onboarding.health_context"),
            ("meal_scan_demo", "screen.onboarding.meal_scan_demo"),
            ("your_plan", "screen.onboarding.your_plan"),
            ("first_log", "screen.onboarding.guided_action"),
            ("social_proof", "screen.onboarding.social_proof"),
            ("all_set", "screen.onboarding.completion"),
        ]

        for phase in phases {
            let app = makeApp(
                language: "en",
                locale: "en_US",
                onboardingCompleted: false,
                appLanguage: "system",
                fontOption: "rounded",
                themeOption: "fruitGrove",
                onboardingStartPhase: phase.launchValue
            )
            app.launch()

            XCTAssertTrue(
                screenElement(in: app, identifier: phase.screenIdentifier).waitForExistence(timeout: 10),
                "Expected onboarding phase \(phase.launchValue) to render with SF Pro Rounded and Fruit Grove."
            )
            assertNoPlaceholderTokensVisible(in: app)
            app.terminate()
        }
    }

    @MainActor
    func testOnboardingThemeStepOffersOwnershipPersonalization() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: false,
            appLanguage: "system",
            onboardingStartPhase: "theme"
        )
        app.launch()

        let screen = screenElement(in: app, identifier: "screen.onboarding.theme")
        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["onboarding.theme.option.lunarCalm"].waitForExistence(timeout: 5))

        let roundedFont = app.buttons["onboarding.font.option.rounded"]
        scrollToElement(roundedFont, in: app, maxSwipes: 8, requireHittable: false, requireSafeTapZone: false)
        XCTAssertTrue(roundedFont.exists)

        let expressiveFont = app.buttons["onboarding.font.option.cormorantGaramond"]
        scrollToElement(expressiveFont, in: app, maxSwipes: 8, requireHittable: false, requireSafeTapZone: false)
        XCTAssertTrue(expressiveFont.exists)

        let monoFont = app.buttons["onboarding.font.option.sfMono"]
        scrollToElement(monoFont, in: app, maxSwipes: 8, requireHittable: false, requireSafeTapZone: false)
        XCTAssertTrue(monoFont.exists)

        app.terminate()
    }

    @MainActor
    func testOnboardingAhaMomentExplainsHealthKitBarcodeAndTracking() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: false,
            appLanguage: "system",
            onboardingStartPhase: "aha"
        )
        app.launch()

        XCTAssertTrue(screenElement(in: app, identifier: "screen.onboarding.aha").waitForExistence(timeout: 10))
    }

    @MainActor
    func testAppLanguageSelectionPersistsAcrossRelaunch() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal"
        )
        app.launch()

        assertMainTabLabel(.settings, equals: "Settings", in: app)

        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let appLanguageRow = app.buttons["settings.app_language.row"]
        scrollToElement(appLanguageRow, in: settingsScreen)
        appLanguageRow.tap()

        let frenchOption = app.buttons["settings.app_language.option.fr"]
        XCTAssertTrue(frenchOption.waitForExistence(timeout: 5))
        frenchOption.tap()

        openCalendarTab(in: app)
        assertCalendarScreen(in: app, localizedTitle: "Calendrier")

        app.terminate()

        let relaunchedApp = makeApp(onboardingCompleted: true)
        relaunchedApp.launch()

        assertMainTabLabel(.settings, equals: "Paramètres", in: relaunchedApp)
    }

    @MainActor
    func testEnglishLanguageSelectionPersistsAcrossRelaunch() throws {
        let app = makeApp(
            language: "fr",
            locale: "fr_FR",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal"
        )
        app.launch()

        assertMainTabLabel(.settings, equals: "Paramètres", in: app)

        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let appLanguageRow = app.buttons["settings.app_language.row"]
        scrollToElement(appLanguageRow, in: settingsScreen)
        appLanguageRow.tap()

        let englishOption = app.buttons["settings.app_language.option.en"]
        XCTAssertTrue(englishOption.waitForExistence(timeout: 5))
        englishOption.tap()

        openCalendarTab(in: app)
        assertCalendarScreen(in: app, localizedTitle: "Calendar")

        app.terminate()

        let relaunchedApp = makeApp(onboardingCompleted: true)
        relaunchedApp.launch()

        assertMainTabLabel(.settings, equals: "Settings", in: relaunchedApp)
    }

    @MainActor
    func testJapaneseLanguageSelectionAppliesImmediatelyWithoutPlaceholderTokens() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            themeOption: "botanicalJournal"
        )
        app.launch()

        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let appLanguageRow = app.buttons["settings.app_language.row"]
        scrollToElement(appLanguageRow, in: settingsScreen)
        appLanguageRow.tap()

        let japaneseOption = app.buttons["settings.app_language.option.ja"]
        XCTAssertTrue(japaneseOption.waitForExistence(timeout: 5))
        japaneseOption.tap()

        openCalendarTab(in: app)
        assertCalendarScreen(in: app, localizedTitle: "カレンダー")
        assertNoPlaceholderTokensVisible(in: app)
    }

    @MainActor
    func testNonPremiumPregnancyModeOpensActivationSheet() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system"
        )
        app.launch()

        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))

        let pregnancyButton = app.buttons["settings.pregnancy.enter"]
        scrollToElement(pregnancyButton, in: settingsScreen)
        pregnancyButton.tap()

        let activationScreen = app.descendants(matching: .any)["screen.pregnancy_activation"]
        XCTAssertTrue(activationScreen.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pregnancy Start Date"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testJapanesePregnancyModeActivationIsLocalized() throws {
        let app = makeApp(
            language: "ja",
            locale: "ja_JP",
            onboardingCompleted: true,
            appLanguage: "system"
        )
        app.launch()

        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))

        let pregnancyButton = app.buttons["settings.pregnancy.enter"]
        scrollToElement(pregnancyButton, in: settingsScreen)
        pregnancyButton.tap()

        let activationScreen = app.descendants(matching: .any)["screen.pregnancy_activation"]
        XCTAssertTrue(activationScreen.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["妊娠開始日"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testExternalCSVImportFixtureSuccessSmoke() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            csvImportFixture: "valid"
        )
        app.launch()

        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let importButton = app.buttons["settings.import_external_csv"]
        scrollToElement(importButton, in: settingsScreen)
        importButton.tap()

        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let importSummary = app.descendants(matching: .any)["settings.import_summary"]
        scrollToElement(importSummary, in: settingsScreen)
    }

    @MainActor
    func testExternalCSVImportFixtureFailureSmoke() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            csvImportFixture: "invalid"
        )
        app.launch()

        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let importButton = app.buttons["settings.import_external_csv"]
        scrollToElement(importButton, in: settingsScreen)
        importButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.settings.import_result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Import Failed"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCSVImportGuideSmoke() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system"
        )
        app.launch()

        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))

        let guideButton = app.buttons["settings.csv_import_guide"]
        scrollToElement(guideButton, in: settingsScreen)
        guideButton.tap()

        let guideScreen = app.descendants(matching: .any)["screen.settings.csv_import_guide"]
        XCTAssertTrue(guideScreen.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CSV Import Guide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["period"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["date uses YYYY-MM-DD"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testJSONImportFixtureSuccessSmoke() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            jsonImportFixture: "valid"
        )
        app.launch()

        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let importButton = app.buttons["settings.import_json_backup"]
        scrollToElement(importButton, in: settingsScreen)
        importButton.tap()

        let confirmationAlert = app.alerts["Replace Existing Data?"]
        XCTAssertTrue(confirmationAlert.waitForExistence(timeout: 5))
        confirmationAlert.buttons["Import Backup"].tap()

        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let importSummary = app.descendants(matching: .any)["settings.import_summary"]
        scrollToElement(importSummary, in: settingsScreen)
    }

    @MainActor
    func testJSONImportFixtureFailureSmoke() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            jsonImportFixture: "invalid"
        )
        app.launch()

        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let importButton = app.buttons["settings.import_json_backup"]
        scrollToElement(importButton, in: settingsScreen)
        importButton.tap()

        let confirmationAlert = app.alerts["Replace Existing Data?"]
        XCTAssertTrue(confirmationAlert.waitForExistence(timeout: 5))
        confirmationAlert.buttons["Import Backup"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.settings.import_result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Import Failed"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testJSONImportFixtureUnsupportedSchemaSmoke() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            jsonImportFixture: "unsupported_schema"
        )
        app.launch()

        openSettingsTab(in: app)

        let settingsScreen = app.collectionViews["screen.settings"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let importButton = app.buttons["settings.import_json_backup"]
        scrollToElement(importButton, in: settingsScreen)
        importButton.tap()

        let confirmationAlert = app.alerts["Replace Existing Data?"]
        XCTAssertTrue(confirmationAlert.waitForExistence(timeout: 5))
        confirmationAlert.buttons["Import Backup"].tap()

        let importResult = app.descendants(matching: .any)["screen.settings.import_result"]
        XCTAssertTrue(importResult.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Import Failed"].waitForExistence(timeout: 5))
        let schemaMessage = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "schema v99")).firstMatch
        scrollToElement(schemaMessage, in: importResult)
        XCTAssertTrue(
            schemaMessage.waitForExistence(timeout: 5)
        )
    }
}
