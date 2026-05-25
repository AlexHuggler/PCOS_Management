import Foundation
import CloudKit
import os

enum CloudKitFallbackReason: String, Sendable {
    case simulator = "simulator"
    case debugLocalOnly = "debugLocalOnly"
    case noAccount = "noAccount"
    case restricted = "restricted"
    case couldNotDetermine = "couldNotDetermine"
    case timeout = "timeout"
    case cloudkitInitError = "cloudkitInitError"
}

struct CloudKitStartupPolicy {
    static func fallbackReason(for accountStatus: CKAccountStatus?) -> CloudKitFallbackReason? {
        guard let accountStatus else {
            return .timeout
        }

        switch accountStatus {
        case .available:
            return nil
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .couldNotDetermine:
            return .couldNotDetermine
        case .temporarilyUnavailable:
            return .couldNotDetermine
        @unknown default:
            return .couldNotDetermine
        }
    }

#if DEBUG
    static let debugCloudKitOptInArgument = "-debug.persistence.cloudkit"
    static let debugCloudKitOptInEnvironmentKey = "DEBUG_PERSISTENCE_CLOUDKIT"

    static func shouldUseLocalStoreInDebug(
        processArguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isSimulator: Bool = runningOnSimulator
    ) -> Bool {
        if isSimulator {
            return true
        }

        return !isDebugCloudKitOptInEnabled(processArguments: processArguments, environment: environment)
    }

    static func debugFallbackReason(isSimulator: Bool = runningOnSimulator) -> CloudKitFallbackReason {
        isSimulator ? .simulator : .debugLocalOnly
    }

    static func isDebugCloudKitOptInEnabled(
        processArguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if processArguments.contains(debugCloudKitOptInArgument) {
            return true
        }

        guard let rawValue = environment[debugCloudKitOptInEnvironmentKey] else {
            return false
        }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }

    static func simulatorFallbackReason() -> CloudKitFallbackReason {
        .simulator
    }

    private static var runningOnSimulator: Bool {
#if targetEnvironment(simulator)
        true
#else
        false
#endif
    }
#endif
}
