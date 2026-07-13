import Foundation
import Testing
@testable import PCOS

@Suite("Meal Scan Release Contract", .serialized)
@MainActor
struct MealScanReleaseContractTests {
    private func source(at relativePath: String) throws -> String {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        return try String(
            contentsOf: projectRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("Tracking Hub scanner fallbacks wait for dismissal and launch the requested meal flow")
    func trackingHubScannerFallbacksRouteThroughMealLog() throws {
        let contentSource = try source(at: "PCOS/PCOS/App/ContentView.swift")
        let mealLogSource = try source(at: "PCOS/PCOS/Features/Meals/Views/MealLogView.swift")

        #expect(contentSource.contains("@State private var pendingMealLogDestinationAfterScan: MealLogInitialDestination?"))
        #expect(contentSource.contains("@State private var activeMealLogDestination: MealLogInitialDestination = .form"))
        #expect(contentSource.contains("onDismiss: presentPendingMealLogDestinationAfterScan"))
        #expect(contentSource.contains("onDismiss: resetMealLogPresentationState"))
        #expect(contentSource.contains("routeMealScanFallback(to: .barcode)"))
        #expect(contentSource.contains("routeMealScanFallback(to: .form)"))
        #expect(contentSource.contains("initialDestination: activeMealLogDestination"))
        #expect(contentSource.contains("pendingMealLogDestinationAfterScan = nil"))
        #expect(contentSource.contains("onDismiss: (() -> Void)? = nil"))
        #expect(!contentSource.contains("MealScanFlowView(mealType: .lunch)"))

        #expect(mealLogSource.contains("enum MealLogInitialDestination: Sendable"))
        #expect(mealLogSource.contains("@State private var pendingInitialDestination: MealLogInitialDestination?"))
        #expect(mealLogSource.contains("_pendingInitialDestination = State(initialValue: initialDestination)"))
        #expect(mealLogSource.contains("consumeInitialDestinationIfNeeded()"))
        #expect(mealLogSource.contains("pendingInitialDestination = nil"))
        #expect(mealLogSource.contains("case .barcode:"))
        #expect(mealLogSource.contains("showingBarcodeImport = true"))
    }

    @Test("Release hard-locks similarity while Debug keeps the override seam")
    func releaseSimilarityGateIsHardLocked() throws {
        let flagsSource = try source(
            at: "PCOS/PCOS/Features/Meals/MealScan/MealScanFeatureFlags.swift"
        )

        #expect(flagsSource.contains(
            "enableSimilarMealSuggestions: releaseLockedFalseValue(key: \"mealScan.enableSimilarMealSuggestions\", launchArgument: \"enableSimilarMealSuggestions\", debugDefault: false)"
        ))
        #expect(!flagsSource.contains("enableSimilarMealSuggestions: boolValue("))
        #expect(flagsSource.contains("#if DEBUG\n        boolValue("))
        #expect(flagsSource.contains("#else\n        false\n#endif"))
    }

    @Test("Release reads only UI and Gemini gates from signed build-time booleans")
    func releaseBuildGatesAreSignedAndFailClosed() throws {
        let flagsSource = try source(
            at: "PCOS/PCOS/Features/Meals/MealScan/MealScanFeatureFlags.swift"
        )
        let projectSource = try source(at: "project.yml")
        let releasePlistSource = try source(at: "PCOS/PCOS/Info.Release.plist")
        let setupSource = try source(at: "docs/meal_scan_flash_lite_production_setup.md")

        #expect(projectSource.contains("MEAL_SCAN_RELEASE_UI_ENABLED: \"NO\""))
        #expect(projectSource.contains("MEAL_SCAN_RELEASE_GEMINI_ENABLED: \"NO\""))
        #expect(projectSource.contains("INFOPLIST_FILE: PCOS/PCOS/Info.Release.plist"))
        #expect(projectSource.contains("MEAL_SCAN_RELEASE_UI_ENABLED_$(MEAL_SCAN_RELEASE_UI_ENABLED)=1"))
        #expect(projectSource.contains("MEAL_SCAN_RELEASE_GEMINI_ENABLED_$(MEAL_SCAN_RELEASE_GEMINI_ENABLED)=1"))

        #expect(releasePlistSource.contains("<key>MealScanReleaseUIEnabled</key>"))
        #expect(releasePlistSource.contains("#if MEAL_SCAN_RELEASE_UI_ENABLED_YES"))
        #expect(releasePlistSource.contains("<key>MealScanReleaseGeminiEnabled</key>"))
        #expect(releasePlistSource.contains("#if MEAL_SCAN_RELEASE_GEMINI_ENABLED_YES"))
        #expect(releasePlistSource.contains("<true/>"))
        #expect(releasePlistSource.contains("<false/>"))

        #expect(flagsSource.contains(
            "enableMealScanV2: releaseBuildConfiguredValue(infoKey: releaseUIInfoKey"
        ))
        #expect(flagsSource.contains(
            "enableGeminiMealScan: releaseBuildConfiguredValue(infoKey: releaseGeminiInfoKey"
        ))

        for lockedFlag in [
            "enableMockMealScanData",
            "enableGeminiMealScanDebugDirect",
            "enableGeminiFallbackModel",
            "enableSimilarMealSuggestions",
        ] {
            #expect(
                flagsSource.contains("\(lockedFlag): releaseLockedFalseValue("),
                "\(lockedFlag) must remain hard-false in Release"
            )
        }

        #expect(MealScanFeatureFlags.releaseBuildBoolean(
            infoDictionary: ["Gate": true],
            key: "Gate"
        ))
        #expect(!MealScanFeatureFlags.releaseBuildBoolean(
            infoDictionary: ["Gate": false],
            key: "Gate"
        ))
        #expect(!MealScanFeatureFlags.releaseBuildBoolean(
            infoDictionary: ["Gate": "YES"],
            key: "Gate"
        ))
        #expect(!MealScanFeatureFlags.releaseBuildBoolean(infoDictionary: nil, key: "Gate"))

        #expect(setupSource.contains(
            "Change only `MEAL_SCAN_RELEASE_UI_ENABLED` and `MEAL_SCAN_RELEASE_GEMINI_ENABLED` from `NO` to `YES`"
        ))
        #expect(setupSource.contains(
            "Mock data, debug-direct transport, fallback-model routing, and visual similarity remain hard-disabled in Release"
        ))
    }
}
