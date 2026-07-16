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
const scannerSettingKeys = Object.freeze([
  "MEAL_SCAN_RELEASE_UI_ENABLED",
  "MEAL_SCAN_RELEASE_GEMINI_ENABLED",
  "MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED",
  "MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED",
  "MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED",
  "MEAL_SCAN_RELEASE_SIMILARITY_ENABLED",
]);
const expectedReleaseSettings = Object.freeze(
  Object.fromEntries(scannerSettingKeys.map((key) => [key, "NO"])),
);
const expectedScannerCanarySettings = Object.freeze({
  MEAL_SCAN_RELEASE_UI_ENABLED: "YES",
  MEAL_SCAN_RELEASE_GEMINI_ENABLED: "YES",
  MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED: "NO",
  MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED: "NO",
  MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED: "NO",
  MEAL_SCAN_RELEASE_SIMILARITY_ENABLED: "NO",
});
const validSchemeSource = [
  "<Scheme>",
  "  <LaunchAction",
  '     buildConfiguration = "ScannerCanary">',
  "    <CommandLineArguments>",
  "      <CommandLineArgument",
  '         argument = "-billing.backendMode"',
  '         isEnabled = "YES">',
  "      </CommandLineArgument>",
  "      <CommandLineArgument",
  '         argument = "revenuecat"',
  '         isEnabled = "YES">',
  "      </CommandLineArgument>",
  "    </CommandLineArguments>",
  "  </LaunchAction>",
  "  <ProfileAction",
  '     buildConfiguration = "ScannerCanary">',
  "  </ProfileAction>",
  "  <AnalyzeAction",
  '     buildConfiguration = "ScannerCanary">',
  "  </AnalyzeAction>",
  "  <ArchiveAction",
  '     buildConfiguration = "Release">',
  "  </ArchiveAction>",
  "</Scheme>",
  "",
].join("\n");

function writeExecutable(filePath, source) {
  writeFileSync(filePath, source);
  chmodSync(filePath, 0o755);
}

