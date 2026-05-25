import XCTest

final class LocaleMatrixInsightsUITests: XCTestCase {
    private struct LocaleSpec {
        let appLanguage: String
        let localeIdentifier: String
        let todayLabel: String
        let calendarLabel: String
        let trackLabel: String
        let insightsLabel: String
        let settingsLabel: String
        let launchLanguage: String
        let launchLocaleIdentifier: String

        static let shardOne: [LocaleSpec] = [
            LocaleSpec(
                appLanguage: "en",
                localeIdentifier: "en_US",
                todayLabel: "Today",
                calendarLabel: "Calendar",
                trackLabel: "Track",
                insightsLabel: "Insights",
                settingsLabel: "Settings",
                launchLanguage: "fr",
                launchLocaleIdentifier: "fr_FR"
            ),
            LocaleSpec(
                appLanguage: "fr",
                localeIdentifier: "fr_FR",
                todayLabel: "Aujourd'hui",
                calendarLabel: "Calendrier",
                trackLabel: "Suivi",
                insightsLabel: "Analyses",
                settingsLabel: "Paramètres",
                launchLanguage: "en",
                launchLocaleIdentifier: "en_US"
            ),
            LocaleSpec(
                appLanguage: "de",
                localeIdentifier: "de_DE",
                todayLabel: "Heute",
                calendarLabel: "Kalender",
                trackLabel: "Erfassen",
                insightsLabel: "Analysen",
                settingsLabel: "Einstellungen",
                launchLanguage: "en",
                launchLocaleIdentifier: "en_US"
            ),
            LocaleSpec(
                appLanguage: "nl",
                localeIdentifier: "nl_NL",
                todayLabel: "Vandaag",
                calendarLabel: "Kalender",
                trackLabel: "Bijhouden",
                insightsLabel: "Inzichten",
                settingsLabel: "Instellingen",
                launchLanguage: "en",
                launchLocaleIdentifier: "en_US"
            ),
            LocaleSpec(
                appLanguage: "it",
                localeIdentifier: "it_IT",
                todayLabel: "Oggi",
                calendarLabel: "Calendario",
                trackLabel: "Registra",
                insightsLabel: "Analisi",
                settingsLabel: "Impostazioni",
                launchLanguage: "en",
                launchLocaleIdentifier: "en_US"
            ),
        ]

        static let shardTwo: [LocaleSpec] = [
            LocaleSpec(
                appLanguage: "ja",
                localeIdentifier: "ja_JP",
                todayLabel: "今日",
                calendarLabel: "カレンダー",
                trackLabel: "記録",
                insightsLabel: "分析",
                settingsLabel: "設定",
                launchLanguage: "en",
                launchLocaleIdentifier: "en_US"
            ),
            LocaleSpec(
                appLanguage: "ko",
                localeIdentifier: "ko_KR",
                todayLabel: "오늘",
                calendarLabel: "달력",
                trackLabel: "기록",
                insightsLabel: "분석",
                settingsLabel: "설정",
                launchLanguage: "en",
                launchLocaleIdentifier: "en_US"
            ),
        ]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLocaleMatrixShardOne() throws {
        try runLocaleMatrix(specs: LocaleSpec.shardOne)
    }

    @MainActor
    func testLocaleMatrixShardTwo() throws {
        try runLocaleMatrix(specs: LocaleSpec.shardTwo)
    }

    @MainActor
    private func runLocaleMatrix(specs: [LocaleSpec]) throws {
        for spec in specs {
            try XCTContext.runActivity(named: "Locale \(spec.appLanguage)") { _ in
                try exerciseLocale(spec)
            }
        }
    }

