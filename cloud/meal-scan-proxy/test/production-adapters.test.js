import assert from "node:assert/strict";
import test from "node:test";
import * as proxyModule from "../src/server.js";

test("Firestore atomically reserves one request and consumes one rolling allowance", async () => {
  assert.equal(typeof proxyModule.createFirestoreIdempotencyStore, "function");
  const firestore = new TransactionalFirestore();
  let timestamp = Date.parse("2026-07-13T12:00:00.000Z");
  let claimSequence = 0;
  const store = proxyModule.createFirestoreIdempotencyStore({
    collectionName: "mealScanIdempotency",
    quotaCollectionName: "mealScanRollingQuota",
    pendingTtlMs: 30_000,
    firestore,
    now: () => timestamp,
    randomUUID: () => `claim-${++claimSequence}`,
  });
  assert.equal(typeof store.claimAndConsumeQuota, "function");
  const request = {
    requestId: "d148889d-8cc8-4839-887f-609fbac55270",
    requestHash: "request-hash",
    quota: { principal: "principal-a", tier: "paid", limit: 10, lifetimeLimit: null },
  };

  const reservations = await Promise.all([
    store.claimAndConsumeQuota(request),
    store.claimAndConsumeQuota(request),
  ]);

  assert.equal(reservations.filter((result) => result.acquired).length, 1);
  assert.equal(reservations.filter((result) => result.state === "pending").length, 2);
  const quotaRecord = firestore.document("mealScanRollingQuota", "principal-a");
  assert.equal(quotaRecord.dispatchTimestamps.length, 1);
  assert.equal(firestore.onlyDocument("mealScanIdempotency").quotaReserved, true);

  // Simulate a process crash after the atomic reservation. The expired claim becomes
  // unknown and the same request cannot consume or dispatch a second allowance.
  timestamp += 30_001;
  const afterCrash = await store.claimAndConsumeQuota(request);
  assert.equal(afterCrash.state, "unknown");
  assert.equal(afterCrash.acquired, false);
  assert.equal(firestore.document("mealScanRollingQuota", "principal-a").dispatchTimestamps.length, 1);
});

test("Firestore reservations cannot exceed the rolling limit after an in-flight call completes", async () => {
  assert.equal(typeof proxyModule.createFirestoreIdempotencyStore, "function");
  const firestore = new TransactionalFirestore();
  const store = proxyModule.createFirestoreIdempotencyStore({
    collectionName: "mealScanIdempotency",
    quotaCollectionName: "mealScanRollingQuota",
    pendingTtlMs: 30_000,
    firestore,
    now: () => Date.parse("2026-07-13T12:00:00.000Z"),
  });
  const quota = { principal: "principal-a", tier: "paid", limit: 1, lifetimeLimit: null };

  const first = await store.claimAndConsumeQuota({ requestId: "request-a", requestHash: "hash-a", quota });
  assert.equal(first.acquired, true);
  await store.complete(first, { ok: true });
  const second = await store.claimAndConsumeQuota({ requestId: "request-b", requestHash: "hash-b", quota });
  const reservations = [first, second];

  assert.equal(reservations.filter((result) => result.acquired).length, 1);
  const rejected = reservations.find((result) => result.state === "quota_denied");
  assert.equal(rejected.quota.allowed, false);
  assert.equal(rejected.quota.remaining, 0);
  assert.equal(firestore.document("mealScanRollingQuota", "principal-a").dispatchTimestamps.length, 1);
  assert.equal(firestore.documentsIn("mealScanIdempotency").length, 1);
});

test("global provider dispatch reservation is concurrent, durable, and does not debit a denied principal", async () => {
  const firestore = new TransactionalFirestore();
  const store = proxyModule.createFirestoreIdempotencyStore({
    collectionName: "mealScanIdempotency",
    quotaCollectionName: "mealScanRollingQuota",
    pendingTtlMs: 30_000,
    globalProviderMinuteLimit: 1,
    globalProviderRollingLimit: 1_000,
    firestore,
    now: () => Date.parse("2026-07-13T12:00:00.000Z"),
  });

  const reservations = await Promise.all([
    store.claimAndConsumeQuota({
      requestId: "global-request-a",
      requestHash: "global-hash-a",
      quota: { principal: "principal-a", tier: "paid", limit: 10, lifetimeLimit: null },
    }),
    store.claimAndConsumeQuota({
      requestId: "global-request-b",
      requestHash: "global-hash-b",
      quota: { principal: "principal-b", tier: "paid", limit: 10, lifetimeLimit: null },
    }),
  ]);

  assert.equal(reservations.filter((result) => result.acquired).length, 1);
  const denied = reservations.find((result) => result.state === "provider_limit_denied");
  assert.equal(denied.reason, "global_provider_minute_limit_exceeded");
  const deniedPrincipal = reservations[0] === denied ? "principal-a" : "principal-b";
  assert.equal(firestore.document("mealScanRollingQuota", deniedPrincipal), undefined);
  assert.equal(firestore.documentsIn("mealScanIdempotency").length, 1);
  assert.equal(
    firestore.document("mealScanRollingQuota", "__globalProviderDispatch__").dispatchTimestamps.length,
    1
  );
});

