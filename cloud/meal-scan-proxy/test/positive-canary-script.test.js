import assert from "node:assert/strict";
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const proxyDirectory = path.resolve(testDirectory, "..");
const repositoryRoot = path.resolve(proxyDirectory, "../..");
const scriptPath = path.join(proxyDirectory, "scripts/run-positive-general-kenobi-canary.sh");
const projectPath = path.join(repositoryRoot, "project.yml");
const productionSetupPath = path.join(repositoryRoot, "docs/meal_scan_flash_lite_production_setup.md");
const appStoreReadinessPath = path.join(repositoryRoot, "AppStoreReadinessChecklist.md");
const scriptExists = existsSync(scriptPath);
const scriptSource = scriptExists ? readFileSync(scriptPath, "utf8") : "";
const projectSource = readFileSync(projectPath, "utf8");
const productionSetupSource = readFileSync(productionSetupPath, "utf8");
const appStoreReadinessSource = readFileSync(appStoreReadinessPath, "utf8");

function runScript(environment = {}, options = {}) {
  return spawnSync("bash", [scriptPath], {
    cwd: repositoryRoot,
    encoding: "utf8",
    env: { ...process.env, ...environment },
    ...options,
  });
}

function callSourcedFunction(functionCall, environment = {}) {
  return spawnSync("bash", ["-c", `source "$1"; ${functionCall}`, "positive-canary-test", scriptPath], {
    cwd: repositoryRoot,
    encoding: "utf8",
    env: { ...process.env, ...environment },
  });
}

