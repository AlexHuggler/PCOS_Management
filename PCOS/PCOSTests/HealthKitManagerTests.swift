import Testing
import Foundation
import HealthKit
import SwiftData
@testable import PCOS

private let healthKitEntitlementsRelativePath = "../../PCOS/PCOS.entitlements"
private let debugEntitlementsRelativePath = "../../PCOS/PCOS.debug.entitlements"

private let healthKitManagerSourceCandidates = [
    "../PCOS/Core/HealthKit/HealthKitManager.swift",
]

private let healthKitSettingsSourceCandidates = [
    "../PCOS/Core/HealthKit/HealthKitSettingsView.swift",
]

private let permissionsStepSourceCandidates = [
    "../PCOS/Features/Onboarding/Views/PermissionsStepView.swift",
]

private let onboardingHealthContextRevealSourceCandidates = [
    "../PCOS/Features/Onboarding/Views/OnboardingHealthContextRevealView.swift",
]

private let settingsViewSourceCandidates = [
    "../PCOS/App/SettingsView.swift",
]

private let healthKitLastSyncKey = "healthkit.lastSyncDate"
private let projectFileRelativePath = "../../PCOS.xcodeproj/project.pbxproj"

private func resolveHealthKitManagerSourceURL(from testFileURL: URL) -> URL? {
    for candidate in healthKitManagerSourceCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    return nil
}

private func resolveHealthKitSettingsSourceURL(from testFileURL: URL) -> URL? {
    for candidate in healthKitSettingsSourceCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    return nil
}

private func resolvePermissionsStepSourceURL(from testFileURL: URL) -> URL? {
    for candidate in permissionsStepSourceCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    return nil
}

private func resolveOnboardingHealthContextRevealSourceURL(from testFileURL: URL) -> URL? {
    for candidate in onboardingHealthContextRevealSourceCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    return nil
}

private func resolveSettingsViewSourceURL(from testFileURL: URL) -> URL? {
    for candidate in settingsViewSourceCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    return nil
}

private func resolveProjectFileURL(from testFileURL: URL) -> URL {
    testFileURL
        .deletingLastPathComponent()
        .appendingPathComponent(projectFileRelativePath)
        .standardizedFileURL
}