test("global provider dispatch limits roll over at one minute and twenty four hours", async () => {
  const firestore = new TransactionalFirestore();
  const start = Date.parse("2026-07-13T12:00:00.000Z");
  let timestamp = start;
  const store = proxyModule.createFirestoreIdempotencyStore({
    collectionName: "mealScanIdempotency",
    quotaCollectionName: "mealScanRollingQuota",
    pendingTtlMs: 30_000,
    globalProviderMinuteLimit: 1,
    globalProviderRollingLimit: 2,
    firestore,
    now: () => timestamp,
  });
  const reserve = (suffix) => store.claimAndConsumeQuota({
    requestId: `rollover-request-${suffix}`,
    requestHash: `rollover-hash-${suffix}`,
    quota: { principal: `rollover-principal-${suffix}`, tier: "paid", limit: 10, lifetimeLimit: null },
  });

  const first = await reserve("a");
  assert.equal(first.acquired, true);
  await store.complete(first, { ok: true });
  const minuteDenied = await reserve("b");
  assert.equal(minuteDenied.state, "provider_limit_denied");
  assert.equal(firestore.document("mealScanRollingQuota", "rollover-principal-b"), undefined);

  timestamp = start + 60_000;
  const second = await reserve("b");
  assert.equal(second.acquired, true);
  await store.complete(second, { ok: true });
  timestamp = start + 120_000;
  const rollingDenied = await reserve("c");
  assert.equal(rollingDenied.state, "provider_limit_denied");
  assert.equal(rollingDenied.reason, "global_provider_rolling_limit_exceeded");
  assert.equal(firestore.document("mealScanRollingQuota", "rollover-principal-c"), undefined);

  timestamp = start + 86_400_000;
  const afterRollover = await reserve("c");
  assert.equal(afterRollover.acquired, true);
});

test("one provider call may be in flight per principal and leases release or expire safely", async () => {
  const firestore = new TransactionalFirestore();
  let timestamp = Date.parse("2026-07-13T12:00:00.000Z");
  const store = proxyModule.createFirestoreIdempotencyStore({
    collectionName: "mealScanIdempotency",
    quotaCollectionName: "mealScanRollingQuota",
    pendingTtlMs: 30_000,
    globalProviderMinuteLimit: 60,
    globalProviderRollingLimit: 1_000,
    firestore,
    now: () => timestamp,
  });
  const reserve = (suffix) => store.claimAndConsumeQuota({
    requestId: `lease-request-${suffix}`,
    requestHash: `lease-hash-${suffix}`,
    quota: { principal: "shared-principal", tier: "paid", limit: 10, lifetimeLimit: null },
  });

  const concurrent = await Promise.all([reserve("a"), reserve("b")]);
  const first = concurrent.find((result) => result.acquired);
  const blocked = concurrent.find((result) => result.state === "principal_busy");
  assert.ok(first);
  assert.equal(blocked.reason, "principal_dispatch_in_progress");
  assert.equal(firestore.document("mealScanRollingQuota", "shared-principal").dispatchTimestamps.length, 1);

  await store.complete(first, { ok: true });
  const second = await reserve("b");
  assert.equal(second.acquired, true, "completion releases the principal lease");
  await store.markUnknown(second);
  const third = await reserve("c");
  assert.equal(third.acquired, true, "unknown finalization releases the principal lease");
  await store.abandon(third);
  const fourth = await reserve("d");
  assert.equal(fourth.acquired, true, "pre-dispatch failure releases the principal lease");

  timestamp += 30_001;
  const afterCrash = await reserve("e");
  assert.equal(afterCrash.acquired, true, "an expired crash lease cannot block the principal forever");
});

