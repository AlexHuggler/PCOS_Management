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
    @Test("Release uses HealthKit entitlements while Debug uses local entitlements")
    func releaseUsesHealthKitEntitlementsAndDebugStaysLocal() throws {
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
        #expect(debugEntitlements["com.apple.developer.healthkit"] == nil)

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

        #expect(readUsage.contains("reads your Apple Health data"))
        #expect(writeUsage.contains("does not write to Apple Health"))
    }

    @Test("HealthKit read types include resting heart rate")
    func healthKitReadTypesIncludeRestingHeartRate() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let sourceURL = resolveHealthKitManagerSourceURL(from: testFileURL) else {
            Issue.record("Unable to locate HealthKitManager.swift in active PCOS paths.")
            return
        }

        let source = try String(contentsOf: sourceURL)
        #expect(source.contains(".restingHeartRate"))
    }

    @Test("HealthKit settings disclosure lists read types and use caveat")
    func healthKitSettingsDisclosureListsReadTypesAndUseCaveat() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let sourceURL = resolveHealthKitSettingsSourceURL(from: testFileURL) else {
            Issue.record("Unable to locate HealthKitSettingsView.swift in active PCOS paths.")
            return
        }

        let source = try String(contentsOf: sourceURL)
        let expectedDisclosureCopy = [
            "Body Mass",
            "Sleep Analysis",
            "Active Energy Burned",
            "Blood Glucose",
            "Step Count",
            "Resting Heart Rate",
            "Used for daily weight and weight trends.",
            "Used for sleep hours and sleep/recovery insights.",
            "Used as activity context for daily logs and activity insights.",
            "Used for blood sugar history and metabolic insight context.",
            "Requested for activity context; not saved or used for insights.",
            "Used for daily resting BPM and recovery context.",
            "Shown on Today when Apple Health has synced daily context.",
            "Imported readings appear in Blood Sugar History with an Apple Health label.",
            "These data types are read only after you connect Apple Health.",
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
            glucoseReadingsFetcher: { _, _ in [] }
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
            }
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
