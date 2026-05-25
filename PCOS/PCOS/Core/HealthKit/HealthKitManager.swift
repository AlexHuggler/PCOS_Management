import HealthKit
import SwiftData
import os

@Observable
@MainActor
final class HealthKitManager {
    enum AuthorizationState: Equatable {
        case unavailable
        case needsAuthorization
        case configured
    }

    typealias AvailabilityProvider = @Sendable () -> Bool
    typealias AuthorizationRequester = (
        _ toShare: Set<HKSampleType>?,
        _ read: Set<HKObjectType>,
        _ completion: @escaping @Sendable (Bool, Error?) -> Void
    ) -> Void
    typealias AuthorizationStatusProvider = (
        _ toShare: Set<HKSampleType>,
        _ read: Set<HKObjectType>,
        _ completion: @escaping @Sendable (HKAuthorizationRequestStatus, Error?) -> Void
    ) -> Void
    typealias SyncOperation = @Sendable (_ modelContainer: ModelContainer, _ now: Date) async throws -> HealthKitSyncResult

    // MARK: - Public State

    var authorizationState: AuthorizationState
    var lastSyncDate: Date?
    var isSyncing = false
    var lastError: String?

    var isAvailable: Bool {
        availabilityProvider()
    }

    var isConfigured: Bool {
        authorizationState == .configured
    }

    // MARK: - Private

    private let availabilityProvider: AvailabilityProvider
    private let authorizationRequester: AuthorizationRequester
    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let syncOperation: SyncOperation

    static let defaultReadTypes: Set<HKObjectType> = {
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
        if let restingHeartRate = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHeartRate)
        }
        return types
    }()

    private let readTypes = HealthKitManager.defaultReadTypes
    private static let lastSyncKey = "healthkit.lastSyncDate"

    // MARK: - Init

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        availabilityProvider: @escaping AvailabilityProvider = { HKHealthStore.isHealthDataAvailable() },
        authorizationRequester: AuthorizationRequester? = nil,
        authorizationStatusProvider: AuthorizationStatusProvider? = nil,
        syncOperation: SyncOperation? = nil
    ) {
        let initialAuthorizationState: AuthorizationState = availabilityProvider() ? .needsAuthorization : .unavailable

        self.authorizationState = initialAuthorizationState
        self.availabilityProvider = availabilityProvider

        if let authorizationRequester {
            self.authorizationRequester = authorizationRequester
        } else {
            let store = healthStore
            self.authorizationRequester = { toShare, read, completion in
                store.requestAuthorization(toShare: toShare, read: read, completion: completion)
            }
        }

        if let authorizationStatusProvider {
            self.authorizationStatusProvider = authorizationStatusProvider
        } else {
            let store = healthStore
            self.authorizationStatusProvider = { toShare, read, completion in
                store.getRequestStatusForAuthorization(toShare: toShare, read: read, completion: completion)
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

    @discardableResult
    func refreshAuthorizationState() async -> AuthorizationState {
        do {
            let resolvedState = try await resolveAuthorizationState()
            authorizationState = resolvedState
            return resolvedState
        } catch {
            authorizationState = isAvailable ? .needsAuthorization : .unavailable
            Logger.database.error("HealthKit authorization status refresh failed: \(error.localizedDescription)")
            return authorizationState
        }
    }

    @discardableResult
    func requestAuthorization() async throws -> AuthorizationState {
        guard isAvailable else {
            Logger.database.warning("HealthKit is not available on this device")
            authorizationState = .unavailable
            return authorizationState
        }

        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                authorizationRequester(nil, readTypes) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }

            authorizationState = try await resolveAuthorizationState()
            return authorizationState
        } catch {
            authorizationState = .needsAuthorization
            throw error
        }
    }

    func connectAndSync(modelContext: ModelContext) async {
        guard isAvailable else {
            Logger.database.warning("HealthKit connect flow skipped because HealthKit is unavailable")
            authorizationState = .unavailable
            return
        }

        lastError = nil

        do {
            if authorizationState == .needsAuthorization {
                try await requestAuthorization()
            }

            guard authorizationState == .configured else {
                Logger.database.notice("HealthKit authorization was not configured after the connect request")
                return
            }

            await performFullSync(modelContext: modelContext)
        } catch {
            lastError = error.localizedDescription
            Logger.database.error("HealthKit connect flow failed: \(error.localizedDescription)")
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

    private func resolveAuthorizationState() async throws -> AuthorizationState {
        guard isAvailable else {
            return .unavailable
        }

        let requestStatus = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<HKAuthorizationRequestStatus, Error>) in
            authorizationStatusProvider([], readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }

        switch requestStatus {
        case .unnecessary:
            return .configured
        case .shouldRequest, .unknown:
            return .needsAuthorization
        @unknown default:
            return .needsAuthorization
        }
    }
}
