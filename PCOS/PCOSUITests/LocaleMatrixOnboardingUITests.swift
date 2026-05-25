import XCTest

final class LocaleMatrixOnboardingUITests: XCTestCase {
    private struct LocaleSpec {
        let languageIdentifier: String
        let localeIdentifier: String
        let questionnaireTitle: String
        let resultsHeadline: String
        let featureTitle: String
        let socialProofTitle: String
        let permissionsTitle: String
        let completionMessage: String

        static let shardOne: [LocaleSpec] = [
            LocaleSpec(
                languageIdentifier: "fr",
                localeIdentifier: "fr_FR",
                questionnaireTitle: "Qu'est-ce qui vous amène à CycleBalance ?",
                resultsHeadline: "CycleBalance est prête à vous aider",
                featureTitle: "Votre espace santé personnel",
                socialProofTitle: "Ce qu'en disent les femmes",
                permissionsTitle: "Aidez CycleBalance à mieux vous servir",
                completionMessage: "Vous faites partie d'une communauté grandissante de femmes qui reprennent la main sur leur PCOS. Nous sommes ravis de vous accueillir."
            ),
            LocaleSpec(
                languageIdentifier: "de",
                localeIdentifier: "de_DE",
                questionnaireTitle: "Was bringt Sie zu CycleBalance?",
                resultsHeadline: "CycleBalance ist bereit, dir zu helfen",
                featureTitle: "Dein persönlicher Gesundheits-Hub",
                socialProofTitle: "Was Frauen sagen",
                permissionsTitle: "Hilf CycleBalance, noch besser zu werden",
                completionMessage: "Du bist Teil einer wachsenden Community von Frauen, die ihr PCOS selbst in die Hand nehmen. Schön, dass du da bist."
            ),
            LocaleSpec(
                languageIdentifier: "nl",
                localeIdentifier: "nl_NL",
                questionnaireTitle: "Wat brengt jou bij CycleBalance?",
                resultsHeadline: "CycleBalance staat klaar om je te helpen",
                featureTitle: "Jouw persoonlijke gezondheidshub",
                socialProofTitle: "Wat vrouwen zeggen",
                permissionsTitle: "Help CycleBalance beter te werken",
                completionMessage: "Je maakt deel uit van een groeiende community van vrouwen die grip krijgen op hun PCOS. Fijn dat je er bent."
            ),
        ]

        static let shardTwo: [LocaleSpec] = [
            LocaleSpec(
                languageIdentifier: "ja",
                localeIdentifier: "ja_JP",
                questionnaireTitle: "CycleBalance に興味を持ったのは何ですか?",
                resultsHeadline: "CycleBalanceはあなたをサポートする準備ができています",
                featureTitle: "あなたのパーソナル健康ハブ",
                socialProofTitle: "みんなの声",
                permissionsTitle: "CycleBalanceをもっと役立てるために",
                completionMessage: "あなたはPCOSと向き合う女性たちの広がるコミュニティの一員です。ここに来てくれてうれしいです。"
            ),
            LocaleSpec(
                languageIdentifier: "it",
                localeIdentifier: "it_IT",
                questionnaireTitle: "Cosa ti porta a CycleBalance?",
                resultsHeadline: "CycleBalance è pronta ad aiutarti",
                featureTitle: "Il tuo hub personale per la salute",
                socialProofTitle: "Cosa dicono le donne",
                permissionsTitle: "Aiuta CycleBalance a funzionare meglio",
                completionMessage: "Fai parte di una comunità in crescita di donne che stanno prendendo in mano il proprio PCOS. Siamo felici che tu sia qui."
            ),
            LocaleSpec(
                languageIdentifier: "ko",
                localeIdentifier: "ko_KR",
                questionnaireTitle: "CycleBalance을(를) 방문하게 된 계기는 무엇인가요?",
                resultsHeadline: "CycleBalance가 도와드릴 준비를 마쳤어요",
                featureTitle: "나만의 건강 허브",
                socialProofTitle: "다른 여성들의 이야기",
                permissionsTitle: "CycleBalance가 더 잘 작동하도록 도와주세요",
                completionMessage: "이제 PCOS를 스스로 관리해 나가는 여성들의 커뮤니티에 함께하고 있어요. 함께해 주셔서 반가워요."
            ),
        ]
    }

