# General Kenobi Xcode Canary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe, development-only Xcode scheme and local handoff that prepares General Kenobi for the CycleBalance AI scanner without enabling canonical Release or mutating the live cloud service.

**Architecture:** XcodeGen gains a release-typed `ScannerCanary` configuration and one shared scheme whose Run action uses that configuration while Archive remains canonical `Release`. A local shell handoff validates ignored public configuration, dry-runs the existing audited canary, regenerates the project, compares Release and canary build settings, and opens Xcode; the existing rollback-bounded live harness remains the only path that may temporarily enable Cloud Run.

**Tech Stack:** XcodeGen YAML, xcconfig, shared Xcode schemes, Bash, Node.js `node:test`, Xcode 26.2, Swift 6/iOS 17+

## Global Constraints

- Canonical `Release` must continue to declare each of the six scanner settings exactly once in `project.yml`, all as `NO`.
- `ScannerCanary` may set only `MEAL_SCAN_RELEASE_UI_ENABLED` and `MEAL_SCAN_RELEASE_GEMINI_ENABLED` to `YES`; mock data, debug-direct transport, fallback-model routing, and visual similarity remain `NO`.
- The canary uses Release optimization, `PCOS/PCOS.entitlements`, `PCOS/PCOS/Info.Release.plist`, production App Attest, bundle ID `alex.PCOS`, and team `2PW989LA87`.
- The shared scheme is named `PCOS General Kenobi Scanner Canary`; Run uses `ScannerCanary`, real RevenueCat, and no local StoreKit configuration; Archive uses canonical `Release`.
- Staging must not deploy, change IAM, enable Cloud Run, install or launch on a device, purchase, call Gemini, archive, export, upload, distribute, or submit.
- Secret values, sandbox credentials, StoreKit JWS values, transaction identifiers, device passcodes, and private key material must never be printed or committed.
- The existing `run-positive-general-kenobi-canary.sh` remains the only live AI path and retains its exact approval, signing, evidence, device-lifecycle, and rollback controls.

---

### Task 1: Add the scanner-canary build configuration and shared scheme

**Files:**
- Create: `Config/ScannerCanary.xcconfig`
- Modify: `project.yml`
- Modify: `cloud/meal-scan-proxy/test/positive-canary-script.test.js`
- Regenerate: `PCOS.xcodeproj/project.pbxproj`
- Generate: `PCOS.xcodeproj/xcshareddata/xcschemes/PCOS General Kenobi Scanner Canary.xcscheme`

**Interfaces:**
- Consumes: canonical Release flags and `Config/Release.xcconfig`.
- Produces: Xcode build configuration `ScannerCanary` and shared scheme `PCOS General Kenobi Scanner Canary` for Task 2.

- [ ] **Step 1: Write the failing source-contract test**

Append a `scanner canary Xcode configuration is isolated from canonical Release` test to `cloud/meal-scan-proxy/test/positive-canary-script.test.js`. It must read `Config/ScannerCanary.xcconfig`, require the top-level release-typed configuration, require the app target config file mapping and shared scheme, assert the scheme Run/Profile/Analyze actions use `ScannerCanary`, assert Archive uses `Release`, reject `storeKitConfiguration` in the scheme slice, and count each canonical YAML flag exactly once with value `NO`.

Use these exact expectations:

