import Foundation

enum BillingBackendMode: String, CaseIterable, Sendable {
    case revenuecat
    case localStoreKit = "local_storekit"

    private static let launchArgumentPrefix = "-premiumBillingMode="
    private static let launchArgumentKey = "-premiumBillingMode"
    private static let modeOverrideEnvironmentKey = "PREMIUM_BILLING_MODE_OVERRIDE"
    private static let plistModeKey = "PREMIUM_BILLING_MODE"

    static func resolved(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> BillingBackendMode {
        if let override = parse(rawValue: launchArgumentOverride(from: processInfo.arguments)) {
            return enforceRuntimePolicy(for: override)
        }

        if let override = parse(rawValue: processInfo.environment[modeOverrideEnvironmentKey]) {
            return enforceRuntimePolicy(for: override)
        }

        if let configured = parse(rawValue: bundle.object(forInfoDictionaryKey: plistModeKey) as? String) {
            return enforceRuntimePolicy(for: configured)
        }

        return enforceRuntimePolicy(for: runtimeDefault)
    }

    private static var runtimeDefault: BillingBackendMode {
#if DEBUG && targetEnvironment(simulator)
        .localStoreKit
#else
        .revenuecat
#endif
    }

    private static func enforceRuntimePolicy(for mode: BillingBackendMode) -> BillingBackendMode {
#if DEBUG
        #if targetEnvironment(simulator)
        return mode
        #else
        return mode == .localStoreKit ? .revenuecat : mode
        #endif
#else
        return .revenuecat
#endif
    }

    private static func parse(rawValue: String?) -> BillingBackendMode? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "revenuecat":
            return .revenuecat
        case "local_storekit", "localstorekit", "storekit":
            return .localStoreKit
        default:
            return nil
        }
    }

    private static func launchArgumentOverride(from arguments: [String]) -> String? {
        for argument in arguments {
            if argument.hasPrefix(launchArgumentPrefix) {
                return String(argument.dropFirst(launchArgumentPrefix.count))
            }
        }

        guard let index = arguments.firstIndex(of: launchArgumentKey),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }

        return arguments[index + 1]
    }
}
