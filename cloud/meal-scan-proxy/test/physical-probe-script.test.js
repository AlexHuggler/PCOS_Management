import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const proxyDirectory = path.resolve(testDirectory, "..");
const repositoryRoot = path.resolve(proxyDirectory, "../..");
const scriptPath = path.join(proxyDirectory, "scripts/run-physical-app-check-probe.sh");
const projectPath = path.join(repositoryRoot, "project.yml");
const scriptSource = readFileSync(scriptPath, "utf8");
const projectSource = readFileSync(projectPath, "utf8");

function runScript(environment = {}) {
  return spawnSync("bash", [scriptPath], {
    cwd: repositoryRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      DRY_RUN: "true",
      ...environment,
    },
  });
}

function callSourcedFunction(functionCall) {
  return spawnSync("bash", ["-c", `source "$1"; ${functionCall}`, "probe-test", scriptPath], {
    cwd: repositoryRoot,
    encoding: "utf8",
    env: process.env,
  });
}

function withJsonFixture(value, callback) {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-probe-test-"));
  const fixturePath = path.join(directory, "fixture.json");
  writeFileSync(fixturePath, JSON.stringify(value));
  try {
    return callback(fixturePath);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test("dry run pins the production project and service", () => {
  const defaultRun = runScript();
  assert.equal(defaultRun.status, 0, defaultRun.stderr);
  assert.match(defaultRun.stdout, /cyclebalance-prod-20260710/);
  assert.match(defaultRun.stdout, /cyclebalance-meal-scan-proxy/);

  for (const override of [
    { PROJECT_ID: "attacker-project" },
    { SERVICE_NAME: "attacker-service" },
  ]) {
    const result = runScript(override);
    assert.notEqual(result.status, 0, `override unexpectedly succeeded: ${JSON.stringify(override)}`);
    assert.match(result.stderr, /pinned to the production (project|service)/i);
  }
});

test("DEVICE_ID and DEVICE_UDID resolve consistently and reject ambiguity", () => {
  const deviceId = "00008110-TEST-DEVICE";
  const fromDeviceId = callSourcedFunction(`DEVICE_ID=${deviceId} DEVICE_UDID= resolve_device_identifier`);
  assert.equal(fromDeviceId.status, 0, fromDeviceId.stderr);
  assert.equal(fromDeviceId.stdout.trim(), deviceId);

  const fromUdid = callSourcedFunction(`DEVICE_ID= DEVICE_UDID=${deviceId} resolve_device_identifier`);
  assert.equal(fromUdid.status, 0, fromUdid.stderr);
  assert.equal(fromUdid.stdout.trim(), deviceId);

  const conflicting = callSourcedFunction(
    "DEVICE_ID=00008110-ONE DEVICE_UDID=00008110-TWO resolve_device_identifier"
  );
  assert.notEqual(conflicting.status, 0);
  assert.match(conflicting.stderr, /must match/i);
});

test("device lock parser requires an explicit recognized unlocked state", () => {
  const acceptedFixtures = [
    { result: { passcodeRequired: false } },
    { result: { isLocked: false } },
    { result: { lockState: "unlocked" } },
  ];
  for (const fixture of acceptedFixtures) {
    withJsonFixture(fixture, (fixturePath) => {
      const result = callSourcedFunction(`device_lock_is_verified_unlocked "${fixturePath}"`);
      assert.equal(result.status, 0, `${JSON.stringify(fixture)}: ${result.stderr}`);
    });
  }

  const rejectedFixtures = [
    {},
    { result: { status: "unknown" } },
    { result: { passcodeRequired: true } },
    { result: { isLocked: true } },
    { result: { lockState: "locked" } },
    { result: { passcodeRequired: false, isLocked: true } },
  ];
  for (const fixture of rejectedFixtures) {
    withJsonFixture(fixture, (fixturePath) => {
      const result = callSourcedFunction(`device_lock_is_verified_unlocked "${fixturePath}"`);
      assert.notEqual(result.status, 0, `unsafe fixture passed: ${JSON.stringify(fixture)}`);
    });
  }
});

test("device details parser accepts Xcode 26 pairing and Developer Mode fields", () => {
  withJsonFixture(
    {
      result: {
        connectionProperties: { pairingState: "paired" },
        deviceProperties: { developerModeStatus: "enabled" },
      },
    },
    (fixturePath) => {
      const paired = callSourcedFunction(`device_details_are_paired "${fixturePath}"`);
      assert.equal(paired.status, 0, paired.stderr);
      const developerMode = callSourcedFunction(`device_details_have_developer_mode "${fixturePath}"`);
      assert.equal(developerMode.status, 0, developerMode.stderr);
    }
  );

  const rejectedFixtures = [
    {
      value: {
        result: {
          connectionProperties: { pairingState: "unpaired" },
          deviceProperties: { developerModeStatus: "enabled" },
        },
      },
      functionName: "device_details_are_paired",
    },
    {
      value: {
        result: {
          connectionProperties: { pairingState: "paired" },
          deviceProperties: { developerModeStatus: "disabled" },
        },
      },
      functionName: "device_details_have_developer_mode",
    },
  ];

  for (const fixture of rejectedFixtures) {
    withJsonFixture(fixture.value, (fixturePath) => {
      const result = callSourcedFunction(`${fixture.functionName} "${fixturePath}"`);
      assert.notEqual(result.status, 0, `unsafe fixture passed: ${JSON.stringify(fixture.value)}`);
    });
  }
});

test("Release proxy URL must equal the verified service URL except for trailing slashes", () => {
  for (const candidate of [
    "https://service.example.run.app",
    "https://service.example.run.app/",
  ]) {
    const result = callSourcedFunction(
      `require_service_url_match "${candidate}" "https://service.example.run.app/"`
    );
    assert.equal(result.status, 0, `${candidate}: ${result.stderr}`);
  }

  const wrongService = callSourcedFunction(
    'require_service_url_match "https://other.example.run.app" "https://service.example.run.app"'
  );
  assert.notEqual(wrongService.status, 0);
  assert.match(wrongService.stderr, /must exactly match/i);

  const wrongPath = callSourcedFunction(
    'require_service_url_match "https://service.example.run.app/v1" "https://service.example.run.app"'
  );
  assert.notEqual(wrongPath.status, 0);

  const repeatedSlash = callSourcedFunction(
    'require_service_url_match "https://service.example.run.app//" "https://service.example.run.app"'
  );
  assert.notEqual(repeatedSlash.status, 0);
});

test("quota snapshots preserve existence, update time, and complete document data", () => {
  const quotaStart = scriptSource.indexOf("quota_snapshot() {");
  const quotaEnd = scriptSource.indexOf("\nservice_json() {", quotaStart);
  const quotaFunction = scriptSource.slice(quotaStart, quotaEnd);
  assert.match(quotaFunction, /exists:/);
  assert.match(quotaFunction, /updateTime:/);
  assert.match(quotaFunction, /data:/);
  assert.match(quotaFunction, /\.fields/);
  assert.doesNotMatch(quotaFunction, /\.fields\.used/);
});

test("Firestore preflight uses a short-lived gcloud token without ADC or service-account keys", () => {
  assert.match(scriptSource, /gcloud auth print-access-token/);
  assert.match(scriptSource, /https:\/\/firestore\.googleapis\.com\/v1\/projects/);
  assert.doesNotMatch(scriptSource, /@google-cloud\/firestore/);
  assert.doesNotMatch(scriptSource, /new Firestore/);
});

test("script preserves ordering, rollback, redaction, fresh-build, and provisioning safety", () => {
  const mainFunction = scriptSource.slice(scriptSource.indexOf("main() {"));
  assert.ok(mainFunction.indexOf("backup_app_data") < mainFunction.indexOf("build_and_inspect_release_product"));
  assert.ok(mainFunction.indexOf("build_and_inspect_release_product") < mainFunction.indexOf("deploy_temporary_public_probe"));
  assert.match(scriptSource, /trap rollback EXIT INT TERM/);
  assert.match(scriptSource, /mktemp -d/);
  assert.doesNotMatch(scriptSource, /set -x/);
  assert.doesNotMatch(scriptSource, /\.ipa\b/i);
  assert.doesNotMatch(scriptSource, /-allowProvisioningUpdates/);
  assert.doesNotMatch(scriptSource, /RUN_PRODUCTION_MEAL_SCAN_INTEGRATION=1/);
});

test("dedicated Release scheme is the only scheme that injects the production probe opt-in", () => {
  assert.match(projectSource, /PCOS Production Meal Scan Probe:/);
  const optInMatches = projectSource.match(/RUN_PRODUCTION_MEAL_SCAN_INTEGRATION/g) ?? [];
  assert.equal(optInMatches.length, 1);
  const probeScheme = projectSource.slice(projectSource.indexOf("PCOS Production Meal Scan Probe:"));
  assert.match(probeScheme, /config: Release/);
  assert.match(probeScheme, /name: PCOSTests/);
  assert.match(probeScheme, /RUN_PRODUCTION_MEAL_SCAN_INTEGRATION:[\s\S]*?(1|"1")/);
});
