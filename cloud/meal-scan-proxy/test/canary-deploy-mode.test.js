import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const proxyDirectory = path.resolve(testDirectory, "..");
const scriptPath = path.join(proxyDirectory, "scripts/deploy-cloud-run.sh");

function runCanary(overrides = {}) {
  const directory = mkdtempSync(path.join(tmpdir(), "cyclebalance-canary-deploy-"));
  const bin = path.join(directory, "bin");
  const log = path.join(directory, "commands.log");
  mkdirSync(bin);
  writeFileSync(path.join(bin, "gcloud"), `#!/usr/bin/env bash
printf 'gcloud %s\n' "$*" >> "$COMMAND_LOG"
if [[ "$*" == *"run services describe"* ]]; then printf 'https://canary.example.run.app\n'; fi
`);
  writeFileSync(path.join(bin, "curl"), `#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$COMMAND_LOG"
printf '403'
`);
  chmodSync(path.join(bin, "gcloud"), 0o755);
  chmodSync(path.join(bin, "curl"), 0o755);
  const result = spawnSync("bash", [scriptPath], {
    cwd: proxyDirectory,
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${bin}:/usr/bin:/bin`,
      COMMAND_LOG: log,
      DEPLOY_MODE: "canary",
      PROJECT_ID: "cyclebalance-prod-20260710",
      REGION: "us-central1",
      SERVICE_NAME: "cyclebalance-meal-scan-proxy",
      GEMINI_SECRET_VERSION: "1",
      MEAL_SCAN_ENABLED: "false",
      ALLOW_UNAUTHENTICATED: "false",
      MEAL_SCAN_CANARY_CORRELATION_SHA256: "a".repeat(64),
      ...overrides,
    },
  });
  const commands = existsSync(log) ? readFileSync(log, "utf8") : "";
  rmSync(directory, { recursive: true, force: true });
  return { result, commands };
}

test("canary deploy touches only pinned Cloud Run state and skips global config plus Firestore Rules", () => {
  const { result, commands } = runCanary();

  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(commands, /gcloud config set/);
  assert.doesNotMatch(commands, /gcloud firestore|firebaserules\.googleapis\.com|\/rulesets/i);
  assert.match(commands, /gcloud run deploy cyclebalance-meal-scan-proxy/);
  assert.match(commands, /gcloud run services update cyclebalance-meal-scan-proxy/);
  assert.match(commands, new RegExp(`MEAL_SCAN_CANARY_CORRELATION_SHA256=${"a".repeat(64)}`));
});

test("canary deploy rejects identity drift and missing or malformed correlation before mutation", () => {
  for (const overrides of [
    { PROJECT_ID: "other-project" },
    { REGION: "europe-west1" },
    { SERVICE_NAME: "other-service" },
    { MEAL_SCAN_CANARY_CORRELATION_SHA256: "" },
    { MEAL_SCAN_CANARY_CORRELATION_SHA256: "not-a-digest" },
  ]) {
    const { result, commands } = runCanary(overrides);
    assert.notEqual(result.status, 0, JSON.stringify(overrides));
    assert.doesNotMatch(commands, /gcloud run (deploy|services update)/);
  }
});
