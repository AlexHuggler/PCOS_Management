import assert from "node:assert/strict";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  findCanaryQuotaSnapshot,
  projectCorrelatedScannerEvents,
  verifyCorrelatedPhase,
} from "../scripts/positive-canary-evidence.mjs";

const canaryId = "90b2ac63-e61f-49e1-a8b0-a5e85f154d4c";
const correlationId = crypto.createHash("sha256").update(canaryId).digest("hex");
const operationTag = "b".repeat(64);
const quotaPrincipal = "principal-document-id-that-must-never-be-retained";
const quotaTag = crypto
  .createHash("sha256")
  .update(`${canaryId}|${quotaPrincipal}`)
  .digest("hex");
const helperPath = fileURLToPath(new URL("../scripts/positive-canary-evidence.mjs", import.meta.url));

function scannerEvent(overrides = {}) {
  return {
    event: "meal_scan_scanner_event",
    severity: "INFO",
    schemaVersion: "cyclebalance.meal_scan.operation.v1",
    eventType: "request_result",
    outcome: "completed",
    canaryCorrelationId: correlationId,
    canaryOperationTag: operationTag,
    canaryQuotaTag: quotaTag,
    ...overrides,
  };
}

test("strict projection retains only allowlisted content-free correlated fields", () => {
  const entries = [{
    timestamp: "2026-07-15T01:00:00Z",
    textPayload: JSON.stringify(scannerEvent({ statusCode: 200, statusClass: "2xx" })),
  }];

  const projected = projectCorrelatedScannerEvents(entries, { correlationId, operationTag });

  assert.deepEqual(projected, [scannerEvent({ statusCode: 200, statusClass: "2xx" })]);
  assert.equal(JSON.stringify(projected).includes(canaryId), false);
  assert.equal(JSON.stringify(projected).includes(quotaPrincipal), false);
});

test("evidence helper CLI executes projection and emits nothing on fail-closed input", () => {
  const entry = { jsonPayload: scannerEvent({ statusCode: 200 }) };
  const valid = spawnSync(
    process.execPath,
    [helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag],
    { input: JSON.stringify([entry]), encoding: "utf8" }
  );
  assert.equal(valid.status, 0, valid.stderr);
  assert.deepEqual(JSON.parse(valid.stdout), [entry.jsonPayload]);

  const invalid = spawnSync(
    process.execPath,
    [helperPath, "project-events", "--correlation", correlationId, "--operation", operationTag],
    { input: JSON.stringify([{ jsonPayload: scannerEvent({ unexpected: "secret" }) }]), encoding: "utf8" }
  );
  assert.notEqual(invalid.status, 0);
  assert.equal(invalid.stdout, "", "fail-closed CLI must not persist a partial projection");
});

test("strict projection rejects unexpected fields and sensitive encodings before output", () => {
  const unsafe = [
    scannerEvent({ unexpected: "value" }),
    scannerEvent({ appCheckToken: "token" }),
    scannerEvent({ app_check_token: "token" }),
    scannerEvent({ signedTransactionJWS: "header.payload.signature" }),
    scannerEvent({ signed_transaction_jws: "header.payload.signature" }),
    scannerEvent({ storeKitJWS: "header.payload.signature" }),
    scannerEvent({ store_kit_jws: "header.payload.signature" }),
    scannerEvent({ reason: "Authorization: Bearer secret" }),
    scannerEvent({ reason: "-----BEGIN PRIVATE KEY-----" }),
    scannerEvent({ reason: "ya29.oauth-secret" }),
    scannerEvent({ reason: "sk_revenuecat_secret_1234567890" }),
    scannerEvent({ reason: "headerpayload.signaturepayload.signaturesuffix" }),
    scannerEvent({ reason: `/9j/${"A".repeat(120)}` }),
    scannerEvent({ reason: `iVBORw0KGgo${"A".repeat(120)}` }),
    scannerEvent({ reason: "A".repeat(160) }),
    scannerEvent({ reason: "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijkl" }),
  ];

  for (const event of unsafe) {
    assert.throws(
      () => projectCorrelatedScannerEvents([{ jsonPayload: event }], { correlationId, operationTag }),
      /unsafe|unexpected|invalid/i
    );
  }
});