private func countOccurrences(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

@MainActor
private func withIsolatedLastSyncDefaults(
    _ operation: () async throws -> Void
) async rethrows {
    let previous = UserDefaults.standard.object(forKey: healthKitLastSyncKey)
    UserDefaults.standard.removeObject(forKey: healthKitLastSyncKey)

    defer {
        if let previous {
            UserDefaults.standard.set(previous, forKey: healthKitLastSyncKey)
        } else {
            UserDefaults.standard.removeObject(forKey: healthKitLastSyncKey)
        }
    }

    try await operation()
}

private enum MockAuthorizationError: LocalizedError {
    case deniedBySystem

    var errorDescription: String? {
        "HealthKit authorization failed in test"
    }
}

private enum MockSyncError: LocalizedError {
    case forcedFailure

    var errorDescription: String? {
        "HealthKit sync worker failed in test"
    }
}

private actor AuthorizationStatusProbe {
    private var statuses: [HKAuthorizationRequestStatus]

    init(_ statuses: [HKAuthorizationRequestStatus]) {
        self.statuses = statuses
    }

    func nextStatus() -> HKAuthorizationRequestStatus {
        if statuses.isEmpty {
            return .shouldRequest
        }

        if statuses.count == 1 {
            return statuses[0]
        }

        return statuses.removeFirst()
    }
}

private actor SyncProbe {
    private var callCount = 0

    func markCall() {
        callCount += 1
    }

    func currentCount() -> Int {
        callCount
    }
}

@Suite("HealthKit Manager", .serialized)
@MainActor
struct HealthKitManagerTests {
    @Test("Debug and Release enable HealthKit entitlement")
    func debugAndReleaseEnableHealthKitEntitlement() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let entitlementsURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(healthKitEntitlementsRelativePath)
            .standardizedFileURL
        let debugEntitlementsURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(debugEntitlementsRelativePath)
            .standardizedFileURL
        let projectFileURL = resolveProjectFileURL(from: testFileURL)

        let plistData = try Data(contentsOf: entitlementsURL)
        let plistObject = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        )
        let entitlements = try #require(plistObject as? [String: Any])
        let healthKitEnabled = entitlements["com.apple.developer.healthkit"] as? Bool
        #expect(healthKitEnabled == true)

        let debugPlistData = try Data(contentsOf: debugEntitlementsURL)
        let debugPlistObject = try PropertyListSerialization.propertyList(
            from: debugPlistData,
            options: [],
            format: nil
        )
        let debugEntitlements = try #require(debugPlistObject as? [String: Any])
        #expect(debugEntitlements["com.apple.developer.healthkit"] as? Bool == true)

        let projectFileSource = try String(contentsOf: projectFileURL)
        #expect(projectFileSource.contains("CODE_SIGN_ENTITLEMENTS = PCOS/PCOS.debug.entitlements;"))
        #expect(projectFileSource.contains("CODE_SIGN_ENTITLEMENTS = PCOS/PCOS.entitlements;"))
    }

    @Test("Info.plist includes read-only HealthKit usage copy")
    func infoPlistIncludesHealthKitUsageCopy() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let infoPlistURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("../PCOS/Info.plist")
            .standardizedFileURL

        let plistData = try Data(contentsOf: infoPlistURL)
        let plistObject = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        )
        let info = try #require(plistObject as? [String: Any])

        let readUsage = try #require(info["NSHealthShareUsageDescription"] as? String)
        let writeUsage = try #require(info["NSHealthUpdateUsageDescription"] as? String)

        #expect(readUsage.contains("reads Apple Health data you allow"))
        #expect(readUsage.contains("cycle"))
        #expect(readUsage.contains("symptoms"))
        #expect(writeUsage.contains("does not write to Apple Health"))
    }

    @Test("HealthKit read types include resting heart rate")
    func healthKitReadTypesIncludeRestingHeartRate() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let sourceURL = resolveHealthKitManagerSourceURL(from: testFileURL) else {
            Issue.record("Unable to locate HealthKitManager.swift in active PCOS paths.")
            return
        }

        let root = try TestHelpers.projectRoot(from: #filePath)
        let registryURL = root.appendingPathComponent("PCOS/PCOS/Core/HealthKit/HealthKitDataTypeDescriptor.swift")
        let source = try String(contentsOf: sourceURL) + "\n" + String(contentsOf: registryURL)
        #expect(source.contains(".restingHeartRate"))
    }

    @Test("HealthKit read types include read-only nutrition identifiers")
    func healthKitReadTypesIncludeNutritionIdentifiers() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let sourceURL = resolveHealthKitManagerSourceURL(from: testFileURL) else {
            Issue.record("Unable to locate HealthKitManager.swift in active PCOS paths.")
            return
        }

        let root = try TestHelpers.projectRoot(from: #filePath)
        let registryURL = root.appendingPathComponent("PCOS/PCOS/Core/HealthKit/HealthKitDataTypeDescriptor.swift")
        let source = try String(contentsOf: sourceURL) + "\n" + String(contentsOf: registryURL)
        #expect(source.contains(".dietaryEnergyConsumed"))
        #expect(source.contains(".dietaryCarbohydrates"))
        #expect(source.contains(".dietaryProtein"))
        #expect(source.contains(".dietaryFatTotal"))
        #expect(source.contains(".dietaryFiber"))
        #expect(source.contains(".dietarySugar"))
        #expect(source.contains(".dietaryWater"))
        #expect(source.contains(".dietarySodium"))
        #expect(source.contains(".dietaryFatSaturated"))
        #expect(source.contains(".dietaryIron"))
    }

    @Test("HealthKit read types come from a broad PCOS-relevant descriptor registry")
    func healthKitReadTypesUseBroadPCOSRelevantRegistry() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let sourceURL = resolveHealthKitManagerSourceURL(from: testFileURL) else {
            Issue.record("Unable to locate HealthKitManager.swift in active PCOS paths.")
            return
        }

        let root = try TestHelpers.projectRoot(from: #filePath)
        let registryURL = root.appendingPathComponent("PCOS/PCOS/Core/HealthKit/HealthKitDataTypeDescriptor.swift")
        let registrySource = (try? String(contentsOf: registryURL)) ?? ""
        let source = try String(contentsOf: sourceURL) + "\n" + registrySource
        #expect(source.contains("HealthKitDataTypeDescriptor.defaultReadTypes"))

        let expectedIdentifiers = [
            ".heartRate",
            ".heartRateVariabilitySDNN",
            ".appleExerciseTime",
            ".stepCount",
            ".distanceWalkingRunning",
            ".height",
            ".bodyTemperature",
            ".basalBodyTemperature",
            ".menstrualFlow",
            ".cervicalMucusQuality",
            ".ovulationTestResult",
            ".progesteroneTestResult",
            ".pregnancyTestResult",
            ".lactation",
            ".sexualActivity",
            ".abdominalCramps",
            ".pelvicPain",
            ".fatigue",
            ".bloating",
            ".acne",
            ".hairLoss",
            ".moodChanges",
            ".appetiteChanges",
            ".sleepChanges",
            "HKObjectType.workoutType()",
        ]

        for identifier in expectedIdentifiers {
            #expect(source.contains(identifier), "Missing broad HealthKit identifier: \(identifier)")
        }
    }

    @Test("HealthKit provenance model is registered with the app and tests")
    func healthKitProvenanceModelIsRegistered() throws {
        let root = try TestHelpers.projectRoot(from: #filePath)
        let appSource = try String(contentsOf: root.appendingPathComponent("PCOS/PCOS/App/CycleBalanceApp.swift"))
        let testHelpersSource = try String(contentsOf: root.appendingPathComponent("PCOS/PCOSTests/TestHelpers.swift"))
        let backupSchemaSource = try String(contentsOf: root.appendingPathComponent("PCOS/PCOS/App/SettingsDataBackupSchema.swift"))

        #expect(appSource.contains("HealthKitImportedSampleRecord.self"))
        #expect(testHelpersSource.contains("HealthKitImportedSampleRecord.self"))
        #expect(backupSchemaSource.contains("healthKitImportedSamples"))
    }


    @Test("HealthKit settings disclosure lists read types and use caveat")
    func healthKitSettingsDisclosureListsReadTypesAndUseCaveat() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let sourceURL = resolveHealthKitSettingsSourceURL(from: testFileURL) else {
            Issue.record("Unable to locate HealthKitSettingsView.swift in active PCOS paths.")
            return
        }

        let root = try TestHelpers.projectRoot(from: #filePath)
        let registryURL = root.appendingPathComponent("PCOS/PCOS/Core/HealthKit/HealthKitDataTypeDescriptor.swift")
        let source = try String(contentsOf: sourceURL) + "\n" + String(contentsOf: registryURL)
        let expectedDisclosureCopy = [
            "Body context",
            "Sleep",
            "Activity",
            "Blood Glucose",
            "Nutrition",
            "Cycle & ovulation",
            "Reproductive context",
            "Symptoms",
            "Used for daily weight and weight trends.",
            "Used for sleep hours and sleep/recovery insights.",
            "Used as movement context for daily logs and activity insights.",
            "Used for blood sugar history and metabolic insight context.",
            "Used for nutrition source summaries and meal/glucose insight context.",
            "Used to prefill cycle and ovulation context after Apple Health shares it.",
            "Stored as sensitive reviewable context.",
            "Used to prefill symptom context from compatible period and wellness apps.",
            "Imported readings appear in Blood Sugar History with an Apple Health label.",
            "These data types are read only after you connect Apple Health. Source summaries show which apps contributed data.",
            "CycleBalance reads data only after you grant permission.",
            "No writes to Apple Health",
            "Health access is configured. Manage permissions in Settings.",
        ]

        for expectedCopy in expectedDisclosureCopy {
            #expect(source.contains(expectedCopy), "Missing HealthKit disclosure copy: \(expectedCopy)")
        }

        #expect(source.contains("dataAccessCard"))
        #expect(source.contains("privacyCard"))
        #expect(source.contains("ScrollView"))
        #expect(source.contains("settings.healthkit.connection"))
        #expect(source.contains("settings.healthkit.sync_now"))
        #expect(source.contains("UIApplication.openSettingsURLString"))
        #expect(source.contains("connectAndSync(modelContext: modelContext)"))
    }

    @Test("isAvailable returns a boolean")
    func isAvailableReturnsBool() {
        let manager = HealthKitManager()
        let result = manager.isAvailable
        #expect(result == true || result == false)
    }

    @Test("authorizationState starts from availability")
    func authorizationStateStartsFromAvailability() {
        let manager = HealthKitManager()
        let expectedState: HealthKitManager.AuthorizationState = manager.isAvailable ? .needsAuthorization : .unavailable
        #expect(manager.authorizationState == expectedState)
    }

    @Test("refreshAuthorizationState sets unavailable when health data is unavailable")
    func refreshAuthorizationStateUnavailable() async {
        let manager = HealthKitManager(
            availabilityProvider: { false }
        )

        let state = await manager.refreshAuthorizationState()
        #expect(state == .unavailable)
        #expect(manager.authorizationState == .unavailable)
    }

    @Test("refreshAuthorizationState keeps needsAuthorization when HealthKit should request")
    func refreshAuthorizationStateNeedsAuthorization() async {
        let manager = HealthKitManager(
            availabilityProvider: { true },
            authorizationStatusProvider: { _, _, completion in
                completion(.shouldRequest, nil)
            }
        )

        let state = await manager.refreshAuthorizationState()
        #expect(state == .needsAuthorization)
        #expect(manager.authorizationState == .needsAuthorization)
    }

    @Test("refreshAuthorizationState sets configured when request is unnecessary")
    func refreshAuthorizationStateConfigured() async {
        let manager = HealthKitManager(
            availabilityProvider: { true },
            authorizationStatusProvider: { _, _, completion in
                completion(.unnecessary, nil)
            }
        )

        let state = await manager.refreshAuthorizationState()
        #expect(state == .configured)
        #expect(manager.authorizationState == .configured)
    }

    @Test("requestAuthorization leaves needsAuthorization when access is still not configured")
    func requestAuthorizationKeepsNeedsAuthorizationState() async throws {
        let statusProbe = AuthorizationStatusProbe([.shouldRequest])
        let manager = HealthKitManager(
            availabilityProvider: { true },
            authorizationRequester: { _, _, completion in
                completion(false, nil)
            },
            authorizationStatusProvider: { _, _, completion in
                Task {
                    let status = await statusProbe.nextStatus()
                    completion(status, nil)
                }
            }
        )

        try await manager.requestAuthorization()
        #expect(manager.authorizationState == .needsAuthorization)
    }

    @Test("requestAuthorization clears configured state when request errors")
    func requestAuthorizationErrorClearsConfiguredState() async {
        let manager = HealthKitManager(
            availabilityProvider: { true },
            authorizationRequester: { _, _, completion in
                completion(false, MockAuthorizationError.deniedBySystem)
            }
        )
        manager.authorizationState = .configured

        var didThrow = false
        do {
            try await manager.requestAuthorization()
        } catch {
            didThrow = true
        }

        #expect(didThrow == true)
        #expect(manager.authorizationState == .needsAuthorization)
    }

    @Test("lastSyncDate starts as nil on fresh install")
    func lastSyncDateStartsNil() {
        let previous = UserDefaults.standard.object(forKey: healthKitLastSyncKey)
        UserDefaults.standard.removeObject(forKey: healthKitLastSyncKey)

        let manager = HealthKitManager()
        #expect(manager.lastSyncDate == nil)

        if let previous {
            UserDefaults.standard.set(previous, forKey: healthKitLastSyncKey)
        }
    }

    @Test("isSyncing starts as false")
    func isSyncingStartsFalse() {
        let manager = HealthKitManager()
        #expect(manager.isSyncing == false)
    }

    @Test("lastError starts as nil")
    func lastErrorStartsNil() {
        let manager = HealthKitManager()
        #expect(manager.lastError == nil)
    }

    @Test("connectAndSync requests authorization and then syncs on first success")
    func connectAndSyncRequestsAuthorizationAndSyncs() async throws {
        try await withIsolatedLastSyncDefaults {
            let fixedDate = Date(timeIntervalSince1970: 1_700_123_456)
            let statusProbe = AuthorizationStatusProbe([.unnecessary])
            let syncProbe = SyncProbe()
            let manager = HealthKitManager(
                availabilityProvider: { true },
                authorizationRequester: { _, _, completion in
                    completion(true, nil)
                },
                authorizationStatusProvider: { _, _, completion in
                    Task {
                        let status = await statusProbe.nextStatus()
                        completion(status, nil)
                    }
                },
                syncOperation: { _, _ in
                    await syncProbe.markCall()
                    return HealthKitSyncResult(
                        syncedAt: fixedDate,
                        didUpdateDailyLog: true,
                        insertedGlucoseCount: 2
                    )
                }
            )

            let container = try TestHelpers.makeModelContainer()
            await manager.connectAndSync(modelContext: container.mainContext)

            #expect(manager.authorizationState == .configured)
            #expect(manager.lastError == nil)
            #expect(manager.lastSyncDate == fixedDate)
            #expect(await syncProbe.currentCount() == 1)
        }
    }

    @Test("connectAndSync surfaces authorization errors and skips sync")
    func connectAndSyncAuthorizationErrorSkipsSync() async throws {
        try await withIsolatedLastSyncDefaults {
            let syncProbe = SyncProbe()
            let manager = HealthKitManager(
                availabilityProvider: { true },
                authorizationRequester: { _, _, completion in
                    completion(false, MockAuthorizationError.deniedBySystem)
                },
                authorizationStatusProvider: { _, _, completion in
                    completion(.shouldRequest, nil)
                },
                syncOperation: { _, _ in
                    await syncProbe.markCall()
                    return HealthKitSyncResult(
                        syncedAt: Date(),
                        didUpdateDailyLog: false,
                        insertedGlucoseCount: 0
                    )
                }
            )

            let container = try TestHelpers.makeModelContainer()
            await manager.connectAndSync(modelContext: container.mainContext)

            #expect(manager.authorizationState == .needsAuthorization)
            #expect(manager.lastError == MockAuthorizationError.deniedBySystem.errorDescription)
            #expect(manager.lastSyncDate == nil)
            #expect(await syncProbe.currentCount() == 0)
        }
    }

    @Test("connectAndSync keeps configured state when sync fails")
    func connectAndSyncSyncFailurePreservesConfiguredState() async throws {
        try await withIsolatedLastSyncDefaults {
            let statusProbe = AuthorizationStatusProbe([.unnecessary])
            let manager = HealthKitManager(
                availabilityProvider: { true },
                authorizationRequester: { _, _, completion in
                    completion(true, nil)
                },
                authorizationStatusProvider: { _, _, completion in
                    Task {
                        let status = await statusProbe.nextStatus()
                        completion(status, nil)
                    }
                },
                syncOperation: { _, _ in
                    throw MockSyncError.forcedFailure
                }
            )

            let container = try TestHelpers.makeModelContainer()
            await manager.connectAndSync(modelContext: container.mainContext)

            #expect(manager.authorizationState == .configured)
            #expect(manager.lastError == MockSyncError.forcedFailure.errorDescription)
            #expect(manager.lastSyncDate == nil)
        }
    }

    @Test("performFullSync success updates state and clears stale errors")
    func performFullSyncSuccessUpdatesState() async throws {
        try await withIsolatedLastSyncDefaults {
            let fixedDate = Date(timeIntervalSince1970: 1_700_123_456)
            let manager = HealthKitManager(
                syncOperation: { _, _ in
                    HealthKitSyncResult(
                        syncedAt: fixedDate,
                        didUpdateDailyLog: true,
                        insertedGlucoseCount: 2
                    )
                }
            )
            manager.lastError = "stale error"

            let container = try TestHelpers.makeModelContainer()
            await manager.performFullSync(modelContext: container.mainContext)

            #expect(manager.isSyncing == false)
            #expect(manager.lastError == nil)
            #expect(manager.lastSyncDate == fixedDate)

            let storedSyncDate = UserDefaults.standard.object(forKey: healthKitLastSyncKey) as? Date
            #expect(storedSyncDate == fixedDate)
        }
    }

    @Test("performFullSync failure sets error and leaves sync state reset")
    func performFullSyncFailureSetsErrorState() async throws {
        try await withIsolatedLastSyncDefaults {
            let manager = HealthKitManager(
                syncOperation: { _, _ in
                    throw MockSyncError.forcedFailure
                }
            )

            let container = try TestHelpers.makeModelContainer()
            await manager.performFullSync(modelContext: container.mainContext)

            #expect(manager.isSyncing == false)
            #expect(manager.lastSyncDate == nil)
            #expect(manager.lastError == MockSyncError.forcedFailure.errorDescription)
        }
    }
}

