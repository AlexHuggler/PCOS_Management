import assert from "node:assert/strict";
import { existsSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(testDirectory, "../../..");
const scriptPath = path.join(
  repositoryRoot,
  "scripts/open_general_kenobi_scanner_canary_xcode.sh",
);
const scriptExists = existsSync(scriptPath);
const scriptSource = scriptExists ? readFileSync(scriptPath, "utf8") : "";

test("Xcode canary staging script exists and is executable", () => {
  assert.equal(scriptExists, true, `missing staging script: ${scriptPath}`);
  assert.notEqual(statSync(scriptPath).mode & 0o111, 0, "staging script must be executable");
});

test("Xcode canary staging script exposes a non-mutating help path", () => {
  assert.equal(scriptExists, true, `missing staging script: ${scriptPath}`);

  const result = spawnSync(scriptPath, ["--help"], {
    cwd: repositoryRoot,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Usage: .*open_general_kenobi_scanner_canary_xcode\.sh \[--no-open\]/);
  assert.match(result.stdout, /local Xcode signing\/launch rehearsal/i);
  assert.match(result.stdout, /does not mutate cloud or device state/i);
});

test("Xcode canary staging script validates the clean ignored-config boundary", () => {
  assert.match(scriptSource, /set -euo pipefail/);
  assert.match(scriptSource, /git status --porcelain --untracked-files=all/);
  assert.match(scriptSource, /git check-ignore -q ["']?\$LOCAL_SECRETS_CONFIG["']?/);
  assert.match(scriptSource, /xcconfig_value ["']?\$LOCAL_SECRETS_CONFIG["']? REVENUECAT_PUBLIC_SDK_KEY/);
  assert.match(scriptSource, /xcconfig_value ["']?\$LOCAL_SECRETS_CONFIG["']? MEAL_SCAN_PROXY_BASE_URL/);
  assert.match(
    scriptSource,
    /readonly PINNED_PROXY_URL="https:\/\/cyclebalance-meal-scan-proxy-mdd7lrfyqa-uc\.a\.run\.app"/,
  );

  for (const command of ["git", "xcodegen", "xcodebuild", "awk", "grep"]) {
    assert.match(scriptSource, new RegExp(`require_command ${command}`));
  }

  assert.match(scriptSource, /--no-open/);
  assert.match(scriptSource, /require_command open/);
  assert.match(scriptSource, /open ["']?\$ROOT\/PCOS\.xcodeproj["']?/);
});

test("Xcode canary staging script performs only local dry-run generation and setting checks", () => {
  assert.match(
    scriptSource,
    /DRY_RUN=true cloud\/meal-scan-proxy\/scripts\/run-positive-general-kenobi-canary\.sh >\/dev\/null/,
  );
  assert.match(scriptSource, /xcodegen generate/);
  assert.match(scriptSource, /mktemp/);
  assert.match(scriptSource, /trap .*EXIT/);
  assert.match(scriptSource, /xcodebuild[^\n]*-configuration Release[^\n]*-showBuildSettings[^\n]*CODE_SIGNING_ALLOWED=NO/);
  assert.match(scriptSource, /xcodebuild[^\n]*-configuration ScannerCanary[^\n]*-showBuildSettings[^\n]*CODE_SIGNING_ALLOWED=NO/);

  for (const setting of [
    "MEAL_SCAN_RELEASE_UI_ENABLED",
    "MEAL_SCAN_RELEASE_GEMINI_ENABLED",
    "MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED",
    "MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED",
    "MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED",
    "MEAL_SCAN_RELEASE_SIMILARITY_ENABLED",
  ]) {
    assert.match(scriptSource, new RegExp(`require_setting [^\\n]* ${setting} NO`));
  }

  for (const setting of [
    "MEAL_SCAN_RELEASE_UI_ENABLED",
    "MEAL_SCAN_RELEASE_GEMINI_ENABLED",
  ]) {
    assert.match(scriptSource, new RegExp(`require_setting [^\\n]* ${setting} YES`));
  }

  for (const setting of [
    "MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED",
    "MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED",
    "MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED",
    "MEAL_SCAN_RELEASE_SIMILARITY_ENABLED",
  ]) {
    assert.match(scriptSource, new RegExp(`require_setting [^\\n]* ${setting} NO`));
  }
});

test("Xcode canary staging script preserves the shared Release archive boundary and handoff", () => {
  assert.match(scriptSource, /readonly SCHEME_NAME="PCOS General Kenobi Scanner Canary"/);
  assert.match(
    scriptSource,
    /PCOS\.xcodeproj\/xcshareddata\/xcschemes\/PCOS General Kenobi Scanner Canary\.xcscheme/,
  );
  assert.match(scriptSource, /<ArchiveAction/);
  assert.match(scriptSource, /buildConfiguration = ["']Release["']/);
  assert.match(scriptSource, /Scheme: PCOS General Kenobi Scanner Canary/);
  assert.match(scriptSource, /Device: General Kenobi/);
  assert.match(scriptSource, /Product > Run/);
  assert.match(scriptSource, /audited terminal harness/i);
});

test("Xcode canary staging script contains no live or mutating path", () => {
  for (const prohibited of [
    /DRY_RUN=false/,
    /I_APPROVE_GENERAL_KENOBI_POSITIVE_CANARY_WITH_TEMPORARY_PUBLIC_CLOUD_RUN/,
    /\bgcloud\b/,
    /\bdevicectl\b/,
    /device install/,
    /xcodebuild[^\n]*archive/,
    /-exportArchive/,
    /sandbox.*password/i,
  ]) {
    assert.doesNotMatch(scriptSource, prohibited);
  }
});