test("quota projection identifies only the correlated principal without retaining its document id", () => {
  const documents = [{
    name: `projects/test/databases/(default)/documents/mealScanRollingQuota/${quotaPrincipal}`,
    updateTime: "2026-07-15T01:00:01Z",
    fields: {
      dispatchTimestamps: {
        arrayValue: {
          values: [
            { timestampValue: "2026-07-14T01:00:00Z" },
            { timestampValue: "2026-07-15T01:00:00Z" },
          ],
        },
      },
      lifetimeUsed: { integerValue: "7" },
    },
  }];

  const snapshot = findCanaryQuotaSnapshot(documents, { canaryId, quotaTag });

  assert.deepEqual(snapshot, {
    canaryQuotaTag: quotaTag,
    exists: true,
    dispatchCount: 2,
    lifetimeUsed: 7,
    updateTime: "2026-07-15T01:00:01Z",
  });
  assert.equal(JSON.stringify(snapshot).includes(quotaPrincipal), false);
});

test("fresh canary proof requires affirmative auth, exact quota delta, cache miss, and one provider operation", () => {
  const events = [
    ...["app_check", "storekit_jws", "apple_current_status", "revenuecat_subscription"].map(
      (control) => scannerEvent({ eventType: "authorization_acceptance", outcome: "accepted", control })
    ),
    scannerEvent({ eventType: "quota_decision", outcome: "allowed", quotaDelta: 1 }),
    scannerEvent({ eventType: "cache_decision", outcome: "observed", cacheDisposition: "fresh_dispatch" }),
    scannerEvent({ eventType: "provider_call", outcome: "started", providerId: "google-gemini" }),
    scannerEvent({ eventType: "provider_call", outcome: "completed", providerId: "google-gemini" }),
    scannerEvent({ eventType: "request_result", outcome: "completed", statusCode: 200, statusClass: "2xx" }),
  ];
  const before = {
    canaryQuotaTag: quotaTag,
    exists: true,
    dispatchCount: 1,
    lifetimeUsed: 7,
    updateTime: "2026-07-14T01:00:00Z",
  };
  const after = { ...before, dispatchCount: 2, updateTime: "2026-07-15T01:00:01Z" };

  const summary = verifyCorrelatedPhase({ phase: "fresh-scan", events, quotaBefore: before, quotaAfter: after });

  assert.equal(summary.requestCompleted, 1);
  assert.equal(summary.quotaDelta, 1);
  assert.deepEqual(summary.authorizationControls, [
    "app_check",
    "storekit_jws",
    "apple_current_status",
    "revenuecat_subscription",
  ]);
});

test("exact reuse requires zero correlated events of every outcome and an unchanged exact quota snapshot", () => {
  const quota = {
    canaryQuotaTag: quotaTag,
    exists: true,
    dispatchCount: 2,
    lifetimeUsed: 7,
    updateTime: "2026-07-15T01:00:01Z",
  };
  assert.equal(
    verifyCorrelatedPhase({ phase: "exact-reuse", events: [], quotaBefore: quota, quotaAfter: quota }).eventCount,
    0
  );

  assert.throws(
    () => verifyCorrelatedPhase({
      phase: "exact-reuse",
      events: [scannerEvent({ eventType: "request_result", outcome: "rejected", statusCode: 401 })],
      quotaBefore: quota,
      quotaAfter: quota,
    }),
    /zero correlated events/i
  );
  assert.throws(
    () => verifyCorrelatedPhase({
      phase: "exact-reuse",
      events: [],
      quotaBefore: quota,
      quotaAfter: { ...quota, dispatchCount: 3 },
    }),
    /unchanged/i
  );
});

test("fresh proof fails closed when an affirmative control or exact quota delta is missing", () => {
  const minimal = [
    scannerEvent({ eventType: "quota_decision", outcome: "allowed", quotaDelta: 1 }),
    scannerEvent({ eventType: "cache_decision", outcome: "observed", cacheDisposition: "fresh_dispatch" }),
    scannerEvent({ eventType: "provider_call", outcome: "started" }),
    scannerEvent({ eventType: "provider_call", outcome: "completed" }),
    scannerEvent({ eventType: "request_result", outcome: "completed", statusCode: 200 }),
  ];
  const before = { canaryQuotaTag: quotaTag, exists: true, dispatchCount: 1, lifetimeUsed: 1, updateTime: "a" };
  const after = { ...before, dispatchCount: 2, updateTime: "b" };

  assert.throws(
    () => verifyCorrelatedPhase({ phase: "scan-as-new", events: minimal, quotaBefore: before, quotaAfter: after }),
    /authorization/i
  );
  assert.throws(
    () => verifyCorrelatedPhase({
      phase: "scan-as-new",
      events: [
        ...["app_check", "storekit_jws", "apple_current_status", "revenuecat_subscription"].map(
          (control) => scannerEvent({ eventType: "authorization_acceptance", outcome: "accepted", control })
        ),
        ...minimal.map((event) => event.eventType === "quota_decision" ? { ...event, quotaDelta: undefined } : event),
      ],
      quotaBefore: before,
      quotaAfter: after,
    }),
    /quota delta/i
  );
});