function withJsonFixture(value, callback) {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-positive-canary-test-"));
  const fixturePath = path.join(directory, "fixture.json");
  writeFileSync(fixturePath, JSON.stringify(value));
  try {
    return callback(fixturePath);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test("positive canary defaults to a complete non-mutating dry run", () => {
  assert.equal(scriptExists, true, `missing ${scriptPath}`);
  assert.notEqual(statSync(scriptPath).mode & 0o111, 0, "positive canary script must be executable");

  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-positive-canary-dry-run-"));
  const binDirectory = path.join(directory, "bin");
  const mutationLog = path.join(directory, "mutations.log");
  mkdirSync(binDirectory);
  for (const command of ["gcloud", "curl", "xcodebuild", "xcrun", "codesign", "security", "npm"] ) {
    const commandPath = path.join(binDirectory, command);
    writeFileSync(
      commandPath,
      `#!/usr/bin/env bash\nprintf '%s\\n' '${command}' >> "$MUTATION_LOG"\nexit 97\n`
    );
    chmodSync(commandPath, 0o755);
  }

  try {
    const result = runScript({
      PATH: `${binDirectory}:/usr/bin:/bin`,
      MUTATION_LOG: mutationLog,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /DRY RUN ONLY/i);
    assert.match(result.stdout, /owner-observed UI evidence/i);
    assert.match(result.stdout, /machine-read evidence/i);
    assert.match(result.stdout, /Scan as New/i);
    assert.match(result.stdout, /rollback/i);
    assert.equal(existsSync(mutationLog) ? readFileSync(mutationLog, "utf8") : "", "");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("production, app, endpoint, and General Kenobi identities are pinned", () => {
  const defaultRun = runScript();
  assert.equal(defaultRun.status, 0, defaultRun.stderr);
  for (const expected of [
    "cyclebalance-prod-20260710",
    "cyclebalance-meal-scan-proxy",
    "alex.PCOS",
    "https://cyclebalance-meal-scan-proxy-mdd7lrfyqa-uc.a.run.app",
    "General Kenobi",
    "0C663BE9-3804-587C-BD8A-A2B4D38F998A",
  ]) {
    assert.match(defaultRun.stdout, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }

  for (const override of [
    { PROJECT_ID: "attacker-project" },
    { SERVICE_NAME: "attacker-service" },
    { APP_BUNDLE_ID: "attacker.bundle" },
    { SERVICE_URL: "https://attacker.example" },
    { DEVICE_NAME: "Ambiguous iPhone" },
    { DEVICE_ID: "00000000-0000-0000-0000-000000000000" },
  ]) {
    const result = runScript(override);
    assert.notEqual(result.status, 0, `override unexpectedly succeeded: ${JSON.stringify(override)}`);
    assert.match(result.stderr, /pinned/i);
  }
});

test("live execution requires the deliberately specific owner confirmation before preflight", () => {
  for (const confirmation of [undefined, "YES", "I_APPROVE"] ) {
    const environment = { DRY_RUN: "false" };
    if (confirmation !== undefined) {
      environment.CONFIRM_GENERAL_KENOBI_POSITIVE_CANARY = confirmation;
    }
    const result = runScript(environment);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /I_APPROVE_GENERAL_KENOBI_POSITIVE_CANARY_WITH_TEMPORARY_PUBLIC_CLOUD_RUN/);
    assert.doesNotMatch(`${result.stdout}\n${result.stderr}`, /Checking Google Cloud|Building Release canary/);
  }
});

test("General Kenobi resolves to exactly one available physical Xcode destination", () => {
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

  for (const fixture of [
    [],
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
  ]) {
    withJsonFixture(fixture, (fixturePath) => {
      const result = callSourcedFunction(`resolve_xcode_device_udid "${fixturePath}" "General Kenobi"`);
      assert.notEqual(result.status, 0, `unsafe fixture passed: ${JSON.stringify(fixture)}`);
    });
  }
});

test("Release canary permits only the two signed scanner-gate overrides", () => {
  const valid = callSourcedFunction(
    "release_override_allowlist_is_valid MEAL_SCAN_RELEASE_UI_ENABLED=YES MEAL_SCAN_RELEASE_GEMINI_ENABLED=YES"
  );
  assert.equal(valid.status, 0, valid.stderr);

  for (const candidate of [
    "MEAL_SCAN_RELEASE_UI_ENABLED=YES",
    "MEAL_SCAN_RELEASE_UI_ENABLED=YES MEAL_SCAN_RELEASE_GEMINI_ENABLED=YES MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED=NO",
    "MEAL_SCAN_RELEASE_UI_ENABLED=YES MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED=YES",
    "MEAL_SCAN_UI_ENABLED=YES GEMINI_MEAL_SCAN_ENABLED=YES",
  ]) {
    const result = callSourcedFunction(`release_override_allowlist_is_valid ${candidate}`);
    assert.notEqual(result.status, 0, `unsafe overrides passed: ${candidate}`);
  }

  const buildFunction = scriptSource.slice(
    scriptSource.indexOf("build_and_inspect_release_canary() {"),
    scriptSource.indexOf("\ninstall_release_canary() {", scriptSource.indexOf("build_and_inspect_release_canary() {"))
  );
  assert.match(buildFunction, /MEAL_SCAN_RELEASE_UI_ENABLED=YES/);
  assert.match(buildFunction, /MEAL_SCAN_RELEASE_GEMINI_ENABLED=YES/);
  assert.doesNotMatch(buildFunction, /MEAL_SCAN_RELEASE_(MOCK_DATA|DEBUG_DIRECT|FALLBACK_MODEL|SIMILARITY)_ENABLED=YES/);
  assert.doesNotMatch(buildFunction, /-allowProvisioningUpdates/);
  assert.doesNotMatch(scriptSource, /\.ipa\b/i);
});

test("canonical Release flags remain NO and are hashed before and after the canary build", () => {
  for (const key of [
    "MEAL_SCAN_RELEASE_UI_ENABLED",
    "MEAL_SCAN_RELEASE_GEMINI_ENABLED",
    "MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED",
    "MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED",
    "MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED",
    "MEAL_SCAN_RELEASE_SIMILARITY_ENABLED",
  ]) {
    assert.match(projectSource, new RegExp(`${key}: ["']?NO["']?`));
  }
  assert.match(scriptSource, /assert_canonical_release_flags/);
  assert.match(scriptSource, /PROJECT_YML_SHA_BEFORE/);
  assert.match(scriptSource, /require_unchanged.*PROJECT_YML_SHA_BEFORE/);
});

test("rollback is armed before public enablement and verifies the final private kill switch", () => {
  const mainFunction = scriptSource.slice(scriptSource.indexOf("main() {"));
  const rollbackArmed = mainFunction.indexOf("ROLLBACK_ARMED=true");
  const publicMutation = mainFunction.indexOf("deploy_temporarily_enabled_public");
  assert.ok(rollbackArmed >= 0, "rollback was not armed");
  assert.ok(publicMutation > rollbackArmed, "public mutation occurs before rollback is armed");
  assert.match(scriptSource, /trap rollback EXIT INT TERM/);

  const rollbackFunction = scriptSource.slice(
    scriptSource.indexOf("rollback() {"),
    scriptSource.indexOf("\nprint_dry_run() {", scriptSource.indexOf("rollback() {"))
  );
  assert.match(rollbackFunction, /deploy_disabled_private/);
  assert.match(rollbackFunction, /verify_final_disabled_private/);

  const finalVerification = scriptSource.slice(
    scriptSource.indexOf("verify_final_disabled_private() {"),
    scriptSource.indexOf("\n", scriptSource.indexOf("verify_final_disabled_private() {") + 40) > 0
      ? scriptSource.indexOf("\nrun_owner_guided_canary() {", scriptSource.indexOf("verify_final_disabled_private() {"))
      : scriptSource.length
  );
  assert.match(finalVerification, /MEAL_SCAN_ENABLED/);
  assert.match(finalVerification, /iam_policy_is_private/);
  assert.match(scriptSource, /allUsers/);
  assert.match(scriptSource, /allAuthenticatedUsers/);
  assert.match(finalVerification, /private_invoker_gate_rejects_status/);
  assert.match(finalVerification, /503/);
  assert.match(finalVerification, /feature_disabled/);
});

test("prohibited log content is rejected and retained evidence is redacted and restricted", () => {
  withJsonFixture(
    [{ jsonPayload: { event: "meal_scan_scanner_event", eventType: "provider_call", outcome: "completed" } }],
    (fixturePath) => {
      const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
      assert.equal(result.status, 0, result.stderr);
    }
  );

  for (const prohibited of [
    "Authorization: Bearer secret-token",
    "x-firebase-appcheck: app-check-token",
    "signedTransactionJWS=header.payload.signature",
    "originalTransactionId=123456789",
    "meal_name=private meal",
    "data:image/jpeg;base64,/9j/4AAQ",
    "AIzaExampleKey",
  ]) {
    withJsonFixture([{ textPayload: prohibited }], (fixturePath) => {
      const result = callSourcedFunction(`assert_no_prohibited_content "${fixturePath}"`);
      assert.notEqual(result.status, 0, `prohibited content passed: ${prohibited}`);
    });
  }

  assert.doesNotMatch(scriptSource, /set -x/);
  assert.match(scriptSource, /secrets versions access "\$REVENUECAT_SECRET_VERSION"/);
  assert.match(scriptSource, /verify-revenuecat-offering-v2\.sh/);
  assert.doesNotMatch(scriptSource, /secrets versions access[^\n]*(gemini|principal|apple)/i);
  assert.doesNotMatch(scriptSource, /auth_config/);
  assert.match(scriptSource, /--config -/);
  assert.match(scriptSource, /chmod 0700/);
  assert.match(scriptSource, /chmod 0600/);
  assert.match(scriptSource, /owner-observed UI evidence/i);
  assert.match(scriptSource, /machine-read evidence/i);

  const captureFunction = scriptSource.slice(
    scriptSource.indexOf("capture_phase_window() {"),
    scriptSource.indexOf("\ncapture_and_verify_phase() {", scriptSource.indexOf("capture_phase_window() {"))
  );
  const loggingFilter = captureFunction.slice(
    captureFunction.indexOf("gcloud logging read"),
    captureFunction.indexOf("--project", captureFunction.indexOf("gcloud logging read"))
  );
  assert.match(loggingFilter, /run\.googleapis\.com%2Fstdout/);
  assert.match(loggingFilter, /run\.googleapis\.com%2Fstderr/);
  assert.doesNotMatch(loggingFilter, /meal_scan_scanner_event/);
});

test("machine evidence arithmetic distinguishes exact local reuse from Scan as New", () => {
  withJsonFixture({ phase: "exact-reuse", eventCount: 0, quotaUnchanged: true }, (fixturePath) => {
    const result = callSourcedFunction(`verify_phase_evidence exact-reuse "${fixturePath}"`);
    assert.equal(result.status, 0, result.stderr);
  });

  withJsonFixture(
    {
      phase: "scan-as-new",
      requestCompleted: 1,
      providerStarted: 1,
      providerCompleted: 1,
      quotaDelta: 1,
      cacheFreshDispatch: 1,
      authorizationControls: [
        "app_check",
        "storekit_jws",
        "apple_current_status",
        "revenuecat_subscription",
      ],
      canaryQuotaTag: "a".repeat(64),
    },
    (fixturePath) => {
      const result = callSourcedFunction(`verify_phase_evidence scan-as-new "${fixturePath}"`);
      assert.equal(result.status, 0, result.stderr);
    }
  );

  const unsafeFixtures = [
    ["exact-reuse", { phase: "exact-reuse", eventCount: 1, quotaUnchanged: true }],
    ["exact-reuse", { phase: "exact-reuse", eventCount: 0, quotaUnchanged: false }],
    ["scan-as-new", {
      phase: "scan-as-new",
      requestCompleted: 1,
      providerStarted: 0,
      providerCompleted: 1,
      quotaDelta: 1,
      cacheFreshDispatch: 1,
      authorizationControls: ["app_check"],
      canaryQuotaTag: "a".repeat(64),
    }],
  ];
  for (const [phase, fixture] of unsafeFixtures) {
    withJsonFixture(fixture, (fixturePath) => {
      const result = callSourcedFunction(`verify_phase_evidence ${phase} "${fixturePath}"`);
      assert.notEqual(result.status, 0, `unsafe ${phase} evidence passed: ${JSON.stringify(fixture)}`);
    });
  }
});

test("each owner-guided action occurs inside its machine evidence window", () => {
  const ownerGuide = scriptSource.slice(
    scriptSource.indexOf("run_owner_guided_canary() {"),
    scriptSource.indexOf("\nrecord_owner_only_observation() {", scriptSource.indexOf("run_owner_guided_canary() {"))
  );
  assert.doesNotMatch(ownerGuide, /read -r -p/);
  assert.match(ownerGuide, /capture_and_verify_phase fresh-scan/);
  assert.match(ownerGuide, /capture_and_verify_phase exact-reuse/);
  assert.match(ownerGuide, /capture_and_verify_phase scan-as-new/);

  const captureFunction = scriptSource.slice(
    scriptSource.indexOf("capture_and_verify_phase() {"),
    scriptSource.indexOf("\nrestore_original_app_absence() {", scriptSource.indexOf("capture_and_verify_phase() {"))
  );
  assert.ok(captureFunction.indexOf("start_utc=") < captureFunction.indexOf("read -r -p"));
  assert.ok(captureFunction.indexOf("read -r -p") < captureFunction.indexOf("end_utc="));
});

test("fresh seed and uncached Scan as New run in separate rollback-bounded live windows", () => {
  assert.match(scriptSource, /CANARY_PHASE="\$\{CANARY_PHASE:-seed\}"/);
  const ownerGuide = scriptSource.slice(
    scriptSource.indexOf("run_owner_guided_canary() {"),
    scriptSource.indexOf("\nrecord_owner_only_observation() {", scriptSource.indexOf("run_owner_guided_canary() {"))
  );
  assert.match(ownerGuide, /case "\$CANARY_PHASE" in/);
  assert.match(ownerGuide, /seed\)[\s\S]*capture_and_verify_phase fresh-scan[\s\S]*capture_and_verify_phase exact-reuse/);
  assert.match(ownerGuide, /rescan\)[\s\S]*capture_and_verify_phase scan-as-new/);
  const seedBody = ownerGuide.slice(ownerGuide.indexOf("seed)"), ownerGuide.indexOf("rescan)"));
  assert.doesNotMatch(seedBody, /capture_and_verify_phase scan-as-new/);
  const rescanBody = ownerGuide.slice(ownerGuide.indexOf("rescan)"));
  assert.doesNotMatch(rescanBody, /capture_and_verify_phase fresh-scan/);
  assert.match(scriptSource, /rollback between the seed and rescan windows/i);

  const invalidPhase = runScript({ CANARY_PHASE: "both-at-once" });
  assert.notEqual(invalidPhase.status, 0);
  assert.match(invalidPhase.stderr, /CANARY_PHASE must be seed or rescan/);
});

test("setup and readiness docs stage dry-run and approval-gated live commands without closing release gates", () => {
  for (const [label, source] of [
    ["production setup", productionSetupSource],
    ["App Store readiness", appStoreReadinessSource],
  ]) {
    assert.match(source, /run-positive-general-kenobi-canary\.sh/, `${label} omits the new harness`);
    assert.match(source, /DRY_RUN=true/, `${label} omits the dry-run command`);
    assert.match(
      source,
      /I_APPROVE_GENERAL_KENOBI_POSITIVE_CANARY_WITH_TEMPORARY_PUBLIC_CLOUD_RUN/,
      `${label} omits the approval gate`
    );
    assert.match(source, /positive sandbox-JWS real-device TestFlight gate/i);
    assert.match(source, /80-image\/120-call/i);
    assert.match(source, /distribution profile/i);
    assert.match(source, /remains open|still open|does not close/i);
  }
});

test("seed receipt enforces the buffered 24-hour rescan boundary", () => {
  withJsonFixture(
    { schemaVersion: 1, lifecycle: "seed_rolled_back", rescanNotBeforeEpoch: 1_000 },
    (fixturePath) => {
      const early = callSourcedFunction(`receipt_rescan_is_due "${fixturePath}" 999`);
      assert.notEqual(early.status, 0);
      const due = callSourcedFunction(`receipt_rescan_is_due "${fixturePath}" 1000`);
      assert.equal(due.status, 0, due.stderr);
    }
  );
  assert.match(scriptSource, /CANARY_RECEIPT_PATH/);
  assert.match(scriptSource, /RESCAN_INGESTION_SKEW_BUFFER_SECONDS="600"/);
  assert.match(scriptSource, /chmod 0700/);
  assert.match(scriptSource, /chmod 0600/);
});

test("Cloud Run policy checks reject both public principals and a disabled invoker IAM check", () => {
  for (const member of ["allUsers", "allAuthenticatedUsers"]) {
    withJsonFixture(
      { bindings: [{ role: "roles/run.invoker", members: [member] }] },
      (fixturePath) => {
        const result = callSourcedFunction(`iam_policy_is_private "${fixturePath}"`);
        assert.notEqual(result.status, 0, `${member} was accepted`);
      }
    );
  }
  withJsonFixture(
    { bindings: [{ role: "roles/run.invoker", members: ["serviceAccount:proxy@example.test"] }] },
    (fixturePath) => {
      const result = callSourcedFunction(`iam_policy_is_private "${fixturePath}"`);
      assert.equal(result.status, 0, result.stderr);
    }
  );

  for (const [annotation, accepted] of [["true", false], ["false", true], [undefined, true]]) {
    withJsonFixture(
      annotation === undefined ? { metadata: { annotations: {} } } : {
        metadata: { annotations: { "run.googleapis.com/invoker-iam-disabled": annotation } },
      },
      (fixturePath) => {
        const result = callSourcedFunction(`invoker_iam_check_is_enabled "${fixturePath}"`);
        assert.equal(result.status === 0, accepted, `${annotation}: ${result.stderr}`);
      }
    );
  }
});

test("live source, signing, device, deploy, and evidence gates are pinned and fail closed", () => {
  assert.match(scriptSource, /APPROVED_SOURCE_COMMIT/);
  assert.match(scriptSource, /git status --porcelain --untracked-files=all/);
  assert.match(scriptSource, /codesign --verify --deep --strict --verbose=4/);
  assert.match(scriptSource, /ProvisionedDevices/);
  assert.match(scriptSource, /TeamIdentifier/);
  assert.match(scriptSource, /application-identifier/);
  assert.match(scriptSource, /XCODE_DEVICE_UDID/);
  assert.match(scriptSource, /CoreDevice.*Xcode|Xcode.*CoreDevice/i);
  assert.match(scriptSource, /DEPLOY_MODE=canary/);
  assert.match(scriptSource, /MEAL_SCAN_CANARY_CORRELATION_SHA256/);
  assert.match(scriptSource, /positive-canary-evidence\.mjs/);
  assert.doesNotMatch(scriptSource, /rolling_quota_digest\(\)/);
});

test("two-window lifecycle keeps the canary installed after seed and restores only after rescan", () => {
  const mainFunction = scriptSource.slice(scriptSource.indexOf("main() {"));
  assert.match(mainFunction, /case "\$CANARY_PHASE"/);
  assert.match(mainFunction, /load_seed_receipt/);
  assert.match(scriptSource, /verify_dormant_window_continuity/);
  assert.match(scriptSource, /manual restore required/i);
  assert.match(scriptSource, /initially absent/i);

  const rollbackFunction = scriptSource.slice(
    scriptSource.indexOf("rollback() {"),
    scriptSource.indexOf("\nmain() {", scriptSource.indexOf("rollback() {"))
  );
  assert.match(rollbackFunction, /finalize_device_lifecycle/);
  assert.doesNotMatch(rollbackFunction, /restore_original_app_absence/);
});

test("command-shim state machine restores cloud and IAM on failures, signals, and rollback errors", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-rollback-state-machine-"));
  const commandLog = path.join(directory, "commands.log");
  const harness = `
source "$1"
TEMP_ROOT="$2/temp"
mkdir -p "$TEMP_ROOT"
COMMAND_LOG="$3"
EVIDENCE_DIR=""
EVIDENCE_SUMMARY=""
ROLLBACK_ARMED=true
ROLLBACK_COMPLETE=false
CANARY_PHASE=seed
CANARY_APP_INSTALL_STARTED=false
RESTORE_RESULT=0
deploy_disabled_private() { printf 'deploy-disabled\n' >> "$COMMAND_LOG"; return 0; }
restore_initial_iam_policy() { printf 'restore-iam\n' >> "$COMMAND_LOG"; return "$RESTORE_RESULT"; }
verify_final_disabled_private() { printf 'verify-final\n' >> "$COMMAND_LOG"; return 0; }
finalize_device_lifecycle() { printf 'finalize-device:%s\n' "$1" >> "$COMMAND_LOG"; return 0; }
cleanup_temp() { :; }
set +e
case "$4" in
  failure) false; rollback ;;
  signal) trap rollback TERM; kill -TERM $$ ;;
  restore-error) RESTORE_RESULT=1; rollback ;;
esac
`;
  try {
    for (const [scenario, expectedStatus] of [["failure", 1], ["signal", 0], ["restore-error", 1]]) {
      writeFileSync(commandLog, "");
      const result = spawnSync(
        "bash",
        ["-c", harness, "rollback-test", scriptPath, directory, commandLog, scenario],
        { cwd: repositoryRoot, encoding: "utf8" }
      );
      assert.equal(result.status, expectedStatus, `${scenario}: ${result.stderr}`);
      const calls = readFileSync(commandLog, "utf8");
      assert.match(calls, /deploy-disabled/);
      assert.match(calls, /restore-iam/);
      if (scenario === "restore-error") assert.doesNotMatch(calls, /verify-final/);
      else assert.match(calls, /verify-final/);
      assert.match(calls, /finalize-device/);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("final rescan lifecycle covers both initially absent and initially present app states", () => {
  for (const [initialState, expectedStatus, expectedLifecycle] of [
    ["absent", 0, "removed"],
    ["present", 1, "manual_restore_required"],
  ]) {
    const directory = mkdtempSync(path.join(tmpdir(), `cyclebalance-final-${initialState}-`));
    const home = path.join(directory, "home");
    mkdirSync(home);
    const harness = `
source "$1"
mkdir -p "$CANARY_RECEIPT_ROOT"
chmod 0700 "$CANARY_RECEIPT_ROOT"
printf '{"lifecycle":"seed_rolled_back"}\n' > "$CANARY_RECEIPT_PATH"
chmod 0600 "$CANARY_RECEIPT_PATH"
CANARY_PHASE=rescan
CANARY_RUN_COMPLETED=true
ROLLBACK_COMPLETE=true
ORIGINAL_APP_VERSION=1.0.4
ORIGINAL_APP_BUILD=17
ORIGINAL_APP_SIGNING_STATE=distribution_or_store
ORIGINAL_APP_DATA_BACKUP_PATH="$HOME/backup"
EVIDENCE_SUMMARY=""
if [[ "$2" == "absent" ]]; then APP_WAS_INSTALLED=false; else APP_WAS_INSTALLED=true; fi
uninstall_and_verify_initial_absence() { printf 'uninstalled-and-verified\n'; return 0; }
set +e
finalize_device_lifecycle 0
exit $?
`;
    try {
      const result = spawnSync(
        "bash",
        ["-c", harness, "lifecycle-test", scriptPath, initialState],
        { cwd: repositoryRoot, encoding: "utf8", env: { ...process.env, HOME: home } }
      );
      assert.equal(result.status, expectedStatus, `${initialState}: ${result.stderr}`);
      const receiptPath = path.join(home, "Library/Application Support/CycleBalance/PositiveCanary/seed-receipt.json");
      if (expectedLifecycle === "removed") {
        assert.match(result.stdout, /uninstalled-and-verified/);
        assert.equal(existsSync(receiptPath), false);
      } else {
        assert.equal(JSON.parse(readFileSync(receiptPath, "utf8")).lifecycle, expectedLifecycle);
        assert.match(result.stderr, /MANUAL RESTORE REQUIRED/);
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }
});
