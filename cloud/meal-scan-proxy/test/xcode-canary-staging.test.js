import assert from "node:assert/strict";
import {
  chmodSync,
  copyFileSync,
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
const repositoryRoot = path.resolve(testDirectory, "../../..");
const scriptPath = path.join(
  repositoryRoot,
  "scripts/open_general_kenobi_scanner_canary_xcode.sh",
);
const scriptExists = existsSync(scriptPath);
const scriptSource = scriptExists ? readFileSync(scriptPath, "utf8") : "";
const pinnedProxyURL = "https://cyclebalance-meal-scan-proxy-mdd7lrfyqa-uc.a.run.app";
const rawRevenueCatKey = "appl_raw_fixture_value";

function writeExecutable(filePath, source) {
  writeFileSync(filePath, source);
  chmodSync(filePath, 0o755);
}

function runStagingScriptWithEffectiveSettings({
  releaseProxyURL = pinnedProxyURL,
  releaseRevenueCatKey = "appl_effective_release_fixture",
  scannerCanaryProxyURL = pinnedProxyURL,
  scannerCanaryRevenueCatKey = "appl_effective_scanner_fixture",
} = {}) {
  const fixtureRoot = mkdtempSync(path.join(tmpdir(), "cyclebalance-xcode-canary-"));

  try {
    const fixtureScriptPath = path.join(
      fixtureRoot,
      "scripts/open_general_kenobi_scanner_canary_xcode.sh",
    );
    const positiveCanaryPath = path.join(
      fixtureRoot,
      "cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh",
    );
    const localSecretsPath = path.join(fixtureRoot, "Config/LocalSecrets.xcconfig");
    const schemePath = path.join(
      fixtureRoot,
      "PCOS.xcodeproj/xcshareddata/xcschemes/PCOS General Kenobi Scanner Canary.xcscheme",
    );
    const shimDirectory = path.join(fixtureRoot, "command-shims");

    for (const directory of [
      path.dirname(fixtureScriptPath),
      path.dirname(positiveCanaryPath),
      path.dirname(localSecretsPath),
      path.dirname(schemePath),
      shimDirectory,
    ]) {
      mkdirSync(directory, { recursive: true });
    }

    copyFileSync(scriptPath, fixtureScriptPath);
    chmodSync(fixtureScriptPath, 0o755);
    writeFileSync(
      localSecretsPath,
      [
        `REVENUECAT_PUBLIC_SDK_KEY = ${rawRevenueCatKey}`,
        `MEAL_SCAN_PROXY_BASE_URL = ${pinnedProxyURL}`,
        "",
      ].join("\n"),
    );
    writeFileSync(
      schemePath,
      [
        "<Scheme>",
        "  <ArchiveAction",
        '     buildConfiguration = "Release">',
        "  </ArchiveAction>",
        "</Scheme>",
        "",
      ].join("\n"),
    );

    writeExecutable(
      positiveCanaryPath,
      '#!/usr/bin/env bash\n[[ "${DRY_RUN:-}" == "true" ]]\n',
    );
    writeExecutable(
      path.join(shimDirectory, "git"),
      [
        "#!/usr/bin/env bash",
        'case "${1:-}" in',
        "  status|check-ignore) exit 0 ;;",
        "  *) exit 2 ;;",
        "esac",
        "",
      ].join("\n"),
    );
    writeExecutable(
      path.join(shimDirectory, "xcodegen"),
      '#!/usr/bin/env bash\n[[ "${1:-}" == "generate" ]]\n',
    );
    writeExecutable(
      path.join(shimDirectory, "xcodebuild"),
      [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        'configuration=""',
        "while (( $# > 0 )); do",
        '  if [[ "$1" == "-configuration" ]]; then',
        "    shift",
        '    configuration="${1:-}"',
        "  fi",
        "  shift",
        "done",
        'if [[ "$configuration" == "Release" ]]; then',
        '  proxy_url="${FAKE_RELEASE_PROXY_URL:-}"',
        '  revenuecat_key="${FAKE_RELEASE_REVENUECAT_KEY:-}"',
        '  ui="NO"',
        '  gemini="NO"',
        'elif [[ "$configuration" == "ScannerCanary" ]]; then',
        '  proxy_url="${FAKE_SCANNER_CANARY_PROXY_URL:-}"',
        '  revenuecat_key="${FAKE_SCANNER_CANARY_REVENUECAT_KEY:-}"',
        '  ui="YES"',
        '  gemini="YES"',
        "else",
        "  exit 2",
        "fi",
        "printf '    MEAL_SCAN_PROXY_BASE_URL = %s\\n' \"$proxy_url\"",
        "printf '    REVENUECAT_PUBLIC_SDK_KEY = %s\\n' \"$revenuecat_key\"",
        "printf '    MEAL_SCAN_RELEASE_UI_ENABLED = %s\\n' \"$ui\"",
        "printf '    MEAL_SCAN_RELEASE_GEMINI_ENABLED = %s\\n' \"$gemini\"",
        "printf '    MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED = NO\\n'",
        "printf '    MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED = NO\\n'",
        "printf '    MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED = NO\\n'",
        "printf '    MEAL_SCAN_RELEASE_SIMILARITY_ENABLED = NO\\n'",
        "",
      ].join("\n"),
    );

    return spawnSync(fixtureScriptPath, ["--no-open"], {
      cwd: fixtureRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${shimDirectory}:${process.env.PATH}`,
        FAKE_RELEASE_PROXY_URL: releaseProxyURL,
        FAKE_RELEASE_REVENUECAT_KEY: releaseRevenueCatKey,
        FAKE_SCANNER_CANARY_PROXY_URL: scannerCanaryProxyURL,
        FAKE_SCANNER_CANARY_REVENUECAT_KEY: scannerCanaryRevenueCatKey,
      },
    });
  } finally {
    rmSync(fixtureRoot, { recursive: true, force: true });
  }
}

function assertConfigurationValuesWereNotPrinted(result, extraValues = []) {
  const output = `${result.stdout}\n${result.stderr}`;
  for (const value of [
    pinnedProxyURL,
    rawRevenueCatKey,
    "appl_effective_release_fixture",
    "appl_effective_scanner_fixture",
    ...extraValues,
  ]) {
    if (value) assert.equal(output.includes(value), false, "configuration value was printed");
  }
}

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

test("Xcode canary staging script accepts pinned non-empty effective settings", () => {
  const result = runStagingScriptWithEffectiveSettings();

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Xcode staging checks passed/);
  assertConfigurationValuesWereNotPrinted(result);
});

for (const scenario of [
  {
    name: "rejects an unescaped effective Release proxy URL",
    overrides: { releaseProxyURL: "https:" },
    expectedError: /Release effective MEAL_SCAN_PROXY_BASE_URL is not pinned/,
    extraValues: ["https:"],
  },
  {
    name: "rejects an overridden empty effective Release RevenueCat key",
    overrides: { releaseRevenueCatKey: "" },
    expectedError: /Release effective REVENUECAT_PUBLIC_SDK_KEY is missing/,
  },
  {
    name: "rejects an overridden effective ScannerCanary proxy URL",
    overrides: { scannerCanaryProxyURL: "https://override.invalid" },
    expectedError: /ScannerCanary effective MEAL_SCAN_PROXY_BASE_URL is not pinned/,
    extraValues: ["https://override.invalid"],
  },
  {
    name: "rejects an overridden empty effective ScannerCanary RevenueCat key",
    overrides: { scannerCanaryRevenueCatKey: "" },
    expectedError: /ScannerCanary effective REVENUECAT_PUBLIC_SDK_KEY is missing/,
  },
]) {
  test(`Xcode canary staging script ${scenario.name} without printing values`, () => {
    const result = runStagingScriptWithEffectiveSettings(scenario.overrides);

    assert.notEqual(result.status, 0, "invalid effective setting was accepted");
    assert.match(result.stderr, scenario.expectedError);
    assertConfigurationValuesWereNotPrinted(result, scenario.extraValues);
  });
}

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
