import XCTest

@MainActor
final class LocaleMatrixOnboardingUITests: XCTestCase {
    private struct LocaleSpec {
        let language: String
        let locale: String
        let welcomeTitle: String
        let choiceTitle: String
        let personalize: String
        let explore: String
    }

    // Literal expectations intentionally verify translations rather than reading the app bundle.
    private static let locales: [LocaleSpec] = [
        LocaleSpec(language: "en", locale: "en_US", welcomeTitle: "A little support for your everyday", choiceTitle: "What would you like support with?", personalize: "Make it yours", explore: "Explore Today"),
        LocaleSpec(language: "fr", locale: "fr_FR", welcomeTitle: "Un peu de soutien au quotidien", choiceTitle: "Dans quel domaine aimeriez-vous du soutien ?", personalize: "À votre image", explore: "Découvrir Aujourd’hui"),
        LocaleSpec(language: "de", locale: "de_DE", welcomeTitle: "Ein bisschen Unterstützung für deinen Alltag", choiceTitle: "Wobei möchtest du Unterstützung?", personalize: "Mach es zu deinem", explore: "„Heute“ entdecken"),
        LocaleSpec(language: "nl", locale: "nl_NL", welcomeTitle: "Een beetje steun voor elke dag", choiceTitle: "Waar wil je ondersteuning bij?", personalize: "Maak het persoonlijk", explore: "Vandaag verkennen"),
        LocaleSpec(language: "ja", locale: "ja_JP", welcomeTitle: "毎日に、ささやかなサポートを", choiceTitle: "どんなサポートがあるとよいですか？", personalize: "自分に合わせる", explore: "「今日」を見てみる"),
        LocaleSpec(language: "it", locale: "it_IT", welcomeTitle: "Un piccolo sostegno per ogni giorno", choiceTitle: "In cosa vorresti un sostegno?", personalize: "A modo tuo", explore: "Esplora Oggi"),
        LocaleSpec(language: "ko", locale: "ko_KR", welcomeTitle: "일상에 더하는 작은 도움", choiceTitle: "어떤 도움을 받고 싶으세요?", personalize: "나에게 맞추기", explore: "오늘 둘러보기"),
    ]

    override func setUpWithError() throws { continueAfterFailure = false }

    func testOnboardingLocaleMatrixShardOne() {
        runLocaleMatrix(specs: Array(Self.locales.prefix(4)))
    }

    func testOnboardingLocaleMatrixShardTwo() {
        runLocaleMatrix(specs: Array(Self.locales.suffix(3)))
    }

    private func runLocaleMatrix(specs: [LocaleSpec]) {
        for spec in specs {
            XCTContext.runActivity(named: "\(spec.language): localized welcome, optional choices, Back and Explore") { _ in
                let app = makeApp(language: spec.language, locale: spec.locale)
                app.launch()
                defer { app.terminate() }
                assertStage(0, in: app)
                assertLocalized(spec.welcomeTitle, fallback: "A little support for your everyday", language: spec.language, in: app)
                XCTAssertEqual(app.buttons["onboarding.explore"].label, spec.explore)
                tap(app.buttons[spec.personalize], in: app)
                assertStage(1, in: app)
                assertLocalized(spec.choiceTitle, fallback: "What would you like support with?", language: spec.language, in: app)
                tap(app.buttons["onboarding.back"], in: app)
                assertStage(0, in: app)
                tap(app.buttons["onboarding.explore"], in: app)
                XCTAssertTrue(app.buttons["today.checkin"].waitForExistence(timeout: 10), spec.language)
                XCTAssertEqual(app.tabBars.buttons.count, 5, spec.language)
            }
        }
    }

    private func makeApp(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITestMode",
            "-onboarding.hasCompletedOnboarding", "NO",
            "-onboarding.hasCompletedWelcome", "NO",
            "-onboarding.hasCompletedQuestionnaire", "NO",
            "-onboarding.hasCompletedGuidedAction", "NO",
            "-onboarding.hasPromptedForReview", "NO",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-app.language", "system",
            "-appearance.themeOption", "calm",
            "-appearance.colorMode", "light",
            "-onboarding.startPhase", "companion_0",
        ]
        return app
    }

    private func assertStage(_ number: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "onboarding.companion.\(number)").firstMatch.waitForExistence(timeout: 10), file: file, line: line)
    }

    private func assertLocalized(_ text: String, fallback: String, language: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts[text].firstMatch.waitForExistence(timeout: 5), file: file, line: line)
        if language != "en" { XCTAssertFalse(app.staticTexts[fallback].exists, file: file, line: line) }
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, file: file, line: line)
        element.tap()
    }
}
