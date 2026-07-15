import assert from "node:assert/strict";
import crypto from "node:crypto";
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const proxyDirectory = path.resolve(testDirectory, "..");
const scriptPath = path.join(proxyDirectory, "scripts/deploy-cloud-run.sh");

const expectedBaseEnvironment = Object.freeze({
  NODE_ENV: "production",
  APP_CHECK_REQUIRED: "true",
  FIREBASE_APP_ID: "1:947929010052:ios:6e68c8645a6a6b5e3057d1",
  APPLE_BUNDLE_ID: "alex.PCOS",
  APPLE_APP_ID: "6760353511",
  APPLE_ALLOWED_PRODUCT_IDS: "cyclebalance.premium.monthly,cyclebalance.premium.annual",
  APPLE_IAP_KEY_ID: "ABCD1234",
  APPLE_IAP_ISSUER_ID: "12345678-1234-1234-1234-123456789abc",
  REVENUECAT_PROJECT_ID: "proj8da4e000",
  REVENUECAT_ENTITLEMENT_ID: "CycleBalance Unlimited",
  REVENUECAT_TIMEOUT_MS: "3000",
  MEAL_SCAN_QUOTA_STORE: "firestore",
  MEAL_SCAN_QUOTA_COLLECTION: "mealScanRollingQuota",
  MEAL_SCAN_RESULT_CACHE: "firestore",
  MEAL_SCAN_RESULT_CACHE_COLLECTION: "mealScanEstimateCache",
  MEAL_SCAN_IDEMPOTENCY_STORE: "firestore",
  MEAL_SCAN_IDEMPOTENCY_COLLECTION: "mealScanIdempotency",
  MEAL_SCAN_IDEMPOTENCY_PENDING_TTL_MS: "30000",
  MEAL_SCAN_REQUEST_GATE: "firestore",
  MEAL_SCAN_REQUEST_GATE_COLLECTION: "mealScanRequestGate",
  MEAL_SCAN_REQUESTS_PER_MINUTE_LIMIT: "30",
  MEAL_SCAN_REQUESTS_PER_DAY_LIMIT: "200",
  MEAL_SCAN_GLOBAL_REQUESTS_PER_MINUTE_LIMIT: "300",
  MEAL_SCAN_GLOBAL_REQUESTS_PER_DAY_LIMIT: "3000",
  MEAL_SCAN_PRINCIPAL_ATTEMPT_STORE: "firestore",
  MEAL_SCAN_PRINCIPAL_ATTEMPT_COLLECTION: "mealScanPrincipalAttempts",
  MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_MINUTE_LIMIT: "3",
  MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_24_HOURS_LIMIT: "30",
  MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_MINUTE_LIMIT: "60",
  MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_24_HOURS_LIMIT: "1000",
  MEAL_SCAN_BUDGET_STORE: "firestore",
  MEAL_SCAN_BUDGET_STATE_MAX_AGE_SECONDS: "86400",
  MEAL_SCAN_RESULT_CACHE_TTL_SECONDS: "86400",
  MEAL_SCAN_RESULT_LEASE_TTL_MS: "30000",
  MEAL_SCAN_CONTROL_COLLECTION: "mealScanControls",
  MEAL_SCAN_CONTROL_DOCUMENT: "global",
  MEAL_SCAN_CONTROL_CACHE_TTL_MS: "30000",
  MEAL_SCAN_DAILY_LIMIT: "10",
  MEAL_SCAN_TRIAL_DAILY_LIMIT: "5",
  MEAL_SCAN_TRIAL_TOTAL_LIMIT: "25",
  MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD: "15",
  MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD: "20",
  MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD: "25",
  MAX_BODY_BYTES: "2200000",
  MAX_IMAGE_BYTES: "1500000",
  MAX_IMAGE_PIXELS: "12000000",
  MAX_CANONICAL_IMAGE_BYTES: "750000",
  APP_CHECK_TIMEOUT_MS: "5000",
  APPLE_STATUS_TIMEOUT_MS: "5000",
  GEMINI_TIMEOUT_MS: "12000",
});

const expectedSecrets = Object.freeze({
  GEMINI_API_KEY: "cyclebalance-gemini-api-key:1",
  MEAL_SCAN_PRINCIPAL_HMAC_SECRET: "cyclebalance-meal-scan-principal-hmac:1",
  APPLE_IAP_PRIVATE_KEY: "cyclebalance-app-store-iap-private-key:1",
  REVENUECAT_SECRET_API_KEY: "cyclebalance-revenuecat-secret-api-key:1",
});

