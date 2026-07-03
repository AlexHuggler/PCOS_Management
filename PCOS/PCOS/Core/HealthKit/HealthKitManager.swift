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
    typealias HealthStoreProvider = @MainActor @Sendable () -> HKHealthStore

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
    private let healthStoreProvider: HealthStoreProvider

    static let defaultReadTypes: Set<HKObjectType> = HealthKitDataTypeDescriptor.defaultReadTypes

    private let readTypes = HealthKitManager.defaultReadTypes
    private static let lastSyncKey = "healthkit.lastSyncDate"
    private static let unavailableError = NSError(
        domain: "CycleBalance.HealthKit",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "HealthKit is unavailable for this build or device."]
    )

    private static let defaultAvailabilityProvider: AvailabilityProvider = {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Init

    init(
        healthStore: HKHealthStore? = nil,
        availabilityProvider: @escaping AvailabilityProvider = HealthKitManager.defaultAvailabilityProvider,
        authorizationRequester: AuthorizationRequester? = nil,
        authorizationStatusProvider: AuthorizationStatusProvider? = nil,
        syncOperation: SyncOperation? = nil
    ) {
        let initialAuthorizationState: AuthorizationState = availabilityProvider() ? .needsAuthorization : .unavailable

        self.authorizationState = initialAuthorizationState
        self.availabilityProvider = availabilityProvider
        self.healthStoreProvider = {
            if let healthStore {
                return healthStore
            }
            return HKHealthStore()
        }

        if let authorizationRequester {
            self.authorizationRequester = authorizationRequester
        } else {
            let availabilityProvider = availabilityProvider
            let healthStoreProvider = self.healthStoreProvider
            self.authorizationRequester = { toShare, read, completion in
                guard availabilityProvider() else {
                    completion(false, Self.unavailableError)
                    return
                }
                let store = Task { @MainActor in healthStoreProvider() }
                Task {
                    let resolvedStore = await store.value
                    do {
                        try await resolvedStore.requestAuthorization(toShare: toShare ?? [], read: read)
                        completion(true, nil)
                    } catch {
                        completion(false, error)
                    }
                }
            }
        }

        if let authorizationStatusProvider {
            self.authorizationStatusProvider = authorizationStatusProvider
        } else {
            let availabilityProvider = availabilityProvider
            let healthStoreProvider = self.healthStoreProvider
            self.authorizationStatusProvider = { toShare, read, completion in
                guard availabilityProvider() else {
                    completion(.unknown, Self.unavailableError)
                    return
                }
                let store = Task { @MainActor in healthStoreProvider() }
                Task {
                    let resolvedStore = await store.value
                    resolvedStore.getRequestStatusForAuthorization(toShare: toShare, read: read, completion: completion)
                }
            }
        }

        if let syncOperation {
            self.syncOperation = syncOperation
        } else {
            let availabilityProvider = availabilityProvider
            let healthStoreProvider = self.healthStoreProvider
            self.syncOperation = { modelContainer, now in
                guard availabilityProvider() else {
                    Logger.database.notice("HealthKit full sync skipped because HealthKit is unavailable")
                    return HealthKitSyncResult(syncedAt: now, didUpdateDailyLog: false, insertedGlucoseCount: 0)
                }
                let store = await MainActor.run { healthStoreProvider() }
                let syncWorker = HealthKitSyncWorker(
                    healthStore: store,
                    availabilityProvider: availabilityProvider
                )
                return try await syncWorker.performFullSync(using: modelContainer, now: now)
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

    /// Performs a full sync for today: DailyLog + glucose and nutrition reads for the last 7 days.
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
                "HealthKit full sync completed successfully. dailyLogUpdated=\(syncResult.didUpdateDailyLog, privacy: .public), glucoseInserted=\(syncResult.insertedGlucoseCount, privacy: .public), nutritionInserted=\(syncResult.insertedNutritionImportCount, privacy: .public)"
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
