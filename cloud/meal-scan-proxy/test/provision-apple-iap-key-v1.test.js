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
const scriptPath = path.join(proxyDirectory, "scripts/provision-apple-iap-key-v1.sh");

function runProvisioner(environment = {}, options = {}) {
  return spawnSync("bash", [scriptPath], {
    cwd: proxyDirectory,
    encoding: "utf8",
    env: { ...process.env, ...environment },
    ...options,
  });
}

function createGcloudHarness({
  resource = "absent",
  versions = "none",
  iam = "exact",
  postAddVersions = "1-enabled",
  postIam = "",
  postIamAfterAdd = "",
} = {}) {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-p8-gcloud-"));
  const binDirectory = path.join(directory, "bin");
  const stateDirectory = path.join(directory, "state");
  const commandLog = path.join(directory, "commands.log");
  const policyCapture = path.join(directory, "policy.json");
  const p8Path = path.join(directory, "AuthKey_TEST.p8");
  mkdirSync(binDirectory);
  mkdirSync(stateDirectory);
  writeFileSync(path.join(stateDirectory, "resource"), resource);
  writeFileSync(path.join(stateDirectory, "versions"), versions);
  writeFileSync(path.join(stateDirectory, "iam"), iam);
  writeFileSync(
    p8Path,
    [
      "-----BEGIN PRIVATE KEY-----",
      "SENSITIVE_P8_SENTINEL_THAT_MUST_NEVER_BE_PRINTED_0123456789",
      "-----END PRIVATE KEY-----",
      "",
    ].join("\n"),
    { mode: 0o600 }
  );

  const gcloudPath = path.join(binDirectory, "gcloud");
  writeFileSync(
    gcloudPath,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >>"$COMMAND_LOG"
resource="$(cat "$STATE_DIR/resource")"
versions="$(cat "$STATE_DIR/versions")"

emit_versions() {
  case "$versions" in
    none) printf '[]\\n' ;;
    1-enabled) printf '[{"name":"projects/cyclebalance-prod-20260710/secrets/cyclebalance-app-store-iap-private-key/versions/1","state":"ENABLED"}]\\n' ;;
    1-disabled) printf '[{"name":"projects/cyclebalance-prod-20260710/secrets/cyclebalance-app-store-iap-private-key/versions/1","state":"DISABLED"}]\\n' ;;
    1-destroyed) printf '[{"name":"projects/cyclebalance-prod-20260710/secrets/cyclebalance-app-store-iap-private-key/versions/1","state":"DESTROYED"}]\\n' ;;
    2-enabled) printf '[{"name":"projects/cyclebalance-prod-20260710/secrets/cyclebalance-app-store-iap-private-key/versions/1","state":"ENABLED"},{"name":"projects/cyclebalance-prod-20260710/secrets/cyclebalance-app-store-iap-private-key/versions/2","state":"ENABLED"}]\\n' ;;
    *) exit 96 ;;
  esac
}

emit_iam() {
  local mode
  mode="$(cat "$STATE_DIR/iam")"
  if [[ -f "$STATE_DIR/policy-set" && "$versions" != "none" && -n "\${POST_IAM_AFTER_ADD:-}" ]]; then
    mode="$POST_IAM_AFTER_ADD"
  elif [[ -f "$STATE_DIR/policy-set" && -n "\${POST_IAM_MODE:-}" ]]; then
    mode="$POST_IAM_MODE"
  fi
  case "$mode" in
    exact) printf '{"version":1,"bindings":[{"role":"roles/secretmanager.secretAccessor","members":["serviceAccount:cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710.iam.gserviceaccount.com"]}]}\\n' ;;
    public) printf '{"version":1,"bindings":[{"role":"roles/secretmanager.secretAccessor","members":["allUsers"]}]}\\n' ;;
    authenticated-public) printf '{"version":1,"bindings":[{"role":"roles/secretmanager.secretAccessor","members":["allAuthenticatedUsers"]}]}\\n' ;;
    extra-accessor) printf '{"version":1,"bindings":[{"role":"roles/secretmanager.secretAccessor","members":["serviceAccount:cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710.iam.gserviceaccount.com","user:other@example.com"]}]}\\n' ;;
    extra-role) printf '{"version":1,"bindings":[{"role":"roles/secretmanager.secretAccessor","members":["serviceAccount:cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710.iam.gserviceaccount.com"]},{"role":"roles/secretmanager.viewer","members":["user:other@example.com"]}]}\\n' ;;
    *) exit 95 ;;
  esac
}

