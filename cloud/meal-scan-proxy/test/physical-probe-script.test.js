import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const proxyDirectory = path.resolve(testDirectory, "..");
const repositoryRoot = path.resolve(proxyDirectory, "../..");
const scriptPath = path.join(proxyDirectory, "scripts/run-physical-app-check-probe.sh");
const deployScriptPath = path.join(proxyDirectory, "scripts/deploy-cloud-run.sh");
const projectPath = path.join(repositoryRoot, "project.yml");
const productionProbeTestPath = path.join(
  repositoryRoot,
  "PCOS/PCOSTests/ProductionMealScanAppCheckProbeTests.swift"
);
const productionSetupPath = path.join(repositoryRoot, "docs/meal_scan_flash_lite_production_setup.md");
const deviceRolloutPlanPath = path.join(
  repositoryRoot,
  "docs/superpowers/plans/2026-07-11-meal-scan-device-review-rollout.md"
);
const appStoreReadinessPath = path.join(repositoryRoot, "AppStoreReadinessChecklist.md");
const appStoreReviewPacketPath = path.join(
  repositoryRoot,
  "docs/app_store_meal_scan_review_packet_2026-07-11.md"
);
const scriptSource = readFileSync(scriptPath, "utf8");
const deployScriptSource = readFileSync(deployScriptPath, "utf8");
const projectSource = readFileSync(projectPath, "utf8");
const productionProbeTestSource = readFileSync(productionProbeTestPath, "utf8");
const productionSetupSource = readFileSync(productionSetupPath, "utf8");
const deviceRolloutPlanSource = readFileSync(deviceRolloutPlanPath, "utf8");
const appStoreReadinessSource = readFileSync(appStoreReadinessPath, "utf8");
const appStoreReviewPacketSource = readFileSync(appStoreReviewPacketPath, "utf8");

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