test("a cache observer cannot steal a pending provider claim or strand its principal lease", async () => {
  const firestore = new TransactionalFirestore();
  const store = proxyModule.createFirestoreIdempotencyStore({
    collectionName: "mealScanIdempotency",
    quotaCollectionName: "mealScanRollingQuota",
    pendingTtlMs: 30_000,
    firestore,
    now: () => Date.parse("2026-07-13T12:00:00.000Z"),
    randomUUID: () => "provider-claim",
  });
  const request = {
    requestId: "cache-race-request",
    requestHash: "cache-race-hash",
    quota: { principal: "cache-race-principal", tier: "paid", limit: 10, lifetimeLimit: null },
  };
  const owner = await store.claimAndConsumeQuota(request);
  assert.equal(owner.acquired, true);

  const observer = await store.completeFromCache({
    requestId: request.requestId,
    requestHash: request.requestHash,
    response: { cacheHit: true },
  });

  assert.deepEqual(observer, { state: "pending", acquired: false });
  assert.equal(firestore.onlyDocument("mealScanIdempotency").state, "pending");
  assert.equal(
    firestore.document("mealScanRollingQuota", request.quota.principal).providerLeaseClaimId,
    "provider-claim"
  );

  await store.complete(owner, { cacheHit: false });
  assert.equal(firestore.onlyDocument("mealScanIdempotency").state, "completed");
  assert.equal(
    firestore.document("mealScanRollingQuota", request.quota.principal).providerLeaseClaimId,
    null
  );
});

test("current subscription checker keeps sandbox and production API clients separated", async () => {
  let productionCalls = 0;
  let sandboxCalls = 0;
  const currentTransaction = {
    originalTransactionId: "1000000123456789",
    transactionId: "1000000987654321",
    bundleId: "alex.PCOS",
    productId: "cyclebalance.premium.monthly",
    type: "Auto-Renewable Subscription",
    environment: "Sandbox",
    expiresDate: Date.parse("2026-07-14T12:00:00.000Z"),
  };
  const checker = proxyModule.createCurrentSubscriptionChecker({
    clients: {
      production: { getAllSubscriptionStatuses: async () => { productionCalls += 1; } },
      sandbox: {
        getAllSubscriptionStatuses: async () => {
          sandboxCalls += 1;
          return {
            environment: "Sandbox",
            bundleId: "alex.PCOS",
            data: [{
              lastTransactions: [{
                status: 1,
                originalTransactionId: currentTransaction.originalTransactionId,
                signedTransactionInfo: "current.signed.transaction",
              }],
            }],
          };
        },
      },
    },
    storeKitVerifier: { verifyAndDecodeTransaction: async () => currentTransaction },
    bundleId: "alex.PCOS",
    appAppleId: 1234567890,
    allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
    now: () => Date.parse("2026-07-13T12:00:00.000Z"),
  });

  const result = await checker.check({ transaction: currentTransaction });

  assert.equal(result.allowed, true);
  assert.equal(productionCalls, 0);
  assert.equal(sandboxCalls, 1);
});

test("current subscription checker rejects Apple API revoked status despite an active captured JWS", async () => {
  const captured = {
    originalTransactionId: "1000000123456789",
    bundleId: "alex.PCOS",
    productId: "cyclebalance.premium.monthly",
    type: "Auto-Renewable Subscription",
    environment: "Production",
    expiresDate: Date.parse("2026-07-14T12:00:00.000Z"),
  };
  const currentRevoked = { ...captured, revocationDate: Date.parse("2026-07-13T11:00:00.000Z") };
  const checker = proxyModule.createCurrentSubscriptionChecker({
    clients: {
      production: {
        getAllSubscriptionStatuses: async () => ({
          environment: "Production",
          bundleId: "alex.PCOS",
          appAppleId: 1234567890,
          data: [{
            lastTransactions: [{
              status: 5,
              originalTransactionId: captured.originalTransactionId,
              signedTransactionInfo: "current.revoked.transaction",
            }],
          }],
        }),
      },
    },
    storeKitVerifier: { verifyAndDecodeTransaction: async () => currentRevoked },
    bundleId: "alex.PCOS",
    appAppleId: 1234567890,
    allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
    now: () => Date.parse("2026-07-13T12:00:00.000Z"),
  });

  const result = await checker.check({ transaction: captured });

  assert.deepEqual(result, { allowed: false, reason: "transaction_revoked" });
});

