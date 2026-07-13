import Testing
import Foundation
@testable import PCOS

private let privacyManifestRelativePath = "../PCOS/PrivacyInfo.xcprivacy"
private let appIconSetRelativePath = "../PCOS/Assets.xcassets/AppIcon.appiconset"
private let accentColorSetRelativePath = "../PCOS/Assets.xcassets/AccentColor.colorset"

@Suite("Privacy Manifest", .serialized)
struct PrivacyManifestTests {
    @Test("App privacy manifest declares UserDefaults required reason")
    func appPrivacyManifestDeclaresUserDefaultsReason() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let manifestURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(privacyManifestRelativePath)
            .standardizedFileURL

        #expect(FileManager.default.fileExists(atPath: manifestURL.path))

        let plistData = try Data(contentsOf: manifestURL)
        let plistObject = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        )

        let manifest = try #require(plistObject as? [String: Any])
        let accessedTypes = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])

        let userDefaultsEntry = accessedTypes.first {
            ($0["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        let entry = try #require(userDefaultsEntry)
        let reasons = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])

        #expect(reasons.contains("CA92.1"))
    }

    @Test("App privacy manifest declares conservative app-functionality data without tracking")
    func appPrivacyManifestDeclaresCollectedDataWithoutTracking() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let manifestURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(privacyManifestRelativePath)
            .standardizedFileURL

        let plistData = try Data(contentsOf: manifestURL)
        let plistObject = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        )
        let manifest = try #require(plistObject as? [String: Any])
        let collectedTypes = try #require(
            manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
        )

        let expectedTypes: Set<String> = [
            "NSPrivacyCollectedDataTypePhotosorVideos",
            "NSPrivacyCollectedDataTypeHealth",
            "NSPrivacyCollectedDataTypeFitness",
            "NSPrivacyCollectedDataTypePurchaseHistory",
            "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypeProductInteraction",
            "NSPrivacyCollectedDataTypeOtherDataTypes",
        ]
        let actualTypes = Set(collectedTypes.compactMap {
            $0["NSPrivacyCollectedDataType"] as? String
        })

        #expect(actualTypes == expectedTypes)
        for entry in collectedTypes {
            #expect((entry["NSPrivacyCollectedDataTypeLinked"] as? Bool) == true)
            #expect((entry["NSPrivacyCollectedDataTypeTracking"] as? Bool) == false)
            let purposes = try #require(
                entry["NSPrivacyCollectedDataTypePurposes"] as? [String]
            )
            #expect(purposes == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }

        #expect((manifest["NSPrivacyTracking"] as? Bool) == false)
        let trackingDomains = try #require(manifest["NSPrivacyTrackingDomains"] as? [String])
        #expect(trackingDomains.isEmpty)
    }

    @Test("repeat meal implementation stays local and outside export serializers")
    @MainActor
    func repeatMealImplementationStaysLocalAndPrivate() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let repeatMealDirectory = projectRoot.appendingPathComponent(
            "PCOS/PCOS/Features/Meals/MealScan/RepeatMeal",
            isDirectory: true
        )
        let repeatMealFiles = try FileManager.default.contentsOfDirectory(
            at: repeatMealDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let forbiddenLocalDependencies = [
            "URLSession",
            "http://",
            "https://",
            "Firebase",
            "RevenueCat",
            "Gemini",
            "AnalyticsService",
            "logEvent(",
            "trackEvent(",
            "SettingsDataBackup",
            "SettingsDataExport",
            "generateCSV",
        ]

        #expect(!repeatMealFiles.isEmpty)
        for fileURL in repeatMealFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for forbiddenDependency in forbiddenLocalDependencies {
                #expect(
                    !source.localizedCaseInsensitiveContains(forbiddenDependency),
                    "\(fileURL.lastPathComponent) must not reference \(forbiddenDependency)"
                )
            }
        }

        for relativePath in [
            "PCOS/PCOS/App/SettingsDataBackupService.swift",
            "PCOS/PCOS/App/SettingsDataExportService.swift",
        ] {
            let source = try String(
                contentsOf: projectRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            #expect(!source.contains("MealScanRepeatCacheRecord"))
            #expect(!source.contains("featurePrintArchive"))
        }
    }

    @Test("meal scan persistence does not log reviewed meal names publicly")
    @MainActor
    func mealScanPersistenceKeepsMealNamesOutOfPublicLogs() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "PCOS/PCOS/Features/Meals/MealScan/Repositories/SwiftDataMealLogRepository.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains("result.mealName, privacy: .public"))
    }
}

@Suite("App Icon Assets", .serialized)
struct AppIconAssetTests {
    @Test("App icon manifest references concrete files for required variants")
    func appIconManifestHasRequiredVariantFiles() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let appIconSetURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(appIconSetRelativePath)
            .standardizedFileURL
        let manifestURL = appIconSetURL.appendingPathComponent("Contents.json")

        #expect(FileManager.default.fileExists(atPath: manifestURL.path))

