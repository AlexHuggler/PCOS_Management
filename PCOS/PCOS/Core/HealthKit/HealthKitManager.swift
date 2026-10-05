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

    static let shared = HealthKitManager()
    private var observerQueries: [String: HKObserverQuery] = [:]
    private var observerStore: HKHealthStore?
    private var syncTask: Task<HealthKitSyncResult, Error>?
    private var syncRequestedAgain = false
    private var syncEpoch = 0

    var enabledCategories = HealthKitCategorySelection.enabled

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

    private var readTypes: Set<HKObjectType> {
        Set(HealthKitDataTypeDescriptor.readDescriptors.filter { enabledCategories.contains($0.category) }.compactMap(\.objectType))
    }
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
                return try await HealthKitAnchoredSync(store: store).sync(container: modelContainer, now: now)
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
    func requestAuthorization(categories: Set<HealthKitDataTypeDescriptor.Category>? = nil) async throws -> AuthorizationState {
        guard isAvailable else {
            Logger.database.warning("HealthKit is not available on this device")
            authorizationState = .unavailable
            return authorizationState
        }

        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                authorizationRequester(nil, categories.map { selected in Set(HealthKitDataTypeDescriptor.readDescriptors.filter { selected.contains($0.category) }.compactMap(\.objectType)) } ?? readTypes) { success, error in
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

    /// Coalesces app, foreground, settings, and observer requests into one transaction.
    func performFullSync(modelContext: ModelContext) async {
        if let syncTask {
            syncRequestedAgain = true
            _ = try? await syncTask.value
            return
        }
        guard isAvailable, !enabledCategories.isEmpty else { return }
        isSyncing = true
        lastError = nil
        let epoch = syncEpoch
        let operation = syncOperation
        let container = modelContext.container
        let task = Task { @MainActor in
            defer {
                if self.syncEpoch == epoch { self.syncTask = nil; self.isSyncing = false }
            }
            var result: HealthKitSyncResult
            repeat {
                self.syncRequestedAgain = false
                try Task.checkCancellation()
                result = try await operation(container, Date())
                try Task.checkCancellation()
                InsightRefreshCoordinator.invalidate()
                NotificationCenter.default.post(name: .healthKitDidCommit, object: nil)
                self.lastSyncDate = result.syncedAt
                UserDefaults.standard.set(result.syncedAt, forKey: Self.lastSyncKey)
            } while self.syncRequestedAgain
            return result
        }
        syncTask = task
        do { _ = try await task.value }
        catch {
            guard syncEpoch == epoch, !(error is CancellationError) else { return }
            lastError = error.localizedDescription
            Logger.database.error("HealthKit sync failed: \(error.localizedDescription)")
        }
    }

    /// Synchronous cancellation is safe because the importer checks cancellation immediately
    /// before its non-suspending MainActor transaction. Old tasks cannot commit after this call.
    func suspendSync(disableCategories: Bool = false) {
        syncEpoch += 1
        syncTask?.cancel()
        syncTask = nil
        syncRequestedAgain = false
        isSyncing = false
        if let store = observerStore {
            for query in observerQueries.values { store.stop(query) }
        }
        observerQueries = [:]
        if disableCategories {
            enabledCategories = []
            HealthKitCategorySelection.enabled = []
        }
    }

    func setCategory(_ category: HealthKitDataTypeDescriptor.Category, enabled: Bool) {
        if enabled { enabledCategories.insert(category) } else { enabledCategories.remove(category) }
        HealthKitCategorySelection.enabled = enabledCategories
    }

    func foregroundSync(modelContainer: ModelContainer) async {
        await refreshAuthorizationState()
        guard isConfigured else { return }
        startObserving(modelContainer: modelContainer)
        await performFullSync(modelContext: ModelContext(modelContainer))
    }

    func startObserving(modelContainer: ModelContainer) {
        guard isAvailable else { return }
        let store = observerStore ?? healthStoreProvider()
        observerStore = store
        let types = readTypes.compactMap { $0 as? HKSampleType }
        let enabledIDs = Set(types.map(\.identifier))
        for (identifier, query) in observerQueries where !enabledIDs.contains(identifier) {
            store.stop(query)
            if let type = HealthKitDataTypeDescriptor.readDescriptors.first(where: { $0.objectType?.identifier == identifier })?.objectType { store.disableBackgroundDelivery(for: type) { _, _ in } }
            observerQueries.removeValue(forKey: identifier)
        }
        for type in types where observerQueries[type.identifier] == nil {
            let observerEpoch = syncEpoch
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                let acknowledgement = HealthKitObserverAcknowledgement(completion)
                Task { @MainActor [weak self] in
                    defer { acknowledgement.finish() }
                    guard error == nil, let self, self.syncEpoch == observerEpoch else { return }
                    await self.performFullSync(modelContext: ModelContext(modelContainer))
                }
            }
            observerQueries[type.identifier] = query
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
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

/// HealthKit's callback is not annotated Sendable. Ownership transfers into this locked,
/// one-shot holder before crossing actors; the callback is invoked at most once.
private final class HealthKitObserverAcknowledgement: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (() -> Void)?
    init(_ completion: @escaping () -> Void) { self.completion = completion }
    func finish() {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?()
    }
}