if [[ "$1 $2" == "secrets list" ]]; then
  if [[ "$resource" == "present" ]]; then
    printf '[{"name":"projects/cyclebalance-prod-20260710/secrets/cyclebalance-app-store-iap-private-key"}]\\n'
  else
    printf '[]\\n'
  fi
elif [[ "$1 $2" == "secrets describe" ]]; then
  [[ "$resource" == "present" ]] || exit 5
  printf '{"name":"projects/cyclebalance-prod-20260710/secrets/cyclebalance-app-store-iap-private-key"}\\n'
elif [[ "$1 $2 $3" == "secrets versions list" ]]; then
  [[ "$resource" == "present" ]] || exit 5
  emit_versions
elif [[ "$1 $2 $3" == "secrets versions describe" ]]; then
  [[ "$versions" == "1-enabled" ]] || exit 5
  printf '{"name":"projects/cyclebalance-prod-20260710/secrets/cyclebalance-app-store-iap-private-key/versions/1","state":"ENABLED"}\\n'
elif [[ "$1 $2" == "secrets get-iam-policy" ]]; then
  [[ "$resource" == "present" ]] || exit 5
  emit_iam
elif [[ "$1 $2" == "secrets create" ]]; then
  [[ "$resource" == "absent" ]] || exit 4
  printf 'present' >"$STATE_DIR/resource"
elif [[ "$1 $2 $3" == "secrets versions add" ]]; then
  [[ "$resource" == "present" && "$versions" == "none" ]] || exit 4
  data_file=""
  for arg in "$@"; do
    case "$arg" in --data-file=*) data_file="\${arg#--data-file=}" ;; esac
  done
  [[ -n "$data_file" && -f "$data_file" ]] || exit 3
  grep -q 'SENSITIVE_P8_SENTINEL_THAT_MUST_NEVER_BE_PRINTED_0123456789' "$data_file" || exit 3
  printf '%s' "$POST_ADD_VERSION_STATE" >"$STATE_DIR/versions"
elif [[ "$1 $2" == "secrets set-iam-policy" ]]; then
  [[ "$resource" == "present" ]] || exit 5
  cp "$4" "$POLICY_CAPTURE"
  printf 'exact' >"$STATE_DIR/iam"
  : >"$STATE_DIR/policy-set"
else
  exit 98
