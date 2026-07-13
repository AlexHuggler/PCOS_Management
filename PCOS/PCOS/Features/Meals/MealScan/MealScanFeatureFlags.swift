import Foundation

struct MealScanFeatureFlags: Equatable, Sendable {
    var enableMealScanV2: Bool
    var enableFoodSegmentation: Bool
    var enableDepthEstimation: Bool
    var enableBarcodeNutritionLookup: Bool
    var enableMealPhotoRetention: Bool
    var enableMockMealScanData: Bool
    var enableOpenFoodFactsLookup: Bool
    var enableGeminiMealScan: Bool
    var enableGeminiMealScanDebugDirect: Bool
    var enableGeminiFallbackModel: Bool
    var enableMealScanResultCache: Bool
    var enableRepeatMealSuggestions: Bool
    var enableSimilarMealSuggestions: Bool

    static var current: MealScanFeatureFlags {
        MealScanFeatureFlags(
            enableMealScanV2: releaseLockedFalseValue(key: "mealScan.enableMealScanV2", launchArgument: "enableMealScanV2", debugDefault: true),
            enableFoodSegmentation: boolValue(key: "mealScan.enableFoodSegmentation", launchArgument: "enableFoodSegmentation", debugDefault: false, releaseDefault: false),
            enableDepthEstimation: boolValue(key: "mealScan.enableDepthEstimation", launchArgument: "enableDepthEstimation", debugDefault: false, releaseDefault: false),
            enableBarcodeNutritionLookup: boolValue(key: "mealScan.enableBarcodeNutritionLookup", launchArgument: "enableBarcodeNutritionLookup", debugDefault: false, releaseDefault: false),
            enableMealPhotoRetention: boolValue(key: "mealScan.enableMealPhotoRetention", launchArgument: "enableMealPhotoRetention", debugDefault: true, releaseDefault: false),
            enableMockMealScanData: releaseLockedFalseValue(key: "mealScan.enableMockMealScanData", launchArgument: "enableMockMealScanData", debugDefault: true),
            enableOpenFoodFactsLookup: boolValue(key: "mealScan.enableOpenFoodFactsLookup", launchArgument: "enableOpenFoodFactsLookup", debugDefault: false, releaseDefault: false),
            enableGeminiMealScan: releaseLockedFalseValue(key: "mealScan.enableGeminiMealScan", launchArgument: "enableGeminiMealScan", debugDefault: false),
            enableGeminiMealScanDebugDirect: releaseLockedFalseValue(key: "mealScan.enableGeminiMealScanDebugDirect", launchArgument: "enableGeminiMealScanDebugDirect", debugDefault: false),
            enableGeminiFallbackModel: releaseLockedFalseValue(key: "mealScan.enableGeminiFallbackModel", launchArgument: "enableGeminiFallbackModel", debugDefault: false),
            enableMealScanResultCache: boolValue(key: "mealScan.enableMealScanResultCache", launchArgument: "enableMealScanResultCache", debugDefault: true, releaseDefault: true),
            enableRepeatMealSuggestions: boolValue(key: "mealScan.enableRepeatMealSuggestions", launchArgument: "enableRepeatMealSuggestions", debugDefault: false, releaseDefault: true),
            enableSimilarMealSuggestions: boolValue(key: "mealScan.enableSimilarMealSuggestions", launchArgument: "enableSimilarMealSuggestions", debugDefault: false, releaseDefault: false)
        )
    }

    static let passOneDefaults = MealScanFeatureFlags(
        enableMealScanV2: true,
        enableFoodSegmentation: false,
        enableDepthEstimation: false,
        enableBarcodeNutritionLookup: false,
        enableMealPhotoRetention: true,
        enableMockMealScanData: true,
        enableOpenFoodFactsLookup: false,
        enableGeminiMealScan: false,
        enableGeminiMealScanDebugDirect: false,
        enableGeminiFallbackModel: false,
        enableMealScanResultCache: true,
        enableRepeatMealSuggestions: false,
        enableSimilarMealSuggestions: false
    )

    private static func boolValue(
        key: String,
        launchArgument: String,
        debugDefault: Bool,
        releaseDefault: Bool
    ) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-\(launchArgument)") || arguments.contains(launchArgument) {
            return true
        }
        let disabledArgument = "-disable" + launchArgument.prefix(1).uppercased() + String(launchArgument.dropFirst())
        if arguments.contains(disabledArgument) {
            return false
        }
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.bool(forKey: key)
        }
        #if DEBUG
        return debugDefault
        #else
        return releaseDefault
        #endif
    }

    private static func releaseLockedFalseValue(
        key: String,
        launchArgument: String,
        debugDefault: Bool
    ) -> Bool {
#if DEBUG
        boolValue(
            key: key,
            launchArgument: launchArgument,
            debugDefault: debugDefault,
            releaseDefault: false
        )
#else
        false
#endif
    }
}
