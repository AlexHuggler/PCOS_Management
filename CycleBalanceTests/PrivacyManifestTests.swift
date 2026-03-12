import Testing
import Foundation
@testable import CycleBalance

#if canImport(PCOS)
private let privacyManifestRelativePath = "../PCOS/PrivacyInfo.xcprivacy"
private let appIconSetRelativePath = "../PCOS/Assets.xcassets/AppIcon.appiconset"
#else
private let privacyManifestRelativePath = "../CycleBalance/PrivacyInfo.xcprivacy"
private let appIconSetRelativePath = "../CycleBalance/Resources/Assets.xcassets/AppIcon.appiconset"
#endif

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

@Suite("App Store Config", .serialized)
struct AppStoreConfigTests {
    @Test("Info.plist declares remote-notification background mode for CloudKit pushes")
    func infoPlistDeclaresRemoteNotificationBackgroundMode() throws {
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

        let backgroundModes = info["UIBackgroundModes"] as? [String] ?? []
        #expect(backgroundModes.contains("remote-notification"))
    }
}