@Suite("Onboarding Permission Flow", .serialized)
@MainActor
struct OnboardingPermissionFlowTests {
    @Test("Primary action requests camera first and queues HealthKit for next active cycle")
    func primaryActionQueuesHealthKitAfterCamera() {
        var state = OnboardingPermissionFlowState()

        let firstAction = state.nextPrimaryAction()

        #expect(firstAction == .requestCamera)
        #expect(state.queuedHealthKitRequest == true)
        #expect(state.healthKitStatus == .notDetermined)
    }

    @Test("Camera requests enter an in-flight phase and transition to waiting for HealthKit handoff")
    func cameraRequestTransitionsIntoWaitingState() {
        var state = OnboardingPermissionFlowState()
        _ = state.nextPrimaryAction()

        let didBeginRequest = state.beginRequest(.requestCamera)
        state.markCameraStatus(.granted)

        #expect(didBeginRequest == true)
        #expect(state.cameraStatus == .granted)
        #expect(state.requestPhase == .waitingForSceneActive)
        #expect(state.isInteractionDisabled == true)
    }

    @Test("Queued HealthKit request is deferred until the next active scene cycle")
    func queuedHealthKitRequestConsumesOnSceneActivation() {
        var state = OnboardingPermissionFlowState(
            cameraStatus: .granted,
            healthKitStatus: .notDetermined,
            queuedHealthKitRequest: true,
            requestPhase: .waitingForSceneActive
        )

        let queuedAction = state.nextQueuedSceneActiveAction()
        let secondQueuedAction = state.nextQueuedSceneActiveAction()

        #expect(queuedAction == .requestHealthKit)
        #expect(secondQueuedAction == nil)
        #expect(state.queuedHealthKitRequest == false)
        #expect(state.requestPhase == .requestingHealthKit)
    }

