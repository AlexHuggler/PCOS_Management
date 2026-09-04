import Testing
import Foundation
@testable import PCOS

@Suite("Paywall compliance and pricing truth")
@MainActor
struct PaywallComplianceTests {
    private var yearlyUSD: BillingProduct {
        BillingProduct(
            id: SubscriptionManager.yearlyProductID,
            displayName: "CycleBalance Premium Yearly",
            displayPrice: "$39.99",
            price: Decimal(string: "39.99")!,
            subscriptionPeriod: BillingPeriod(unit: .year, value: 1),
            currencyCode: "USD"
        )
    }

    @Test("Yearly plan exposes a per-month equivalent so annual value is visible")
    func yearlyPerMonthEquivalent() throws {
        let text = try #require(yearlyUSD.monthlyEquivalentPriceText(language: .en))
        #expect(text.contains("3.33"), "was \(text)")
        #expect(text.contains("month"))

        let monthly = BillingProduct(
            id: SubscriptionManager.monthlyProductID,
            displayName: "CycleBalance Premium Monthly",
            displayPrice: "$6.99",
            price: Decimal(string: "6.99")!,
            subscriptionPeriod: BillingPeriod(unit: .month, value: 1),
            currencyCode: "USD"
        )
        #expect(monthly.monthlyEquivalentPriceText(language: .en) == nil)

        var noCurrency = yearlyUSD
        noCurrency.currencyCode = nil
        #expect(noCurrency.monthlyEquivalentPriceText(language: .en) == nil)
    }

    @Test("Binary states auto-renewal terms and links Apple's standard EULA")
    func renewalTermsAndEULA() throws {
        let disclosure = SubscriptionDisclosure.autoRenewText(language: .en)
        #expect(disclosure.lowercased().contains("renew"))
        #expect(disclosure.contains("24 hours"))
        #expect(!SubscriptionDisclosure.termsOfUseLabel(language: .en).isEmpty)
        let eula = try #require(AppLinks.appleStandardEULA)
        #expect(eula.host == "www.apple.com")
        #expect(eula.path.contains("stdeula"))
    }

    @Test("Paywall and Settings wire the disclosure, EULA link, per-month price and subscription management")
    func surfacesAreWired() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        func source(_ path: String) throws -> String {
            try String(contentsOf: projectRoot.appendingPathComponent(path), encoding: .utf8)
        }
        let paywall = try source("PCOS/PCOS/Core/StoreKit/PaywallView.swift")
        #expect(paywall.contains("SubscriptionDisclosure.autoRenewText("))
        #expect(paywall.contains("AppLinks.appleStandardEULA"))
        #expect(paywall.contains("monthlyEquivalentPriceText("))

        let settings = try source("PCOS/PCOS/App/SettingsView.swift")
        #expect(settings.contains("manageSubscriptionsSheet"))
        #expect(!settings.contains(".onTapGesture {\n                            appState.showPremiumPaywall = true"))

        for path in ["PCOS/PCOS/Core/StoreKit/StoreKitBillingClient.swift", "PCOS/PCOS/Core/StoreKit/RevenueCatBillingClient.swift"] {
            #expect(try source(path).contains("currencyCode:"), "\(path)")
        }
    }

    @Test("Local StoreKit configuration matches the live App Store tier")
    func storeKitConfigurationMatchesLiveTier() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let data = try Data(contentsOf: projectRoot.appendingPathComponent("PCOS/PCOS/StoreKit/PCOS.storekit"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var prices: [String: String] = [:]
        func collect(_ object: Any) {
            if let dict = object as? [String: Any] {
                if let name = dict["referenceName"] as? String, let price = dict["displayPrice"] as? String {
                    prices[name] = price
                }
                dict.values.forEach(collect)
            } else if let array = object as? [Any] {
                array.forEach(collect)
            }
        }
        collect(json)
        #expect(prices["CycleBalance Premium Monthly"] == "6.99", "monthly was \(prices["CycleBalance Premium Monthly"] ?? "missing")")
        #expect(prices["CycleBalance Premium Yearly"] == "39.99", "yearly was \(prices["CycleBalance Premium Yearly"] ?? "missing")")

        let checklist = try String(contentsOf: projectRoot.appendingPathComponent("AppStoreReadinessChecklist.md"), encoding: .utf8)
        #expect(checklist.contains("$6.99") && checklist.contains("$39.99"))
    }
}