    private struct PhaseExpectation {
        let launchPhase: String
        let localizedText: String
        let englishFallback: String
    }

    private let englishQuestionnaireTitle = "What brings you to CycleBalance?"
    private let englishResultsHeadline = "CycleBalance is ready to help"
    private let englishFeatureTitle = "Your Personal Health Hub"
    private let englishSocialProofTitle = "What women are saying"
    private let englishPermissionsTitle = "Help CycleBalance work better"
    private let englishCompletionMessage = "You're part of a growing community of women taking control of their PCOS. We're glad you're here."

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingLocaleMatrixShardOne() throws {
        try runLocaleMatrix(specs: LocaleSpec.shardOne)
    }

    @MainActor
    func testOnboardingLocaleMatrixShardTwo() throws {
        try runLocaleMatrix(specs: LocaleSpec.shardTwo)
    }

    @MainActor
    private func runLocaleMatrix(specs: [LocaleSpec]) throws {
        for spec in specs {
            for expectation in phaseExpectations(for: spec) {
                try XCTContext.runActivity(
                    named: "\(spec.languageIdentifier) \(expectation.launchPhase)"
                ) { _ in
                    let app = makeApp(
                        language: spec.languageIdentifier,
                        locale: spec.localeIdentifier,
                        startPhase: expectation.launchPhase
                    )
                    app.launch()
                    assertLocalizedText(
                        localized: expectation.localizedText,
                        englishFallback: expectation.englishFallback,
                        in: app
                    )
                    app.terminate()
                }
            }
        }
    }

    private func phaseExpectations(for spec: LocaleSpec) -> [PhaseExpectation] {
        [
            PhaseExpectation(
                launchPhase: "quiz",
                localizedText: spec.questionnaireTitle,
                englishFallback: englishQuestionnaireTitle
            ),
            PhaseExpectation(
                launchPhase: "results",
                localizedText: spec.resultsHeadline,
                englishFallback: englishResultsHeadline
            ),
            PhaseExpectation(
                launchPhase: "how_app_helps",
                localizedText: spec.featureTitle,
                englishFallback: englishFeatureTitle
            ),
            PhaseExpectation(
                launchPhase: "social_proof",
                localizedText: spec.socialProofTitle,
                englishFallback: englishSocialProofTitle
            ),
            PhaseExpectation(
                launchPhase: "permissions",
                localizedText: spec.permissionsTitle,
                englishFallback: englishPermissionsTitle
            ),
            PhaseExpectation(
                launchPhase: "completion",
                localizedText: spec.completionMessage,
                englishFallback: englishCompletionMessage
            ),
        ]
    }

    @MainActor
    private func makeApp(language: String, locale: String, startPhase: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITestMode",
            "-onboarding.hasCompletedOnboarding", "NO",
            "-onboarding.hasCompletedWelcome", "NO",
            "-onboarding.hasCompletedQuestionnaire", "NO",
            "-onboarding.hasCompletedGuidedAction", "NO",
            "-onboarding.hasPromptedForReview", "NO",
            "-onboarding.primaryGoal", "__unset__",
            "-onboarding.pcosExperience", "__unset__",
            "-onboarding.symptomFocusAreas", "__unset__",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-app.language", "system",
            "-onboarding.startPhase", startPhase,
        ]
        return app
    }

    @MainActor
    private func assertLocalizedText(
        localized: String,
        englishFallback: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let localizedText = app.staticTexts.matching(NSPredicate(format: "label == %@", localized)).firstMatch
        let englishText = app.staticTexts.matching(NSPredicate(format: "label == %@", englishFallback)).firstMatch

        XCTAssertTrue(localizedText.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertFalse(englishText.exists, file: file, line: line)
    }
}