        let manifestData = try Data(contentsOf: manifestURL)
        let manifestObject = try JSONSerialization.jsonObject(with: manifestData)
        let manifest = try #require(manifestObject as? [String: Any])
        let images = try #require(manifest["images"] as? [[String: Any]])

        #expect(!images.isEmpty)

        var variantsWithFiles: Set<String> = []
        for imageEntry in images {
            let filename = try #require(imageEntry["filename"] as? String)
            #expect(!filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            let iconFileURL = appIconSetURL.appendingPathComponent(filename)
            #expect(FileManager.default.fileExists(atPath: iconFileURL.path))

            let appearances = imageEntry["appearances"] as? [[String: Any]]
            let variant = appearances?
                .first(where: { ($0["appearance"] as? String) == "luminosity" })?["value"] as? String
            variantsWithFiles.insert(variant ?? "default")
        }

        #expect(variantsWithFiles.contains("default"))
        #expect(variantsWithFiles.contains("dark"))
        #expect(variantsWithFiles.contains("tinted"))
    }
}

@Suite("Accent Color Assets", .serialized)
struct AccentColorAssetTests {
    @Test("Accent color manifest references concrete components for required variants")
    func accentColorManifestHasRequiredVariantComponents() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let accentColorSetURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(accentColorSetRelativePath)
            .standardizedFileURL
        let manifestURL = accentColorSetURL.appendingPathComponent("Contents.json")

        #expect(FileManager.default.fileExists(atPath: manifestURL.path))

        let manifestData = try Data(contentsOf: manifestURL)
        let manifestObject = try JSONSerialization.jsonObject(with: manifestData)
        let manifest = try #require(manifestObject as? [String: Any])
        let colors = try #require(manifest["colors"] as? [[String: Any]])

        #expect(!colors.isEmpty)

        var variantsWithComponents: Set<String> = []
        for colorEntry in colors {
            let color = try #require(colorEntry["color"] as? [String: Any])
            let components = try #require(color["components"] as? [String: Any])

            for component in ["red", "green", "blue", "alpha"] {
                let rawValue = try #require(components[component] as? String)
                #expect(!rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            let appearances = colorEntry["appearances"] as? [[String: Any]]
            let variant = appearances?
                .first(where: { ($0["appearance"] as? String) == "luminosity" })?["value"] as? String
            variantsWithComponents.insert(variant ?? "default")
        }

        #expect(variantsWithComponents.contains("default"))
        #expect(variantsWithComponents.contains("dark"))
    }
}

@Suite("App Appearance Policy", .serialized)
struct AppAppearancePolicyTests {
    @Test("App root keeps light mode by default while allowing Lunar Calm dark mode")
    @MainActor
    func appRootKeepsLightModeByDefaultWhileAllowingLunarCalmDarkMode() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let appFileURL = projectRoot
            .appendingPathComponent("PCOS/PCOS/App/CycleBalanceApp.swift")
        let source = try String(contentsOf: appFileURL)

        #expect(source.contains(".preferredColorScheme(appearancePreferences.preferredColorScheme)"))
        #expect(source.contains("appearance.enableExperimentalThemes"))
        #expect(!source.contains("#if DEBUG && targetEnvironment(simulator)"))
    }

    @Test("Saved feedback overlay does not force dark color scheme")
    @MainActor
    func savedFeedbackOverlayDoesNotForceDarkColorScheme() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let overlayFileURL = projectRoot
            .appendingPathComponent("PCOS/PCOS/SharedUI/Components/SavedFeedbackOverlay.swift")
        let source = try String(contentsOf: overlayFileURL)

        #expect(!source.contains(".colorScheme, .dark"))
    }
}

@Suite("App Store Config", .serialized)
struct AppStoreConfigTests {
    @Test("Release candidate is 1.0.5 build 18 with fail-closed scanner settings")
    @MainActor
    func releaseCandidateUsesFailClosedMealScannerSettings() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let projectSource = try String(
            contentsOf: projectRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )

        #expect(projectSource.contains("MARKETING_VERSION: \"1.0.5\""))
        #expect(projectSource.contains("CURRENT_PROJECT_VERSION: \"18\""))
        #expect(projectSource.contains("USDA_FDC_API_KEY: \"\""))

        for setting in [
            "MEAL_SCAN_RELEASE_UI_ENABLED",
            "MEAL_SCAN_RELEASE_GEMINI_ENABLED",
            "MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED",
            "MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED",
            "MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED",
            "MEAL_SCAN_RELEASE_SIMILARITY_ENABLED",
        ] {
            #expect(projectSource.contains("\(setting): \"NO\""), "\(setting) must be NO")
        }