    @MainActor
    private func exerciseLocale(_ spec: LocaleSpec) throws {
        let app = makeApp(
            language: spec.launchLanguage,
            locale: spec.launchLocaleIdentifier,
            onboardingCompleted: true,
            appLanguage: "system",
            demoScenario: "symptomManagement"
        )
        app.launch()

        assertTabBarPresent(in: app, phase: "initial")

        openSettingsTab(in: app)
        XCTAssertTrue(settingsScreenElement(in: app).waitForExistence(timeout: 5))
        captureScreenshot(named: "\(spec.appLanguage)-settings-initial")

        let appLanguageRow = app.buttons["settings.app_language.row"]
        XCTAssertTrue(appLanguageRow.waitForExistence(timeout: 5))
        appLanguageRow.tap()

        let targetLanguageOption = app.buttons["settings.app_language.option.\(spec.appLanguage)"]
        XCTAssertTrue(targetLanguageOption.waitForExistence(timeout: 5))
        targetLanguageOption.tap()

        assertTabShellLabels(in: app, spec: spec, phase: "selected")
        assertNoPlaceholderTokensVisible(in: app)
        assertNoObviousEnglishFallback(in: app, spec: spec)

        openCalendarTab(in: app)
        XCTAssertTrue(calendarScreenElement(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["calendar.grid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[spec.calendarLabel].waitForExistence(timeout: 5))
        assertWeekdayHeaders(in: app, localeIdentifier: spec.localeIdentifier)
        captureScreenshot(named: "\(spec.appLanguage)-calendar")

        openInsightsTab(in: app)
        XCTAssertTrue(insightsScreenElement(in: app, title: spec.insightsLabel).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForInsightsContent(in: app, timeout: 5), debugInsightsState(in: app))
        XCTAssertFalse(app.otherElements["insights.empty_state"].exists)
        assertNoEnglishInsightExplanationFallback(in: app, spec: spec)
        let hasInsightCard = assertInsightsSurfaceVisible(in: app)
        if hasInsightCard {
            exerciseInsightDisclosure(in: app, spec: spec)
        }
        captureScreenshot(named: "\(spec.appLanguage)-insights")

        app.terminate()

        let relaunchedApp = makeApp(onboardingCompleted: true, demoScenario: "symptomManagement")
        relaunchedApp.launch()

        assertTabShellLabels(in: relaunchedApp, spec: spec, phase: "relaunch")

        openCalendarTab(in: relaunchedApp)
        XCTAssertTrue(relaunchedApp.staticTexts[spec.calendarLabel].waitForExistence(timeout: 5))
        openInsightsTab(in: relaunchedApp)
        XCTAssertTrue(waitForInsightsContent(in: relaunchedApp, timeout: 5), debugInsightsState(in: relaunchedApp))
        _ = assertInsightsSurfaceVisible(in: relaunchedApp)

        relaunchedApp.terminate()
    }

    @MainActor
    private func makeApp(
        language: String? = nil,
        locale: String? = nil,
        onboardingCompleted: Bool,
        appLanguage: String? = nil,
        demoScenario: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = [
            "UITestMode",
            "-onboarding.hasCompletedOnboarding", onboardingCompleted ? "YES" : "NO",
            "-onboarding.hasCompletedWelcome", onboardingCompleted ? "YES" : "NO",
            "-onboarding.hasCompletedQuestionnaire", onboardingCompleted ? "YES" : "NO",
            "-onboarding.hasCompletedGuidedAction", onboardingCompleted ? "YES" : "NO",
        ]

        if let language, let locale {
            launchArguments += [
                "-AppleLanguages", "(\(language))",
                "-AppleLocale", locale,
            ]
        }
        if let appLanguage {
            launchArguments += ["-app.language", appLanguage]
        }
        if let demoScenario {
            launchArguments += ["-uiTest.demoScenario", demoScenario]
        }

        app.launchArguments = launchArguments
        return app
    }

    @MainActor
    private func openSettingsTab(in app: XCUIApplication) {
        tapMainTab(.settings, in: app)
    }

    @MainActor
    private func openCalendarTab(in app: XCUIApplication) {
        tapMainTab(.calendar, in: app)
    }

    @MainActor
    private func openInsightsTab(in app: XCUIApplication) {
        tapMainTab(.insights, in: app)
    }

    @MainActor
    private func assertTabBarPresent(in app: XCUIApplication, phase: String) {
        assertMainTabShellPresent(in: app, timeout: 10)
    }

    @MainActor
    private func assertTabShellLabels(in app: XCUIApplication, spec: LocaleSpec, phase: String) {
        let expectedLabels: [(MainTab, String)] = [
            (.today, spec.todayLabel),
            (.calendar, spec.calendarLabel),
            (.track, spec.trackLabel),
            (.insights, spec.insightsLabel),
            (.settings, spec.settingsLabel),
        ]

        for (tab, label) in expectedLabels {
            assertMainTabLabel(tab, equals: label, in: app, timeout: 8)
        }
    }

    @MainActor
    private func assertWeekdayHeaders(in app: XCUIApplication, localeIdentifier: String) {
        let expectedSymbols = orderedWeekdaySymbols(localeIdentifier: localeIdentifier)
        XCTAssertEqual(expectedSymbols.count, 7)

        for (index, expectedSymbol) in expectedSymbols.enumerated() {
            let header = app.staticTexts["calendar.weekday.\(index)"]
            XCTAssertTrue(header.waitForExistence(timeout: 5), "Missing weekday header \(index) for \(localeIdentifier)")
            XCTAssertEqual(header.label, expectedSymbol)
        }
    }

    private func orderedWeekdaySymbols(localeIdentifier: String) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: localeIdentifier)
        let symbols = calendar.shortWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    @MainActor
    @discardableResult
    private func assertInsightsSurfaceVisible(in app: XCUIApplication) -> Bool {
        XCTAssertTrue(app.otherElements["insights.shared_intro_card"].waitForExistence(timeout: 5), debugInsightsState(in: app))

        let disclosureButton = firstVisibleInsightDisclosureButton(in: app)
        guard disclosureButton.exists else {
            return false
        }

        XCTAssertTrue(!disclosureButton.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, debugInsightsState(in: app))
        return true
    }

    @MainActor
    private func assertNoEnglishInsightExplanationFallback(in app: XCUIApplication, spec: LocaleSpec) {
        guard spec.appLanguage != "en" else { return }

        let introTitle = app.staticTexts["insights.shared_intro_card.title"]
        XCTAssertTrue(introTitle.waitForExistence(timeout: 5))
        XCTAssertNotEqual(introTitle.label, "How to read your insights")

        let logsRow = app.descendants(matching: .any)["insights.shared_intro_card.logs"]
        XCTAssertTrue(logsRow.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Built from your logs"].exists)

        let confidenceRow = app.descendants(matching: .any)["insights.shared_intro_card.confidence"]
        XCTAssertTrue(confidenceRow.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Confidence shows pattern strength"].exists)

        let researchRow = app.descendants(matching: .any)["insights.shared_intro_card.research"]
        XCTAssertTrue(researchRow.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Research adds context"].exists)

        let disclosureButton = firstVisibleInsightDisclosureButton(in: app)
        if disclosureButton.exists {
            XCTAssertNotEqual(disclosureButton.label, "Learn more")
        }
    }

    @MainActor
    private func exerciseInsightDisclosure(in app: XCUIApplication, spec: LocaleSpec) {
        let disclosureButton = firstVisibleInsightDisclosureButton(in: app)
        XCTAssertTrue(disclosureButton.waitForExistence(timeout: 5), debugInsightsState(in: app))

        if spec.appLanguage != "en" {
            XCTAssertNotEqual(disclosureButton.label, "Learn more")
        }

        disclosureButton.tap()

        let sheet = app.otherElements["evidence_disclosure.sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        let whyTitle = app.staticTexts["evidence_disclosure.specific_explanation.title"]
        XCTAssertTrue(whyTitle.waitForExistence(timeout: 5))

        let evidenceTitle = app.staticTexts["evidence_disclosure.evidence_summary.title"]
        XCTAssertTrue(evidenceTitle.waitForExistence(timeout: 5))

        let sheetNavigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(sheetNavigationBar.waitForExistence(timeout: 5))

        if spec.appLanguage != "en" {
            XCTAssertNotEqual(sheetNavigationBar.label, "How this works")
            XCTAssertNotEqual(whyTitle.label, "Why you're seeing this")
            XCTAssertNotEqual(evidenceTitle.label, "Evidence overview")
        }

        let referencesToggle = app.buttons["evidence_disclosure.references_toggle"]
        for _ in 0..<3 where !referencesToggle.exists {
            app.swipeUp()
        }

        if referencesToggle.waitForExistence(timeout: 2) {
            if spec.appLanguage != "en" {
                XCTAssertNotEqual(referencesToggle.label, "References")
            }

            referencesToggle.tap()
        }

        let doneButton = app.buttons["evidence_disclosure.done_button"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
    }

    @MainActor
    private func assertNoPlaceholderTokensVisible(in app: XCUIApplication) {
        let forbiddenTokens = ["トークン", "GETTONE", "JETON", "TOKEN_", "__", "토큰"]

        for token in forbiddenTokens {
            let predicate = NSPredicate(format: "label CONTAINS %@", token)
            let matches = app.staticTexts.matching(predicate)
            XCTAssertEqual(matches.count, 0, "Found placeholder token '\(token)' in visible UI")
        }
    }

    @MainActor
    private func assertNoObviousEnglishFallback(in app: XCUIApplication, spec: LocaleSpec) {
        guard spec.appLanguage != "en" else { return }

        XCTAssertFalse(mainTabShellContainsLabel("Today", in: app))
        XCTAssertFalse(mainTabShellContainsLabel("Calendar", in: app))
        XCTAssertFalse(mainTabShellContainsLabel("Track", in: app))
        XCTAssertFalse(mainTabShellContainsLabel("Insights", in: app))
        XCTAssertFalse(mainTabShellContainsLabel("Settings", in: app))
    }

    @MainActor
    private func settingsScreenElement(in app: XCUIApplication) -> XCUIElement {
        let screen = app.otherElements["screen.settings"]
        if screen.exists {
            return screen
        }
        return app.navigationBars.firstMatch
    }

    @MainActor
    private func calendarScreenElement(in app: XCUIApplication) -> XCUIElement {
        let screen = app.otherElements["screen.calendar"]
        if screen.exists {
            return screen
        }
        return app.otherElements["calendar.grid"]
    }

    @MainActor
    private func insightsScreenElement(in app: XCUIApplication, title: String) -> XCUIElement {
        let collectionViewScreen = app.collectionViews["screen.insights"]
        if collectionViewScreen.exists {
            return collectionViewScreen
        }

        let identifiedScreen = app.otherElements["screen.insights"]
        if identifiedScreen.exists {
            return identifiedScreen
        }

        let navigationBar = app.navigationBars[title]
        if navigationBar.exists {
            return navigationBar
        }

        return app.navigationBars.firstMatch
    }

    @MainActor
    private func insightsListElement(in app: XCUIApplication) -> XCUIElement {
        let screenCollectionView = app.collectionViews["screen.insights"]
        if screenCollectionView.exists {
            return screenCollectionView
        }

        let tables = app.tables["insights.list"]
        if tables.exists {
            return tables
        }

        let collectionViews = app.collectionViews["insights.list"]
        if collectionViews.exists {
            return collectionViews
        }

        return app.otherElements["insights.list"]
    }

    @MainActor
    private func captureScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForInsightsContent(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        if insightsListElement(in: app).waitForExistence(timeout: timeout) {
            return true
        }

        if app.otherElements["insights.shared_intro_card"].waitForExistence(timeout: timeout) {
            return true
        }

        let disclosureButton = app.buttons.matching(insightDisclosureButtonPredicate()).firstMatch
        return disclosureButton.waitForExistence(timeout: timeout)
    }

    @MainActor
    private func debugInsightsState(in app: XCUIApplication) -> String {
        let insightsScreen = app.collectionViews["screen.insights"]
        let otherList = app.otherElements["insights.list"]
        let tableList = app.tables["insights.list"]
        let collectionList = app.collectionViews["insights.list"]
        let loading = app.otherElements["insights.loading"]
        let emptyState = app.otherElements["insights.empty_state"]
        let errorBanner = app.otherElements["insights.error_banner"]
        let sharedIntro = app.otherElements["insights.shared_intro_card"]
        let disclosureButtonCount = app.buttons.matching(insightDisclosureButtonPredicate()).count

        return [
            "screen.insights=\(insightsScreen.exists)",
            "navBars=\(app.navigationBars.count)",
            "list.other=\(otherList.exists)",
            "list.table=\(tableList.exists)",
            "list.collection=\(collectionList.exists)",
            "loading=\(loading.exists)",
            "empty=\(emptyState.exists)",
            "error=\(errorBanner.exists)",
            "sharedIntro=\(sharedIntro.exists)",
            "disclosureButtons=\(disclosureButtonCount)",
        ].joined(separator: " ")
    }
}