```js
const scannerCanaryConfigPath = path.join(repositoryRoot, "Config/ScannerCanary.xcconfig");
const scannerCanaryConfigSource = existsSync(scannerCanaryConfigPath)
  ? readFileSync(scannerCanaryConfigPath, "utf8")
  : "";

test("scanner canary Xcode configuration is isolated from canonical Release", () => {
  assert.equal(existsSync(scannerCanaryConfigPath), true);
  assert.match(projectSource, /configs:\n  Debug: debug\n  Release: release\n  ScannerCanary: release/);
  assert.match(projectSource, /ScannerCanary: Config\/ScannerCanary\.xcconfig/);

  const schemeStart = projectSource.indexOf("  PCOS General Kenobi Scanner Canary:");
  assert.notEqual(schemeStart, -1);
  const schemeSource = projectSource.slice(schemeStart);
  assert.match(schemeSource, /run:\n      config: ScannerCanary/);
  assert.match(schemeSource, /profile:\n      config: ScannerCanary/);
  assert.match(schemeSource, /analyze:\n      config: ScannerCanary/);
  assert.match(schemeSource, /archive:\n      config: Release/);
  assert.doesNotMatch(schemeSource, /storeKitConfiguration:/);
  assert.match(schemeSource, /"-billing\.backendMode": true/);
  assert.match(schemeSource, /"revenuecat": true/);

  const expectedCanaryFlags = new Map([
    ["MEAL_SCAN_RELEASE_UI_ENABLED", "YES"],
    ["MEAL_SCAN_RELEASE_GEMINI_ENABLED", "YES"],
    ["MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED", "NO"],
    ["MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED", "NO"],
    ["MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED", "NO"],
    ["MEAL_SCAN_RELEASE_SIMILARITY_ENABLED", "NO"],
  ]);
  for (const [key, expected] of expectedCanaryFlags) {
    assert.match(scannerCanaryConfigSource, new RegExp(`^${key} = ${expected}$`, "m"));
    const declarations = projectSource.match(new RegExp(`^\\s+${key}: ["']?NO["']?$`, "gm")) ?? [];
    assert.equal(declarations.length, 1, `${key} must remain one canonical NO declaration`);
  }
});
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
cd cloud/meal-scan-proxy
node --test --test-name-pattern='scanner canary Xcode configuration' test/positive-canary-script.test.js
```

Expected: FAIL because `Config/ScannerCanary.xcconfig` and the shared scheme do not exist.

- [ ] **Step 3: Add the minimal XcodeGen configuration**

Add this top-level mapping after `options` in `project.yml`:

```yaml
configs:
  Debug: debug
  Release: release
  ScannerCanary: release
```

Add the app target config-file mapping:

```yaml
    configFiles:
      Debug: Config/Debug.xcconfig
      Release: Config/Release.xcconfig
      ScannerCanary: Config/ScannerCanary.xcconfig
```

Add a `ScannerCanary` target configuration that repeats the non-gate Release build behavior but does not redeclare the six canonical YAML gate keys:

```yaml
        ScannerCanary:
          SWIFT_OPTIMIZATION_LEVEL: "-Owholemodule"
          SWIFT_COMPILATION_MODE: wholemodule
          CODE_SIGN_ENTITLEMENTS: PCOS/PCOS.entitlements
          INFOPLIST_FILE: PCOS/PCOS/Info.Release.plist
          INFOPLIST_PREPROCESS: "YES"
          INFOPLIST_PREPROCESSOR_DEFINITIONS: "$(inherited) MEAL_SCAN_RELEASE_UI_ENABLED_$(MEAL_SCAN_RELEASE_UI_ENABLED)=1 MEAL_SCAN_RELEASE_GEMINI_ENABLED_$(MEAL_SCAN_RELEASE_GEMINI_ENABLED)=1"
          USDA_FDC_API_KEY: ""
```

Create `Config/ScannerCanary.xcconfig` exactly as:

```xcconfig
#include "Release.xcconfig"

// Development-only General Kenobi canary. Canonical Release remains disabled.
MEAL_SCAN_RELEASE_UI_ENABLED = YES
MEAL_SCAN_RELEASE_GEMINI_ENABLED = YES
MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED = NO
MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED = NO
MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED = NO
MEAL_SCAN_RELEASE_SIMILARITY_ENABLED = NO
```

Add this XcodeGen scheme after `PCOS Local StoreKit` and before the production probe:

```yaml
  PCOS General Kenobi Scanner Canary:
    build:
      targets:
        PCOS: all
    run:
      config: ScannerCanary
      commandLineArguments:
        "-billing.backendMode": true
        "revenuecat": true
    profile:
      config: ScannerCanary
    analyze:
      config: ScannerCanary
    archive:
      config: Release
