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

        for _ in 0..<2 where !questionnaireSkip.exists {
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

        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
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
                "Found token placeholder text containing '\(token)' in the visible UI.",
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
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if element.exists && element.isHittable && isInSafeTapZone(element, in: container) {
            return
        }

        _ = element.waitForExistence(timeout: 1)

        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable && isInSafeTapZone(element, in: container) {
                return
            }
            container.swipeUp()
        }

        XCTAssertTrue(element.waitForExistence(timeout: 2), file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertTrue(isInSafeTapZone(element, in: container), file: file, line: line)
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
    private func saveScreenshotArtifact(named filename: String) throws {
        let directoryURL: URL
        if let artifactDirectory = ProcessInfo.processInfo.environment["BOTANICAL_UI_ARTIFACT_DIR"] {
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
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: screenshotURL, options: .atomic)
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

            let saveButton = app.buttons["Save"]
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
            demoScenario: "symptomManagement"
        )
        app.launch()

        openTrackTab(in: app)

        let mealCard = app.buttons["tracking.card.meal"]
        scrollToElement(mealCard, in: app)
        mealCard.tap()

        XCTAssertTrue(app.textFields["meal_log.description"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal_log.history_button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOvulationLogOpensFromTrackHubWithDemoData() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
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
    func testInsightsDisclosureSheetAndFooterAreVisibleWithDemoData() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system",
            demoScenario: "symptomManagement"
        )
        app.launch()

        openInsightsTab(in: app)

        let footer = app.staticTexts["insights.footer.disclaimer"]
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForInsightsContent(in: app))
        let sharedIntroCard = app.descendants(matching: .any)["insights.shared_intro_card"]
        XCTAssertTrue(sharedIntroCard.waitForExistence(timeout: 5))

        let disclosureButton = firstVisibleInsightDisclosureButton(in: app, timeout: 0.5, maxSwipes: 3)
        if disclosureButton.exists {
            disclosureButton.tap()

            XCTAssertTrue(app.otherElements["evidence_disclosure.sheet"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["evidence_disclosure.specific_explanation.title"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["evidence_disclosure.evidence_summary.title"].waitForExistence(timeout: 5))

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

        let calendarTab = app.buttons["tab.calendar"]
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 10))
        calendarTab.tap()
        XCTAssertTrue(app.otherElements["screen.calendar"].waitForExistence(timeout: 10))
        let cycleDetailsCard = app.descendants(matching: .any)["calendar.cycle_details.card"]
        scrollToElement(cycleDetailsCard, in: app)
        XCTAssertTrue(cycleDetailsCard.isHittable)
        try saveScreenshotArtifact(named: "botanical-calendar-bottom-clearance.png")

        let trackTab = app.buttons["tab.track"]
        XCTAssertTrue(trackTab.waitForExistence(timeout: 10))
        trackTab.tap()
        let photoJournalCard = app.buttons["tracking.card.photo"]
        scrollToElement(photoJournalCard, in: app)
        XCTAssertTrue(photoJournalCard.isHittable)
        try saveScreenshotArtifact(named: "botanical-track-bottom-clearance.png")
    }

    @MainActor
    func testFrenchMainTabsSettingsAndAlertSmoke() throws {
        let app = makeApp(
            language: "fr",
            locale: "fr_FR",
            onboardingCompleted: true,
            appLanguage: "system"
        )
        app.launch()

        assertMainTabShellPresent(in: app)

        assertMainTabLabel(.calendar, equals: "Calendrier", in: app)
        tapMainTab(.calendar, in: app)
        XCTAssertTrue(app.otherElements["calendar.grid"].waitForExistence(timeout: 5))

        assertMainTabLabel(.settings, equals: "Paramètres", in: app)
        tapMainTab(.settings, in: app)

        let appLanguageRow = app.buttons["settings.app_language.row"]
        XCTAssertTrue(appLanguageRow.waitForExistence(timeout: 5))
        let deleteButton = app.buttons["settings.delete_all_data"]
        scrollToElement(deleteButton, in: app)
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
            appLanguage: "system"
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
    func testRoundedFontAndFruitGroveThemeCoverOnboardingPhases() throws {
        let phases: [(launchValue: String, screenIdentifier: String)] = [
            ("quiz", "screen.onboarding.questionnaire"),
            ("results", "screen.onboarding.results"),
            ("how_app_helps", "screen.onboarding.how_app_helps"),
            ("social_proof", "screen.onboarding.social_proof"),
            ("your_plan", "screen.onboarding.your_plan"),
            ("guided_action", "screen.onboarding.guided_action"),
            ("permissions", "screen.onboarding.permissions"),
            ("rating", "screen.onboarding.rating"),
            ("completion", "screen.onboarding.completion"),
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
    func testAppLanguageSelectionPersistsAcrossRelaunch() throws {
        let app = makeApp(
            language: "en",
            locale: "en_US",
            onboardingCompleted: true,
            appLanguage: "system"
        )
        app.launch()

        assertMainTabLabel(.settings, equals: "Settings", in: app)

        openSettingsTab(in: app)

        let appLanguageRow = app.buttons["settings.app_language.row"]
        XCTAssertTrue(appLanguageRow.waitForExistence(timeout: 5))
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
            appLanguage: "system"
        )
        app.launch()

        assertMainTabLabel(.settings, equals: "Paramètres", in: app)

        openSettingsTab(in: app)

        let appLanguageRow = app.buttons["settings.app_language.row"]
        XCTAssertTrue(appLanguageRow.waitForExistence(timeout: 5))
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
            appLanguage: "system"
        )
        app.launch()

        openSettingsTab(in: app)

        let appLanguageRow = app.buttons["settings.app_language.row"]
        XCTAssertTrue(appLanguageRow.waitForExistence(timeout: 5))
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
