import Testing
import Foundation
@testable import PCOS

#if canImport(PCOS)
private let paywallSourceRelativePath = "../PCOS/Core/StoreKit/PaywallView.swift"
#else
private let paywallSourceRelativePath = "../CycleBalance/Core/StoreKit/PaywallView.swift"
#endif

@Suite("Paywall Error Handling", .serialized)
struct PaywallErrorHandlingTests {
    private func loadPaywallSource() throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(paywallSourceRelativePath)
            .standardizedFileURL
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    @Test("Paywall purchase action uses explicit do/catch")
    func paywallPurchaseUsesDoCatch() throws {
        let source = try loadPaywallSource()

        #expect(!source.contains("try? await subscriptionManager.purchase(product)"))

        let purchaseCall = "try await subscriptionManager.purchase(product)"
        let range = try #require(source.range(of: purchaseCall))

        let contextStart = source.index(range.lowerBound, offsetBy: -120, limitedBy: source.startIndex) ?? source.startIndex
        let contextEnd = source.index(range.upperBound, offsetBy: 120, limitedBy: source.endIndex) ?? source.endIndex
        let context = String(source[contextStart..<contextEnd])

        #expect(context.contains("do {"))
        #expect(context.contains("} catch {"))
    }
}
