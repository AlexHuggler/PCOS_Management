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
import { generateKeyPairSync } from "node:crypto";
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
  labels = "none",
  postAddVersions = "1-enabled",
  postIam = "",
  postIamAfterAdd = "",
  resourceProject = "947929010052",
  failClaimCas = false,
  mutateSourceBeforeUpload = false,
} = {}) {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-p8-gcloud-"));
  const binDirectory = path.join(directory, "bin");
  const stateDirectory = path.join(directory, "state");
  const commandLog = path.join(directory, "commands.log");
  const policyCapture = path.join(directory, "policy.json");
  const uploadedKeyCapture = path.join(directory, "uploaded-key.p8");
  const p8Path = path.join(directory, "AuthKey_TEST.p8");
  const { privateKey: privateKeyPem } = generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
    publicKeyEncoding: { type: "spki", format: "pem" },
  });
  const { privateKey: replacementPrivateKeyPem } = generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
    publicKeyEncoding: { type: "spki", format: "pem" },
  });
  mkdirSync(binDirectory);
  mkdirSync(stateDirectory);
  writeFileSync(path.join(stateDirectory, "resource"), resource);
  writeFileSync(path.join(stateDirectory, "versions"), versions);
  writeFileSync(path.join(stateDirectory, "iam"), iam);
  writeFileSync(path.join(stateDirectory, "etag"), "etag-1");
  writeFileSync(path.join(stateDirectory, "labels"), labels === "locked"
    ? '{"cyclebalance_iap_provision_state":"locked","cyclebalance_iap_provision_owner":"foreign-owner"}'
    : labels === "complete"
      ? '{"cyclebalance_iap_provision_state":"complete","cyclebalance_iap_provision_owner":"prior-owner"}'
      : "{}");
  writeFileSync(p8Path, privateKeyPem, { mode: 0o600 });
  const replacementP8Path = path.join(directory, "replacement.p8");
  writeFileSync(replacementP8Path, replacementPrivateKeyPem, { mode: 0o600 });

  const gcloudPath = path.join(binDirectory, "gcloud");
  writeFileSync(
    gcloudPath,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >>"$COMMAND_LOG"
resource="$(cat "$STATE_DIR/resource")"
versions="$(cat "$STATE_DIR/versions")"

option_value() {
  local prefix="$1"
  shift
  local arg
  for arg in "$@"; do
    case "$arg" in "$prefix"*) printf '%s' "\${arg#"$prefix"}"; return 0 ;; esac
  done
  return 1
}

write_labels() {
  local value="$1" state owner
  state="$(printf '%s' "$value" | sed -n 's/.*cyclebalance_iap_provision_state=\\([^,]*\\).*/\\1/p')"
  owner="$(printf '%s' "$value" | sed -n 's/.*cyclebalance_iap_provision_owner=\\([^,]*\\).*/\\1/p')"
  [[ -n "$state" && -n "$owner" ]] || exit 92
  printf '{"cyclebalance_iap_provision_state":"%s","cyclebalance_iap_provision_owner":"%s"}' \
    "$state" "$owner" >"$STATE_DIR/labels"
}

capture_data_file() {
  local data_file="$1"
  if [[ "$MUTATE_SOURCE_BEFORE_UPLOAD" == "true" && ! -f "$STATE_DIR/source-mutated" ]]; then
    cp "$REPLACEMENT_P8_PATH" "$P8_SOURCE_PATH"
    chmod 0600 "$P8_SOURCE_PATH"
    : >"$STATE_DIR/source-mutated"
  fi
  [[ -n "$data_file" && -f "$data_file" && -s "$data_file" ]] || exit 3
  cp "$data_file" "$UPLOADED_KEY_CAPTURE"
}

