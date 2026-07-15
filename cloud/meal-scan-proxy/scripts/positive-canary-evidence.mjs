#!/usr/bin/env node
import crypto from "node:crypto";
import { isDeepStrictEqual } from "node:util";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const EVENT_NAME = "meal_scan_scanner_event";
const EVENT_SCHEMA = "cyclebalance.meal_scan.operation.v1";
const HEX_64 = /^[a-f0-9]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SAFE_DIMENSION = /^[a-z0-9][a-z0-9_.-]{0,63}$/;
const EXPECTED_AUTHORIZATION_CONTROLS = Object.freeze([
  "app_check",
  "storekit_jws",
  "apple_current_status",
  "revenuecat_subscription",
]);
const STRING_FIELDS = new Set([
  "event",
  "severity",
  "schemaVersion",
  "eventType",
  "outcome",
  "control",
  "cacheDisposition",
  "localCacheDisposition",
  "providerId",
  "modelId",
  "tier",
  "budgetMode",
  "statusClass",
  "reason",
  "canaryCorrelationId",
  "canaryOperationTag",
  "canaryQuotaTag",
]);
const NUMBER_FIELDS = new Set([
  "statusCode",
  "latencyMs",
  "inputTokens",
  "outputTokens",
  "totalTokens",
  "estimatedCostUSD",
  "quotaUsed",
  "quotaLimit",
  "quotaRemaining",
  "stateAgeSeconds",
  "quotaDelta",
]);
const ALLOWED_EVENT_FIELDS = new Set([...STRING_FIELDS, ...NUMBER_FIELDS]);
const SENSITIVE_TEXT_PATTERNS = [
  /authorization\s*:\s*bearer/i,
  /-----BEGIN [A-Z ]+-----/,
  /\bya29\.[A-Za-z0-9_-]+/,
  /\b(?:sk|rc)_[A-Za-z0-9_-]{16,}\b/i,
  /[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/,
  /\/9j\/[A-Za-z0-9+/=]{16,}/,
  /iVBORw0KGgo[A-Za-z0-9+/=]{16,}/,
];

function fail(message) {
  throw new Error(message);
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function shannonEntropy(value) {
  const counts = new Map();
  for (const character of value) counts.set(character, (counts.get(character) ?? 0) + 1);
  return [...counts.values()].reduce((entropy, count) => {
    const probability = count / value.length;
    return entropy - (probability * Math.log2(probability));
  }, 0);
}

function rejectSensitiveText(value) {
  if (typeof value !== "string") return;
  if (SENSITIVE_TEXT_PATTERNS.some((pattern) => pattern.test(value))) {
    fail("unsafe sensitive content detected before evidence projection");
  }
}

function scannerPayload(entry) {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
    fail("invalid Cloud Logging entry");
  }
  if (entry.jsonPayload && typeof entry.jsonPayload === "object" && !Array.isArray(entry.jsonPayload)) {
    return entry.jsonPayload;
  }
  if (typeof entry.textPayload === "string") {
    try {
      const parsed = JSON.parse(entry.textPayload);
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
    } catch {
      rejectSensitiveText(entry.textPayload);
      return null;
    }
  }
  return null;
}

function validateEventValue(field, value) {
  if (STRING_FIELDS.has(field)) {
    if (typeof value !== "string") fail(`invalid ${field} field`);
    if (field !== "schemaVersion" || value !== EVENT_SCHEMA) rejectSensitiveText(value);
    if (
      !["canaryCorrelationId", "canaryOperationTag", "canaryQuotaTag", "schemaVersion"].includes(field) &&
      value.length >= 40 &&
      shannonEntropy(value) >= 4.2
    ) {
      fail(`unsafe high-entropy ${field} field`);
    }
  }
  if (NUMBER_FIELDS.has(field)) {
    if (!Number.isFinite(value) || value < 0) fail(`invalid ${field} field`);
  }
  if (["canaryCorrelationId", "canaryOperationTag", "canaryQuotaTag"].includes(field)) {
    if (!HEX_64.test(value)) fail(`invalid ${field} digest`);
    return;
  }
  if (field === "quotaDelta") {
    if (value !== 1) fail("invalid quotaDelta field");
    return;
  }
  if (field === "event" && value !== EVENT_NAME) fail("invalid event name");
  if (field === "severity" && value !== "INFO") fail("invalid scanner severity");
  if (field === "schemaVersion" && value !== EVENT_SCHEMA) fail("invalid scanner schema");
  if (field === "statusClass" && !/^[1-5]xx$/.test(value)) fail("invalid statusClass field");
  if (
    STRING_FIELDS.has(field) &&
    !["event", "severity", "schemaVersion", "statusClass", "canaryCorrelationId", "canaryOperationTag", "canaryQuotaTag"].includes(field) &&
    !SAFE_DIMENSION.test(value)
  ) {
    fail(`invalid ${field} dimension`);
  }
}

export function projectCorrelatedScannerEvents(entries, { correlationId, operationTag }) {
  if (!Array.isArray(entries)) fail("Cloud Logging input must be an array");
  if (!HEX_64.test(correlationId ?? "") || !HEX_64.test(operationTag ?? "")) {
    fail("invalid canary correlation arguments");
  }
  if (entries.length > 200) fail("canary log window exceeds the 200-entry bound");

  const events = [];
  for (const entry of entries) {
    const payload = scannerPayload(entry);
    if (!payload || payload.event !== EVENT_NAME) continue;
    const unexpected = Object.keys(payload).filter((field) => !ALLOWED_EVENT_FIELDS.has(field));
    if (unexpected.length > 0) fail(`unexpected scanner event field: ${unexpected[0]}`);
    for (const [field, value] of Object.entries(payload)) validateEventValue(field, value);
    if (
      payload.canaryCorrelationId !== correlationId ||
      payload.canaryOperationTag !== operationTag
    ) {
      fail("invalid or uncorrelated scanner event in canary window");
    }
    events.push(Object.fromEntries(
      Object.entries(payload).filter(([field]) => ALLOWED_EVENT_FIELDS.has(field))
    ));
  }
  return events;
}

function firestoreInteger(field, label) {
  if (field === undefined) return 0;
  const value = Number(field?.integerValue);
  if (!Number.isSafeInteger(value) || value < 0) fail(`invalid Firestore ${label}`);
  return value;
}

function dispatchCount(field, capturedAt) {
  if (field === undefined) return 0;
  const values = field?.arrayValue?.values;
  if (!Array.isArray(values)) fail("invalid Firestore dispatchTimestamps");
  const activeThreshold = Number.isFinite(capturedAt)
    ? capturedAt - (24 * 60 * 60 * 1_000)
    : null;
  let count = 0;
  for (const value of values) {
    if (typeof value?.timestampValue !== "string" || value.timestampValue.length > 64) {
      fail("invalid Firestore dispatch timestamp");
    }
    const timestamp = Date.parse(value.timestampValue);
    if (!Number.isFinite(timestamp)) fail("invalid Firestore dispatch timestamp");
    if (activeThreshold === null || timestamp >= activeThreshold) count += 1;
  }
  return count;
}

export function findCanaryQuotaSnapshot(input, { canaryId, quotaTag }) {
  if (!UUID.test(canaryId ?? "") || !HEX_64.test(quotaTag ?? "")) {
    fail("invalid quota correlation arguments");
  }
  const documents = Array.isArray(input) ? input : input?.documents ?? [];
  const capturedAt = Array.isArray(input) ? null : Date.parse(input?.capturedAt ?? "");
  if (!Array.isArray(documents)) fail("invalid Firestore quota response");
  const matches = [];
  for (const document of documents) {
    const name = document?.name;
    if (typeof name !== "string") fail("invalid Firestore quota document name");
    const principal = name.slice(name.lastIndexOf("/") + 1);
    if (!principal || sha256(`${canaryId}|${principal}`) !== quotaTag) continue;
    const fields = document.fields ?? {};
    matches.push({
      canaryQuotaTag: quotaTag,
      exists: true,
      dispatchCount: dispatchCount(fields.dispatchTimestamps, capturedAt),
      lifetimeUsed: firestoreInteger(fields.lifetimeUsed, "lifetimeUsed"),
      updateTime: typeof document.updateTime === "string" ? document.updateTime : null,
    });
  }
  if (matches.length > 1) fail("multiple quota documents matched one canary quota tag");
  return matches[0] ?? {
    canaryQuotaTag: quotaTag,
    exists: false,
    dispatchCount: 0,
    lifetimeUsed: 0,
    updateTime: null,
  };
}

function matchingEvents(events, eventType, predicate = () => true) {
  return events.filter((event) => event.eventType === eventType && predicate(event));
}

function requireExactlyOne(events, eventType, predicate, description) {
  const matches = matchingEvents(events, eventType, predicate);
  if (matches.length !== 1) fail(`expected exactly one ${description}`);
  return matches[0];
}

export function verifyCorrelatedPhase({ phase, events, quotaBefore, quotaAfter }) {
  if (!Array.isArray(events)) fail("invalid projected event input");
  if (!["exact-reuse", "fresh-scan", "scan-as-new"].includes(phase)) fail("invalid canary phase");
  if (phase === "exact-reuse") {
    if (events.length !== 0) fail("exact reuse requires zero correlated events of every outcome");
    if (!isDeepStrictEqual(quotaBefore, quotaAfter)) {
      fail("exact reuse requires an unchanged exact quota snapshot");
    }
    return { phase, eventCount: 0, quotaUnchanged: true };
  }

  const authorizationControls = matchingEvents(
    events,
    "authorization_acceptance",
    (event) => event.outcome === "accepted"
  ).map((event) => event.control);
  if (!isDeepStrictEqual(authorizationControls, EXPECTED_AUTHORIZATION_CONTROLS)) {
    fail("fresh canary requires exactly four affirmative authorization controls");
  }
  const request = requireExactlyOne(
    events,
    "request_result",
    (event) => event.outcome === "completed" && event.statusCode === 200,
    "completed request result"
  );
  const quota = requireExactlyOne(
    events,
    "quota_decision",
    (event) => event.outcome === "allowed" && event.quotaDelta === 1,
    "allowed quota delta of one"
  );
  requireExactlyOne(
    events,
    "cache_decision",
    (event) => event.cacheDisposition === "fresh_dispatch",
    "fresh cache dispatch"
  );
  if (matchingEvents(events, "cache_decision", (event) => /^server_hit/.test(event.cacheDisposition ?? "")).length) {
    fail("fresh canary cannot use a server cache hit");
  }
  requireExactlyOne(events, "provider_call", (event) => event.outcome === "started", "provider start");
  requireExactlyOne(events, "provider_call", (event) => event.outcome === "completed", "provider completion");

  if (!HEX_64.test(quota.canaryQuotaTag ?? "")) fail("fresh canary quota tag is missing");
  if (
    quotaBefore?.canaryQuotaTag !== quota.canaryQuotaTag ||
    quotaAfter?.canaryQuotaTag !== quota.canaryQuotaTag
  ) {
    fail("quota snapshots are not bound to the correlated principal");
  }
  if (
    !Number.isSafeInteger(quotaBefore?.dispatchCount) ||
    !Number.isSafeInteger(quotaAfter?.dispatchCount) ||
    quotaAfter.dispatchCount - quotaBefore.dispatchCount !== 1
  ) {
    fail("fresh canary exact quota delta is not one");
  }
  return {
    phase,
    eventCount: events.length,
    requestCompleted: 1,
    requestStatusCode: request.statusCode,
    authorizationControls: [...EXPECTED_AUTHORIZATION_CONTROLS],
    quotaDelta: 1,
    cacheFreshDispatch: 1,
    providerStarted: 1,
    providerCompleted: 1,
    canaryQuotaTag: quota.canaryQuotaTag,
  };
}

function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined) fail("invalid command arguments");
    values[key.slice(2)] = value;
  }
  return values;
}

function readStandardInputJSON() {
  const value = readFileSync(0, "utf8");
  return JSON.parse(value || "null");
}

function main() {
  const [command, ...argv] = process.argv.slice(2);
  const args = parseArguments(argv);
  const input = readStandardInputJSON();
  let output;
  if (command === "project-events") {
    output = projectCorrelatedScannerEvents(input, {
      correlationId: args.correlation,
      operationTag: args.operation,
    });
  } else if (command === "quota-snapshot") {
    output = findCanaryQuotaSnapshot(input, {
      canaryId: args["canary-id"],
      quotaTag: args["quota-tag"],
    });
  } else if (command === "verify-phase") {
    output = verifyCorrelatedPhase(input);
  } else {
    fail("unknown evidence command");
  }
  process.stdout.write(`${JSON.stringify(output)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`ERROR: ${error.message}\n`);
    process.exitCode = 1;
  }
}