function callSourcedFunction(functionCall, environment = {}) {
  return spawnSync("bash", ["-c", `source "$1"; ${functionCall}`, "probe-test", scriptPath], {
    cwd: repositoryRoot,
    encoding: "utf8",
    env: { ...process.env, ...environment },
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

test("named physical device resolves to one available Xcode hardware UDID", () => {
  withJsonFixture(
    [
      {
        name: "General Kenobi",
        identifier: "00008130-001929003AE2001C",
        available: true,
        simulator: false,
        platform: "com.apple.platform.iphoneos",
      },
      {
        name: "General Kenobi",
        identifier: "SIMULATOR-IGNORED",
        available: true,
        simulator: true,
        platform: "com.apple.platform.iphonesimulator",
      },
    ],
    (fixturePath) => {
      const result = callSourcedFunction(`resolve_xcode_device_udid "${fixturePath}" "General Kenobi"`);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout.trim(), "00008130-001929003AE2001C");
    }
  );

  const rejectedFixtures = [
    [],
    [
      {
        name: "General Kenobi",
        identifier: "UNAVAILABLE",
        available: false,
        simulator: false,
        platform: "com.apple.platform.iphoneos",
      },
    ],
    [
      {
        name: "General Kenobi",
        identifier: "DEVICE-ONE",
        available: true,
        simulator: false,
        platform: "com.apple.platform.iphoneos",
      },
      {
        name: "General Kenobi",
        identifier: "DEVICE-TWO",
        available: true,
        simulator: false,
        platform: "com.apple.platform.iphoneos",
      },
    ],
  ];

  for (const fixture of rejectedFixtures) {
    withJsonFixture(fixture, (fixturePath) => {
      const result = callSourcedFunction(`resolve_xcode_device_udid "${fixturePath}" "General Kenobi"`);
      assert.notEqual(result.status, 0, `unsafe fixture passed: ${JSON.stringify(fixture)}`);
    });
  }

  assert.match(scriptSource, /-destination "platform=iOS,id=\$XCODE_DEVICE_UDID"/);
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

test("DDI parser accepts current Xcode usable-compatible metadata and legacy services", () => {
  const acceptedFixtures = [
    { result: { ddiMetadata: { isUsable: true, contentIsCompatible: true } } },
    { result: { services: [{ identifier: "com.apple.test" }] } },
  ];
  for (const fixture of acceptedFixtures) {
    withJsonFixture(fixture, (fixturePath) => {
      const result = callSourcedFunction(`device_ddi_is_usable "${fixturePath}"`);
      assert.equal(result.status, 0, `${JSON.stringify(fixture)}: ${result.stderr}`);
    });
  }

  const rejectedFixtures = [
    {},
    { result: { ddiMetadata: { isUsable: false, contentIsCompatible: true } } },
    { result: { ddiMetadata: { isUsable: true, contentIsCompatible: false } } },
    { result: { services: [] } },
  ];
  for (const fixture of rejectedFixtures) {
    withJsonFixture(fixture, (fixturePath) => {
      const result = callSourcedFunction(`device_ddi_is_usable "${fixturePath}"`);
      assert.notEqual(result.status, 0, `unsafe fixture passed: ${JSON.stringify(fixture)}`);
    });
  }
});

test("app inventory distinguishes exact installation absence from invalid inventory", () => {
  withJsonFixture(
    {
      info: { outcome: "success" },
      result: { apps: [{ bundleIdentifier: "alex.PCOS" }] },
    },
    (fixturePath) => {
      const valid = callSourcedFunction(`device_app_inventory_is_valid "${fixturePath}"`);
      assert.equal(valid.status, 0, valid.stderr);
      const installed = callSourcedFunction(`device_has_installed_app "${fixturePath}" alex.PCOS`);
      assert.equal(installed.status, 0, installed.stderr);
    }
  );

  withJsonFixture(
    {
      info: { outcome: "success" },
      result: { apps: [{ bundleIdentifier: "alex.PoolFlow" }] },
    },
    (fixturePath) => {
      const valid = callSourcedFunction(`device_app_inventory_is_valid "${fixturePath}"`);
      assert.equal(valid.status, 0, valid.stderr);
      const installed = callSourcedFunction(`device_has_installed_app "${fixturePath}" alex.PCOS`);
      assert.notEqual(installed.status, 0);
    }
  );

  for (const fixture of [{}, { info: { outcome: "failure" }, result: { apps: [] } }, { info: { outcome: "success" }, result: {} }]) {
    withJsonFixture(fixture, (fixturePath) => {
      const valid = callSourcedFunction(`device_app_inventory_is_valid "${fixturePath}"`);
      assert.notEqual(valid.status, 0, `unsafe fixture passed: ${JSON.stringify(fixture)}`);
    });
  }
});

test("signed App Attest parser requests XML stdout without mixing codesign diagnostics", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-codesign-test-"));
  const binDirectory = path.join(directory, "bin");
  mkdirSync(binDirectory);
  const fakeCodesign = path.join(binDirectory, "codesign");
  writeFileSync(
    fakeCodesign,
    `#!/usr/bin/env bash
printf '%s\n' 'Executable=/tmp/PCOS.app/PCOS' >&2
cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.developer.devicecheck.appattest-environment</key><string>production</string></dict></plist>
PLIST
`
  );
  chmodSync(fakeCodesign, 0o755);

  try {
    const result = spawnSync(
      "bash",
      ["-c", 'source "$1"; app_attest_environment_from_app /tmp/PCOS.app', "probe-test", scriptPath],
      {
        cwd: repositoryRoot,
        encoding: "utf8",
        env: { ...process.env, PATH: `${binDirectory}:${process.env.PATH}` },
      }
    );
    assert.equal(result.status, 0, `stdout: ${result.stdout}\nstderr: ${result.stderr}`);
    assert.equal(result.stdout.trim(), "production");
    assert.match(scriptSource, /codesign --display --xml --entitlements -/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
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

test("rolling quota snapshot is complete, paginated, and principal independent", () => {
  assert.match(scriptSource, /MEAL_SCAN_ROLLING_QUOTA_COLLECTION="mealScanRollingQuota"/);
  assert.match(scriptSource, /MAX_FIRESTORE_SNAPSHOT_PAGES/);
  assert.match(scriptSource, /firestore_collection_snapshot\(\)/);
  const snapshotStart = scriptSource.indexOf("firestore_collection_snapshot() {");
  const snapshotEnd = scriptSource.indexOf("\nrolling_quota_snapshot() {", snapshotStart);
  const snapshotFunction = scriptSource.slice(snapshotStart, snapshotEnd);
  assert.match(snapshotFunction, /pageSize=/);
  assert.match(snapshotFunction, /nextPageToken/);
  assert.match(snapshotFunction, /pageToken=/);
  assert.match(snapshotFunction, /sort_by\(\.name\)/);

  const probeFunction = scriptSource.slice(
    scriptSource.indexOf("run_probe_and_verify_side_effects() {"),
    scriptSource.indexOf("\nmain() {")
  );
  assert.match(probeFunction, /before_rolling_quota="\$\(rolling_quota_snapshot\)"/);
  assert.match(probeFunction, /after_rolling_quota="\$\(rolling_quota_snapshot\)"/);
  assert.match(probeFunction, /require_unchanged "\$after_rolling_quota" "\$before_rolling_quota"/);
  assert.match(probeFunction, /PROBE_REVISION/);
  assert.match(probeFunction, /date -u -v\+2S/);
  assert.match(probeFunction, /sleep 10/);
  assert.doesNotMatch(scriptSource, /PROBE_USER_ID/);
  assert.doesNotMatch(scriptSource, /mealScanDailyQuota/);
  assert.doesNotMatch(scriptSource, /probe_app_user_hash/);
  assert.doesNotMatch(scriptSource, /request_gate_snapshot/);
  assert.doesNotMatch(scriptSource, /request_gate_advanced_once/);
  assert.doesNotMatch(scriptSource, /isolated request-gate advance/);
});

test("negative probe forbids provider activity without closing the positive sandbox gate", () => {
  const probeFunction = scriptSource.slice(
    scriptSource.indexOf("run_probe_and_verify_side_effects() {"),
    scriptSource.indexOf("\nmain() {")
  );
  assert.match(probeFunction, /provider_call/);
  assert.match(probeFunction, /meal_scan_estimate/);
  assert.match(probeFunction, /Probe must not create a provider call event/);
  assert.match(probeFunction, /Probe must not create a Gemini estimate event/);

  for (const [label, source] of [
    ["probe script", scriptSource],
    ["production setup", productionSetupSource],
    ["device rollout plan", deviceRolloutPlanSource],
    ["App Store readiness", appStoreReadinessSource],
    ["App Store review packet", appStoreReviewPacketSource],
  ]) {
    assert.match(source, /positive sandbox-JWS real-device TestFlight gate/i, `${label} omits the positive gate`);
    assert.match(source, /does not satisfy|remains open/i, `${label} incorrectly closes the positive gate`);
  }
});

test("physical probe retains a result bundle and redacted console diagnostics on failure", () => {
  assert.match(scriptSource, /-resultBundlePath "\$TEMP_ROOT\/PhysicalProbe\.xcresult"/);
  assert.match(scriptSource, /preserve_probe_diagnostics/);
  assert.match(scriptSource, /Library\/Logs\/CycleBalance\/PhysicalProbe/);
  assert.match(scriptSource, /chmod 0700/);
});

test("Firestore preflight uses a short-lived gcloud token without ADC or service-account keys", () => {
  assert.match(scriptSource, /gcloud auth print-access-token/);
  assert.match(scriptSource, /https:\/\/firestore\.googleapis\.com\/v1\/projects/);
  assert.doesNotMatch(scriptSource, /@google-cloud\/firestore/);
  assert.doesNotMatch(scriptSource, /new Firestore/);
});

test("physical probe treats the most restrictive budget mode as authoritative", () => {
  const billingDisabled = callSourcedFunction(
    `printf '%s' '{"fields":{"manualMode":{"stringValue":"normal"},"billingMode":{"stringValue":"disabled"}}}' | effective_budget_mode_from_json`
  );
  assert.equal(billingDisabled.status, 0, billingDisabled.stderr);
  assert.equal(billingDisabled.stdout.trim(), "disabled");

  const manualDisabled = callSourcedFunction(
    `printf '%s' '{"fields":{"manualMode":{"stringValue":"disabled"},"billingMode":{"stringValue":"normal"}}}' | effective_budget_mode_from_json`
  );
  assert.equal(manualDisabled.status, 0, manualDisabled.stderr);
  assert.equal(manualDisabled.stdout.trim(), "disabled");
});

test("initial cloud preflight proves the service rejects anonymous transport", () => {
  const initialStart = scriptSource.indexOf("verify_initial_cloud_state() {");
  const initialEnd = scriptSource.indexOf("\nverify_device_preconditions() {", initialStart);
  const initialFunction = scriptSource.slice(initialStart, initialEnd);

  assert.match(initialFunction, /curl/);
  assert.match(initialFunction, /unauthenticated_status/);
  assert.match(initialFunction, /private_invoker_gate_rejects_status/);
});

test("private invoker gate accepts Cloud Run 403 or concealed 404 only", () => {
  for (const status of ["403", "404"]) {
    const result = callSourcedFunction(`private_invoker_gate_rejects_status ${status}`);
    assert.equal(result.status, 0, `${status}: ${result.stderr}`);
  }

  for (const status of ["000", "200", "400", "401", "503"]) {
    const result = callSourcedFunction(`private_invoker_gate_rejects_status ${status}`);
    assert.notEqual(result.status, 0, `application/transport status ${status} passed as private`);
  }

  assert.match(deployScriptSource, /private_invoker_gate_rejects_status/);
  assert.match(deployScriptSource, /public_app_integrity_challenge_status/);
});

test("script preserves ordering, rollback, redaction, fresh-build, and provisioning safety", () => {
  const mainFunction = scriptSource.slice(scriptSource.indexOf("main() {"));
  const firstDeviceCheck = mainFunction.indexOf("verify_device_preconditions");
  const buildCall = mainFunction.indexOf("build_and_inspect_release_product");
  const secondDeviceCheck = mainFunction.indexOf("verify_device_preconditions", firstDeviceCheck + 1);
  const publicDeploy = mainFunction.indexOf("deploy_temporary_public_probe");
  assert.ok(mainFunction.indexOf("backup_app_data") < mainFunction.indexOf("build_and_inspect_release_product"));
  assert.ok(mainFunction.indexOf("build_and_inspect_release_product") < mainFunction.indexOf("deploy_temporary_public_probe"));
  assert.ok(firstDeviceCheck >= 0 && firstDeviceCheck < buildCall);
  assert.ok(secondDeviceCheck > buildCall && secondDeviceCheck < publicDeploy);
  assert.match(scriptSource, /trap rollback EXIT INT TERM/);
  assert.match(scriptSource, /mktemp -d/);
  assert.doesNotMatch(scriptSource, /set -x/);
  assert.doesNotMatch(scriptSource, /\.ipa\b/i);
  assert.doesNotMatch(scriptSource, /-allowProvisioningUpdates/);
  assert.doesNotMatch(scriptSource, /RUN_PRODUCTION_MEAL_SCAN_INTEGRATION=1/);
  assert.doesNotMatch(scriptSource, /--header\s+"Authorization: Bearer \$\{identity_token\}"/);
  assert.doesNotMatch(scriptSource, /ProbeTestDerivedData/);
  assert.match(scriptSource, /auth_header_curl_config/);
});

test("rollback removes only a transient probe app when CycleBalance was initially absent", () => {
  assert.match(scriptSource, /APP_WAS_INSTALLED=""/);
  assert.match(scriptSource, /PROBE_APP_INSTALL_STARTED=false/);

  const backupFunction = scriptSource.slice(
    scriptSource.indexOf("backup_app_data() {"),
    scriptSource.indexOf("\nbuild_and_inspect_release_product() {")
  );
  assert.match(backupFunction, /APP_WAS_INSTALLED=false/);
  assert.match(backupFunction, /APP_WAS_INSTALLED=true/);

  const restoreFunction = scriptSource.slice(
    scriptSource.indexOf("restore_original_app_absence() {"),
    scriptSource.indexOf("\nrollback() {")
  );
  assert.match(restoreFunction, /APP_WAS_INSTALLED.*false/);
  assert.match(restoreFunction, /PROBE_APP_INSTALL_STARTED.*true/);
  assert.match(
    restoreFunction,
    /xcrun devicectl device uninstall app[\s\S]*?--device "\$DEVICE_IDENTIFIER"[\s\S]*?"\$APP_BUNDLE_ID"/
  );

  const rollbackFunction = scriptSource.slice(
    scriptSource.indexOf("rollback() {"),
    scriptSource.indexOf("\nprint_dry_run() {")
  );
  assert.match(rollbackFunction, /restore_original_app_absence/);
});

test("dedicated probe build and test use one testable Release product", () => {
  const testabilityMatches = scriptSource.match(/ENABLE_TESTABILITY=YES/g) ?? [];
  assert.equal(testabilityMatches.length, 2);

  const buildFunction = scriptSource.slice(
    scriptSource.indexOf("build_and_inspect_release_product() {"),
    scriptSource.indexOf("\ndeploy_temporary_public_probe() {")
  );
  const testFunction = scriptSource.slice(
    scriptSource.indexOf("run_probe_and_verify_side_effects() {"),
    scriptSource.indexOf("\nmain() {")
  );
  assert.match(buildFunction, /ENABLE_TESTABILITY=YES/);
  assert.match(testFunction, /ENABLE_TESTABILITY=YES/);
});

test("dedicated Release scheme is the only scheme that injects the production probe opt-in", () => {
  assert.match(projectSource, /PCOSProductionProbeTests:/);
  assert.match(projectSource, /PRODUCT_BUNDLE_IDENTIFIER: alex\.PCOSProductionProbeTests/);
  assert.match(projectSource, /path: PCOS\/PCOSTests\/ProductionMealScanAppCheckProbeTests\.swift/);
  assert.match(projectSource, /PCOS Production Meal Scan Probe:/);
  const optInMatches = projectSource.match(/RUN_PRODUCTION_MEAL_SCAN_INTEGRATION/g) ?? [];
  assert.equal(optInMatches.length, 1);
  const probeScheme = projectSource.slice(projectSource.indexOf("PCOS Production Meal Scan Probe:"));
  assert.match(probeScheme, /config: Release/);
  assert.match(probeScheme, /name: PCOSProductionProbeTests/);
  assert.match(probeScheme, /RUN_PRODUCTION_MEAL_SCAN_INTEGRATION:[\s\S]*?(1|"1")/);
  assert.match(scriptSource, /PCOSProductionProbeTests\/ProductionMealScanAppCheckProbeTests/);
});

test("invalid StoreKit probe contract is consistent across test, script, and documentation", () => {
  assert.match(productionProbeTestSource, /invalidProbeTransactionJWS/);
  assert.match(productionProbeTestSource, /error\.reason == "storekit_transaction_invalid"/);
  assert.doesNotMatch(productionProbeTestSource, /image hash prefix|print\(/i);

  for (const [label, source] of [
    ["probe test", productionProbeTestSource],
    ["probe script", scriptSource],
    ["production setup", productionSetupSource],
    ["device rollout plan", deviceRolloutPlanSource],
  ]) {
    assert.match(source, /storekit_transaction_invalid/, `${label} omits the current rejection reason`);
    assert.doesNotMatch(source, /entitlement_inactive/, `${label} retains the legacy rejection reason`);
  }
});