emit_versions() {
  case "$versions" in
    none) printf '[]\\n' ;;
    1-enabled) printf '[{"name":"projects/%s/secrets/cyclebalance-app-store-iap-private-key/versions/1","state":"ENABLED"}]\\n' "$RESOURCE_PROJECT" ;;
    1-disabled) printf '[{"name":"projects/%s/secrets/cyclebalance-app-store-iap-private-key/versions/1","state":"DISABLED"}]\\n' "$RESOURCE_PROJECT" ;;
    1-destroyed) printf '[{"name":"projects/%s/secrets/cyclebalance-app-store-iap-private-key/versions/1","state":"DESTROYED"}]\\n' "$RESOURCE_PROJECT" ;;
    2-enabled) printf '[{"name":"projects/%s/secrets/cyclebalance-app-store-iap-private-key/versions/1","state":"ENABLED"},{"name":"projects/%s/secrets/cyclebalance-app-store-iap-private-key/versions/2","state":"ENABLED"}]\\n' "$RESOURCE_PROJECT" "$RESOURCE_PROJECT" ;;
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
    conditional) printf '{"version":3,"bindings":[{"role":"roles/secretmanager.secretAccessor","members":["serviceAccount:cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710.iam.gserviceaccount.com"],"condition":{"title":"temporary","expression":"request.time < timestamp(2030-01-01T00:00:00Z)"}}]}\\n' ;;
    audited) printf '{"version":1,"bindings":[{"role":"roles/secretmanager.secretAccessor","members":["serviceAccount:cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710.iam.gserviceaccount.com"]}],"auditConfigs":[{"service":"secretmanager.googleapis.com"}]}\\n' ;;
    *) exit 95 ;;
  esac
}

if [[ "$1 $2" == "secrets list" ]]; then
  if [[ "$resource" == "present" ]]; then
    printf '[{"name":"projects/%s/secrets/cyclebalance-app-store-iap-private-key"}]\\n' "$RESOURCE_PROJECT"
  else
    printf '[]\\n'
  fi
elif [[ "$1 $2" == "secrets describe" ]]; then
  [[ "$resource" == "present" ]] || exit 5
  printf '{"name":"projects/%s/secrets/cyclebalance-app-store-iap-private-key","etag":"%s","labels":%s}\\n' \
    "$RESOURCE_PROJECT" "$(cat "$STATE_DIR/etag")" "$(cat "$STATE_DIR/labels")"
elif [[ "$1 $2 $3" == "secrets versions list" ]]; then
  [[ "$resource" == "present" ]] || exit 5
  emit_versions
elif [[ "$1 $2 $3" == "secrets versions describe" ]]; then
  [[ "$versions" == "1-enabled" ]] || exit 5
  printf '{"name":"projects/%s/secrets/cyclebalance-app-store-iap-private-key/versions/1","state":"ENABLED"}\\n' "$RESOURCE_PROJECT"
elif [[ "$1 $2" == "secrets get-iam-policy" ]]; then
  [[ "$resource" == "present" ]] || exit 5
  emit_iam
elif [[ "$1 $2" == "secrets create" ]]; then
  [[ "$resource" == "absent" ]] || exit 4
  data_file="$(option_value --data-file= "$@" || true)"
  label_value="$(option_value --labels= "$@" || true)"
  capture_data_file "$data_file"
  write_labels "$label_value"
  printf 'present' >"$STATE_DIR/resource"
  printf '%s' "$POST_ADD_VERSION_STATE" >"$STATE_DIR/versions"
elif [[ "$1 $2" == "secrets update" ]]; then
  [[ "$resource" == "present" ]] || exit 5
  supplied_etag="$(option_value --etag= "$@" || true)"
  label_value="$(option_value --update-labels= "$@" || true)"
  [[ -n "$supplied_etag" && "$supplied_etag" == "$(cat "$STATE_DIR/etag")" ]] || exit 9
  if [[ "$FAIL_CLAIM_CAS" == "true" && "$label_value" == *"provision_state=locked"* ]]; then
    exit 9
  fi
  write_labels "$label_value"
  current_etag="$(cat "$STATE_DIR/etag")"
  etag_number="\${current_etag#etag-}"
  printf 'etag-%s' "$((etag_number + 1))" >"$STATE_DIR/etag"
elif [[ "$1 $2 $3" == "secrets versions add" ]]; then
  [[ "$resource" == "present" && "$versions" == "none" ]] || exit 4
  data_file="$(option_value --data-file= "$@" || true)"
  capture_data_file "$data_file"
  printf '%s' "$POST_ADD_VERSION_STATE" >"$STATE_DIR/versions"