function runStagingScript({
  releaseProxyURL = pinnedProxyURL,
  releaseRevenueCatKey = "appl_effective_release_fixture",
  scannerCanaryProxyURL = pinnedProxyURL,
  scannerCanaryRevenueCatKey = "appl_effective_scanner_fixture",
  releaseSettings = {},
  scannerCanarySettings = {},
  gitInitialStatus = "",
  gitPostGenerationStatus = "",
  gitInitialExit = 0,
  gitPostGenerationExit = 0,
  localSecretsState = "ignored",
  schemeSource = validSchemeSource,
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
    const xcodegenMarkerPath = path.join(fixtureRoot, ".xcodegen-ran");
    const effectiveReleaseSettings = { ...expectedReleaseSettings, ...releaseSettings };
    const effectiveScannerCanarySettings = {
      ...expectedScannerCanarySettings,
      ...scannerCanarySettings,
    };

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
    if (localSecretsState !== "missing") {
      writeFileSync(
        localSecretsPath,
        [
          `REVENUECAT_PUBLIC_SDK_KEY = ${rawRevenueCatKey}`,
          `MEAL_SCAN_PROXY_BASE_URL = ${pinnedProxyURL}`,
          "",
        ].join("\n"),
      );
    }
    writeFileSync(schemePath, schemeSource);

    writeExecutable(
      positiveCanaryPath,
      '#!/usr/bin/env bash\n[[ "${DRY_RUN:-}" == "true" ]]\n',
    );
    writeExecutable(
      path.join(shimDirectory, "git"),
      [
        "#!/usr/bin/env bash",
        'case "${1:-}" in',
        "  status)",
        '    if [[ -f "${FAKE_XCODEGEN_MARKER:-}" ]]; then',
        '      printf "%s" "${FAKE_GIT_POST_GENERATION_STATUS:-}"',
        '      exit "${FAKE_GIT_POST_GENERATION_EXIT:-0}"',
        "    else",
        '      printf "%s" "${FAKE_GIT_INITIAL_STATUS:-}"',
        '      exit "${FAKE_GIT_INITIAL_EXIT:-0}"',
        "    fi",
        "    ;;",
        "  check-ignore)",
        '    [[ "${FAKE_LOCAL_SECRETS_IGNORED:-false}" == "true" ]]',
        "    ;;",
        "  *) exit 2 ;;",
        "esac",
        "",
      ].join("\n"),
    );
    writeExecutable(
      path.join(shimDirectory, "xcodegen"),
      [
        "#!/usr/bin/env bash",
        '[[ "${1:-}" == "generate" ]] || exit 2',
        ': > "${FAKE_XCODEGEN_MARKER:?}"',
        "",
      ].join("\n"),
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
        '  setting_prefix="FAKE_RELEASE"',
        'elif [[ "$configuration" == "ScannerCanary" ]]; then',
        '  proxy_url="${FAKE_SCANNER_CANARY_PROXY_URL:-}"',
        '  revenuecat_key="${FAKE_SCANNER_CANARY_REVENUECAT_KEY:-}"',
        '  setting_prefix="FAKE_SCANNER_CANARY"',
        "else",
        "  exit 2",
        "fi",
        "printf '    MEAL_SCAN_PROXY_BASE_URL = %s\\n' \"$proxy_url\"",
        "printf '    REVENUECAT_PUBLIC_SDK_KEY = %s\\n' \"$revenuecat_key\"",
        "for key in \\",
        "  MEAL_SCAN_RELEASE_UI_ENABLED \\",
        "  MEAL_SCAN_RELEASE_GEMINI_ENABLED \\",
        "  MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED \\",
        "  MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED \\",
        "  MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED \\",
        "  MEAL_SCAN_RELEASE_SIMILARITY_ENABLED; do",
        '  variable_name="${setting_prefix}_${key}"',
        "  printf '    %s = %s\\n' \"$key\" \"${!variable_name:-}\"",
        "done",
        "",
      ].join("\n"),
    );

    const environment = {
      ...process.env,
      PATH: `${shimDirectory}:${process.env.PATH}`,
      FAKE_XCODEGEN_MARKER: xcodegenMarkerPath,
      FAKE_GIT_INITIAL_STATUS: gitInitialStatus,
      FAKE_GIT_POST_GENERATION_STATUS: gitPostGenerationStatus,
      FAKE_GIT_INITIAL_EXIT: String(gitInitialExit),
      FAKE_GIT_POST_GENERATION_EXIT: String(gitPostGenerationExit),
      FAKE_LOCAL_SECRETS_IGNORED: String(localSecretsState === "ignored"),
      FAKE_RELEASE_PROXY_URL: releaseProxyURL,
      FAKE_RELEASE_REVENUECAT_KEY: releaseRevenueCatKey,
      FAKE_SCANNER_CANARY_PROXY_URL: scannerCanaryProxyURL,
      FAKE_SCANNER_CANARY_REVENUECAT_KEY: scannerCanaryRevenueCatKey,
    };
    for (const key of scannerSettingKeys) {
      environment[`FAKE_RELEASE_${key}`] = effectiveReleaseSettings[key];
      environment[`FAKE_SCANNER_CANARY_${key}`] = effectiveScannerCanarySettings[key];
    }

    return spawnSync(fixtureScriptPath, ["--no-open"], {
      cwd: fixtureRoot,
      encoding: "utf8",
      env: environment,
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
    "-billing.backendMode",
    "revenuecat",
    "PCOS.storekit",
    ...extraValues,
  ]) {
    if (value) assert.equal(output.includes(value), false, "configuration value was printed");
  }
  assert.doesNotMatch(output, /expected (?:YES|NO), found (?:YES|NO|missing)/);
}

function replaceActionConfiguration(source, action, configuration) {
  return source.replace(
    new RegExp(`(<${action}\\b[\\s\\S]*?buildConfiguration = ")[^"]+("[\\s\\S]*?<\\/${action}>)`),
    `$1${configuration}$2`,
  );
}

function removeAction(source, action) {
  return source.replace(new RegExp(`\\s*<${action}\\b[\\s\\S]*?<\\/${action}>`), "");
}

