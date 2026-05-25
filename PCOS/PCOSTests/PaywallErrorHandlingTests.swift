import Testing
import Foundation
@testable import PCOS

private let paywallSourceRelativePath = "../PCOS/Core/StoreKit/PaywallView.swift"
private let premiumGateSourceRelativePath = "../PCOS/Core/StoreKit/PremiumGate.swift"
private let insightsSourceRelativePath = "../PCOS/Features/Insights/Views/InsightsView.swift"

@Suite("Paywall Error Handling", .serialized)
struct PaywallErrorHandlingTests {
    private func loadSource(relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func loadPaywallSource() throws -> String {
        try loadSource(relativePath: paywallSourceRelativePath)
    }

    @Test("Paywall loading and purchase flows surface explicit error handling across billing backends")
    func paywallLoadingAndCallbacksUseExplicitErrorHandling() throws {
        let source = try loadPaywallSource()

        #expect(source.contains("await loadPaywallIfNeeded()"))
        #expect(source.contains("billingProducts = try await subscriptionManager.loadProducts()"))
        #expect(source.contains("let outcome = try await subscriptionManager.purchase(productID: product.id)"))
        #expect(source.contains("try await subscriptionManager.restorePurchases()"))
        #expect(source.contains("loadErrorMessage = Self.userFacingMessage("))
        #expect(source.contains("alertErrorMessage = Self.userFacingMessage("))
        #expect(source.contains("case .pending:"))
        #expect(source.contains("case .cancelled:"))
    }

    @Test("Premium gate presents visible unlock affordance before opening paywall")
    func premiumGateShowsVisibleAffordance() throws {
        let source = try loadSource(relativePath: premiumGateSourceRelativePath)

        #expect(source.contains("premium_gate.unlock"))
        #expect(source.contains("sparkles"))
        #expect(!source.contains("lock.fill"))
        #expect(source.contains("Unlock Premium"))
    }

    @Test("Paywall feature table matches enforced premium gates")
    func paywallFeatureTableMatchesEnforcedPremiumGates() throws {
        let source = try loadPaywallSource()

        #expect(source.contains("advanced_insights"))
        #expect(source.contains("unlimited_pdf_reports"))
        #expect(source.contains("meal_glucose_logging"))
        #expect(source.contains("supplement_tracking"))
        #expect(source.contains("photo_journal"))
        #expect(source.contains("full_cycle_history"))
        #expect(source.contains("Apple Health sync"))
        #expect(source.contains("freeIncluded: true"))
        #expect(!source.contains("priority_support"))
        #expect(!source.contains("HealthKit sync\", defaultValue: \"HealthKit sync\", language: language),\n                freeIncluded: false"))
    }

    @Test("Insights errors include an explicit retry CTA")
    func insightsErrorsExposeRetryCTA() throws {
        let source = try loadSource(relativePath: insightsSourceRelativePath)

        #expect(source.contains("insights.error_retry"))
        #expect(source.contains("retryInsights"))
        #expect(source.contains("Try Again"))
    }
}