test("current subscription checker binds the current product to the submitted transaction", async () => {
  const captured = {
    originalTransactionId: "1000000123456789",
    bundleId: "alex.PCOS",
    productId: "cyclebalance.premium.monthly",
    type: "Auto-Renewable Subscription",
    environment: "Production",
    expiresDate: Date.parse("2026-07-14T12:00:00.000Z"),
  };
  const currentDifferentProduct = {
    ...captured,
    productId: "cyclebalance.premium.annual",
  };
  const checker = proxyModule.createCurrentSubscriptionChecker({
    clients: {
      production: {
        getAllSubscriptionStatuses: async () => ({
          environment: "Production",
          bundleId: "alex.PCOS",
          appAppleId: 1234567890,
          data: [{
            lastTransactions: [{
              status: 1,
              originalTransactionId: captured.originalTransactionId,
              signedTransactionInfo: "current.different.product",
            }],
          }],
        }),
      },
    },
    storeKitVerifier: { verifyAndDecodeTransaction: async () => currentDifferentProduct },
    bundleId: "alex.PCOS",
    appAppleId: 1234567890,
    allowedProductIds: new Set([
      "cyclebalance.premium.monthly",
      "cyclebalance.premium.annual",
    ]),
    now: () => Date.parse("2026-07-13T12:00:00.000Z"),
  });

  const result = await checker.check({ transaction: captured });

  assert.deepEqual(result, { allowed: false, reason: "storekit_transaction_mismatch" });
});

test("RevenueCat corroboration searches by the verified Apple transaction and accepts one exact mapped subscription", async () => {
  assert.equal(typeof proxyModule.createRevenueCatSubscriptionVerifier, "function");
  const transactionId = "1000000987654321";
  let request;
  const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
    apiKey: "sk_test_server_key",
    projectId: "proj8da4e000",
    entitlementLookupKey: "CycleBalance Unlimited",
    allowedProductIds: new Set([
      "cyclebalance.premium.monthly",
      "cyclebalance.premium.annual",
    ]),
    timeoutMs: 3_000,
    fetchImpl: async (url, options) => {
      request = { url: String(url), options };
      return new Response(JSON.stringify({
        object: "list",
        items: [{
          object: "subscription",
          product_id: "prod_monthly",
          gives_access: true,
          entitlements: {
            object: "list",
            next_page: null,
            items: [{
              object: "entitlement",
              lookup_key: "CycleBalance Unlimited",
              products: {
                object: "list",
                next_page: null,
                items: [{
                  object: "product",
                  id: "prod_monthly",
                  store_identifier: "cyclebalance.premium.monthly",
                }],
              },
            }],
          },
          environment: "production",
          store: "app_store",
          store_subscription_identifier: transactionId,
        }],
        next_page: null,
        url: "/v2/projects/proj8da4e000/subscriptions",
      }), {
        status: 200,
        headers: { "content-type": "application/json", "content-length": "1024" },
      });
    },
  });

  const result = await verifier.check({
    transaction: { transactionId, environment: "Production" },
  });

  assert.deepEqual(result, { allowed: true });
  assert.equal(
    request.url,
    `https://api.revenuecat.com/v2/projects/proj8da4e000/subscriptions?store_subscription_identifier=${transactionId}`
  );
  assert.equal(request.options.headers.authorization, "Bearer sk_test_server_key");
  assert.equal(request.options.headers.accept, "application/json");
  assert.equal(request.options.method, "GET");
});

test("RevenueCat corroboration treats an empty synchronized search as retryable ingestion lag", async () => {
  const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
    apiKey: "sk_test_server_key",
    projectId: "proj8da4e000",
    entitlementLookupKey: "CycleBalance Unlimited",
    allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
    timeoutMs: 3_000,
    fetchImpl: async () => new Response(JSON.stringify({
      object: "list",
      items: [],
      next_page: null,
      url: "/v2/projects/proj8da4e000/subscriptions",
    }), { status: 200, headers: { "content-type": "application/json" } }),
  });

  const result = await verifier.check({
    transaction: { transactionId: "1000000987654321", environment: "Production" },
  });

  assert.deepEqual(result, {
    allowed: false,
    reason: "revenuecat_subscription_not_synced",
    retryable: true,
  });
});