elif [[ "$1 $2" == "secrets set-iam-policy" ]]; then
  [[ "$resource" == "present" ]] || exit 5
  if [[ "$MUTATE_SOURCE_BEFORE_UPLOAD" == "true" && ! -f "$STATE_DIR/source-mutated" ]]; then
    cp "$REPLACEMENT_P8_PATH" "$P8_SOURCE_PATH"
    chmod 0600 "$P8_SOURCE_PATH"
    : >"$STATE_DIR/source-mutated"
  fi
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
    uploadedKeyCapture,
    p8Path,
    privateKeyPem,
    replacementPrivateKeyPem,
    stateDirectory,
    environment: {
      DRY_RUN: "false",
      CONFIRM_APPLE_IAP_P8_V1: "I_APPROVE_CREATE_APPLE_IAP_P8_SECRET_VERSION_1",
      APPLE_IAP_P8_FILE: p8Path,
      PATH: `${binDirectory}:${path.dirname(process.execPath)}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`,
      COMMAND_LOG: commandLog,
      STATE_DIR: stateDirectory,
      POLICY_CAPTURE: policyCapture,
      UPLOADED_KEY_CAPTURE: uploadedKeyCapture,
      POST_ADD_VERSION_STATE: postAddVersions,
      POST_IAM_MODE: postIam,
      POST_IAM_AFTER_ADD: postIamAfterAdd,
      RESOURCE_PROJECT: resourceProject,
      FAIL_CLAIM_CAS: failClaimCas ? "true" : "false",
      MUTATE_SOURCE_BEFORE_UPLOAD: mutateSourceBeforeUpload ? "true" : "false",
      P8_SOURCE_PATH: p8Path,
      REPLACEMENT_P8_PATH: replacementP8Path,
    },
    cleanup() {
      rmSync(directory, { recursive: true, force: true });
    },
  };
}

test("Apple IAP p8 dry run performs only authenticated read-only metadata inspection", () => {
  assert.equal(existsSync(scriptPath), true, `missing ${scriptPath}`);
  assert.notEqual(statSync(scriptPath).mode & 0o111, 0, "provisioner must be executable");

  for (const resource of ["absent", "present"]) {
    const harness = createGcloudHarness({ resource, versions: "none", iam: "exact" });
    try {
      const result = runProvisioner({
        ...harness.environment,
        DRY_RUN: "true",
        APPLE_IAP_P8_FILE: path.join(harness.directory, "must-not-be-read.p8"),
      });
      assert.equal(result.status, 0, `${resource}: ${result.stderr}`);
      assert.match(result.stdout, /read-only metadata inspection/i);
      assert.match(result.stdout, new RegExp(`resource: ${resource}`, "i"));
      assert.match(result.stdout, /versions: 0/i);
      const commands = existsSync(harness.commandLog) ? readFileSync(harness.commandLog, "utf8") : "";
      assert.match(commands, /^secrets list /m);
      if (resource === "present") {
        assert.match(commands, /^secrets describe /m);
        assert.match(commands, /^secrets versions list /m);
        assert.match(commands, /^secrets get-iam-policy /m);
      } else {
        assert.doesNotMatch(commands, /secrets describe|secrets versions list|secrets get-iam-policy/);
      }
      assert.doesNotMatch(commands, /secrets create|secrets set-iam-policy|secrets versions add/);
    } finally {
      harness.cleanup();
    }
  }
});

test("Apple IAP inventory matches the short secret name and validates the pinned numeric project resource", () => {
  const harness = createGcloudHarness({
    resource: "present",
    versions: "none",
    iam: "exact",
    resourceProject: "947929010052",
  });
  try {
    const result = runProvisioner({
      ...harness.environment,
      DRY_RUN: "true",
      APPLE_IAP_P8_FILE: path.join(harness.directory, "must-not-be-read.p8"),
    });
    assert.equal(result.status, 0, result.stderr);
    const commands = readFileSync(harness.commandLog, "utf8");
    assert.match(
      commands,
      /secrets list .*--project cyclebalance-prod-20260710 .*--filter=name:cyclebalance-app-store-iap-private-key/
    );
  } finally {
    harness.cleanup();
  }
});

