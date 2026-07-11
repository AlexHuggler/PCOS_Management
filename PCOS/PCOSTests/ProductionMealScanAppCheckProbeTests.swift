import Foundation
import Testing
import UIKit
@testable import PCOS

private let shouldRunProductionMealScanIntegration =
    ProcessInfo.processInfo.environment["RUN_PRODUCTION_MEAL_SCAN_INTEGRATION"] == "1"

@Suite("Production Meal Scan App Check Probe", .serialized)
@MainActor
struct ProductionMealScanAppCheckProbeTests {
    private static let probeAppUserID = "cyclebalance-appcheck-probe-no-entitlement"

    @Test(
        "physical App Check probe rejects an account without entitlement",
        .enabled(
            if: shouldRunProductionMealScanIntegration,
            "Set RUN_PRODUCTION_MEAL_SCAN_INTEGRATION=1 only from the reviewed physical-device probe scheme."
        )
    )
    func physicalAppCheckProbeRejectsNoEntitlementUser() async throws {
        guard let configuration = GeminiRemoteMealScanConfiguration.from(
            bundle: Bundle(identifier: "alex.PCOS") ?? .main,
            revenueCatAppUserID: Self.probeAppUserID
        ), let endpointURL = configuration.proxyEndpointURL else {
            Issue.record("The Release app must contain a complete production meal-scan proxy URL.")
            return
        }

        let normalized = try MealScanImageNormalizer().normalizeJPEGData(from: Self.probeImage)
        #expect(normalized.jpegData.count > 2)
        #expect(normalized.jpegData.starts(with: Data([0xFF, 0xD8])))

        let hashPrefix = String(normalized.sourceImageHash.prefix(12))
        print("Production meal-scan App Check probe image hash prefix: \(hashPrefix)")

        // Do not log or otherwise expose the limited-use App Check token.
        let limitedUseToken = try await FirebaseMealScanAppCheckTokenProvider().limitedUseToken()
        let request = RemoteMealScanRequest(
            normalizedImageJPEGData: normalized.jpegData,
            sourceImageHash: normalized.sourceImageHash,
            mealType: .lunch,
            localeIdentifier: "en_US",
            modelID: GeminiRemoteMealScanConfiguration.defaultModelID,
            schemaVersion: GeminiRemoteMealScanConfiguration.schemaVersion,
            promptVersion: GeminiRemoteMealScanConfiguration.promptVersion,
            revenueCatAppUserID: Self.probeAppUserID,
            firebaseAppCheckToken: limitedUseToken
        )

        do {
            _ = try await GeminiMealScanProxyClient(endpointURL: endpointURL).estimateMeal(request: request)
            Issue.record("The no-entitlement probe must never return 200 or reach quota/model processing.")
        } catch let error as GeminiMealScanProxyError {
            #expect(error.statusCode == 403)
            #expect(error.error == "premium_entitlement_required")
            #expect(error.reason == "entitlement_inactive")
        } catch {
            Issue.record("Expected entitlement rejection, received \(String(describing: error))")
        }
    }

    private static var probeImage: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 48, height: 32)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        }
    }
}