test("RevenueCat corroboration rejects a response for a different store subscription identifier", async () => {
  const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
    apiKey: "sk_test_server_key",
    projectId: "proj8da4e000",
    entitlementLookupKey: "CycleBalance Unlimited",
    allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
    fetchImpl: async () => new Response(JSON.stringify(revenueCatSubscriptionList({
      store_subscription_identifier: "1000000000000000",
    })), { status: 200, headers: { "content-type": "application/json" } }),
  });

  const result = await verifier.check({
    transaction: { transactionId: "1000000987654321", environment: "Production" },
  });

  assert.deepEqual(result, { allowed: false, reason: "revenuecat_subscription_mismatch" });
});

test("RevenueCat corroboration requires one exact App Store environment entitlement and current product mapping", async () => {
  const mutations = [
    (item) => { item.store = "play_store"; },
    (item) => { item.environment = "sandbox"; },
    (item) => { item.gives_access = false; },
    (item) => { item.entitlements.items[0].lookup_key = "Other Entitlement"; },
    (item) => { item.entitlements.items[0].products.items[0].store_identifier = "attacker.product"; },
    (item) => { item.entitlements.items[0].products.items[0].id = "prod_other"; },
    (item) => { item.entitlements.items.push(structuredClone(item.entitlements.items[0])); },
    (item) => { item.entitlements.items[0].products.items.push(structuredClone(item.entitlements.items[0].products.items[0])); },
  ];
  for (const mutate of mutations) {
    const body = revenueCatSubscriptionList();
    mutate(body.items[0]);
    const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
      apiKey: "sk_test_server_key",
      projectId: "proj8da4e000",
      entitlementLookupKey: "CycleBalance Unlimited",
      allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
      fetchImpl: async () => new Response(JSON.stringify(body), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    });

    const result = await verifier.check({
      transaction: { transactionId: "1000000987654321", environment: "Production" },
    });

    assert.deepEqual(result, { allowed: false, reason: "revenuecat_subscription_mismatch" });
  }
});

test("RevenueCat corroboration rejects paginated or multiple subscription matches", async () => {
  for (const body of [
    { ...revenueCatSubscriptionList(), next_page: "/v2/projects/proj8da4e000/subscriptions?starting_after=sub2" },
    (() => {
      const value = revenueCatSubscriptionList();
      value.items[0].entitlements.next_page = "/v2/projects/proj8da4e000/subscriptions/sub1/entitlements?starting_after=ent2";
      return value;
    })(),
    (() => {
      const value = revenueCatSubscriptionList();
      value.items[0].entitlements.items[0].products.next_page = "/v2/projects/proj8da4e000/entitlements/ent1/products?starting_after=prod2";
      return value;
    })(),
    (() => {
      const value = revenueCatSubscriptionList();
      value.items.push({ ...value.items[0], id: "sub_duplicate" });
      return value;
    })(),
  ]) {
    const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
      apiKey: "sk_test_server_key",
      projectId: "proj8da4e000",
      entitlementLookupKey: "CycleBalance Unlimited",
      allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
      fetchImpl: async () => new Response(JSON.stringify(body), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    });

    const result = await verifier.check({
      transaction: { transactionId: "1000000987654321", environment: "Production" },
    });

    assert.deepEqual(result, { allowed: false, reason: "revenuecat_subscription_mismatch" });
  }
});

test("RevenueCat corroboration fails closed on malformed JSON without exposing upstream content", async () => {
  const upstreamContent = "sensitive-revenuecat-response-must-not-leak";
  const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
    apiKey: "sk_test_server_key",
    projectId: "proj8da4e000",
    entitlementLookupKey: "CycleBalance Unlimited",
    allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
    fetchImpl: async () => new Response(`{"unexpected":"${upstreamContent}"`, {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  });

  await assert.rejects(
    () => verifier.check({
      transaction: { transactionId: "1000000987654321", environment: "Production" },
    }),
    (error) => {
      assert.equal(error.code, "REVENUECAT_RESPONSE_INVALID");
      assert.equal(error.retryable, true);
      assert.equal(error.message.includes(upstreamContent), false);
      return true;
    }
  );
});