fi
`
  );
  chmodSync(gcloudPath, 0o755);

  return {
    directory,
    commandLog,
    policyCapture,
    p8Path,
    stateDirectory,
    environment: {
      DRY_RUN: "false",
      CONFIRM_APPLE_IAP_P8_V1: "I_APPROVE_CREATE_APPLE_IAP_P8_SECRET_VERSION_1",
      APPLE_IAP_P8_FILE: p8Path,
      PATH: `${binDirectory}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`,
      COMMAND_LOG: commandLog,
      STATE_DIR: stateDirectory,
      POLICY_CAPTURE: policyCapture,
      POST_ADD_VERSION_STATE: postAddVersions,
      POST_IAM_MODE: postIam,
      POST_IAM_AFTER_ADD: postIamAfterAdd,
    },
    cleanup() {
      rmSync(directory, { recursive: true, force: true });
    },
  };
}

test("Apple IAP p8 provisioning defaults to a non-mutating dry run", () => {
  assert.equal(existsSync(scriptPath), true, `missing ${scriptPath}`);
  assert.notEqual(statSync(scriptPath).mode & 0o111, 0, "provisioner must be executable");

  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-p8-dry-run-"));
  const binDirectory = path.join(directory, "bin");
  const commandLog = path.join(directory, "commands.log");
  mkdirSync(binDirectory);
  const gcloudPath = path.join(binDirectory, "gcloud");
  writeFileSync(
    gcloudPath,
    "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$COMMAND_LOG\"\nexit 97\n"
  );
  chmodSync(gcloudPath, 0o755);

  try {
    const result = runProvisioner({
        PATH: `${binDirectory}:/usr/bin:/bin`,
        COMMAND_LOG: commandLog,
    });

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /DRY RUN ONLY/i);
    assert.match(result.stdout, /version 1/i);
    assert.match(result.stdout, /service-account-only/i);
    assert.equal(existsSync(commandLog) ? readFileSync(commandLog, "utf8") : "", "");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("live p8 provisioning requires the exact one-time owner approval before metadata access", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-p8-approval-"));
  const binDirectory = path.join(directory, "bin");
  const commandLog = path.join(directory, "commands.log");
  mkdirSync(binDirectory);
  const gcloudPath = path.join(binDirectory, "gcloud");
  writeFileSync(
    gcloudPath,
    "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$COMMAND_LOG\"\nexit 97\n"
  );
  chmodSync(gcloudPath, 0o755);

  try {
    for (const approval of [undefined, "YES", "I_APPROVE_CREATE_VERSION_1"]) {
      const environment = {
        DRY_RUN: "false",
        PATH: `${binDirectory}:/usr/bin:/bin`,
        COMMAND_LOG: commandLog,
      };
      if (approval !== undefined) {
        environment.CONFIRM_APPLE_IAP_P8_V1 = approval;
      }
      const result = runProvisioner(environment);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /I_APPROVE_CREATE_APPLE_IAP_P8_SECRET_VERSION_1/);
    }
    assert.equal(existsSync(commandLog) ? readFileSync(commandLog, "utf8") : "", "");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("production p8 resource identities are pinned before metadata access", () => {
  for (const override of [
    { PROJECT_ID: "attacker-project" },
    { APPLE_IAP_PRIVATE_KEY_SECRET_NAME: "attacker-secret" },
    { PROXY_SERVICE_ACCOUNT: "attacker@example.iam.gserviceaccount.com" },
  ]) {
    const result = runProvisioner({
      DRY_RUN: "false",
      CONFIRM_APPLE_IAP_P8_V1: "I_APPROVE_CREATE_APPLE_IAP_P8_SECRET_VERSION_1",
      ...override,
    });
    assert.notEqual(result.status, 0, `unsafe override passed: ${JSON.stringify(override)}`);
    assert.match(result.stderr, /pinned/i);
  }
});

test("any existing p8 secret version aborts before key-file access or mutation", () => {
  for (const versions of ["1-enabled", "1-disabled", "1-destroyed", "2-enabled"]) {
    const harness = createGcloudHarness({ resource: "present", versions });
    try {
      const result = runProvisioner({
        ...harness.environment,
        APPLE_IAP_P8_FILE: path.join(harness.directory, "does-not-exist.p8"),
      });
      assert.notEqual(result.status, 0, `existing ${versions} state passed`);
      assert.match(result.stderr, /already has.*version/i);
      const commands = readFileSync(harness.commandLog, "utf8");
      assert.match(commands, /secrets list/);
      assert.match(commands, /secrets describe/);
      assert.match(commands, /secrets versions list/);
      assert.doesNotMatch(commands, /secrets create|secrets versions add|secrets set-iam-policy/);
    } finally {
      harness.cleanup();
    }
  }
});

test("an empty secret with a public principal aborts before version creation", () => {
  for (const iam of ["public", "authenticated-public"]) {
    const harness = createGcloudHarness({ resource: "present", versions: "none", iam });
    try {
      const result = runProvisioner({
        ...harness.environment,
        APPLE_IAP_P8_FILE: path.join(harness.directory, "does-not-exist.p8"),
      });
      assert.notEqual(result.status, 0, `public IAM mode ${iam} passed`);
      assert.match(result.stderr, /public principal/i);
      const commands = readFileSync(harness.commandLog, "utf8");
      assert.match(commands, /secrets get-iam-policy/);
      assert.doesNotMatch(commands, /secrets versions add|secrets set-iam-policy/);
    } finally {
      harness.cleanup();
    }
  }
});

test("zero versions transitions once to enabled v1 with exact proxy-only secretAccessor IAM", () => {
  for (const resource of ["absent", "present"]) {
    const harness = createGcloudHarness({ resource, versions: "none", iam: "extra-role" });
    try {
      const result = runProvisioner(harness.environment);
      assert.equal(result.status, 0, result.stderr);
      assert.match(result.stdout, /enabled version 1/i);
      assert.match(result.stdout, /proxy service account only/i);

      const commands = readFileSync(harness.commandLog, "utf8").trim().split("\n");
      assert.match(commands[0], /^secrets list /, "secret inventory must be first");
      const createCalls = commands.filter((line) => /^secrets create /.test(line));
      assert.equal(createCalls.length, resource === "absent" ? 1 : 0);
      assert.equal(commands.filter((line) => /^secrets versions add /.test(line)).length, 1);
      assert.ok(
        commands.findIndex((line) => /^secrets versions list /.test(line)) <
          commands.findIndex((line) => /^secrets versions add /.test(line)),
        "zero-version metadata must be read before the add"
      );
      const setIamIndex = commands.findIndex((line) => /^secrets set-iam-policy /.test(line));
      const addVersionIndex = commands.findIndex((line) => /^secrets versions add /.test(line));
      assert.ok(setIamIndex >= 0 && setIamIndex < addVersionIndex, "exact IAM must be set before key material exists");
      assert.ok(
        commands.slice(setIamIndex + 1, addVersionIndex).some((line) => /^secrets get-iam-policy /.test(line)),
        "exact IAM must be read back before key material exists"
      );
      assert.ok(
        commands.slice(setIamIndex + 1, addVersionIndex).some((line) => /^secrets versions list /.test(line)),
        "zero versions must be re-read after IAM hardening and immediately before the only add"
      );
      assert.match(commands.join("\n"), /secrets versions describe 1 /);
      assert.equal(readFileSync(path.join(harness.stateDirectory, "versions"), "utf8"), "1-enabled");

      const policy = JSON.parse(readFileSync(harness.policyCapture, "utf8"));
      assert.deepEqual(policy.bindings, [
        {
          role: "roles/secretmanager.secretAccessor",
          members: [
            "serviceAccount:cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710.iam.gserviceaccount.com",
          ],
        },
      ]);

      const allOutput = `${result.stdout}\n${result.stderr}\n${commands.join("\n")}`;
      assert.doesNotMatch(allOutput, /SENSITIVE_P8_SENTINEL/);
      assert.doesNotMatch(allOutput, /BEGIN PRIVATE KEY|END PRIVATE KEY/);
    } finally {
      harness.cleanup();
    }
  }
});

test("version and IAM readbacks reject v2, disabled v1, public IAM, or any extra IAM member or role", () => {
  for (const postAddVersions of ["2-enabled", "1-disabled"]) {
    const harness = createGcloudHarness({ postAddVersions });
    try {
      const result = runProvisioner(harness.environment);
      assert.notEqual(result.status, 0, `unsafe post-add state ${postAddVersions} passed`);
      assert.match(result.stderr, /exactly.*enabled.*version 1/i);
      const commands = readFileSync(harness.commandLog, "utf8");
      assert.equal((commands.match(/secrets versions add/g) ?? []).length, 1);
      assert.doesNotMatch(commands, /versions add[\s\S]*versions add/);
    } finally {
      harness.cleanup();
    }
  }

  for (const postIam of ["public", "authenticated-public", "extra-accessor", "extra-role"]) {
    const harness = createGcloudHarness({ postIam });
    try {
      const result = runProvisioner(harness.environment);
      assert.notEqual(result.status, 0, `unsafe IAM readback ${postIam} passed`);
      assert.match(
        result.stderr,
        /public principal|exact.*service-account-only.*secretAccessor IAM/i
      );
      const commands = readFileSync(harness.commandLog, "utf8");
      assert.equal((commands.match(/secrets versions add/g) ?? []).length, 0);
      assert.equal((commands.match(/secrets set-iam-policy/g) ?? []).length, 1);
      assert.match(commands, /secrets get-iam-policy/);
    } finally {
      harness.cleanup();
    }
  }

  for (const postIamAfterAdd of ["public", "extra-accessor", "extra-role"]) {
    const harness = createGcloudHarness({ postIamAfterAdd });
    try {
      const result = runProvisioner(harness.environment);
      assert.notEqual(result.status, 0, `unsafe post-add IAM readback ${postIamAfterAdd} passed`);
      assert.match(
        result.stderr,
        /public principal|exact.*service-account-only.*secretAccessor IAM/i
      );
      const commands = readFileSync(harness.commandLog, "utf8");
      assert.equal((commands.match(/secrets versions add/g) ?? []).length, 1);
      assert.equal((commands.match(/secrets set-iam-policy/g) ?? []).length, 1);
    } finally {
      harness.cleanup();
    }
  }
});