    @Test("Busy permission phases block overlapping requests")
    func busyPermissionPhasesBlockOverlappingRequests() {
        var state = OnboardingPermissionFlowState(
            cameraStatus: .notDetermined,
            healthKitStatus: .notDetermined,
            queuedHealthKitRequest: true,
            requestPhase: .requestingCamera
        )

        let didBeginHealthKit = state.beginRequest(.requestHealthKit)

        #expect(didBeginHealthKit == false)
        #expect(state.requestPhase == .requestingCamera)
    }

    @Test("Recoverable HealthKit failure keeps onboarding retryable")
    func recoverableHealthKitFailureStaysRetryable() {
        var state = OnboardingPermissionFlowState(
            cameraStatus: .granted,
            healthKitStatus: .denied,
            queuedHealthKitRequest: true,
            requestPhase: .requestingHealthKit
        )

        state.markHealthKitRecoverableFailure()

        #expect(state.healthKitStatus == .notDetermined)
        #expect(state.queuedHealthKitRequest == false)
        #expect(state.allResolved == false)
        #expect(state.requestPhase == .idle)
    }

    @Test("Permissions step uses HealthKitManager instead of direct HealthKit store requests")
    func permissionsStepUsesSharedHealthKitManager() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let sourceURL = resolvePermissionsStepSourceURL(from: testFileURL) else {
            Issue.record("Unable to locate PermissionsStepView.swift in active PCOS paths.")
            return
        }