```

- [ ] **Step 4: Regenerate the root Xcode project**

Run:

```bash
xcodegen generate
```

Expected: `PCOS.xcodeproj` regenerates and includes `PCOS General Kenobi Scanner Canary.xcscheme`.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
cd cloud/meal-scan-proxy
node --test --test-name-pattern='scanner canary Xcode configuration|canonical Release flags remain NO|Release canary permits only' test/positive-canary-script.test.js
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add Config/ScannerCanary.xcconfig project.yml PCOS.xcodeproj cloud/meal-scan-proxy/test/positive-canary-script.test.js
git commit -m "feat: add General Kenobi Xcode canary scheme"
```

---

### Task 2: Add the safe Xcode staging handoff and owner runbook

**Files:**
- Create: `scripts/open_general_kenobi_scanner_canary_xcode.sh`
- Create: `cloud/meal-scan-proxy/test/xcode-canary-staging.test.js`
- Modify: `README.md`
- Modify: `docs/meal_scan_flash_lite_production_setup.md`
- Modify: `AppStoreReadinessChecklist.md`

**Interfaces:**
- Consumes: `ScannerCanary`, `PCOS General Kenobi Scanner Canary`, ignored `Config/LocalSecrets.xcconfig`, and `run-positive-general-kenobi-canary.sh` dry-run mode.
- Produces: `scripts/open_general_kenobi_scanner_canary_xcode.sh [--no-open]` and an exact owner handoff that never mutates cloud/device state.

- [ ] **Step 1: Write failing script-contract tests**

Create `cloud/meal-scan-proxy/test/xcode-canary-staging.test.js` with `node:test`. The tests must require an executable script, verify `--help`, and exercise shimmed clean-worktree, ignored-config, exact pinned URL, positive-canary `DRY_RUN=true`, XcodeGen generation, Release/ScannerCanary setting, full generated-scheme action/argument/StoreKit, and optional `--no-open` behavior. They must reject any live confirmation string, `DRY_RUN=false`, `gcloud`, `devicectl`, device installation, archive/export, or StoreKit credential handling.

Use the exact prohibited list:

```js
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
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
cd cloud/meal-scan-proxy
node --test test/xcode-canary-staging.test.js
```

Expected: FAIL because the staging script does not exist.

- [ ] **Step 3: Implement the minimal staging script**

Create an executable Bash script with these named helpers and behaviors:

```bash
readonly PINNED_PROXY_URL="https://cyclebalance-meal-scan-proxy-mdd7lrfyqa-uc.a.run.app"
readonly SCHEME_NAME="PCOS General Kenobi Scanner Canary"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
xcconfig_value() {
  awk -F= -v key="$2" '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" { value=$2; sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value); print value; exit }' "$1"
}
build_setting() {
  awk -F ' = ' -v key="$2" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }' "$1"
}
require_setting() {
  local file="$1" key="$2" expected="$3" actual
  actual="$(build_setting "$file" "$key")"
  [[ "$actual" == "$expected" ]] || die "$key does not match required staging policy"
}
```

The main path must:

- accept only no argument, `--no-open`, or `--help`;
- require `git`, `xcodegen`, `xcodebuild`, `awk`, and `grep`, plus `open` unless `--no-open`;
- fail unless `git status --porcelain --untracked-files=all` is empty;
- require `Config/LocalSecrets.xcconfig` to be ignored;
- require a non-empty `REVENUECAT_PUBLIC_SDK_KEY` and exact pinned `MEAL_SCAN_PROXY_BASE_URL` without printing values;
- run `DRY_RUN=true cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh >/dev/null`;
- run `xcodegen generate`;
- fail if XcodeGen changes tracked or untracked files;
- collect `xcodebuild -showBuildSettings` for `Release` and `ScannerCanary` with `CODE_SIGNING_ALLOWED=NO` into `mktemp` files cleaned by a trap;
- require six `NO` Release values and only UI/Gemini `YES` for ScannerCanary;
- inspect `PCOS.xcodeproj/xcshareddata/xcschemes/PCOS General Kenobi Scanner Canary.xcscheme`, require Launch/Profile/Analyze `ScannerCanary`, exact enabled `-billing.backendMode` and `revenuecat` Launch arguments, no StoreKit configuration, and Archive `Release`;
- print the exact scheme/device/run instructions;
- invoke `open "$ROOT/PCOS.xcodeproj"` only when `--no-open` is absent.

