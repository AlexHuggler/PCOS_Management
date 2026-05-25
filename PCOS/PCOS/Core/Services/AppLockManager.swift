import Foundation
import LocalAuthentication
import Observation
import SwiftUI

enum AppLockRelockDelay: String, CaseIterable, Identifiable, Codable {
    case immediately
    case oneMinute
    case fiveMinutes

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .immediately:
            0
        case .oneMinute:
            60
        case .fiveMinutes:
            300
        }
    }

    var displayName: String {
        switch self {
        case .immediately:
            L10n.string("Immediately", defaultValue: "Immediately")
        case .oneMinute:
            L10n.string("After 1 minute", defaultValue: "After 1 minute")
        case .fiveMinutes:
            L10n.string("After 5 minutes", defaultValue: "After 5 minutes")
        }
    }
}

struct AppLockLifecycleSnapshot: Codable, Equatable {
    var lastBackgroundedAt: Date?
    var pendingAutomaticUnlockOnNextActive: Bool
    var isLocked: Bool

    static let `default` = AppLockLifecycleSnapshot(
        lastBackgroundedAt: nil,
        pendingAutomaticUnlockOnNextActive: false,
        isLocked: false
    )
}

struct AppLockSettings: Codable, Equatable {
    var isEnabled: Bool
    var relockDelay: AppLockRelockDelay

    static let `default` = AppLockSettings(
        isEnabled: false,
        relockDelay: .immediately
    )
}

@MainActor
@Observable
final class AppLockManager {
    private static let settingsKey = "privacy.appLock.settings"
    private static let lifecycleSnapshotKey = "privacy.appLock.lifecycleSnapshot"

    private let defaults: UserDefaults
    private let authenticate: @Sendable (String) async throws -> Void
    private let nowProvider: @Sendable () -> Date

    var settings: AppLockSettings {
        didSet {
            persist()
            if !settings.isEnabled {
                resetRuntimeState()
                defaults.removeObject(forKey: Self.lifecycleSnapshotKey)
            } else {
                syncLockedState(now: nowProvider())
                persistLifecycleState()
            }
        }
    }
    var isLocked = false
    var isAuthenticating = false
    var lastAuthErrorMessage: String?

    private var lastBackgroundedAt: Date?
    private var lastScenePhase: ScenePhase?
    private var needsAutomaticUnlockOnNextActive = false

    init(
        defaults: UserDefaults = .standard,
        authenticate: @escaping @Sendable (String) async throws -> Void = DeviceOwnerAuthenticator.authenticate,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.authenticate = authenticate
        self.nowProvider = nowProvider

        if let data = defaults.data(forKey: Self.settingsKey),
           let storedSettings = try? JSONDecoder().decode(AppLockSettings.self, from: data) {
            settings = storedSettings
        } else {
            settings = .default
        }

        if let data = defaults.data(forKey: Self.lifecycleSnapshotKey),
           let snapshot = try? JSONDecoder().decode(AppLockLifecycleSnapshot.self, from: data) {
            lastBackgroundedAt = snapshot.lastBackgroundedAt
            needsAutomaticUnlockOnNextActive = snapshot.pendingAutomaticUnlockOnNextActive
            isLocked = snapshot.isLocked
            syncLockedState(now: nowProvider())
        } else {
            resetRuntimeState()
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        settings.isEnabled = isEnabled
    }

    func setRelockDelay(_ delay: AppLockRelockDelay) {
        settings.relockDelay = delay
    }

    func handleScenePhaseChange(_ phase: ScenePhase, now: Date = Date()) {
        guard settings.isEnabled else { return }

        defer { lastScenePhase = phase }

        switch phase {
        case .active:
            let shouldEvaluateActivation =
                needsAutomaticUnlockOnNextActive ||
                (lastScenePhase == nil && (lastBackgroundedAt != nil || isLocked))

            guard shouldEvaluateActivation else { return }

            let shouldAttemptAutomaticUnlock = needsAutomaticUnlockOnNextActive
            syncLockedState(now: now)
            needsAutomaticUnlockOnNextActive = false
            persistLifecycleState()

            if isLocked && shouldAttemptAutomaticUnlock {
                isLocked = true
                Task {
                    await authenticateIfNeeded()
                }
            } else if !isLocked {
                clearPersistedLockState()
            }
        case .inactive:
            break
        case .background:
            lastBackgroundedAt = now
            if settings.relockDelay == .immediately {
                isLocked = true
            }
            needsAutomaticUnlockOnNextActive = true
            persistLifecycleState()
        @unknown default:
            break
        }
    }

    func shouldMaskContent(for scenePhase: ScenePhase) -> Bool {
        settings.isEnabled && (scenePhase != .active || isLocked || isAuthenticating)
    }

    func requestUnlock() {
        guard settings.isEnabled else { return }
        isLocked = true
        lastAuthErrorMessage = nil
        needsAutomaticUnlockOnNextActive = false
        persistLifecycleState()
        Task {
            await authenticateIfNeeded()
        }
    }

    func authenticateIfNeeded() async {
        guard settings.isEnabled, isLocked, !isAuthenticating else { return }

        isAuthenticating = true
        defer { isAuthenticating = false }
        lastAuthErrorMessage = nil

        do {
            try await authenticate(
                L10n.string(
                    "Unlock CycleBalance to view your health data.",
                    defaultValue: "Unlock CycleBalance to view your health data."
                )
            )
            lastAuthErrorMessage = nil
            isLocked = false
            clearPersistedLockState()
        } catch {
            lastAuthErrorMessage = Self.userFacingMessage(for: error)
            isLocked = true
            needsAutomaticUnlockOnNextActive = false
            persistLifecycleState()
        }
    }
}

private extension AppLockManager {
    func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.settingsKey)
    }

    func shouldRequireUnlock(now: Date) -> Bool {
        guard settings.isEnabled else { return false }
        guard let lastBackgroundedAt else { return isLocked }
        if settings.relockDelay == .immediately {
            return true
        }
        return now.timeIntervalSince(lastBackgroundedAt) >= settings.relockDelay.seconds || isLocked
    }

    func syncLockedState(now: Date) {
        isLocked = shouldRequireUnlock(now: now)
    }

    func persistLifecycleState() {
        guard settings.isEnabled else {
            defaults.removeObject(forKey: Self.lifecycleSnapshotKey)
            return
        }

        let snapshot = AppLockLifecycleSnapshot(
            lastBackgroundedAt: lastBackgroundedAt,
            pendingAutomaticUnlockOnNextActive: needsAutomaticUnlockOnNextActive,
            isLocked: isLocked
        )

        if snapshot == .default {
            defaults.removeObject(forKey: Self.lifecycleSnapshotKey)
            return
        }

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.lifecycleSnapshotKey)
    }

    func clearPersistedLockState() {
        lastBackgroundedAt = nil
        needsAutomaticUnlockOnNextActive = false
        isLocked = false
        lastAuthErrorMessage = nil
        persistLifecycleState()
    }

    func resetRuntimeState() {
        isLocked = false
        isAuthenticating = false
        lastAuthErrorMessage = nil
        lastBackgroundedAt = nil
        lastScenePhase = nil
        needsAutomaticUnlockOnNextActive = false
    }

    static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return L10n.string(
            "Unlock failed. Try Face ID, Touch ID, or your device passcode again.",
            defaultValue: "Unlock failed. Try Face ID, Touch ID, or your device passcode again."
        )
    }
}

private enum DeviceOwnerAuthenticator {
    static func authenticate(reason: String) async throws {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw authError ?? LAError(.authenticationFailed)
        }

        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}