        let source = try String(contentsOf: sourceURL)
        #expect(source.contains("HealthKitManager()"))
        #expect(source.contains("OnboardingPermissionRequestPhase"))
        #expect(source.contains("ProgressView()"))
        #expect(source.contains(".disabled(permissionState.isInteractionDisabled)"))
        #expect(!source.contains("HKHealthStore()"))
        #expect(!source.contains("requestAuthorization(toShare: nil, read: readTypes)"))
    }

    @Test("Onboarding explains Apple Health as a bridge for wearables and nutrition apps")
    func onboardingExplainsAppleHealthBridgeForWearablesAndNutritionApps() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let permissionsSourceURL = resolvePermissionsStepSourceURL(from: testFileURL),
              let healthContextSourceURL = resolveOnboardingHealthContextRevealSourceURL(from: testFileURL)
        else {
            Issue.record("Unable to locate onboarding HealthKit source files in active PCOS paths.")
            return
        }

        let source = try String(contentsOf: permissionsSourceURL) + "\n" + String(contentsOf: healthContextSourceURL)
        let expectedCopy = [
            "Already tracking with Apple Watch, Oura, MyFitnessPal, Cal AI, or another health app?",
            "Connect Apple Health",
            "Make sure your wearable or nutrition app shares data to Apple Health",
            "CycleBalance reads only the data you approve",
            "Actual source labels appear after sync",
            "Apple Health is the bridge",
        ]

        for expectedCopy in expectedCopy {
            #expect(source.contains(expectedCopy), "Missing onboarding HealthKit bridge copy: \(expectedCopy)")
        }

        #expect(source.contains("wearableExampleChips"))
        #expect(source.contains("healthDataBridgeCard"))
        #expect(source.contains("healthSourceSetupSteps"))
        #expect(!source.localizedCaseInsensitiveContains("top 50"))
        #expect(!source.localizedCaseInsensitiveContains("scan installed apps"))
        #expect(!source.localizedCaseInsensitiveContains("detect every app"))
    }

    @Test("FSA/HSA settings row allows the medical necessity description to fully wrap")
    func settingsFSAHSARowAllowsFullDescriptionWrap() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let sourceURL = resolveSettingsViewSourceURL(from: testFileURL) else {
            Issue.record("Unable to locate SettingsView.swift in active PCOS paths.")
            return
        }

        let source = try String(contentsOf: sourceURL)
        #expect(source.contains("Image(systemName: \"doc.text.magnifyingglass\")"))
        #expect(source.contains("Generate a Letter of Medical Necessity for FSA/HSA reimbursement of PCOS-related wellness expenses."))
        #expect(!source.contains(".lineLimit(3)"))
    }
}

