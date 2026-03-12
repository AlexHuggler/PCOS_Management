import Testing
import Foundation
@testable import PCOS

@Suite("StoreKit Billing Client", .serialized)
@MainActor
struct StoreKitBillingClientTests {
    private enum MockRefreshError: Error {
        case refreshFailed
    }

    private final class UpdateTrigger {
        var continuation: AsyncStream<Void>.Continuation?

        lazy var stream: AsyncStream<Void> = {
            AsyncStream { continuation in
                self.continuation = continuation
            }
        }()

        func yield() {
            continuation?.yield(())
        }

        func finish() {
            continuation?.finish()
        }
    }

    private func makeConfiguration() -> BillingConfiguration {
        BillingConfiguration(
            revenueCatPublicSDKKey: nil,
            revenueCatEntitlementID: "premium",
            revenueCatOfferingID: "default",
            productIDs: [
                SubscriptionManager.monthlyProductID,
                SubscriptionManager.yearlyProductID,
            ]
        )
    }

    private func collectValues(
        from stream: AsyncStream<Set<String>>,
        count: Int
    ) async -> [Set<String>] {
        var iterator = stream.makeAsyncIterator()
        var values: [Set<String>] = []

        while values.count < count, let value = await iterator.next() {
            values.append(value)
        }

        return values
    }

    @Test("entitlement updates stream emits latest entitlements on successful refresh")
    func streamEmitsLatestEntitlementsOnSuccess() async {
        let trigger = UpdateTrigger()
        let expected = Set([SubscriptionManager.monthlyProductID])

        let client = StoreKitBillingClient(
            configuration: makeConfiguration(),
            updatesStreamFactory: { trigger.stream },
            entitlementRefresher: { expected }
        )

        let stream = client.makeEntitlementUpdatesStream()
        let collectorTask = Task {
            await collectValues(from: stream, count: 1)
        }

        await Task.yield()
        trigger.yield()
        trigger.finish()

        let values = await collectorTask.value
        #expect(values == [expected])
    }

    @Test("entitlement updates stream uses last-known entitlements when refresh fails")
    func streamUsesLastKnownEntitlementsOnRefreshFailure() async {
        let trigger = UpdateTrigger()
        let monthly = Set([SubscriptionManager.monthlyProductID])

        var refreshResults: [Result<Set<String>, Error>] = [
            .success(monthly),
            .failure(MockRefreshError.refreshFailed),
        ]

        let client = StoreKitBillingClient(
            configuration: makeConfiguration(),
            updatesStreamFactory: { trigger.stream },
            entitlementRefresher: {
                let next = refreshResults.removeFirst()
                return try next.get()
            }
        )

        let stream = client.makeEntitlementUpdatesStream()
        let collectorTask = Task {
            await collectValues(from: stream, count: 2)
        }

        await Task.yield()
        trigger.yield()
        trigger.yield()
        trigger.finish()

        let values = await collectorTask.value
        #expect(values == [monthly, monthly])
    }

    @Test("entitlement updates stream continues after refresh failure")
    func streamContinuesAfterRefreshFailure() async {
        let trigger = UpdateTrigger()
        let monthly = Set([SubscriptionManager.monthlyProductID])
        let yearly = Set([SubscriptionManager.yearlyProductID])

        var refreshResults: [Result<Set<String>, Error>] = [
            .success(monthly),
            .failure(MockRefreshError.refreshFailed),
            .success(yearly),
        ]

        let client = StoreKitBillingClient(
            configuration: makeConfiguration(),
            updatesStreamFactory: { trigger.stream },
            entitlementRefresher: {
                let next = refreshResults.removeFirst()
                return try next.get()
            }
        )

        let stream = client.makeEntitlementUpdatesStream()
        let collectorTask = Task {
            await collectValues(from: stream, count: 3)
        }

        await Task.yield()
        trigger.yield()
        trigger.yield()
        trigger.yield()
        trigger.finish()

        let values = await collectorTask.value
        #expect(values == [monthly, monthly, yearly])
    }
}
