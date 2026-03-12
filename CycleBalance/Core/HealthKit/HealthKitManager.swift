import HealthKit
import SwiftData
import os

@Observable
@MainActor
final class HealthKitManager {
    typealias AvailabilityProvider = @Sendable () -> Bool
    typealias AuthorizationRequester = (
        _ toShare: Set<HKSampleType>?,
        _ read: Set<HKObjectType>,
        _ completion: @escaping @Sendable (Bool, Error?) -> Void
    ) -> Void
    typealias SyncOperation = @Sendable (_ modelContainer: ModelContainer, _ now: Date) async throws -> HealthKitSyncResult

    // MARK: - Public State

    var isAuthorized = false
    var lastSyncDate: Date?
    var isSyncing = false
    var lastError: String?

    var isAvailable: Bool {
        availabilityProvider()
    }

    // MARK: - Private

    private let availabilityProvider: AvailabilityProvider
    private let authorizationRequester: AuthorizationRequester
    private let syncOperation: SyncOperation

    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            types.insert(bodyMass)
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        if let glucose = HKObjectType.quantityType(forIdentifier: .bloodGlucose) {
            types.insert(glucose)
        }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        return types
    }()

    private static let lastSyncKey = "healthkit.lastSyncDate"

    // MARK: - Init

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        availabilityProvider: @escaping AvailabilityProvider = { HKHealthStore.isHealthDataAvailable() },
        authorizationRequester: AuthorizationRequester? = nil,
        syncOperation: SyncOperation? = nil
    ) {
        self.availabilityProvider = availabilityProvider

        if let authorizationRequester {
            self.authorizationRequester = authorizationRequester
        } else {
            let store = healthStore
            self.authorizationRequester = { toShare, read, completion in
                store.requestAuthorization(toShare: toShare, read: read, completion: completion)
            }
        }

        if let syncOperation {
            self.syncOperation = syncOperation
        } else {
            let syncWorker = HealthKitSyncWorker(
                healthStore: healthStore,
                availabilityProvider: availabilityProvider
            )
            self.syncOperation = { modelContainer, now in
                try await syncWorker.performFullSync(using: modelContainer, now: now)
            }
        }

        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard isAvailable else {
            Logger.database.warning("HealthKit is not available on this device")
            isAuthorized = false
            return
        }

        do {
            let isGranted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                authorizationRequester([], readTypes) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }

            isAuthorized = isGranted
        } catch {
            isAuthorized = false
            throw error
        }
    }

    // MARK: - Sync

    /// Performs a full sync for today: DailyLog + glucose readings for the last 7 days.
    func performFullSync(modelContext: ModelContext) async {
        isSyncing = true
        lastError = nil

        defer {
            isSyncing = false
        }

        do {
            let syncResult = try await syncOperation(modelContext.container, Date())

            lastSyncDate = syncResult.syncedAt
            UserDefaults.standard.set(syncResult.syncedAt, forKey: Self.lastSyncKey)

            Logger.database.info(
                "HealthKit full sync completed successfully. dailyLogUpdated=\(syncResult.didUpdateDailyLog, privacy: .public), glucoseInserted=\(syncResult.insertedGlucoseCount, privacy: .public)"
            )
        } catch {
            lastError = error.localizedDescription
            Logger.database.error("HealthKit sync failed: \(error.localizedDescription)")
        }
    }
}
