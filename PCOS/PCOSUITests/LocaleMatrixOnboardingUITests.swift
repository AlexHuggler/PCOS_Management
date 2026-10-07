import XCTest

@MainActor
final class LocaleMatrixOnboardingUITests: XCTestCase {
    private struct LocaleSpec {
        let language: String
        let locale: String
        let welcomeTitle: String
        let stageTitle: String
        let getStarted: String
    }

    // Literal expectations intentionally verify translations rather than reading the app bundle.
    private static let locales: [LocaleSpec] = [
        LocaleSpec(language: "en", locale: "en_US", welcomeTitle: "Understand your PCOS patterns, privately.", stageTitle: "Where are you in your PCOS journey?", getStarted: "Get started"),
        LocaleSpec(language: "fr", locale: "fr_FR", welcomeTitle: "Comprenez vos tendances SOPK, en toute confidentialité.", stageTitle: "Où en êtes-vous avec votre SOPK ?", getStarted: "Commencer"),
        LocaleSpec(language: "de", locale: "de_DE", welcomeTitle: "Verstehe deine PCOS-Muster – ganz privat.", stageTitle: "Wo stehst du mit deinem PCOS?", getStarted: "Los geht's"),
        LocaleSpec(language: "nl", locale: "nl_NL", welcomeTitle: "Begrijp je PCOS-patronen, privé.", stageTitle: "Waar sta je met je PCOS?", getStarted: "Aan de slag"),
        LocaleSpec(language: "ja", locale: "ja_JP", welcomeTitle: "PCOSのパターンを、プライベートに理解する。", stageTitle: "PCOSとの付き合いはどのくらいですか？", getStarted: "はじめる"),
        LocaleSpec(language: "it", locale: "it_IT", welcomeTitle: "Comprendi i tuoi schemi di PCOS, in privato.", stageTitle: "A che punto sei con la tua PCOS?", getStarted: "Inizia"),
        LocaleSpec(language: "ko", locale: "ko_KR", welcomeTitle: "나의 PCOS 패턴을 비공개로 이해하세요.", stageTitle: "PCOS와 함께한 여정은 어디쯤인가요?", getStarted: "시작하기"),
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
            XCTContext.runActivity(named: "\(spec.language): localized welcome, skippable steps, Back and Today") { _ in
                let app = makeApp(language: spec.language, locale: spec.locale)
                app.launch()
                defer { app.terminate() }
                assertStage(0, in: app)
                assertLocalized(spec.welcomeTitle, fallback: "Understand your PCOS patterns, privately.", language: spec.language, in: app)
                XCTAssertEqual(app.buttons["onboarding.get_started"].label, spec.getStarted)
                XCTAssertFalse(app.buttons["onboarding.explore"].exists)
                tap(app.buttons["onboarding.get_started"], in: app)
                assertStage(1, in: app)
                assertLocalized(spec.stageTitle, fallback: "Where are you in your PCOS journey?", language: spec.language, in: app)
                tap(app.buttons["onboarding.back"], in: app)
                assertStage(0, in: app)
                tap(app.buttons["onboarding.get_started"], in: app)
                for stage in 1...4 {
                    assertStage(stage, in: app)
                    tap(app.buttons["onboarding.skip"], in: app)
                }
                assertStage(5, in: app)
                tap(app.buttons["onboarding.finish"], in: app)
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
            "-onboarding.startPhase", "journey_0",
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
