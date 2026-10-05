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
                heroTitle: "Tirez davantage de chaque bilan",
                closeLabel: "Fermer",
                restoreLabel: "Restaurer les achats",
                privacyLabel: "politique de confidentialité",
                termsLabel: "Conditions d'utilisation",
                monthlyTitle: "CycleBalance Premium Mensuel",
                yearlyTitle: "CycleBalance Premium Annuel",
                monthlyPeriodSuffix: "/ mois",
                yearlyPeriodSuffix: "/ an",
                unavailableTitle: "Abonnements indisponibles"
            ),
            LocaleSpec(
                appLanguage: "de",
                localeIdentifier: "de_DE",
                heroTitle: "Hol mehr aus jedem Check-in heraus",
                closeLabel: "Schließen",
                restoreLabel: "Käufe wiederherstellen",
                privacyLabel: "Datenschutzrichtlinie",
                termsLabel: "Nutzungsbedingungen",
                monthlyTitle: "CycleBalance Premium Monatlich",
                yearlyTitle: "CycleBalance Premium Jährlich",
                monthlyPeriodSuffix: "/ Monat",
                yearlyPeriodSuffix: "/ Jahr",
                unavailableTitle: "Abonnements nicht verfügbar"
            ),
            LocaleSpec(
                appLanguage: "nl",
                localeIdentifier: "nl_NL",
                heroTitle: "Haal meer uit elke check-in",
                closeLabel: "Sluiten",
                restoreLabel: "Aankopen herstellen",
                privacyLabel: "Privacybeleid",
                termsLabel: "Gebruiksvoorwaarden",
                monthlyTitle: "CycleBalance Premium Maandelijks",
                yearlyTitle: "CycleBalance Premium Jaarlijks",
                monthlyPeriodSuffix: "/ maand",
                yearlyPeriodSuffix: "/ jaar",
                unavailableTitle: "Abonnementen niet beschikbaar"
            ),
        ]

        static let shardTwo: [LocaleSpec] = [
            LocaleSpec(
                appLanguage: "it",
                localeIdentifier: "it_IT",
                heroTitle: "Ottieni di più da ogni check-in",
                closeLabel: "Chiudi",
                restoreLabel: "Ripristina acquisti",
                privacyLabel: "politica sulla riservatezza",
                termsLabel: "Condizioni d'uso",
                monthlyTitle: "CycleBalance Premium Mensile",
                yearlyTitle: "CycleBalance Premium Annuale",
                monthlyPeriodSuffix: "/ mese",
                yearlyPeriodSuffix: "/ anno",
                unavailableTitle: "Abbonamenti non disponibili"
            ),
            LocaleSpec(
                appLanguage: "ja",
                localeIdentifier: "ja_JP",
                heroTitle: "毎日のチェックインをもっと活かす",
                closeLabel: "閉じる",
                restoreLabel: "購入を復元",
                privacyLabel: "プライバシーポリシー",
                termsLabel: "利用規約",
                monthlyTitle: "CycleBalance プレミアム 月額",
                yearlyTitle: "CycleBalance プレミアム 年額",
                monthlyPeriodSuffix: "/ 月",
                yearlyPeriodSuffix: "/ 年",
                unavailableTitle: "購読は利用できません"
            ),
            LocaleSpec(
                appLanguage: "ko",
                localeIdentifier: "ko_KR",
                heroTitle: "매번의 체크인을 더 알차게",
                closeLabel: "닫기",
                restoreLabel: "구매 복원",
                privacyLabel: "개인 정보 보호 정책",
                termsLabel: "이용 약관",
                monthlyTitle: "CycleBalance 프리미엄 월간",
                yearlyTitle: "CycleBalance 프리미엄 연간",
                monthlyPeriodSuffix: "/ 월",
                yearlyPeriodSuffix: "/ 년",
                unavailableTitle: "구독을 사용할 수 없음"
            ),
        ]
    }

    private let englishHeroTitle = "Get more from every check-in"
    private let englishMonthlyTitle = "CycleBalance Premium Monthly"
    private let englishYearlyTitle = "CycleBalance Premium Yearly"
    private let englishMonthlyPeriodSuffix = "/ month"
    private let englishYearlyPeriodSuffix = "/ year"
    private let englishRestoreLabel = "Restore purchases"
    private let englishPrivacyLabel = "Privacy Policy"
    private let englishTermsLabel = "Terms of Use"
    private let englishUnavailableTitle = "Subscriptions Unavailable"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSystemLocalePaywallMatrixShardOne() {
        runSystemLocaleMatrix(specs: LocaleSpec.shardOne)
    }

    @MainActor
    func testSystemLocalePaywallMatrixShardTwo() {
        runSystemLocaleMatrix(specs: LocaleSpec.shardTwo)
    }

    @MainActor
    func testAppLanguagePaywallMatrixShardOne() {
        runAppLanguageMatrix(specs: LocaleSpec.shardOne)
    }

    @MainActor
    func testAppLanguagePaywallMatrixShardTwo() {
        runAppLanguageMatrix(specs: LocaleSpec.shardTwo)
    }

    @MainActor
    private func runSystemLocaleMatrix(specs: [LocaleSpec]) {
        for spec in specs {
            XCTContext.runActivity(named: "system \(spec.appLanguage)") { _ in
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
    private func runAppLanguageMatrix(specs: [LocaleSpec]) {
        for spec in specs {
            XCTContext.runActivity(named: "app-language \(spec.appLanguage)") { _ in
                let app = makeApp(
                    language: "en",
                    locale: "en_US",
                    onboardingCompleted: true,
                    appLanguage: "system"
                )
                app.launch()
                openSettingsTab(in: app)

                let settingsScreen = settingsScreenElement(in: app)
                XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
                let appLanguageRow = identifiedElement("settings.app_language.row", in: app)
                scrollToElement(appLanguageRow, in: settingsScreen)
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
            "-appearance.enableExperimentalThemes", "NO",
            "-appearance.themeOption", "botanicalJournal",
        ]
        return app
    }

    @MainActor
    private func openSettingsTab(in app: XCUIApplication) {
        tapMainTab(.settings, in: app)
    }

    @MainActor
    private func openPaywallFromSettings(in app: XCUIApplication) {
        let settingsScreen = settingsScreenElement(in: app)
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let subscriptionRow = identifiedElement("settings.subscription.row", in: app)
        scrollToElement(subscriptionRow, in: settingsScreen)
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

        // Plan cards are single buttons whose accessibility label combines the localized plan
        // name and the "/ month" style price, so the labels are checked rather than child texts.
        let yearlyPlan = identifiedElement("paywall.plan.cyclebalance.premium.annual", in: app)
        let monthlyPlan = identifiedElement("paywall.plan.cyclebalance.premium.monthly", in: app)

        if yearlyPlan.waitForExistence(timeout: 8), monthlyPlan.waitForExistence(timeout: 5) {
            XCTAssertTrue(yearlyPlan.label.contains(spec.yearlyTitle), file: file, line: line)
            XCTAssertTrue(yearlyPlan.label.contains(spec.yearlyPeriodSuffix), file: file, line: line)
            XCTAssertTrue(monthlyPlan.label.contains(spec.monthlyTitle), file: file, line: line)
            XCTAssertTrue(monthlyPlan.label.contains(spec.monthlyPeriodSuffix), file: file, line: line)
            XCTAssertFalse(monthlyPlan.label.contains(englishMonthlyPeriodSuffix), file: file, line: line)
            XCTAssertFalse(yearlyPlan.label.contains(englishYearlyPeriodSuffix), file: file, line: line)
            XCTAssertTrue(identifiedElement("paywall.continue", in: app).exists, file: file, line: line)
            XCTAssertTrue(identifiedElement("paywall.renewal_terms", in: app).exists, file: file, line: line)
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
    private func settingsScreenElement(in app: XCUIApplication) -> XCUIElement {
        let screen = identifiedElement("screen.settings", in: app)
        if screen.exists {
            return screen
        }
        return app.collectionViews["screen.settings"]
    }

    @MainActor
    private func scrollToElement(_ element: XCUIElement, in container: XCUIElement, maxSwipes: Int = 8) {
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

        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable && isInSafeTapZone(element, in: container) {
                return
            }
            container.swipeDown()
        }

        XCTAssertTrue(element.waitForExistence(timeout: 2))
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(isInSafeTapZone(element, in: container))
    }

    @MainActor
    private func isInSafeTapZone(_ element: XCUIElement, in container: XCUIElement) -> Bool {
        let bottomSafeInset: CGFloat = 80
        return element.frame.maxY <= container.frame.maxY - bottomSafeInset
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