test("live p8 approval is evaluated only after safe zero-version metadata inspection", () => {
  for (const approval of ["", "YES", "I_APPROVE_CREATE_VERSION_1"]) {
    const harness = createGcloudHarness({ resource: "present", versions: "none", iam: "exact" });
    try {
      const result = runProvisioner({
        ...harness.environment,
        CONFIRM_APPLE_IAP_P8_V1: approval,
        APPLE_IAP_P8_FILE: path.join(harness.directory, "must-not-be-read.p8"),
      });
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /I_APPROVE_CREATE_APPLE_IAP_P8_SECRET_VERSION_1/);
      const commands = existsSync(harness.commandLog) ? readFileSync(harness.commandLog, "utf8") : "";
      assert.match(commands, /secrets list/);
      assert.match(commands, /secrets describe/);
      assert.match(commands, /secrets versions list/);
      assert.match(commands, /secrets get-iam-policy/);
      assert.doesNotMatch(commands, /secrets create|secrets set-iam-policy|secrets versions add/);
    } finally {
      harness.cleanup();
    }
  }

  const existingVersion = createGcloudHarness({ resource: "present", versions: "1-disabled", iam: "exact" });
  try {
    const result = runProvisioner({
      ...existingVersion.environment,
      CONFIRM_APPLE_IAP_P8_V1: "",
      APPLE_IAP_P8_FILE: path.join(existingVersion.directory, "must-not-be-read.p8"),
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /already has.*version/i);
    assert.doesNotMatch(result.stderr, /live provisioning requires/);
  } finally {
    existingVersion.cleanup();
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

test("fake, RSA, and wrong-curve PKCS8 material is rejected before any mutation", () => {
  const { privateKey: rsaPrivateKey } = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
    publicKeyEncoding: { type: "spki", format: "pem" },
  });
  const { privateKey: p384PrivateKey } = generateKeyPairSync("ec", {
    namedCurve: "secp384r1",
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
    publicKeyEncoding: { type: "spki", format: "pem" },
  });
  const candidates = [
    [
      "-----BEGIN PRIVATE KEY-----",
      "SENSITIVE_FAKE_P8_SENTINEL_THAT_IS_NOT_VALID_DER_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ",
      "-----END PRIVATE KEY-----",
      "",
    ].join("\n"),
    rsaPrivateKey,
    p384PrivateKey,
  ];

  for (const candidate of candidates) {
    const harness = createGcloudHarness({ resource: "present", versions: "none", iam: "exact" });
    try {
      writeFileSync(harness.p8Path, candidate, { mode: 0o600 });
      const result = runProvisioner(harness.environment);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /valid PKCS8 P-256 EC private key/i);
      const commands = readFileSync(harness.commandLog, "utf8");
      assert.doesNotMatch(commands, /secrets create|secrets set-iam-policy|secrets versions add/);
      const allOutput = `${result.stdout}\n${result.stderr}\n${commands}`;
      for (const line of candidate.split("\n").filter((line) => line && !line.startsWith("-----"))) {
        assert.equal(allOutput.includes(line), false, "private key material leaked into output");
      }
    } finally {
      harness.cleanup();
    }
  }
});

test("an absent secret is created atomically with sealed data and a provisioning owner", () => {
  const harness = createGcloudHarness({ resource: "absent", versions: "none", iam: "extra-role" });
  try {
    const result = runProvisioner(harness.environment);
    assert.equal(result.status, 0, result.stderr);
    const commands = readFileSync(harness.commandLog, "utf8").trim().split("\n");
    const createCalls = commands.filter((line) => /^secrets create /.test(line));
    assert.equal(createCalls.length, 1);
    assert.match(createCalls[0], /--data-file=/);
    assert.match(createCalls[0], /--labels=.*cyclebalance_iap_provision_state=locked/);
    assert.match(createCalls[0], /cyclebalance_iap_provision_owner=/);
    assert.equal(commands.filter((line) => /^secrets versions add /.test(line)).length, 0);
    assert.equal(readFileSync(harness.uploadedKeyCapture, "utf8"), harness.privateKeyPem);
    const labels = JSON.parse(readFileSync(path.join(harness.stateDirectory, "labels"), "utf8"));
    assert.equal(labels.cyclebalance_iap_provision_state, "complete");
    assert.match(labels.cyclebalance_iap_provision_owner, /^[a-f0-9]{32}$/);
  } finally {
    harness.cleanup();
  }
});

test("a present zero-version secret is CAS-locked before IAM or version mutation", () => {
  const harness = createGcloudHarness({ resource: "present", versions: "none", iam: "extra-role" });
  try {
    const result = runProvisioner(harness.environment);
    assert.equal(result.status, 0, result.stderr);
    const commands = readFileSync(harness.commandLog, "utf8").trim().split("\n");
    const lockIndex = commands.findIndex((line) => (
      /^secrets update /.test(line) && /provision_state=locked/.test(line)
    ));
    const setIamIndex = commands.findIndex((line) => /^secrets set-iam-policy /.test(line));
    const addIndex = commands.findIndex((line) => /^secrets versions add /.test(line));
    const completeIndex = commands.findIndex((line) => (
      /^secrets update /.test(line) && /provision_state=complete/.test(line)
    ));
    assert.ok(lockIndex >= 0 && lockIndex < setIamIndex);
    assert.ok(setIamIndex < addIndex && addIndex < completeIndex);
    assert.match(commands[lockIndex], /--etag=etag-1/);
    assert.equal(readFileSync(harness.uploadedKeyCapture, "utf8"), harness.privateKeyPem);
  } finally {
    harness.cleanup();
  }
});