test("RevenueCat corroboration treats a malformed list envelope as an invalid response rather than synchronization lag", async () => {
  const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
    apiKey: "sk_test_server_key",
    projectId: "proj8da4e000",
    entitlementLookupKey: "CycleBalance Unlimited",
    allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
    fetchImpl: async () => new Response(JSON.stringify({
      object: "unexpected",
      items: [],
      next_page: null,
    }), { status: 200, headers: { "content-type": "application/json" } }),
  });

  await assert.rejects(
    () => verifier.check({
      transaction: { transactionId: "1000000987654321", environment: "Production" },
    }),
    (error) => error.code === "REVENUECAT_RESPONSE_INVALID" && error.retryable === true
  );
});

test("RevenueCat corroboration cancels an oversized streamed JSON response at the byte bound", async () => {
  let pulls = 0;
  let cancelled = false;
  const body = new ReadableStream({
    pull(controller) {
      pulls += 1;
      controller.enqueue(new Uint8Array(64 * 1_024));
      if (pulls === 10) controller.close();
    },
    cancel() {
      cancelled = true;
    },
  });
  const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
    apiKey: "sk_test_server_key",
    projectId: "proj8da4e000",
    entitlementLookupKey: "CycleBalance Unlimited",
    allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
    fetchImpl: async () => new Response(body, {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  });

  await assert.rejects(
    () => verifier.check({
      transaction: { transactionId: "1000000987654321", environment: "Production" },
    }),
    (error) => error.code === "REVENUECAT_RESPONSE_INVALID" && error.retryable === true
  );
  assert.equal(cancelled, true);
  assert.equal(pulls <= 5, true, `read ${pulls} chunks before enforcing the bound`);
});

test("RevenueCat corroboration classifies non-success responses without exposing the API key or body", async () => {
  const apiKey = "sk_sensitive_server_key_must_not_leak";
  const upstreamBody = "sensitive-upstream-error-must-not-leak";
  for (const [status, retryable] of [[401, false], [429, true], [503, true]]) {
    const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
      apiKey,
      projectId: "proj8da4e000",
      entitlementLookupKey: "CycleBalance Unlimited",
      allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
      fetchImpl: async () => new Response(upstreamBody, { status }),
    });

    await assert.rejects(
      () => verifier.check({
        transaction: { transactionId: "1000000987654321", environment: "Production" },
      }),
      (error) => {
        assert.equal(error.code, "REVENUECAT_UNAVAILABLE");
        assert.equal(error.retryable, retryable);
        assert.equal(error.message.includes(apiKey), false);
        assert.equal(error.message.includes(upstreamBody), false);
        return true;
      }
    );
  }
});

test("RevenueCat corroboration converts a short timeout to a retryable secret-safe failure", async () => {
  const apiKey = "sk_sensitive_timeout_key_must_not_leak";
  const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
    apiKey,
    projectId: "proj8da4e000",
    entitlementLookupKey: "CycleBalance Unlimited",
    allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
    timeoutMs: 10,
    fetchImpl: async (_url, { signal }) => new Promise((resolve, reject) => {
      signal.addEventListener("abort", () => reject(new Error(apiKey)), { once: true });
    }),
  });

  await assert.rejects(
    () => verifier.check({
      transaction: { transactionId: "1000000987654321", environment: "Production" },
    }),
    (error) => {
      assert.equal(error.code, "REVENUECAT_UNAVAILABLE");
      assert.equal(error.retryable, true);
      assert.equal(error.message.includes(apiKey), false);
      return true;
    }
  );
});

test("RevenueCat corroboration applies its short timeout while reading the response body", async () => {
  const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
    apiKey: "sk_sensitive_body_timeout_key",
    projectId: "proj8da4e000",
    entitlementLookupKey: "CycleBalance Unlimited",
    allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
    timeoutMs: 10,
    fetchImpl: async () => new Response(new ReadableStream({ start() {} }), { status: 200 }),
  });

  let guardTimeout;
  try {
    await assert.rejects(
      Promise.race([
        verifier.check({
          transaction: { transactionId: "1000000987654321", environment: "Production" },
        }),
        new Promise((_, reject) => {
          guardTimeout = setTimeout(() => reject(new Error("body read hung")), 250);
        }),
      ]),
      (error) => error.code === "REVENUECAT_UNAVAILABLE" && error.retryable === true
    );
  } finally {
    clearTimeout(guardTimeout);
  }
});

