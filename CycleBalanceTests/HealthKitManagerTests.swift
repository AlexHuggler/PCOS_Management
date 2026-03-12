import Testing
import Foundation
import SwiftData
@testable import CycleBalance

#if canImport(PCOS)
private let healthKitEntitlementsRelativePath = "../PCOS/PCOS.entitlements"
#else
private let healthKitEntitlementsRelativePath = "../CycleBalance/CycleBalance.entitlements"
#endif

private let healthKitManagerSourceCandidates = [
    "../PCOS/Core/HealthKit/HealthKitManager.swift",
    "../CycleBalance/Core/HealthKit/HealthKitManager.swift",
]

private let healthKitLastSyncKey = "healthkit.lastSyncDate"

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

private enum MockAuthorizationError: Error {
    case deniedBySystem
}

private enum MockSyncError: LocalizedError {
    case forcedFailure

    var errorDescription: String? {
        "HealthKit sync worker failed in test"
    }
}

@Suite("HealthKit Manager", .serialized)
@MainActor
struct HealthKitManagerTests {
    @Test("Entitlements include HealthKit capability")
    func entitlementsIncludeHealthKitCapability() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let entitlementsURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(healthKitEntitlementsRelativePath)
            .standardizedFileURL

        let plistData = try Data(contentsOf: entitlementsURL)
        let plistObject = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        )
        let entitlements = try #require(plistObject as? [String: Any])
        let healthKitEnabled = entitlements["com.apple.developer.healthkit"] as? Bool
        #expect(healthKitEnabled == true)
    }

    @Test("Info.plist includes HealthKit usage descriptions")
    func infoPlistIncludesHealthKitUsageDescriptions() throws {
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

        let readUsage = info["NSHealthShareUsageDescription"] as? String
        let writeUsage = info["NSHealthUpdateUsageDescription"] as? String

        #expect(readUsage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        #expect(writeUsage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    @Test("isAvailable returns a boolean")
    func isAvailableReturnsBool() {
        let manager = HealthKitManager()
        let result = manager.isAvailable
        #expect(result == true || result == false)
    }

    @Test("isAuthorized starts as false")
    func isAuthorizedStartsFalse() {
        let manager = HealthKitManager()
        #expect(manager.isAuthorized == false)
    }

    @Test("requestAuthorization sets isAuthorized true when access is granted")
    func requestAuthorizationGrantedSetsAuthorizedState() async throws {
        let manager = HealthKitManager(
            availabilityProvider: { true },
            authorizationRequester: { _, _, completion in
                completion(true, nil)
            }
        )

        try await manager.requestAuthorization()
        #expect(manager.isAuthorized == true)
    }

    @Test("requestAuthorization keeps isAuthorized false when access is denied")
    func requestAuthorizationDeniedKeepsUnauthorizedState() async throws {
        let manager = HealthKitManager(
            availabilityProvider: { true },
            authorizationRequester: { _, _, completion in
                completion(false, nil)
            }
        )

        try await manager.requestAuthorization()
        #expect(manager.isAuthorized == false)
    }

    @Test("requestAuthorization clears stale auth state when request errors")
    func requestAuthorizationErrorClearsAuthorizedState() async {
        let manager = HealthKitManager(
            availabilityProvider: { true },
            authorizationRequester: { _, _, completion in
                completion(false, MockAuthorizationError.deniedBySystem)
            }
        )
        manager.isAuthorized = true

        var didThrow = false
        do {
            try await manager.requestAuthorization()
        } catch {
            didThrow = true
        }

        #expect(didThrow == true)
        #expect(manager.isAuthorized == false)
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
        context.insert(existingLog)
        try context.save()

        let worker = HealthKitSyncWorker(
            availabilityProvider: { true },
            weightFetcher: { _ in 72.4 },
            sleepHoursFetcher: { _ in 7.25 },
            activeMinutesFetcher: { _ in 43 },
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
        #expect(syncedLog.stressLevel == 4)
        #expect(syncedLog.energyLevel == 2)
        #expect(syncedLog.waterOz == 16)
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
            Issue.record("Unable to locate HealthKitManager.swift in expected mirrored paths.")
            return
        }

        let source = try String(contentsOf: sourceURL)
        #expect(!source.contains("modelContext.fetch("))
        #expect(!source.contains("modelContext.save("))
    }
}
