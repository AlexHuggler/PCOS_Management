import Testing
import CloudKit
@testable import PCOS

@Suite("CloudKit Startup Policy")
struct CloudKitStartupPolicyTests {
    @Test("Available account does not fallback")
    func availableStatusDoesNotFallback() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: .available) == nil)
    }

    @Test("No account falls back")
    func noAccountFallsBack() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: .noAccount) == .noAccount)
    }

    @Test("Restricted account falls back")
    func restrictedFallsBack() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: .restricted) == .restricted)
    }

    @Test("Could-not-determine falls back")
    func couldNotDetermineFallsBack() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: .couldNotDetermine) == .couldNotDetermine)
    }

    @Test("Temporarily unavailable maps to fallback")
    func temporarilyUnavailableFallsBack() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: .temporarilyUnavailable) == .couldNotDetermine)
    }

    @Test("Timeout maps to fallback")
    func timeoutFallsBack() {
        #expect(CloudKitStartupPolicy.fallbackReason(for: nil) == .timeout)
    }

    @Test("Simulator policy always returns simulator fallback reason")
    func simulatorPolicyAlwaysFallsBack() {
        let reason = CloudKitStartupPolicy.simulatorFallbackReason()
        #expect(reason == .simulator)
    }
}
