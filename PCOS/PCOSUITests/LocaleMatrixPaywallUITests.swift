import XCTest

final class LocaleMatrixPaywallUITests: XCTestCase {
    private struct LocaleSpec {
        let appLanguage: String
        let localeIdentifier: String
        let heroTitle: String
        let closeLabel: String
        let restoreLabel: String
        let privacyLabel: String
        let termsLabel: String
        let monthlyTitle: String
        let yearlyTitle: String
        let monthlyPeriodSuffix: String
        let yearlyPeriodSuffix: String
        let unavailableTitle: String

        static let shardOne: [LocaleSpec] = [
            LocaleSpec(
                appLanguage: "fr",
                localeIdentifier: "fr_FR",
                heroTitle: "Débloquez Premium",
                closeLabel: "Fermer",
                restoreLabel: "Restaurer les achats",
                privacyLabel: "politique de confidentialité",
                termsLabel: "Conditions d'utilisation",
                monthlyTitle: "CycleBalance Premium Mensuel",
                yearlyTitle: "CycleBalance Premium Annuel",
                monthlyPeriodSuffix: "/ 1 mois",
                yearlyPeriodSuffix: "/ 1 an",
                unavailableTitle: "Abonnements indisponibles"
            ),
            LocaleSpec(
                appLanguage: "de",
                localeIdentifier: "de_DE",
                heroTitle: "Premium freischalten",
                closeLabel: "Schließen",
                restoreLabel: "Einkäufe wiederherstellen",
                privacyLabel: "Datenschutzrichtlinie",
                termsLabel: "Nutzungsbedingungen",
                monthlyTitle: "CycleBalance Premium Monatlich",
                yearlyTitle: "CycleBalance Premium Jährlich",
                monthlyPeriodSuffix: "/ 1 Monat",
                yearlyPeriodSuffix: "/ 1 Jahr",
                unavailableTitle: "Abonnements nicht verfügbar"
            ),
            LocaleSpec(
                appLanguage: "nl",
                localeIdentifier: "nl_NL",
                heroTitle: "Ontgrendel Premium",
                closeLabel: "Sluiten",
                restoreLabel: "Aankopen herstellen",
                privacyLabel: "Privacybeleid",
                termsLabel: "Servicevoorwaarden",
                monthlyTitle: "CycleBalance Premium Maandelijks",
                yearlyTitle: "CycleBalance Premium Jaarlijks",
                monthlyPeriodSuffix: "/ 1 maand",
                yearlyPeriodSuffix: "/ 1 jaar",
                unavailableTitle: "Abonnementen niet beschikbaar"
            ),
        ]

        static let shardTwo: [LocaleSpec] = [
            LocaleSpec(
                appLanguage: "it",
                localeIdentifier: "it_IT",
                heroTitle: "Sblocca Premium",
                closeLabel: "Chiudi",
                restoreLabel: "Ripristina gli acquisti",
                privacyLabel: "politica sulla riservatezza",
                termsLabel: "Termini di servizio",
                monthlyTitle: "CycleBalance Premium Mensile",
                yearlyTitle: "CycleBalance Premium Annuale",
                monthlyPeriodSuffix: "/ 1 mese",
                yearlyPeriodSuffix: "/ 1 anno",
                unavailableTitle: "Abbonamenti non disponibili"
            ),
            LocaleSpec(
                appLanguage: "ja",
                localeIdentifier: "ja_JP",
                heroTitle: "プレミアムをアンロック",
                closeLabel: "閉じる",
                restoreLabel: "購入を復元する",
                privacyLabel: "プライバシーポリシー",
                termsLabel: "利用規約",
                monthlyTitle: "CycleBalance プレミアム 月額",
                yearlyTitle: "CycleBalance プレミアム 年額",
                monthlyPeriodSuffix: "/ 1 か月",
                yearlyPeriodSuffix: "/ 1 年",
                unavailableTitle: "購読は利用できません"
            ),
            LocaleSpec(
                appLanguage: "ko",
                localeIdentifier: "ko_KR",
                heroTitle: "프리미엄 잠금 해제",
                closeLabel: "닫기",
                restoreLabel: "구매 복원",
                privacyLabel: "개인 정보 보호 정책",
                termsLabel: "서비스 약관",
                monthlyTitle: "CycleBalance 프리미엄 월간",
                yearlyTitle: "CycleBalance 프리미엄 연간",
                monthlyPeriodSuffix: "/ 1개월",
                yearlyPeriodSuffix: "/ 1년",
                unavailableTitle: "구독을 사용할 수 없음"
            ),
        ]
    }

    private let englishHeroTitle = "Unlock Premium"
    private let englishMonthlyTitle = "CycleBalance Premium Monthly"
    private let englishYearlyTitle = "CycleBalance Premium Yearly"
    private let englishMonthlyPeriodSuffix = "/ 1 month"
    private let englishYearlyPeriodSuffix = "/ 1 year"
    private let englishRestoreLabel = "Restore Purchases"
    private let englishPrivacyLabel = "Privacy Policy"
    private let englishTermsLabel = "Terms of Service"
    private let englishUnavailableTitle = "Subscriptions Unavailable"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSystemLocalePaywallMatrixShardOne() throws {
        try runSystemLocaleMatrix(specs: LocaleSpec.shardOne)
    }

    @MainActor
    func testSystemLocalePaywallMatrixShardTwo() throws {
        try runSystemLocaleMatrix(specs: LocaleSpec.shardTwo)
    }

    @MainActor
    func testAppLanguagePaywallMatrixShardOne() throws {
        try runAppLanguageMatrix(specs: LocaleSpec.shardOne)
    }

