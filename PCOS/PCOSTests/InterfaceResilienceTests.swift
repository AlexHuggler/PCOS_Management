import Testing
import Foundation
@testable import PCOS

private let contentViewSourceRelativePath = "../PCOS/App/ContentView.swift"
private let paywallSourceRelativePath = "../PCOS/Core/StoreKit/PaywallView.swift"
private let premiumGateSourceRelativePath = "../PCOS/Core/StoreKit/PremiumGate.swift"
private let calendarSourceRelativePath = "../PCOS/Features/Cycle/Views/CalendarMonthView.swift"
private let supplementHistorySourceRelativePath = "../PCOS/Features/Supplements/Views/SupplementHistoryView.swift"
private let bloodSugarHistorySourceRelativePath = "../PCOS/Features/BloodSugar/Views/BloodSugarHistoryView.swift"
private let todayViewSourceRelativePath = "../PCOS/Features/Cycle/Views/TodayView.swift"
private let mealLogSourceRelativePath = "../PCOS/Features/Meals/Views/MealLogView.swift"
private let mealScanFlowSourceRelativePath = "../PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift"
private let mealScanFeatureFlagsSourceRelativePath = "../PCOS/Features/Meals/MealScan/MealScanFeatureFlags.swift"
private let onboardingContainerSourceRelativePath = "../PCOS/Features/Onboarding/Views/OnboardingContainerView.swift"
private let onboardingHowAppHelpsSourceRelativePath = "../PCOS/Features/Onboarding/Views/HowAppHelpsView.swift"
private let onboardingQuestionnaireSourceRelativePath = "../PCOS/Features/Onboarding/Views/QuestionnaireView.swift"
private let onboardingMealScanDemoSourceRelativePath = "../PCOS/Features/Onboarding/Views/OnboardingMealScanDemoView.swift"
private let symptomGridItemSourceRelativePath = "../PCOS/Features/Symptoms/Views/SymptomGridItem.swift"
private let settingsSourceRelativePath = "../PCOS/App/SettingsView.swift"
private let settingsDebugToolsSourceRelativePath = "../PCOS/App/SettingsDebugToolsState.swift"
private let fsaHSAResourcesSourceRelativePath = "../PCOS/App/FSAHSAResourcesView.swift"
private let notificationManagerSourceRelativePath = "../PCOS/Core/Notifications/NotificationManager.swift"
private let notificationSettingsSourceRelativePath = "../PCOS/Core/Notifications/NotificationSettingsView.swift"

private let sharedSchemeDirectoryCandidates = [
    "../../PCOS.xcodeproj/xcshareddata/xcschemes",
    "../PCOS.xcodeproj/xcshareddata/xcschemes",
]