test("a failed provisioning-label CAS performs no IAM or version mutation", () => {
  const harness = createGcloudHarness({
    resource: "present",
    versions: "none",
    iam: "extra-role",
    failClaimCas: true,
  });
  try {
    const result = runProvisioner(harness.environment);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /lock|concurrent|etag|claim/i);
    const commands = readFileSync(harness.commandLog, "utf8");
    assert.match(commands, /^secrets update /m);
    assert.doesNotMatch(commands, /secrets set-iam-policy|secrets versions add|secrets create/);
    assert.equal(readFileSync(path.join(harness.stateDirectory, "versions"), "utf8"), "none");
  } finally {
    harness.cleanup();
  }
});

test("an existing provisioning lock is refused before key-file access or mutation", () => {
  const harness = createGcloudHarness({
    resource: "present",
    versions: "none",
    iam: "exact",
    labels: "locked",
  });
  try {
    const result = runProvisioner({
      ...harness.environment,
      APPLE_IAP_P8_FILE: path.join(harness.directory, "must-not-be-read.p8"),
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /lock|claimed|manual/i);
    const commands = readFileSync(harness.commandLog, "utf8");
    assert.doesNotMatch(commands, /secrets update|secrets set-iam-policy|secrets versions add|secrets create/);
  } finally {
    harness.cleanup();
  }
});

test("source-path replacement after validation cannot change the sealed uploaded key", () => {
  for (const resource of ["absent", "present"]) {
    const harness = createGcloudHarness({
      resource,
      versions: "none",
      iam: "extra-role",
      mutateSourceBeforeUpload: true,
    });
    try {
      const result = runProvisioner(harness.environment);
      assert.equal(result.status, 0, resource + ": " + result.stderr);
      assert.equal(readFileSync(harness.p8Path, "utf8"), harness.replacementPrivateKeyPem);
      assert.equal(readFileSync(harness.uploadedKeyCapture, "utf8"), harness.privateKeyPem);
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
      assert.equal(
        commands.filter((line) => /^secrets versions add /.test(line)).length,
        resource === "present" ? 1 : 0
      );
      const setIamIndex = commands.findIndex((line) => /^secrets set-iam-policy /.test(line));
      const addVersionIndex = commands.findIndex((line) => /^secrets versions add /.test(line));
      if (resource === "present") {
        assert.ok(
          commands.findIndex((line) => /^secrets versions list /.test(line)) < addVersionIndex,
          "zero-version metadata must be read before the add"
        );
        assert.ok(setIamIndex >= 0 && setIamIndex < addVersionIndex, "exact IAM must be set before key material exists");
        assert.ok(
          commands.slice(setIamIndex + 1, addVersionIndex).some((line) => /^secrets get-iam-policy /.test(line)),
          "exact IAM must be read back before key material exists"
        );
        assert.ok(
          commands.slice(setIamIndex + 1, addVersionIndex).some((line) => /^secrets versions list /.test(line)),
          "zero versions must be re-read after IAM hardening and immediately before the only add"
        );
      } else {
        assert.match(createCalls[0], /--data-file=/);
        assert.ok(commands.indexOf(createCalls[0]) < setIamIndex);
      }
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
      assert.doesNotMatch(allOutput, /BEGIN PRIVATE KEY|END PRIVATE KEY/);
      for (const line of harness.privateKeyPem.split("\n").filter((line) => line && !line.startsWith("-----"))) {
        assert.equal(allOutput.includes(line), false, "private key material leaked into output");
      }
    } finally {
      harness.cleanup();
    }
  }
});

test("version and IAM readbacks reject v2, disabled v1, public, conditional, audited, or extra IAM", () => {
  for (const postAddVersions of ["2-enabled", "1-disabled"]) {
    const harness = createGcloudHarness({ postAddVersions });
    try {
      const result = runProvisioner(harness.environment);
      assert.notEqual(result.status, 0, `unsafe post-add state ${postAddVersions} passed`);
      assert.match(result.stderr, /exactly.*enabled.*version 1/i);
      const commands = readFileSync(harness.commandLog, "utf8");
      assert.equal((commands.match(/secrets versions add/g) ?? []).length, 0);
      assert.doesNotMatch(commands, /versions add[\s\S]*versions add/);
    } finally {
      harness.cleanup();
    }
  }

  for (const postIam of ["public", "authenticated-public", "extra-accessor", "extra-role", "conditional", "audited"]) {
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

  for (const postIamAfterAdd of ["public", "extra-accessor", "extra-role", "conditional", "audited"]) {
    const harness = createGcloudHarness({ resource: "present", postIamAfterAdd });
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