    @MainActor
    func testAppLanguagePaywallMatrixShardTwo() throws {
        try runAppLanguageMatrix(specs: LocaleSpec.shardTwo)
    }

    @MainActor
    private func runSystemLocaleMatrix(specs: [LocaleSpec]) throws {
        for spec in specs {
            try XCTContext.runActivity(named: "system \(spec.appLanguage)") { _ in
                let app = makeApp(
                    language: spec.appLanguage,
                    locale: spec.localeIdentifier,
                    onboardingCompleted: true,
                    appLanguage: "system"
                )
                app.launch()
                openSettingsTab(in: app)
                openPaywallFromSettings(in: app)
                assertLocalizedPaywall(in: app, spec: spec)
                captureScreenshot(named: "paywall-system-\(spec.appLanguage)")
                app.terminate()
            }
        }
    }

    @MainActor
    private func runAppLanguageMatrix(specs: [LocaleSpec]) throws {
        for spec in specs {
            try XCTContext.runActivity(named: "app-language \(spec.appLanguage)") { _ in
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

                let option = app.buttons["settings.app_language.option.\(spec.appLanguage)"]
                XCTAssertTrue(option.waitForExistence(timeout: 5))
                option.tap()

                openPaywallFromSettings(in: app)
                assertLocalizedPaywall(in: app, spec: spec)
                captureScreenshot(named: "paywall-app-language-\(spec.appLanguage)")
                app.terminate()
            }
        }
    }

    @MainActor
    private func makeApp(
        language: String,
        locale: String,
        onboardingCompleted: Bool,
        appLanguage: String
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITestMode",
            "-onboarding.hasCompletedOnboarding", onboardingCompleted ? "YES" : "NO",
            "-onboarding.hasCompletedWelcome", onboardingCompleted ? "YES" : "NO",
            "-onboarding.hasCompletedQuestionnaire", onboardingCompleted ? "YES" : "NO",
            "-onboarding.hasCompletedGuidedAction", onboardingCompleted ? "YES" : "NO",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-app.language", appLanguage,
        ]
        return app
    }

    @MainActor
    private func openSettingsTab(in app: XCUIApplication) {
        tapMainTab(.settings, in: app)
    }

    @MainActor
    private func openPaywallFromSettings(in app: XCUIApplication) {
        let subscriptionRow = identifiedElement("settings.subscription.row", in: app)
        XCTAssertTrue(subscriptionRow.waitForExistence(timeout: 10))
        subscriptionRow.tap()

        XCTAssertTrue(identifiedElement("screen.paywall", in: app).waitForExistence(timeout: 8))
    }

    @MainActor
    private func assertLocalizedPaywall(
        in app: XCUIApplication,
        spec: LocaleSpec,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(identifiedElement("paywall.hero", in: app).waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(identifiedElement("paywall.hero.title", in: app).waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(app.staticTexts[spec.heroTitle].waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertFalse(app.staticTexts[englishHeroTitle].exists, file: file, line: line)

        XCTAssertTrue(paywallElement(identifier: "paywall.close", label: spec.closeLabel, in: app).waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(paywallElement(identifier: "paywall.restore", label: spec.restoreLabel, in: app).waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(paywallElement(identifier: "paywall.privacy_policy", label: spec.privacyLabel, in: app).waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(paywallElement(identifier: "paywall.terms_of_service", label: spec.termsLabel, in: app).waitForExistence(timeout: 5), file: file, line: line)

        assertEnglishFallbackIsHidden(in: app, file: file, line: line)

        let monthlyTitle = app.staticTexts[spec.monthlyTitle]
        let yearlyTitle = app.staticTexts[spec.yearlyTitle]

        if monthlyTitle.waitForExistence(timeout: 8), yearlyTitle.waitForExistence(timeout: 5) {
            XCTAssertTrue(monthlyTitle.exists, file: file, line: line)
            XCTAssertTrue(yearlyTitle.exists, file: file, line: line)
            XCTAssertTrue(staticText(endingWith: spec.monthlyPeriodSuffix, in: app).waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertTrue(staticText(endingWith: spec.yearlyPeriodSuffix, in: app).waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertFalse(staticText(endingWith: englishMonthlyPeriodSuffix, in: app).exists, file: file, line: line)
            XCTAssertFalse(staticText(endingWith: englishYearlyPeriodSuffix, in: app).exists, file: file, line: line)
        } else {
            XCTAssertTrue(app.staticTexts[spec.unavailableTitle].waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertFalse(app.staticTexts[englishUnavailableTitle].exists, file: file, line: line)
        }
    }

    @MainActor
    private func assertEnglishFallbackIsHidden(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(app.staticTexts[englishMonthlyTitle].exists, file: file, line: line)
        XCTAssertFalse(app.staticTexts[englishYearlyTitle].exists, file: file, line: line)
        XCTAssertFalse(app.buttons[englishRestoreLabel].exists, file: file, line: line)
        XCTAssertFalse(app.links[englishPrivacyLabel].exists, file: file, line: line)
        XCTAssertFalse(app.links[englishTermsLabel].exists, file: file, line: line)
    }

    @MainActor
    private func staticText(endingWith suffix: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", suffix)).firstMatch
    }

    @MainActor
    private func identifiedElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    @MainActor
    private func paywallElement(identifier: String, label: String, in app: XCUIApplication) -> XCUIElement {
        let identified = identifiedElement(identifier, in: app)
        if identified.exists {
            return identified
        }

        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func captureScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