@Suite("Interface Resilience", .serialized)
struct InterfaceResilienceTests {
    private func loadSource(relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func loadSharedScheme(named name: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)

        for candidate in sharedSchemeDirectoryCandidates {
            let schemeURL = testFileURL
                .deletingLastPathComponent()
                .appendingPathComponent(candidate)
                .appendingPathComponent(name)
                .standardizedFileURL

            if FileManager.default.fileExists(atPath: schemeURL.path) {
                return try String(contentsOf: schemeURL, encoding: .utf8)
            }
        }

        throw NSError(
            domain: "InterfaceResilienceTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate shared scheme \(name)."]
        )
    }

    @Test("PaywallView supports RevenueCat and local StoreKit while refreshing premium state")
    func paywallViewSupportsBothBillingBackends() throws {
        let source = try loadSource(relativePath: paywallSourceRelativePath)

        #expect(source.contains("private enum PaywallCopy"))
        #expect(source.contains("private var isLocalStoreKit: Bool"))
        #expect(source.contains("PaywallFeatureComparisonCard"))
        #expect(source.contains("PaywallPlanCard"))
        #expect(source.contains("PaywallLocalModeBadge"))
        #expect(source.contains("product.paywallDisplayName"))
        #expect(source.contains("L10n.format("))
        #expect(source.contains("\"Save %lld%%\""))
        #expect(!source.contains("RevenueCatUI.PaywallView("))
        #expect(!source.contains("StoreKitBillingClient(configuration:"))
        #expect(source.contains("billingProducts = try await subscriptionManager.loadProducts()"))
        #expect(source.contains("let outcome = try await subscriptionManager.purchase(productID: product.id)"))
        #expect(source.contains("try await subscriptionManager.restorePurchases()"))
        #expect(source.contains("await refreshPremiumStateAndDismissIfNeeded()"))
        #expect(source.contains("appState.isPremium = subscriptionManager.isPremium"))
    }

    @Test("ContentView guards the Insights tab and presents a shared paywall sheet")
    func contentViewGuardsInsightsTabSelection() throws {
        let source = try loadSource(relativePath: contentViewSourceRelativePath)

        #expect(source.contains("private var premiumTabSelection: Binding<AppTab>"))
        #expect(source.contains("appState.selectTab(requestedTab)"))
        #expect(source.contains("TabView(selection: premiumTabSelection)"))
        #expect(source.contains(".sheet(isPresented: paywallPresentation)"))
        #expect(source.contains("PaywallView()"))
    }

    @Test("Calendar day cell avoids fixed micro-font and rigid height")
    func calendarDayCellUsesAdaptiveTextAndHeight() throws {
        let source = try loadSource(relativePath: calendarSourceRelativePath)

        #expect(!source.contains(".font(.system(size: 7, weight: .bold))"))
        #expect(source.contains(".appFont(.caption2)"))
        #expect(source.contains(".minimumScaleFactor(0.75)"))
        #expect(source.contains(".frame(minHeight: 44)"))
        #expect(!source.contains(".frame(height: 44)"))
    }

    @Test("Supplement history ring uses scaled metric sizing without fixed 120x120 frames")
    func supplementHistoryRingUsesAdaptiveSizing() throws {
        let source = try loadSource(relativePath: supplementHistorySourceRelativePath)

        #expect(source.contains("@ScaledMetric(relativeTo: .title2) private var adherenceRingDiameter"))
        #expect(source.contains("private var clampedAdherenceRingDiameter: CGFloat"))
        #expect(source.contains(".frame(width: clampedAdherenceRingDiameter, height: clampedAdherenceRingDiameter)"))
        #expect(!source.contains(".frame(width: 120, height: 120)"))
    }

    @Test("Blood sugar time column uses adaptive single-line width")
    func bloodSugarTimeColumnUsesAdaptiveSingleLineWidth() throws {
        let source = try loadSource(relativePath: bloodSugarHistorySourceRelativePath)

        #expect(source.contains("@ScaledMetric(relativeTo: .subheadline) private var timeColumnIdealWidth: CGFloat"))
        #expect(source.contains(".frame(minWidth: timeColumnIdealWidth * 0.8, idealWidth: timeColumnIdealWidth, alignment: .leading)"))
        #expect(source.contains(".lineLimit(1)"))
        #expect(source.contains(".minimumScaleFactor(0.8)"))
        #expect(!source.contains(".frame(width: 70, alignment: .leading)"))
    }

    @Test("Meal log exposes a unified add nutrition entry point with manual fallback")
    func mealLogExposesUnifiedNutritionEntryPoint() throws {
        let source = try loadSource(relativePath: mealLogSourceRelativePath)

        #expect(source.contains("Add nutrition"))
        #expect(source.contains("showingBarcodeImport = true"))
        #expect(source.contains("BarcodeMealImportSheet"))
        #expect(source.contains("meal_log.manual_barcode_field"))
        #expect(source.contains("meal_log.lookup_barcode_button"))
        #expect(source.contains("AI meal scanning is coming soon"))
        #expect(source.contains("Scan barcode now"))
        #expect(source.contains("private func openMealScanIfAvailable()"))
        #expect(source.contains("guard MealScanFeatureFlags.current.enableMealScanV2 else {"))
        #expect(source.contains("showingMealScan = true"))
        #expect(source.contains("lunarPrimaryMealScanCard"))
        #expect(source.contains("focusManualNutritionEntry()"))
        #expect(source.contains("meal_log.manual_nutrition_button"))
    }

    @Test("Meal scan preview opens without root premium gate while real photos present contextual paywall")
    func mealScanPreviewSeparatesSampleFromPremiumPhotoActions() throws {
        let flowSource = try loadSource(relativePath: mealScanFlowSourceRelativePath)
        let featureFlagsSource = try loadSource(relativePath: mealScanFeatureFlagsSourceRelativePath)
        let settingsSource = try loadSource(relativePath: settingsSourceRelativePath)
        let onboardingSource = try loadSource(relativePath: onboardingMealScanDemoSourceRelativePath)
        let contentSource = try loadSource(relativePath: contentViewSourceRelativePath)

        #expect(!flowSource.contains(".premiumGated()"))
        #expect(flowSource.contains("presentPremiumPaywall(reason: .mealScan)"))
        #expect(flowSource.contains("Use sample meal"))
        #expect(flowSource.contains("if MealScanFeatureFlags.current.enableMockMealScanData {"))
        #expect(flowSource.contains("a compressed copy is sent securely to our AI service for analysis"))
        #expect(flowSource.contains("CycleBalance does not retain the uploaded photo on its server"))
        #expect(flowSource.contains("By default, only nutrition you review and save is kept"))
        #expect(flowSource.contains("Keep Saved Meal Photos in Settings"))
        #expect(featureFlagsSource.contains("enableMealPhotoRetention: boolValue(key: \"mealScan.enableMealPhotoRetention\", launchArgument: \"enableMealPhotoRetention\", debugDefault: true, releaseDefault: false)"))
        #expect(settingsSource.contains("@AppStorage(\"mealScan.enableMealPhotoRetention\") private var enableMealPhotoRetention = false"))
        #expect(!flowSource.contains("Meal estimates stay on your device unless you choose to sync through iCloud."))
        #expect(!flowSource.contains("Meal estimates and nutrition logs stay on your device unless you choose to sync through iCloud."))
        #expect(!onboardingSource.contains("MealScanFlowView("))
        #expect(onboardingSource.contains("Sample meal estimate"))
        #expect(!contentSource.contains("guard appState.allowsPremiumAccess else {\n            appState.presentPremiumPaywall()\n            return\n        }\n        showingMealScan = true"))
    }

    @Test("FSA letter preview uses readable selectable text instead of a disabled fixed editor")
    func fsaLetterPreviewUsesReadableSelectableText() throws {
        let source = try loadSource(relativePath: fsaHSAResourcesSourceRelativePath)

        #expect(!source.contains("TextEditor(text: .constant(letterText))"))
        #expect(source.contains("textSelection(.enabled)"))
        #expect(source.contains("fixedSize(horizontal: false, vertical: true)"))
        #expect(source.contains("Read Full Letter"))
    }

    @Test("Symptom cards use labeled intensity choices instead of unlabeled dots")
    func symptomCardsUseLabeledIntensityChoices() throws {
        let source = try loadSource(relativePath: symptomGridItemSourceRelativePath)

        #expect(source.contains("SymptomIntensityOption"))
        #expect(source.contains("None"))
        #expect(source.contains("Mild"))
        #expect(source.contains("Moderate"))
        #expect(source.contains("Severe"))
        #expect(!source.contains("SeverityPicker(severity: severity"))
    }

    @Test("Settings Your Space opens a daily private journal editor")
    func settingsYourSpaceOpensDailyJournalEditor() throws {
        let source = try loadSource(relativePath: settingsSourceRelativePath)

        #expect(source.contains("DailyJournalEditorView"))
        #expect(source.contains("showingPrivateJournal"))
        #expect(source.contains("settings.lunar.private_notes.open"))
        #expect(source.contains("saveDailyCheckIn("))
    }

    @Test("Tracking support card uses a clear moon icon without overlapping wave art")
    func trackingSupportCardUsesClearMoonIcon() throws {
        let source = try loadSource(relativePath: contentViewSourceRelativePath)

        #expect(source.contains("tracking.lunar.support_card"))
        #expect(source.contains("moon.stars.fill"))
        #expect(!source.contains("LunarWaveMark()\n                .frame(width: 134, height: 58)"))
    }

    @Test("Cycle hero ring reflects cycle-day progress instead of a fixed decorative arc")
    func cycleHeroRingReflectsCycleDayProgress() throws {
        let source = try loadSource(relativePath: todayViewSourceRelativePath)

        #expect(source.contains("LunarCycleHeroRing("))
        #expect(source.contains("progress: cycleHeroRingProgress"))
        #expect(source.contains("private var cycleHeroRingProgress: Double"))
        #expect(source.contains("SilkCometRingModel("))
        #expect(!source.contains(".trim(from: 0.08, to: 0.82)"))
        #expect(!source.contains(".offset(x: 66, y: -72)"))
    }

    @Test("Meal scan reminders have a settings toggle and notification route payload")
    func mealScanRemindersHaveSettingsToggleAndRoutePayload() throws {
        let managerSource = try loadSource(relativePath: notificationManagerSourceRelativePath)
        let settingsSource = try loadSource(relativePath: notificationSettingsSourceRelativePath)
        let contentSource = try loadSource(relativePath: contentViewSourceRelativePath)

        #expect(managerSource.contains("mealScanRemindersEnabled"))
        #expect(managerSource.contains("scheduleMealScanReminder"))
        #expect(managerSource.contains("AppNotificationRoute.mealScan.rawValue"))
        #expect(managerSource.contains("Log a meal or scan a barcode"))
        #expect(!managerSource.contains("Scan a meal with AI"))
        #expect(settingsSource.contains("settings.notifications.meal_scan_toggle"))
        #expect(settingsSource.contains("Meal Check-In"))
        #expect(settingsSource.contains("scan a barcode"))
        #expect(contentSource.contains("pendingNotificationRoute"))
        #expect(contentSource.contains("handleNotificationRoute"))
        #expect(contentSource.contains("guard MealScanFeatureFlags.current.enableMealScanV2 else {"))
        #expect(contentSource.contains("open(shortcut: .meal)"))
    }

    @Test("Positive actions show ranked recommendations while preserving all quick actions")
    func positiveActionsShowRankedRecommendations() throws {
        let source = try loadSource(relativePath: todayViewSourceRelativePath)

        #expect(source.contains("recommendedPositiveActions"))
        #expect(source.contains("PositiveActionRecommendationEngine.rankedRecommendations"))
        #expect(source.contains("ForEach(recommendedPositiveActions.prefix(3))"))
        #expect(source.contains("positive_action.recommendation."))
        #expect(source.contains("ForEach(PositiveActionType.allCases)"))
    }

    @Test("Swipe navigation is bounded to onboarding and not global tab switching")
    func swipeNavigationIsBoundedToOnboarding() throws {
        let onboardingSource = try loadSource(relativePath: onboardingContainerSourceRelativePath)
        let howAppHelpsSource = try loadSource(relativePath: onboardingHowAppHelpsSourceRelativePath)
        let questionnaireSource = try loadSource(relativePath: onboardingQuestionnaireSourceRelativePath)
        let contentSource = try loadSource(relativePath: contentViewSourceRelativePath)

        #expect(onboardingSource.contains("boundedOnboardingSwipeGesture"))
        #expect(onboardingSource.contains("DragGesture(minimumDistance:"))
        #expect(onboardingSource.contains("phaseAllowsContainerSwipe"))
        #expect(onboardingSource.contains("retreat()"))
        #expect(howAppHelpsSource.contains("boundedFeaturePreviewSwipeGesture"))
        #expect(questionnaireSource.contains("boundedQuestionnaireSwipeGesture"))
        #expect(!contentSource.contains("DragGesture(minimumDistance:"))
        #expect(!contentSource.contains("PageTabViewStyle"))
        #expect(!contentSource.contains(".tabViewStyle(.page"))
    }

    @Test("Settings premium QA surfaces RevenueCat scheme warning")
    func settingsPremiumQASurfacesRevenueCatSchemeWarning() throws {
        let settingsSource = try loadSource(relativePath: settingsSourceRelativePath)
        let debugToolsSource = try loadSource(relativePath: settingsDebugToolsSourceRelativePath)

        #expect(settingsSource.contains("debugTools.billingBackendWarning"))
        #expect(settingsSource.contains("RevenueCat App User ID"))
        #expect(settingsSource.contains("Debug: Apple Ads Attribution"))
        #expect(settingsSource.contains("Refresh Apple Ads Diagnostics"))
        #expect(debugToolsSource.contains("var revenueCatAppUserID: String?"))
        #expect(debugToolsSource.contains("var appleAdsDiagnostics = AppleAdsAttributionDiagnostics.empty"))
        #expect(debugToolsSource.contains("PCOS Local StoreKit"))
        #expect(debugToolsSource.contains("[Environment: Xcode]"))
        #expect(debugToolsSource.contains("PCOS.storekit"))
    }

    @Test("Shared Xcode schemes split RevenueCat and local StoreKit launch configuration")
    func sharedXcodeSchemesSplitBillingBackends() throws {
        let revenueCatScheme = try loadSharedScheme(named: "PCOS.xcscheme")
        let localStoreKitScheme = try loadSharedScheme(named: "PCOS Local StoreKit.xcscheme")

        #expect(revenueCatScheme.contains("argument = \"revenuecat\""))
        #expect(!revenueCatScheme.contains("StoreKitConfigurationFileReference"))
        #expect(localStoreKitScheme.contains("argument = \"local_storekit\""))
        #expect(localStoreKitScheme.contains("StoreKitConfigurationFileReference"))
        #expect(localStoreKitScheme.contains("PCOS.storekit"))
    }

    @Test("Premium gate no longer renders lock art overlay content")
    func premiumGateNoLongerRendersLockArtOverlay() throws {
        let source = try loadSource(relativePath: premiumGateSourceRelativePath)

        #expect(source.contains("Color(.systemBackground)"))
        #expect(source.contains("appState.presentPremiumPaywall()"))
        #expect(!source.contains("Image(systemName: \"lock.fill\")"))
        #expect(!source.contains("Text(\"Premium Feature\")"))
        #expect(!source.contains("Button(\"Unlock Premium\")"))
        #expect(!source.contains(".sheet(isPresented: $showPaywall)"))
    }
}