function argumentAfter(args, flag) {
  const index = args.indexOf(flag);
  assert.notEqual(index, -1, `missing ${flag}`);
  assert.ok(index + 1 < args.length, `missing value for ${flag}`);
  return args[index + 1];
}

function parseAssignments(raw, separator, prefix = "") {
  assert.ok(raw.startsWith(prefix), `missing assignment prefix ${prefix}`);
  return Object.fromEntries(raw.slice(prefix.length).split(separator).map((assignment) => {
    const equalsIndex = assignment.indexOf("=");
    assert.ok(equalsIndex > 0, `malformed assignment: ${assignment}`);
    return [assignment.slice(0, equalsIndex), assignment.slice(equalsIndex + 1)];
  }));
}

function runCanary(overrides = {}) {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-canary-deploy-"));
  const bin = path.join(directory, "bin");
  const log = path.join(directory, "commands.log");
  const gcloudArgsLog = path.join(directory, "gcloud-args.log");
  const sourceRoot = path.join(directory, "approved-source");
  const sourceDirectory = path.join(sourceRoot, "cloud/meal-scan-proxy");
  const sourceArchive = path.join(directory, "approved-source.tar");
  const serviceFixture = path.join(directory, "service.json");
  const buildFixture = path.join(directory, "build.json");
  mkdirSync(bin);
  mkdirSync(sourceDirectory, { recursive: true });
  writeFileSync(path.join(sourceDirectory, "package.json"), '{"name":"approved-canary-source"}\n');
  const archiveResult = spawnSync("tar", ["-cf", sourceArchive, "-C", sourceRoot, "cloud/meal-scan-proxy"], {
    encoding: "utf8",
  });
  assert.equal(archiveResult.status, 0, archiveResult.stderr);
  chmodSync(sourceArchive, 0o400);
  const sourceArchiveSha256 = crypto.createHash("sha256").update(readFileSync(sourceArchive)).digest("hex");
  const buildId = "3b68eb76-3ce2-4c71-b75f-f08dc70a9e13";
  const revision = "cyclebalance-meal-scan-proxy-00099-canary";
  const imageName = "us-central1-docker.pkg.dev/cyclebalance-prod-20260710/cloud-run-source-deploy/cyclebalance-meal-scan-proxy";
  const imageDigest = `sha256:${"d".repeat(64)}`;
  const buildName = `projects/cyclebalance-prod-20260710/locations/us-central1/builds/${buildId}`;
  const buildServiceAccount = "projects/cyclebalance-prod-20260710/serviceAccounts/cyclebalance-cloud-build@cyclebalance-prod-20260710.iam.gserviceaccount.com";
  const sourceLocation = "gs://run-sources-cyclebalance-prod-20260710-us-central1/services/cyclebalance-meal-scan-proxy/source.tgz#1731549123456789";
  writeFileSync(serviceFixture, JSON.stringify({
    metadata: { annotations: {
      "run.googleapis.com/build-id": buildId,
      "run.googleapis.com/build-name": buildName,
      "run.googleapis.com/build-service-account": buildServiceAccount,
      "run.googleapis.com/build-source-location": sourceLocation,
    } },
    spec: { template: { metadata: { name: revision }, spec: { containers: [{ image: `${imageName}@${imageDigest}` }] } } },
    status: {
      url: "https://canary.example.run.app",
      latestCreatedRevisionName: revision,
      latestReadyRevisionName: revision,
    },
  }));
  writeFileSync(buildFixture, JSON.stringify({
    id: buildId,
    name: buildName,
    status: "SUCCESS",
    serviceAccount: buildServiceAccount,
    source: { storageSource: {
      bucket: "run-sources-cyclebalance-prod-20260710-us-central1",
      object: "services/cyclebalance-meal-scan-proxy/source.tgz",
      generation: "1731549123456789",
    } },
    results: { images: [{ name: imageName, digest: imageDigest }] },
  }));
  writeFileSync(path.join(bin, "gcloud"), `#!/usr/bin/env bash
printf 'gcloud %s\n' "$*" >> "$COMMAND_LOG"
{
  printf 'gcloud-args'
  printf '\\t%s' "$@"
  printf '\\n'
} >> "$GCLOUD_ARGS_LOG"
if [[ "$1 $2" == "run deploy" && "\${MUTATE_SOURCE_DURING_DEPLOY:-false}" == "true" ]]; then
  previous=""
  for argument in "$@"; do
    if [[ "$previous" == "--source" ]]; then
      chmod u+w "$argument/package.json"
      printf '{"mutated":true}\n' >"$argument/package.json"
      break
    fi
    previous="$argument"
  done
fi
if [[ "$*" == *"run services describe"* && "$*" == *"--format=json"* ]]; then
  cat "$SERVICE_FIXTURE"
elif [[ "$*" == *"run services describe"* ]]; then
  printf 'https://canary.example.run.app\n'
elif [[ "$*" == *"builds describe"* ]]; then
  cat "$BUILD_FIXTURE"
fi
`);
  writeFileSync(path.join(bin, "curl"), `#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$COMMAND_LOG"
if [[ "\${ALLOW_UNAUTHENTICATED:-false}" == "true" ]]; then printf '401'; else printf '403'; fi
`);
  writeFileSync(path.join(bin, "git"), `#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$COMMAND_LOG"
if [[ "$*" == *"rev-parse HEAD"* ]]; then
  printf '%s\n' "$FAKE_GIT_HEAD"
elif [[ "$*" == *"status --porcelain --untracked-files=all"* ]]; then
  printf '%s' "$FAKE_GIT_STATUS"
elif [[ "$*" == *"archive --format=tar"* ]]; then
  cat "$FAKE_GIT_ARCHIVE"
else
  exit 98
fi
`);
  chmodSync(path.join(bin, "gcloud"), 0o755);
  chmodSync(path.join(bin, "curl"), 0o755);
  chmodSync(path.join(bin, "git"), 0o755);
  const result = spawnSync("bash", [scriptPath], {
    cwd: proxyDirectory,
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${bin}:${path.dirname(process.execPath)}:/usr/bin:/bin`,
      COMMAND_LOG: log,
      GCLOUD_ARGS_LOG: gcloudArgsLog,
      SERVICE_FIXTURE: serviceFixture,
      BUILD_FIXTURE: buildFixture,
      DEPLOY_MODE: "canary",
      PROJECT_ID: "cyclebalance-prod-20260710",
      REGION: "us-central1",
      SERVICE_NAME: "cyclebalance-meal-scan-proxy",
      GEMINI_SECRET_VERSION: "1",
      PRINCIPAL_HMAC_SECRET_VERSION: "1",
      APPLE_IAP_PRIVATE_KEY_SECRET_VERSION: "1",
      REVENUECAT_SECRET_VERSION: "1",
      APPLE_IAP_KEY_ID: "ABCD1234",
      APPLE_IAP_ISSUER_ID: "12345678-1234-1234-1234-123456789abc",
      MEAL_SCAN_ENABLED: "true",
      ALLOW_UNAUTHENTICATED: "true",
      MEAL_SCAN_CANARY_CORRELATION_SHA256: "a".repeat(64),
      APPROVED_SOURCE_COMMIT: "c".repeat(40),
      CANARY_SOURCE_ARCHIVE: sourceArchive,
      CANARY_SOURCE_ARCHIVE_SHA256: sourceArchiveSha256,
      FAKE_GIT_HEAD: "c".repeat(40),
      FAKE_GIT_STATUS: "",
      FAKE_GIT_ARCHIVE: sourceArchive,
      ...overrides,
    },
  });
  const commands = existsSync(log) ? readFileSync(log, "utf8") : "";
  const gcloudCalls = existsSync(gcloudArgsLog)
    ? readFileSync(gcloudArgsLog, "utf8").trim().split("\n").filter(Boolean).map((line) => {
      const [marker, ...args] = line.split("\t");
      assert.equal(marker, "gcloud-args");
      return args;
    })
    : [];
  rmSync(directory, { recursive: true, force: true });
  return { result, commands, gcloudCalls };
}

test("canary deploy emits the complete pinned runtime contract for enabled and disabled phases", () => {
  for (const phase of [
    {
      enabled: true,
      authFlag: "--allow-unauthenticated",
      invokerFlag: "--no-invoker-iam-check",
      correlation: "a".repeat(64),
    },
    {
      enabled: false,
      authFlag: "--no-allow-unauthenticated",
      invokerFlag: "--invoker-iam-check",
      correlation: "",
    },
  ]) {
    const { result, gcloudCalls } = runCanary({
      MEAL_SCAN_ENABLED: String(phase.enabled),
      ALLOW_UNAUTHENTICATED: String(phase.enabled),
      MEAL_SCAN_CANARY_CORRELATION_SHA256: phase.correlation,
    });
    assert.equal(result.status, 0, result.stderr);

    const deployArgs = gcloudCalls.find((args) => args[0] === "run" && args[1] === "deploy");
    assert.ok(deployArgs, "missing Cloud Run deploy command");
    const source = argumentAfter(deployArgs, "--source");
    const environmentArgument = argumentAfter(deployArgs, "--set-env-vars");
    const secretsArgument = argumentAfter(deployArgs, "--set-secrets");

    assert.match(source, /^\/.*\/cyclebalance-canary-source\.[^/]+\/cloud\/meal-scan-proxy$/);
    assert.notEqual(source, proxyDirectory, "canary must deploy only from the sealed source snapshot");
    assert.deepEqual(
      parseAssignments(environmentArgument, "@", "^@^"),
      {
        ...expectedBaseEnvironment,
        MEAL_SCAN_ENABLED: String(phase.enabled),
        ...(phase.enabled ? { MEAL_SCAN_CANARY_CORRELATION_SHA256: phase.correlation } : {}),
      },
    );
    assert.deepEqual(parseAssignments(secretsArgument, ","), expectedSecrets);
    for (const secretReference of Object.values(expectedSecrets)) {
      assert.match(secretReference, /:[1-9][0-9]*$/, `secret version must be numeric: ${secretReference}`);
    }

    assert.deepEqual(deployArgs, [
      "run", "deploy", "cyclebalance-meal-scan-proxy",
      "--project", "cyclebalance-prod-20260710",
      "--region", "us-central1",
      "--source", source,
      "--service-account", "cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710.iam.gserviceaccount.com",
      "--build-service-account", "projects/cyclebalance-prod-20260710/serviceAccounts/cyclebalance-cloud-build@cyclebalance-prod-20260710.iam.gserviceaccount.com",
      "--set-env-vars", environmentArgument,
      "--set-secrets", secretsArgument,
      "--cpu", "1",
      "--memory", "512Mi",
      "--min-instances", "0",
      "--max-instances", "2",
      "--concurrency", "20",
      "--timeout", "30s",
      "--execution-environment", "gen2",
      "--no-automatic-updates",
      "--ingress", "all",
      "--quiet",
      phase.authFlag,
      phase.invokerFlag,
    ]);

    const updateArgs = gcloudCalls.find((args) => args[0] === "run" && args[1] === "services" && args[2] === "update");
    assert.deepEqual(updateArgs, [
      "run", "services", "update", "cyclebalance-meal-scan-proxy",
      "--project", "cyclebalance-prod-20260710",
      "--region", "us-central1",
      "--quiet",
      phase.invokerFlag,
    ]);
  }
});

test("canary deploy touches only pinned Cloud Run state and skips global config plus Firestore Rules", () => {
  const { result, commands } = runCanary();

  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(commands, /gcloud config set/);
  assert.doesNotMatch(commands, /gcloud firestore|firebaserules\.googleapis\.com|\/rulesets/i);
  assert.match(commands, /gcloud run deploy cyclebalance-meal-scan-proxy/);
  assert.match(commands, /gcloud run services update cyclebalance-meal-scan-proxy/);
  assert.match(commands, /curl --disable --silent/, "readiness probe must ignore user curl configuration");
  assert.match(
    commands,
    /--service-account cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710\.iam\.gserviceaccount\.com/
  );
  assert.match(
    commands,
    /--build-service-account projects\/cyclebalance-prod-20260710\/serviceAccounts\/cyclebalance-cloud-build@cyclebalance-prod-20260710\.iam\.gserviceaccount\.com/
  );
  for (const expectedSecret of [
    "GEMINI_API_KEY=cyclebalance-gemini-api-key:1",
    "MEAL_SCAN_PRINCIPAL_HMAC_SECRET=cyclebalance-meal-scan-principal-hmac:1",
    "APPLE_IAP_PRIVATE_KEY=cyclebalance-app-store-iap-private-key:1",
    "REVENUECAT_SECRET_API_KEY=cyclebalance-revenuecat-secret-api-key:1",
  ]) {
    assert.ok(commands.includes(expectedSecret), `missing pinned secret reference ${expectedSecret}`);
  }
  assert.match(commands, new RegExp(`MEAL_SCAN_CANARY_CORRELATION_SHA256=${"a".repeat(64)}`));
});

test("disabled canary rollback removes the correlation environment value", () => {
  const { result, commands } = runCanary({
    MEAL_SCAN_ENABLED: "false",
    ALLOW_UNAUTHENTICATED: "false",
    MEAL_SCAN_CANARY_CORRELATION_SHA256: "",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(commands, /MEAL_SCAN_CANARY_CORRELATION_SHA256=/);
});

test("disabled rollback reuses the sealed approved source even after the checkout becomes dirty", () => {
  const { result, commands } = runCanary({
    MEAL_SCAN_ENABLED: "false",
    ALLOW_UNAUTHENTICATED: "false",
    MEAL_SCAN_CANARY_CORRELATION_SHA256: "",
    FAKE_GIT_STATUS: " M cloud/meal-scan-proxy/src/server.js\n",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(commands, /git .*archive --format=tar/);
  assert.match(commands, /gcloud run deploy cyclebalance-meal-scan-proxy/);
});

test("canary source deployment uses a private read-only snapshot instead of the mutable checkout", () => {
  const { result, commands } = runCanary();
  assert.equal(result.status, 0, result.stderr);
  const deployLine = commands.split("\n").find((line) => /gcloud run deploy/.test(line)) ?? "";
  assert.match(deployLine, /--source \/.*cyclebalance-canary-source\./);
  assert.doesNotMatch(deployLine, new RegExp(proxyDirectory.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
});

test("canary deploy detects any source snapshot mutation during gcloud packaging", () => {
  const { result } = runCanary({ MUTATE_SOURCE_DURING_DEPLOY: "true" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /snapshot changed or became writable while gcloud packaged it/i);
});

test("canary deploy revalidates the approved clean source at the gcloud mutation boundary", () => {
  for (const overrides of [
    { FAKE_GIT_HEAD: "d".repeat(40) },
    { FAKE_GIT_STATUS: " M cloud/meal-scan-proxy/src/server.js\n" },
    { APPROVED_SOURCE_COMMIT: "short" },
  ]) {
    const { result, commands } = runCanary(overrides);
    assert.notEqual(result.status, 0, JSON.stringify(overrides));
    assert.doesNotMatch(commands, /gcloud run deploy/);
  }

  const { result, commands } = runCanary();
  assert.equal(result.status, 0, result.stderr);
  const lines = commands.trim().split("\n");
  const sourceStatusIndex = lines.findLastIndex((line) => /git .*status --porcelain --untracked-files=all/.test(line));
  const deployIndex = lines.findIndex((line) => /gcloud run deploy/.test(line));
  assert.ok(sourceStatusIndex >= 0 && sourceStatusIndex < deployIndex, "source status was not rechecked before deploy");
});

test("canary deploy rejects identity drift and missing or malformed correlation before mutation", () => {
  for (const overrides of [
    { PROJECT_ID: "other-project" },
    { REGION: "europe-west1" },
    { SERVICE_NAME: "other-service" },
    { SERVICE_ACCOUNT_NAME: "other-runtime" },
    { BUILD_SERVICE_ACCOUNT_NAME: "other-builder" },
    { GEMINI_SECRET_NAME: "other-gemini" },
    { PRINCIPAL_HMAC_SECRET_NAME: "other-principal" },
    { APPLE_IAP_PRIVATE_KEY_SECRET_NAME: "other-apple" },
    { REVENUECAT_SECRET_NAME: "other-revenuecat" },
    { MEAL_SCAN_CANARY_CORRELATION_SHA256: "" },
    { MEAL_SCAN_CANARY_CORRELATION_SHA256: "not-a-digest" },
  ]) {
    const { result, commands } = runCanary(overrides);
    assert.notEqual(result.status, 0, JSON.stringify(overrides));
    assert.doesNotMatch(commands, /gcloud run (deploy|services update)/);
  }
});
