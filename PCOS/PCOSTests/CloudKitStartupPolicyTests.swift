import Testing
import CloudKit
import Foundation
@testable import PCOS

@Suite("CloudKit Startup Policy")
struct CloudKitStartupPolicyTests {
    @Test("Available account does not fallback")
    func availableStatusDoesNotFallback() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: .available) == nil)
    }

    @Test("No account falls back")
    func noAccountFallsBack() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: .noAccount) == .noAccount)
    }

    @Test("Restricted account falls back")
    func restrictedFallsBack() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: .restricted) == .restricted)
    }

    @Test("Could-not-determine falls back")
    func couldNotDetermineFallsBack() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: .couldNotDetermine) == .couldNotDetermine)
    }

    @Test("Temporarily unavailable maps to fallback")
    func temporarilyUnavailableFallsBack() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: .temporarilyUnavailable) == .couldNotDetermine)
    }

    @Test("Timeout maps to fallback")
    func timeoutFallsBack() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: nil) == .timeout)
    }

    @Test("Simulator policy always returns simulator fallback reason")
    func simulatorPolicyAlwaysFallsBack() {
        let reason = CloudKitStartupPolicy.simulatorFallbackReason()
        #expect(reason == .simulator)
    }

    @Test("Debug device defaults to local fallback unless CloudKit is explicitly enabled")
    func debugDeviceDefaultsToLocalFallback() {
        let shouldUseLocalStore = CloudKitStartupPolicy.shouldUseLocalStoreInDebug(
            processArguments: [],
            environment: [:],
            isSimulator: false
        )
        #expect(shouldUseLocalStore == true)
        #expect(CloudKitStartupPolicy.debugFallbackReason(isSimulator: false) == .debugLocalOnly)
    }

    @Test("Debug CloudKit opt-in argument disables local-only fallback")
    func debugCloudKitOptInArgumentDisablesLocalFallback() {
        let shouldUseLocalStore = CloudKitStartupPolicy.shouldUseLocalStoreInDebug(
            processArguments: [CloudKitStartupPolicy.debugCloudKitOptInArgument],
            environment: [:],
            isSimulator: false
        )
        #expect(shouldUseLocalStore == false)
    }

    @Test("Debug CloudKit opt-in environment variable disables local-only fallback")
    func debugCloudKitOptInEnvironmentDisablesLocalFallback() {
        let shouldUseLocalStore = CloudKitStartupPolicy.shouldUseLocalStoreInDebug(
            processArguments: [],
            environment: [CloudKitStartupPolicy.debugCloudKitOptInEnvironmentKey: "true"],
            isSimulator: false
        )
        #expect(shouldUseLocalStore == false)
    }

    @Test("Project config splits debug and release entitlements")
    @MainActor
    func projectConfigSplitsDebugAndReleaseEntitlements() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let projectYAML = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"))

        #expect(projectYAML.contains("CODE_SIGN_ENTITLEMENTS: PCOS/PCOS.debug.entitlements"))
        #expect(projectYAML.contains("CODE_SIGN_ENTITLEMENTS: PCOS/PCOS.entitlements"))
    }

    @Test("Debug entitlements enable HealthKit but exclude CloudKit capabilities")
    @MainActor
    func debugEntitlementsEnableHealthKitAndExcludeCloudKit() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let debugEntitlementsURL = projectRoot.appendingPathComponent("PCOS/PCOS.debug.entitlements")
        let data = try Data(contentsOf: debugEntitlementsURL)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let entitlements = try #require(object as? [String: Any])

        #expect((entitlements["com.apple.developer.healthkit"] as? Bool) == true)
        #expect(entitlements["com.apple.developer.icloud-services"] == nil)
        #expect(entitlements["com.apple.developer.icloud-container-identifiers"] == nil)
    }

    @Test("Release config uses optional local secrets include")
    @MainActor
    func releaseConfigUsesOptionalSecretsInclude() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let releaseConfigURL = projectRoot.appendingPathComponent("Config/Release.xcconfig")
        let releaseConfig = try String(contentsOf: releaseConfigURL)

        #expect(releaseConfig.contains("#include? \"LocalSecrets.xcconfig\""))
        #expect(!releaseConfig.contains("#include \"LocalSecrets.xcconfig\""))
    }

    @Test("Release entitlements exclude CloudKit")
    @MainActor
    func releaseEntitlementsExcludeCloudKit() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let releaseEntitlementsURL = projectRoot.appendingPathComponent("PCOS/PCOS.entitlements")
        let data = try Data(contentsOf: releaseEntitlementsURL)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let entitlements = try #require(object as? [String: Any])

        #expect((entitlements["com.apple.developer.healthkit"] as? Bool) == true)
        #expect(entitlements["com.apple.developer.icloud-services"] == nil)
        #expect(entitlements["com.apple.developer.icloud-container-identifiers"] == nil)
    }

    @Test("Release Info.plist declares read-only HealthKit access")
    @MainActor
    func releaseInfoPlistIsReadOnlyForHealthKit() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let infoPlistURL = projectRoot.appendingPathComponent("PCOS/PCOS/Info.plist")
        let plistData = try Data(contentsOf: infoPlistURL)
        let plistObject = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        let info = try #require(plistObject as? [String: Any])

        let healthShareDescription = try #require(info["NSHealthShareUsageDescription"] as? String)
        let healthUpdateDescription = try #require(info["NSHealthUpdateUsageDescription"] as? String)
        #expect(healthShareDescription.contains("reads Apple Health data you allow"))
        #expect(healthShareDescription.contains("cycle"))
        #expect(healthShareDescription.contains("symptoms"))
        #expect(healthUpdateDescription.contains("does not write to Apple Health"))
        #expect(info["UIBackgroundModes"] == nil)
    }
}
