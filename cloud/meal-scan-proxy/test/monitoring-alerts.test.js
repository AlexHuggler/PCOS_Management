import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const proxyDirectory = path.resolve(testDirectory, "..");
const scriptPath = path.join(proxyDirectory, "scripts/deploy-monitoring-alerts.sh");
const readmePath = path.join(proxyDirectory, "README.md");
const scriptExists = existsSync(scriptPath);
const scriptSource = scriptExists ? readFileSync(scriptPath, "utf8") : "";
const readmeSource = readFileSync(readmePath, "utf8");

test("monitoring deployment script is staged and shell-safe by construction", () => {
  assert.equal(scriptExists, true, "deploy-monitoring-alerts.sh must be version controlled");
  assert.match(scriptSource, /^#!\/usr\/bin\/env bash/m);
  assert.match(scriptSource, /set -euo pipefail/);
  assert.match(scriptSource, /trap ['"]rm -rf/);
});

test("monitoring deployment is pinned, validation-only by default, and APPLY=true gated", () => {
  assert.match(scriptSource, /PINNED_PROJECT_ID="cyclebalance-prod-20260710"/);
  assert.match(scriptSource, /PROJECT_ID="\$\{PROJECT_ID:-\$PINNED_PROJECT_ID\}"/);
  assert.match(scriptSource, /APPLY="\$\{APPLY:-false\}"/);
  assert.match(scriptSource, /\[\[ "\$APPLY" != "true" \]\]/);
  assert.match(scriptSource, /validation-only/i);
  assert.match(scriptSource, /upsert_log_metric/);
  assert.match(scriptSource, /gcloud logging metrics describe/);
  assert.match(scriptSource, /gcloud logging metrics update/);
  assert.match(scriptSource, /gcloud logging metrics create/);
  assert.match(scriptSource, /upsert_alert_policy/);
  assert.match(scriptSource, /gcloud monitoring policies list/);
  assert.match(scriptSource, /gcloud monitoring policies update/);
  assert.match(scriptSource, /gcloud monitoring policies create/);
});

test("live alert application requires an owner notification channel before any mutation", () => {
  assert.match(scriptSource, /NOTIFICATION_CHANNEL_NAME="\$\{NOTIFICATION_CHANNEL_NAME:-\}"/);
  assert.match(scriptSource, /notificationChannels/);
  assert.match(scriptSource, /projects\/\$PINNED_PROJECT_ID\/notificationChannels/);

  const scratchDirectory = mkdtempSync(path.join(tmpdir(), "cyclebalance-monitoring-channel-test-"));
  const markerPath = path.join(scratchDirectory, "gcloud-was-invoked");
  const fakeGcloudPath = path.join(scratchDirectory, "gcloud");
  writeFileSync(fakeGcloudPath, `#!/bin/sh\ntouch "${markerPath}"\nexit 99\n`, { mode: 0o700 });
  chmodSync(fakeGcloudPath, 0o700);
  try {
    const result = spawnSync("bash", [scriptPath], {
      cwd: proxyDirectory,
      encoding: "utf8",
      env: {
        ...process.env,
        APPLY: "true",
        PROJECT_ID: "cyclebalance-prod-20260710",
        NOTIFICATION_CHANNEL_NAME: "",
        PATH: `${scratchDirectory}:${path.dirname(process.execPath)}:${process.env.PATH}`,
      },
    });

    assert.notEqual(result.status, 0);
    assert.equal(existsSync(markerPath), false, "a missing owner channel must fail before gcloud");
    assert.match(`${result.stdout}\n${result.stderr}`, /notification channel/i);
  } finally {
    rmSync(scratchDirectory, { recursive: true, force: true });
  }
});

test("monitoring policies encode the exact scanner thresholds and windows", () => {
  assert.match(scriptSource, /PROVIDER_DISPATCH_THRESHOLD_PER_MINUTE=60/);
  assert.match(scriptSource, /ERROR_RATIO_THRESHOLD="0\.05"/);
  assert.match(scriptSource, /ERROR_RATIO_DURATION_SECONDS=600/);
  assert.match(scriptSource, /AUTH_REJECTION_THRESHOLD_PER_MINUTE=20/);
  assert.match(scriptSource, /increase\([^\n]+\[1m\]\)\)\s*>=\s*60/);
  assert.match(scriptSource, />\s*0\.05/);
  assert.match(scriptSource, /\[10m\]/);
  assert.match(scriptSource, /"duration":\s*"600s"/);
  assert.match(scriptSource, /increase\([^\n]+\[1m\]\)\)\s*>\s*20/);
  assert.match(scriptSource, /eventType="budget_state"/);
  assert.match(scriptSource, /outcome=~"transitioned\|stale\|unavailable"/);
  assert.match(
    scriptSource,
    /\(jsonPayload\.outcome=~"transitioned\|stale\|unavailable" OR jsonPayload\.budgetMode=~"alert\|degraded\|disabled"\)/
  );
});

test("monitoring filters use only identifier-free scanner event fields", () => {
  for (const field of [
    "jsonPayload.eventType",
    "jsonPayload.outcome",
    "jsonPayload.control",
    "jsonPayload.statusClass",
    "jsonPayload.budgetMode",
  ]) {
    assert.match(scriptSource, new RegExp(field.replace(".", "\\.")));
  }
  assert.doesNotMatch(
    scriptSource,
    /requestId|signedTransactionJWS|originalTransactionId|transactionId|principal|appUserId|imageHash|image\.base64|appCheckToken|apiKey/
  );
  assert.doesNotMatch(scriptSource, /@[A-Za-z0-9.-]+|hooks\.slack|pagerduty|api\.opsgenie/i);
  assert.doesNotMatch(scriptSource, /-----BEGIN [A-Z ]*PRIVATE KEY-----|AIza[0-9A-Za-z_-]{20,}/);
});

test("monitoring script never changes Cloud Run access or scanner activation", () => {
  assert.doesNotMatch(scriptSource, /gcloud\s+run/);
  assert.doesNotMatch(scriptSource, /MEAL_SCAN_ENABLED\s*=\s*true/);
  assert.doesNotMatch(scriptSource, /allow-unauthenticated|no-invoker-iam-check/);
});

test("default execution validates resources without invoking gcloud mutation", () => {
  assert.equal(scriptExists, true);
  const scratchDirectory = mkdtempSync(path.join(tmpdir(), "cyclebalance-monitoring-test-"));
  const markerPath = path.join(scratchDirectory, "gcloud-was-invoked");
  const fakeGcloudPath = path.join(scratchDirectory, "gcloud");
  writeFileSync(fakeGcloudPath, `#!/bin/sh\ntouch "${markerPath}"\nexit 99\n`, { mode: 0o700 });
  chmodSync(fakeGcloudPath, 0o700);
  try {
    const result = spawnSync("bash", [scriptPath], {
      cwd: proxyDirectory,
      encoding: "utf8",
      env: {
        ...process.env,
        APPLY: "false",
        PROJECT_ID: "cyclebalance-prod-20260710",
        PATH: `${scratchDirectory}:${path.dirname(process.execPath)}:${process.env.PATH}`,
      },
    });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(existsSync(markerPath), false, "validation-only mode must never invoke gcloud");
    assert.match(`${result.stdout}\n${result.stderr}`, /validation-only/i);
    assert.match(result.stdout, /CycleBalance Meal Scan - Budget State/);
    assert.match(result.stdout, /CycleBalance Meal Scan - Provider Dispatch 60 per minute/);
    assert.match(result.stdout, /CycleBalance Meal Scan - 5xx Ratio over 5 percent for 10 minutes/);
    assert.match(result.stdout, /CycleBalance Meal Scan - Auth Rejections over 20 per minute/);
  } finally {
    rmSync(scratchDirectory, { recursive: true, force: true });
  }
});

test("even dry-run rejects a project other than the pinned production project", () => {
  assert.equal(scriptExists, true);
  const result = spawnSync("bash", [scriptPath], {
    cwd: proxyDirectory,
    encoding: "utf8",
    env: {
      ...process.env,
      APPLY: "false",
      PROJECT_ID: "attacker-project",
      GCLOUD_BIN: "/usr/bin/false",
    },
  });

  assert.notEqual(result.status, 0);
  assert.match(`${result.stdout}\n${result.stderr}`, /pinned production project/i);
});

test("README documents identifier-free events and approval-gated monitoring deployment", () => {
  assert.match(readmeSource, /meal_scan_scanner_event/);
  assert.match(readmeSource, /authorization_rejection/);
  assert.match(readmeSource, /request_gate_decision/);
  assert.match(readmeSource, /quota_decision/);
  assert.match(readmeSource, /global_dispatch_decision/);
  assert.match(readmeSource, /cache_decision/);
  assert.match(readmeSource, /provider_call/);
  assert.match(readmeSource, /request_result/);
  assert.match(readmeSource, /not_observed/);
  assert.match(readmeSource, /deploy-monitoring-alerts\.sh/);
  assert.match(readmeSource, /APPLY=true/);
  assert.match(readmeSource, /NOTIFICATION_CHANNEL_NAME/);
  assert.match(readmeSource, /60 fresh provider calls per minute/);
  assert.match(readmeSource, /5xx ratio above 5% for 10 minutes/);
  assert.match(readmeSource, /more than 20 combined App Check and StoreKit\/JWS rejections per minute/);
  assert.match(readmeSource, /MEAL_SCAN_ENABLED=false/);
  assert.match(readmeSource, /ALLOW_UNAUTHENTICATED=false/);
  assert.match(
    readmeSource,
    /never include raw JWS, original transaction IDs, pseudonymous principals, request IDs, image hashes or bytes, App Check tokens, API keys, or user-entered content/i
  );
});