- [ ] **Step 4: Update the owner-facing docs**

Add a `General Kenobi Scanner Canary` section to `README.md` with:

```bash
./scripts/open_general_kenobi_scanner_canary_xcode.sh
```

State that Xcode Run is a local signing/launch rehearsal while Cloud Run remains disabled/private, and the real AI scan still requires the audited terminal harness.

Update `docs/meal_scan_flash_lite_production_setup.md` and `AppStoreReadinessChecklist.md` to record the staged scheme/script, the missing current Apple Development identity, the absent physical connection, and the still-open live seed/purchase/restore gates. Do not mark the General Kenobi canary or TestFlight gate complete.

- [ ] **Step 5: Make the script executable and run focused tests**

```bash
chmod 0755 scripts/open_general_kenobi_scanner_canary_xcode.sh
cd cloud/meal-scan-proxy
node --test test/xcode-canary-staging.test.js test/positive-canary-script.test.js test/readme-contract.test.js
```

Expected: all tests pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add scripts/open_general_kenobi_scanner_canary_xcode.sh cloud/meal-scan-proxy/test/xcode-canary-staging.test.js README.md docs/meal_scan_flash_lite_production_setup.md AppStoreReadinessChecklist.md
git commit -m "feat: stage General Kenobi Xcode canary handoff"
```

---

### Task 3: Verify the staged Xcode handoff and open Xcode

**Files:**
- Verify only: all Task 1 and Task 2 files

**Interfaces:**
- Consumes: committed clean RC head and the staging script.
- Produces: a locally opened canonical Xcode project plus an evidence-backed owner unlock handoff; no source changes.

- [ ] **Step 1: Run the non-opening preflight**

```bash
./scripts/open_general_kenobi_scanner_canary_xcode.sh --no-open
```

Expected: successful validation of clean state before and after generation, ignored local public configuration, dry-run boundary, generated Launch/Profile/Analyze/argument/StoreKit contract, Release six-`NO` contract, canary two-`YES` contract, and Release-only Archive action.

- [ ] **Step 2: Build the canary for simulator without signing**

```bash
xcodebuild \
  -project PCOS.xcodeproj \
  -scheme 'PCOS General Kenobi Scanner Canary' \
  -configuration ScannerCanary \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Inspect build settings and generated scheme**

Read back the six flags from `xcodebuild -showBuildSettings` for Release and ScannerCanary. Confirm the generated scheme's Launch/Profile/Analyze configurations are `ScannerCanary` and Archive is `Release`. Confirm `Config/LocalSecrets.xcconfig` remains ignored and no private credential pattern appears in tracked changes or the built app.

- [ ] **Step 4: Run the complete targeted verification set**

```bash
cd cloud/meal-scan-proxy
node --test test/xcode-canary-staging.test.js test/positive-canary-script.test.js test/readme-contract.test.js test/revenuecat-offering-verifier.test.js
bash -n scripts/run-positive-general-kenobi-canary.sh ../../scripts/open_general_kenobi_scanner_canary_xcode.sh
```

Expected: all tests and syntax checks pass.

- [ ] **Step 5: Open Xcode**

```bash
./scripts/open_general_kenobi_scanner_canary_xcode.sh
```

Expected: the canonical root `PCOS.xcodeproj` opens. Tell the owner only now to unlock General Kenobi, select `PCOS General Kenobi Scanner Canary`, choose the device, and resolve Apple Development signing. If the phone is not paired wirelessly, stop at this handoff without enabling Cloud Run.

- [ ] **Step 6: Final review and clean-state proof**

Run `git status --short --branch`, `git diff --check`, and a final credential-pattern scan. Obtain an independent review covering canonical Release isolation, Archive safety, staging-script non-mutation, documentation truthfulness, and preserved live-harness authority. Record the final commit hashes and current open device/signing blockers.
