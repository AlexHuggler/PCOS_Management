import Foundation
import CloudKit
import os

enum CloudKitFallbackReason: String, Sendable {
    case simulator = "simulator"
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
    static func simulatorFallbackReason() -> CloudKitFallbackReason {
        .simulator
    }
#endif
}