@Suite("HealthKit Sync Worker", .serialized)
@MainActor
struct HealthKitSyncWorkerTests {
    @Test("Worker upserts DailyLog metrics while preserving user-entered fields")
    func workerUpsertsDailyLogMetrics() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_700_200_000)
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endOfDay = try #require(Calendar.current.date(byAdding: .day, value: 1, to: startOfDay))

        let existingLog = DailyLog(
            date: startOfDay,
            weight: nil,
            sleepHours: nil,
            activeMinutes: nil,
            stressLevel: 4,
            energyLevel: 2,
            waterOz: 16
        )
        existingLog.setPositiveAction(.walkMovement, isCompleted: true)
        context.insert(existingLog)
        try context.save()

        let worker = HealthKitSyncWorker(
            availabilityProvider: { true },
            weightFetcher: { _ in 72.4 },
            sleepHoursFetcher: { _ in 7.25 },
            activeMinutesFetcher: { _ in 43 },
            restingHeartRateFetcher: { _ in 61.0 },
            glucoseReadingsFetcher: { _, _ in [] },
            nutritionSamplesFetcher: { _, _ in [] }
        )

        let result = try await worker.performFullSync(using: container, now: now)
        #expect(result.didUpdateDailyLog == true)
        #expect(result.insertedGlucoseCount == 0)

        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { log in
                log.date >= startOfDay
                    && log.date < endOfDay
            }
        )

        let logs = try context.fetch(descriptor)
        #expect(logs.count == 1)

        let syncedLog = try #require(logs.first)
        #expect(syncedLog.weight == 72.4)
        #expect(syncedLog.sleepHours == 7.25)
        #expect(syncedLog.activeMinutes == 43)
        #expect(syncedLog.restingHeartRateBPM == 61.0)
        #expect(syncedLog.stressLevel == 4)
        #expect(syncedLog.energyLevel == 2)
        #expect(syncedLog.waterOz == 16)
        #expect(syncedLog.hasPositiveAction(.walkMovement))
    }

    @Test("Worker deduplicates glucose readings by timestamp")
    func workerDeduplicatesGlucoseReadings() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_700_260_000)

        let duplicateTimestamp = now.addingTimeInterval(-3600)
        let newTimestamp = now.addingTimeInterval(-1800)

        let existingReading = BloodSugarReading(
            timestamp: duplicateTimestamp,
            glucoseValue: 105,
            readingType: .random,
            fromHealthKit: true
        )
        context.insert(existingReading)
        try context.save()

        let worker = HealthKitSyncWorker(
            availabilityProvider: { true },
            weightFetcher: { _ in nil },
            sleepHoursFetcher: { _ in nil },
            activeMinutesFetcher: { _ in nil },
            glucoseReadingsFetcher: { _, _ in
                [
                    (date: duplicateTimestamp, value: 105),
                    (date: newTimestamp, value: 112),
                ]
            },
            nutritionSamplesFetcher: { _, _ in [] }
        )

        let result = try await worker.performFullSync(using: container, now: now)
        #expect(result.didUpdateDailyLog == false)
        #expect(result.insertedGlucoseCount == 1)

        let calendar = Calendar.current
        let startDate = try #require(calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)))

        let descriptor = FetchDescriptor<BloodSugarReading>(
            predicate: #Predicate<BloodSugarReading> { reading in
                reading.fromHealthKit == true
                    && reading.timestamp >= startDate
                    && reading.timestamp < now
            }
        )

        let readings = try context.fetch(descriptor)
        #expect(readings.count == 2)

        let matchingNewReadings = readings.filter {
            Int($0.timestamp.timeIntervalSince1970) == Int(newTimestamp.timeIntervalSince1970)
        }
        #expect(matchingNewReadings.count == 1)
    }

    @Test("Worker groups HealthKit nutrition samples by source and close time window")
    func workerGroupsHealthKitNutritionSamplesBySourceAndTimeWindow() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_700_260_000)
        let lunch = now.addingTimeInterval(-7200)

        let worker = HealthKitSyncWorker(
            availabilityProvider: { true },
            weightFetcher: { _ in nil },
            sleepHoursFetcher: { _ in nil },
            activeMinutesFetcher: { _ in nil },
            glucoseReadingsFetcher: { _, _ in [] },
            nutritionSamplesFetcher: { _, _ in
                [
                    HealthKitNutritionSample(
                        metric: .carbohydrates,
                        startDate: lunch,
                        endDate: lunch.addingTimeInterval(60),
                        value: 38,
                        sourceName: "MyFitnessPal",
                        externalIdentifier: "carbs-1"
                    ),
                    HealthKitNutritionSample(
                        metric: .protein,
                        startDate: lunch.addingTimeInterval(8 * 60),
                        endDate: lunch.addingTimeInterval(9 * 60),
                        value: 21,
                        sourceName: "MyFitnessPal",
                        externalIdentifier: "protein-1"
                    ),
                    HealthKitNutritionSample(
                        metric: .fiber,
                        startDate: lunch.addingTimeInterval(10 * 60),
                        endDate: lunch.addingTimeInterval(11 * 60),
                        value: 7,
                        sourceName: "MyFitnessPal",
                        externalIdentifier: "fiber-1"
                    ),
                ]
            }
        )

        let result = try await worker.performFullSync(using: container, now: now)
        let imports = try context.fetch(FetchDescriptor<NutritionImportRecord>())
        let record = try #require(imports.first)

        #expect(result.insertedNutritionImportCount == 1)
        #expect(imports.count == 1)
        #expect(record.sourceKind == .healthKit)
        #expect(record.sourceName == "MyFitnessPal")
        #expect(record.productName == nil)
        #expect(record.carbsGrams == 38)
        #expect(record.proteinGrams == 21)
        #expect(record.fiberGrams == 7)
        #expect(record.reviewStatus == .needsReview)
        #expect(record.userReviewed == false)
    }

    @Test("Worker stores nutrition micronutrients and sample provenance")
    func workerStoresNutritionMicronutrientsAndProvenance() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_700_260_000)
        let lunch = now.addingTimeInterval(-3_600)

        let worker = HealthKitSyncWorker(
            availabilityProvider: { true },
            weightFetcher: { _ in nil },
            sleepHoursFetcher: { _ in nil },
            activeMinutesFetcher: { _ in nil },
            glucoseReadingsFetcher: { _, _ in [] },
            nutritionSamplesFetcher: { _, _ in
                [
                    HealthKitNutritionSample(metric: .dietaryEnergy, startDate: lunch, endDate: lunch, value: 410, sourceName: "MyFitnessPal", externalIdentifier: "energy-1"),
                    HealthKitNutritionSample(metric: .sodium, startDate: lunch, endDate: lunch, value: 720, sourceName: "MyFitnessPal", externalIdentifier: "sodium-1"),
                    HealthKitNutritionSample(metric: .saturatedFat, startDate: lunch, endDate: lunch, value: 3.5, sourceName: "MyFitnessPal", externalIdentifier: "sat-fat-1"),
                    HealthKitNutritionSample(metric: .iron, startDate: lunch, endDate: lunch, value: 2.1, sourceName: "MyFitnessPal", externalIdentifier: "iron-1"),
                ]
            }
        )

        let result = try await worker.performFullSync(using: container, now: now)
        let imports = try context.fetch(FetchDescriptor<NutritionImportRecord>())
        let importRecord = try #require(imports.first)
        let provenance = try context.fetch(FetchDescriptor<HealthKitImportedSampleRecord>())

        #expect(result.insertedNutritionImportCount == 1)
        #expect(importRecord.calories == 410)
        #expect(importRecord.sodiumMg == 720)
        #expect(importRecord.saturatedFatGrams == 3.5)
        #expect(importRecord.ironMg == 2.1)
        #expect(provenance.count == 4)
        #expect(Set(provenance.map(\.sourceName)) == ["MyFitnessPal"])
        #expect(Set(provenance.map(\.derivedRecordKind)) == [.nutritionImport])
    }

    @Test("Worker maps cycle, ovulation, symptom, and sensitive HealthKit categories with provenance")
    func workerMapsCategorySamplesWithProvenance() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_700_260_000)
        let sampleDate = now.addingTimeInterval(-86_400)

        let worker = HealthKitSyncWorker(
            availabilityProvider: { true },
            weightFetcher: { _ in nil },
            sleepHoursFetcher: { _ in nil },
            activeMinutesFetcher: { _ in nil },
            glucoseReadingsFetcher: { _, _ in [] },
            nutritionSamplesFetcher: { _, _ in [] },
            categorySamplesFetcher: { _, _ in
                [
                    HealthKitCategorySamplePayload(
                        healthKitIdentifier: HKCategoryTypeIdentifier.menstrualFlow.rawValue,
                        startDate: sampleDate,
                        endDate: sampleDate,
                        value: HKCategoryValueMenstrualFlow.medium.rawValue,
                        sourceName: "Flo",
                        sourceBundleIdentifier: "org.flo",
                        externalIdentifier: "flow-1"
                    ),
                    HealthKitCategorySamplePayload(
                        healthKitIdentifier: HKCategoryTypeIdentifier.cervicalMucusQuality.rawValue,
                        startDate: sampleDate,
                        endDate: sampleDate,
                        value: HKCategoryValueCervicalMucusQuality.eggWhite.rawValue,
                        sourceName: "Clover",
                        sourceBundleIdentifier: "com.clover",
                        externalIdentifier: "mucus-1"
                    ),
                    HealthKitCategorySamplePayload(
                        healthKitIdentifier: HKCategoryTypeIdentifier.ovulationTestResult.rawValue,
                        startDate: sampleDate,
                        endDate: sampleDate,
                        value: HKCategoryValueOvulationTestResult.luteinizingHormoneSurge.rawValue,
                        sourceName: "Clover",
                        sourceBundleIdentifier: "com.clover",
                        externalIdentifier: "ovulation-1"
                    ),
                    HealthKitCategorySamplePayload(
                        healthKitIdentifier: HKCategoryTypeIdentifier.abdominalCramps.rawValue,
                        startDate: sampleDate,
                        endDate: sampleDate,
                        value: HKCategoryValueSeverity.moderate.rawValue,
                        sourceName: "FemFast",
                        sourceBundleIdentifier: "com.femfast",
                        externalIdentifier: "cramps-1"
                    ),
                    HealthKitCategorySamplePayload(
                        healthKitIdentifier: HKCategoryTypeIdentifier.pregnancyTestResult.rawValue,
                        startDate: sampleDate,
                        endDate: sampleDate,
                        value: HKCategoryValuePregnancyTestResult.positive.rawValue,
                        sourceName: "Clover",
                        sourceBundleIdentifier: "com.clover",
                        externalIdentifier: "pregnancy-test-1"
                    ),
                ]
            },
            extendedQuantitySamplesFetcher: { _, _ in
                [
                    HealthKitQuantitySamplePayload(
                        healthKitIdentifier: HKQuantityTypeIdentifier.basalBodyTemperature.rawValue,
                        startDate: sampleDate,
                        endDate: sampleDate,
                        value: 36.72,
                        unitLabel: "degC",
                        sourceName: "Clover",
                        sourceBundleIdentifier: "com.clover",
                        externalIdentifier: "bbt-1"
                    )
                ]
            }
        )

        let result = try await worker.performFullSync(using: container, now: now)
        let cycleEntries = try context.fetch(FetchDescriptor<CycleEntry>())
        let ovulation = try context.fetch(FetchDescriptor<OvulationObservation>())
        let symptoms = try context.fetch(FetchDescriptor<SymptomEntry>())
        let provenance = try context.fetch(FetchDescriptor<HealthKitImportedSampleRecord>())

        #expect(result.insertedCycleEntryCount == 1)
        #expect(result.insertedOvulationObservationCount == 1)
        #expect(result.insertedSymptomCount == 1)
        #expect(cycleEntries.first?.isPeriodDay == true)
        #expect(cycleEntries.first?.flowIntensity == .medium)
        #expect(ovulation.first?.basalBodyTemperatureCelsius == 36.72)
        #expect(ovulation.first?.cervicalMucus == .eggWhite)
        #expect(ovulation.first?.lhTestResult == .peak)
        #expect(symptoms.first?.symptomType == .cramps)
        #expect(symptoms.first?.severity == 3)
        #expect(provenance.count == 6)
        #expect(provenance.contains { $0.derivedRecordKind == .sensitiveContext && $0.sourceName == "Clover" })
        #expect(provenance.contains { $0.derivedRecordKind == .symptomEntry && $0.sourceName == "FemFast" })
    }

    @Test("Worker keeps smart-device activity samples as local source context")
    func workerKeepsSmartDeviceActivitySamplesAsSourceContext() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_700_260_000)
        let sampleDate = now.addingTimeInterval(-3_600)

        let worker = HealthKitSyncWorker(
            availabilityProvider: { true },
            weightFetcher: { _ in nil },
            sleepHoursFetcher: { _ in nil },
            activeMinutesFetcher: { _ in nil },
            glucoseReadingsFetcher: { _, _ in [] },
            nutritionSamplesFetcher: { _, _ in [] },
            categorySamplesFetcher: { _, _ in [] },
            extendedQuantitySamplesFetcher: { _, _ in
                [
                    HealthKitQuantitySamplePayload(
                        healthKitIdentifier: HKQuantityTypeIdentifier.stepCount.rawValue,
                        startDate: sampleDate,
                        endDate: sampleDate.addingTimeInterval(60),
                        value: 2_400,
                        unitLabel: "count",
                        sourceName: "Oura",
                        sourceBundleIdentifier: "com.ouraring.oura",
                        externalIdentifier: "oura-steps-1"
                    ),
                    HealthKitQuantitySamplePayload(
                        healthKitIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
                        startDate: sampleDate,
                        endDate: sampleDate.addingTimeInterval(60),
                        value: 182,
                        unitLabel: "kcal",
                        sourceName: "Apple Watch",
                        sourceBundleIdentifier: "com.apple.watch",
                        externalIdentifier: "watch-energy-1"
                    ),
                    HealthKitQuantitySamplePayload(
                        healthKitIdentifier: HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
                        startDate: sampleDate,
                        endDate: sampleDate.addingTimeInterval(60),
                        value: 1_750,
                        unitLabel: "m",
                        sourceName: "Oura",
                        sourceBundleIdentifier: "com.ouraring.oura",
                        externalIdentifier: "oura-distance-1"
                    ),
                ]
            }
        )

        let result = try await worker.performFullSync(using: container, now: now)
        let provenance = try context.fetch(FetchDescriptor<HealthKitImportedSampleRecord>())
        let summaries = try HealthKitContributionSummaryService(modelContext: context).summaries(days: 7, now: now)
        let activitySummary = try #require(summaries.first { $0.kind == .activeMinutes })

        #expect(result.insertedProvenanceCount == 3)
        #expect(provenance.count == 3)
        #expect(Set(provenance.map(\.healthKitIdentifier)).isSuperset(of: [
            HKQuantityTypeIdentifier.stepCount.rawValue,
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
        ]))
        #expect(Set(provenance.map(\.derivedRecordKind)) == [.sourceOnly])
        #expect(activitySummary.sampleCount == 3)
        #expect(activitySummary.sourceLabel.contains("Apple Watch"))
        #expect(activitySummary.sourceLabel.contains("Oura") || activitySummary.sourceLabel.contains("more apps"))
    }
}

@Suite("HealthKit Sync Concurrency Regressions", .serialized)
@MainActor
struct HealthKitSyncConcurrencyRegressionTests {
    @Test("HealthKitManager avoids direct SwiftData fetch/save sync loops")
    func healthKitManagerAvoidsDirectFetchSaveSyncLoops() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let sourceURL = resolveHealthKitManagerSourceURL(from: testFileURL) else {
            Issue.record("Unable to locate HealthKitManager.swift in active PCOS paths.")
            return
        }

        let source = try String(contentsOf: sourceURL)
        #expect(!source.contains("modelContext.fetch("))
        #expect(!source.contains("modelContext.save("))
    }
}