test("RevenueCat corroboration refuses empty project entitlement key and product allowlist configuration", () => {
  const base = {
    apiKey: "sk_test_server_key",
    projectId: "proj8da4e000",
    entitlementLookupKey: "CycleBalance Unlimited",
    allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
  };
  for (const override of [
    { apiKey: "" },
    { apiKey: " ".repeat(16) },
    { projectId: "" },
    { entitlementLookupKey: "" },
    { allowedProductIds: [] },
    { allowedProductIds: new Set() },
    { allowedProductIds: new Set([" "]) },
  ]) {
    assert.throws(
      () => proxyModule.createRevenueCatSubscriptionVerifier({ ...base, ...override }),
      /RevenueCat verifier configuration is invalid/
    );
  }
});

test("RevenueCat corroboration refuses an invalid verified transaction before network access", async () => {
  let fetchCalls = 0;
  const verifier = proxyModule.createRevenueCatSubscriptionVerifier({
    apiKey: "sk_test_server_key",
    projectId: "proj8da4e000",
    entitlementLookupKey: "CycleBalance Unlimited",
    allowedProductIds: new Set(["cyclebalance.premium.monthly"]),
    fetchImpl: async () => {
      fetchCalls += 1;
      return new Response(JSON.stringify(revenueCatSubscriptionList()));
    },
  });

  for (const transaction of [
    { transactionId: "", environment: "Production" },
    { transactionId: "1000000987654321", environment: "Staging" },
    { transactionId: "x".repeat(256), environment: "Sandbox" },
  ]) {
    assert.deepEqual(await verifier.check({ transaction }), {
      allowed: false,
      reason: "revenuecat_subscription_mismatch",
    });
  }
  assert.equal(fetchCalls, 0);
});

function revenueCatSubscriptionList(subscriptionOverrides = {}) {
  return {
    object: "list",
    items: [{
      object: "subscription",
      product_id: "prod_monthly",
      gives_access: true,
      entitlements: {
        object: "list",
        next_page: null,
        items: [{
          object: "entitlement",
          lookup_key: "CycleBalance Unlimited",
          products: {
            object: "list",
            next_page: null,
            items: [{
              object: "product",
              id: "prod_monthly",
              store_identifier: "cyclebalance.premium.monthly",
            }],
          },
        }],
      },
      environment: "production",
      store: "app_store",
      store_subscription_identifier: "1000000987654321",
      ...subscriptionOverrides,
    }],
    next_page: null,
    url: "/v2/projects/proj8da4e000/subscriptions",
  };
}

class TransactionalFirestore {
  #documents = new Map();
  #queue = Promise.resolve();

  collection(name) {
    return {
      doc: (id) => ({ path: `${name}/${id}`, id }),
    };
  }

  runTransaction(callback) {
    const run = async () => {
      const writes = [];
      const transaction = {
        get: async (reference) => this.#snapshot(reference.path),
        create: (reference, value) => writes.push({ type: "create", path: reference.path, value }),
        set: (reference, value, options) => writes.push({ type: "set", path: reference.path, value, options }),
        delete: (reference) => writes.push({ type: "delete", path: reference.path }),
      };
      const result = await callback(transaction);
      for (const write of writes) this.#apply(write);
      return result;
    };
    const result = this.#queue.then(run, run);
    this.#queue = result.then(() => undefined, () => undefined);
    return result;
  }

  documentsIn(collection) {
    const prefix = `${collection}/`;
    return [...this.#documents.entries()]
      .filter(([key]) => key.startsWith(prefix))
      .map(([, value]) => structuredClone(value));
  }

  document(collection, id) {
    const value = this.#documents.get(`${collection}/${id}`);
    return value === undefined ? undefined : structuredClone(value);
  }

  onlyDocument(collection) {
    const documents = this.documentsIn(collection);
    assert.equal(documents.length, 1, `expected one document in ${collection}`);
    return documents[0];
  }

  #snapshot(documentPath) {
    const value = this.#documents.get(documentPath);
    const cloned = value === undefined ? undefined : structuredClone(value);
    return {
      exists: cloned !== undefined,
      id: documentPath.split("/").at(-1),
      get: (field) => cloned?.[field],
      data: () => cloned,
    };
  }

  #apply(write) {
    if (write.type === "delete") {
      this.#documents.delete(write.path);
      return;
    }
    if (write.type === "create" && this.#documents.has(write.path)) {
      throw new Error("document already exists");
    }
    const existing = this.#documents.get(write.path) ?? {};
    this.#documents.set(
      write.path,
      structuredClone(write.options?.merge ? { ...existing, ...write.value } : write.value)
    );
  }
}