        let flagsSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "PCOS/PCOS/Features/Meals/MealScan/MealScanFeatureFlags.swift"
            ),
            encoding: .utf8
        )
        for flag in [
            "enableMealScanV2",
            "enableGeminiMealScan",
            "enableMockMealScanData",
            "enableGeminiMealScanDebugDirect",
            "enableGeminiFallbackModel",
            "enableSimilarMealSuggestions",
        ] {
            let escapedFlag = NSRegularExpression.escapedPattern(for: flag)
            let pattern = "\\b\(escapedFlag): (?:boolValue\\([^\\n]*releaseDefault: false\\)|releaseLockedFalseValue\\()"
            let expression = try NSRegularExpression(pattern: pattern)
            let range = NSRange(flagsSource.startIndex..., in: flagsSource)
            #expect(
                expression.firstMatch(in: flagsSource, range: range) != nil,
                "\(flag) must remain false in non-Debug builds"
            )
        }

        if flagsSource.contains("releaseLockedFalseValue(") {
            let lockedHelperPattern = "private static func releaseLockedFalseValue[\\s\\S]*?#else\\s+false\\s+#endif"
            let lockedHelper = try NSRegularExpression(pattern: lockedHelperPattern)
            let range = NSRange(flagsSource.startIndex..., in: flagsSource)
            #expect(
                lockedHelper.firstMatch(in: flagsSource, range: range) != nil,
                "releaseLockedFalseValue must return false outside Debug"
            )
        }
    }

    @Test("Meal scan review packet documents hardened release limits")
    @MainActor
    func mealScanReviewPacketDocumentsHardenedReleaseLimits() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let packet = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "docs/app_store_meal_scan_review_packet_2026-07-11.md"
            ),
            encoding: .utf8
        )

        for requiredText in [
            "StoreKit 2 transaction JWS",
            "HMAC-derived purchase principal",
            "10 fresh estimates per rolling 24 hours",
            "immutable server maximum of 15",
            "warning at 2 remaining",
            "5 fresh estimates per rolling 24 hours and 25 lifetime",
            "$15 alert, $20 degraded, and $25 disabled",
            "24-hour structured-result cache",
            "up to 55 days",
            "manual meal entry and barcode lookup",
        ] {
            #expect(packet.contains(requiredText), "Missing review contract: \(requiredText)")
        }

        #expect(!packet.contains("anonymous RevenueCat App User ID"))
        #expect(!packet.contains("Daily/trial quota"))
    }

    @Test("Localized 1.0.5 metadata packet covers every storefront locale")
    @MainActor
    func localizedMetadataPacketCoversEveryStorefrontLocale() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let metadataURL = projectRoot.appendingPathComponent(
            "docs/app_store_1.0.5_localized_metadata.md"
        )
        #expect(FileManager.default.fileExists(atPath: metadataURL.path))

        let metadata = try String(contentsOf: metadataURL, encoding: .utf8)
        for locale in ["en-US", "de-DE", "fr-FR", "it", "ja", "ko", "nl-NL"] {
            #expect(metadata.contains("## \(locale)"), "Missing \(locale) metadata")
        }
        #expect(metadata.components(separatedBy: "### Release Notes").count - 1 == 7)
        #expect(metadata.components(separatedBy: "### Replacement Description Paragraph").count - 1 == 7)
        #expect(!metadata.localizedCaseInsensitiveContains("no accounts, no servers, no exceptions"))
    }

    @Test("Info.plist omits CloudKit push background mode")
    func infoPlistOmitsRemoteNotificationBackgroundMode() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let infoPlistURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("../PCOS/Info.plist")
            .standardizedFileURL

        #expect(FileManager.default.fileExists(atPath: infoPlistURL.path))

        let plistData = try Data(contentsOf: infoPlistURL)
        let plistObject = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        )
        let info = try #require(plistObject as? [String: Any])

        let cameraUsageDescription = info["NSCameraUsageDescription"] as? String ?? ""
        #expect(cameraUsageDescription.localizedCaseInsensitiveContains("meal photo"))
        #expect(cameraUsageDescription.localizedCaseInsensitiveContains("analysis"))

        let photoLibraryUsageDescription = info["NSPhotoLibraryUsageDescription"] as? String ?? ""
        #expect(photoLibraryUsageDescription.localizedCaseInsensitiveContains("meal photo"))
        #expect(photoLibraryUsageDescription.localizedCaseInsensitiveContains("analysis"))

        let backgroundModes = info["UIBackgroundModes"] as? [String] ?? []
        #expect(!backgroundModes.contains("remote-notification"))

        let healthShareUsageDescription = info["NSHealthShareUsageDescription"] as? String ?? ""
        #expect(!healthShareUsageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(
            healthShareUsageDescription.localizedCaseInsensitiveContains("read")
                || healthShareUsageDescription.localizedCaseInsensitiveContains("import")
        )

        let healthUpdateUsageDescription = info["NSHealthUpdateUsageDescription"] as? String ?? ""
        #expect(!healthUpdateUsageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(
            healthUpdateUsageDescription.localizedCaseInsensitiveContains("does not write")
                || healthUpdateUsageDescription.localizedCaseInsensitiveContains("not write")
        )
    }
}