function removeLaunchArgument(source, argument) {
  const escaped = argument.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return source.replace(
    new RegExp(`\\s*<CommandLineArgument\\b[\\s\\S]*?argument = "${escaped}"[\\s\\S]*?<\\/CommandLineArgument>`),
    "",
  );
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

test("Xcode canary staging script rejects an unknown argument without echoing it", () => {
  const argument = "--private-argument-fixture";
  const result = spawnSync(scriptPath, [argument], {
    cwd: repositoryRoot,
    encoding: "utf8",
  });

  assert.notEqual(result.status, 0, "unknown argument was accepted");
  assert.match(result.stderr, /Unknown argument/);
  assert.equal(`${result.stdout}\n${result.stderr}`.includes(argument), false, "unknown argument was printed");
});

test("Xcode canary staging script accepts pinned non-empty effective settings", () => {
  const result = runStagingScript();

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
    const result = runStagingScript(scenario.overrides);

    assert.notEqual(result.status, 0, "invalid effective setting was accepted");
    assert.match(result.stderr, scenario.expectedError);
    assertConfigurationValuesWereNotPrinted(result, scenario.extraValues);
  });
}

for (const scenario of [
  {
    name: "rejects an initially dirty worktree",
    overrides: { gitInitialStatus: " M private-fixture\n" },
    expectedError: /Worktree must be clean before staging Xcode/,
    extraValues: ["private-fixture"],
  },
  {
    name: "fails closed when the initial git status inspection fails",
    overrides: { gitInitialExit: 23 },
    expectedError: /Unable to inspect worktree state/,
  },
  {
    name: "rejects project generation that dirties the worktree",
    overrides: { gitPostGenerationStatus: " M generated-fixture\n" },
    expectedError: /Xcode project generation changed tracked or untracked files/,
    extraValues: ["generated-fixture"],
  },
  {
    name: "fails closed when the post-generation git status inspection fails",
    overrides: { gitPostGenerationExit: 23 },
    expectedError: /Unable to inspect worktree state/,
  },
  {
    name: "rejects a missing LocalSecrets configuration",
    overrides: { localSecretsState: "missing" },
    expectedError: /Missing ignored local Xcode configuration/,
  },
  {
    name: "rejects a non-ignored LocalSecrets configuration",
    overrides: { localSecretsState: "tracked" },
    expectedError: /Local Xcode configuration must remain ignored/,
  },
]) {
  test(`Xcode canary staging script ${scenario.name} without printing values`, () => {
    const result = runStagingScript(scenario.overrides);

    assert.notEqual(result.status, 0, "unsafe preflight state was accepted");
    assert.match(result.stderr, scenario.expectedError);
    assertConfigurationValuesWereNotPrinted(result, scenario.extraValues);
  });
}

for (const [configuration, expectedSettings, overrideName] of [
  ["Release", expectedReleaseSettings, "releaseSettings"],
  ["ScannerCanary", expectedScannerCanarySettings, "scannerCanarySettings"],
]) {
  for (const key of scannerSettingKeys) {
    const unsafeValue = expectedSettings[key] === "YES" ? "NO" : "YES";
    test(`Xcode canary staging script rejects ${configuration} ${key} drift without printing values`, () => {
      const result = runStagingScript({ [overrideName]: { [key]: unsafeValue } });

      assert.notEqual(result.status, 0, "unsafe build-setting drift was accepted");
      assert.match(result.stderr, new RegExp(`${key} does not match required staging policy`));
      assertConfigurationValuesWereNotPrinted(result);
    });
  }
}

