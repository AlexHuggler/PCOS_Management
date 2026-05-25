import Testing
import Foundation
@testable import PCOS

private let contentViewSourceRelativePath = "../PCOS/App/ContentView.swift"
private let paywallSourceRelativePath = "../PCOS/Core/StoreKit/PaywallView.swift"
private let premiumGateSourceRelativePath = "../PCOS/Core/StoreKit/PremiumGate.swift"
private let calendarSourceRelativePath = "../PCOS/Features/Cycle/Views/CalendarMonthView.swift"
private let supplementHistorySourceRelativePath = "../PCOS/Features/Supplements/Views/SupplementHistoryView.swift"
private let bloodSugarHistorySourceRelativePath = "../PCOS/Features/BloodSugar/Views/BloodSugarHistoryView.swift"
private let settingsSourceRelativePath = "../PCOS/App/SettingsView.swift"
private let settingsDebugToolsSourceRelativePath = "../PCOS/App/SettingsDebugToolsState.swift"

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