const schemeFailureScenarios = [
  {
    name: "rejects a missing Launch action",
    source: removeAction(validSchemeSource, "LaunchAction"),
    expectedError: /LaunchAction is missing or duplicated/,
  },
  {
    name: "rejects duplicate Launch actions placed on one line",
    source: removeAction(validSchemeSource, "LaunchAction").replace(
      "<Scheme>",
      [
        "<Scheme>",
        '<LaunchAction buildConfiguration = "ScannerCanary"></LaunchAction><LaunchAction></LaunchAction>',
      ].join("\n"),
    ),
    expectedError: /LaunchAction is missing or duplicated/,
    extraValues: ["ScannerCanary"],
  },
  {
    name: "rejects an unsafe Launch configuration",
    source: replaceActionConfiguration(validSchemeSource, "LaunchAction", "Debug"),
    expectedError: /LaunchAction build configuration is invalid/,
    extraValues: ["Debug"],
  },
  {
    name: "rejects a prefixed Launch configuration attribute spoof",
    source: validSchemeSource.replace(
      'buildConfiguration = "ScannerCanary">',
      'notbuildConfiguration = "ScannerCanary">',
    ),
    expectedError: /LaunchAction build configuration is invalid/,
  },
  {
    name: "rejects a missing Launch configuration even when a child spoofs it",
    source: validSchemeSource
      .replace(
        '     buildConfiguration = "ScannerCanary">',
        '     shouldUseLaunchSchemeArgsEnv = "YES">\n    <Spoof buildConfiguration = "ScannerCanary">',
      )
      .replace("    <CommandLineArguments>", "    </Spoof>\n    <CommandLineArguments>"),
    expectedError: /LaunchAction build configuration is invalid/,
  },
  {
    name: "rejects an unsafe Profile configuration",
    source: replaceActionConfiguration(validSchemeSource, "ProfileAction", "Debug"),
    expectedError: /ProfileAction build configuration is invalid/,
    extraValues: ["Debug"],
  },
  {
    name: "rejects an unsafe Analyze configuration",
    source: replaceActionConfiguration(validSchemeSource, "AnalyzeAction", "Debug"),
    expectedError: /AnalyzeAction build configuration is invalid/,
    extraValues: ["Debug"],
  },
  {
    name: "rejects an unsafe Archive configuration",
    source: replaceActionConfiguration(validSchemeSource, "ArchiveAction", "ScannerCanary"),
    expectedError: /ArchiveAction build configuration is invalid/,
  },
  {
    name: "rejects a StoreKit configuration",
    source: validSchemeSource.replace(
      "  <LaunchAction\n",
      '  <LaunchAction\n     storeKitConfiguration = "PCOS.storekit"\n',
    ),
    expectedError: /must not contain a StoreKit configuration/,
  },
  ...["-billing.backendMode", "revenuecat"].map((argument) => ({
    name: `rejects a missing ${argument} Launch argument`,
    source: removeLaunchArgument(validSchemeSource, argument),
    expectedError: /LaunchAction command-line argument contract is invalid/,
  })),
  {
    name: "rejects Launch arguments outside the CommandLineArguments container",
    source: validSchemeSource
      .replace("    <CommandLineArguments>\n", "")
      .replace("    </CommandLineArguments>\n", ""),
    expectedError: /LaunchAction command-line argument contract is invalid/,
  },
  {
    name: "rejects duplicate CommandLineArgument tags placed on one line",
    source: validSchemeSource.replace(
      "      <CommandLineArgument\n",
      "      <CommandLineArgument><CommandLineArgument\n",
    ),
    expectedError: /LaunchAction command-line argument contract is invalid/,
  },
  {
    name: "rejects a disabled required Launch argument",
    source: validSchemeSource.replace(
      'argument = "-billing.backendMode"\n         isEnabled = "YES"',
      'argument = "-billing.backendMode"\n         isEnabled = "NO"',
    ),
    expectedError: /LaunchAction command-line argument contract is invalid/,
  },
  {
    name: "rejects an unexpected enabled Launch argument",
    source: validSchemeSource.replace(
      "    </CommandLineArguments>",
      [
        "      <CommandLineArgument",
        '         argument = "unexpected-fixture"',
        '         isEnabled = "YES">',
        "      </CommandLineArgument>",
        "    </CommandLineArguments>",
      ].join("\n"),
    ),
    expectedError: /LaunchAction command-line argument contract is invalid/,
    extraValues: ["unexpected-fixture"],
  },
];

for (const scenario of schemeFailureScenarios) {
  test(`Xcode canary staging script ${scenario.name} without printing values`, () => {
    const result = runStagingScript({ schemeSource: scenario.source });

    assert.notEqual(result.status, 0, "unsafe generated scheme was accepted");
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
  assert.match(scriptSource, /require_scheme_action_configuration LaunchAction ScannerCanary/);
  assert.match(scriptSource, /require_scheme_action_configuration ProfileAction ScannerCanary/);
  assert.match(scriptSource, /require_scheme_action_configuration AnalyzeAction ScannerCanary/);
  assert.match(scriptSource, /require_scheme_action_configuration ArchiveAction Release/);
  assert.match(scriptSource, /require_launch_argument_contract/);
  assert.match(scriptSource, /-billing\.backendMode/);
  assert.match(scriptSource, /revenuecat/);
  assert.match(scriptSource, /storeKitConfiguration/);
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
