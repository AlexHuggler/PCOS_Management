# CycleBalance General Kenobi Xcode Canary Design

**Status:** Approved in conversation on July 16, 2026

## Scope

This design stages a development-only Xcode configuration for preparing General Kenobi to exercise the CycleBalance AI meal scanner. It supplements, but does not replace, the existing rollback-bounded `run-positive-general-kenobi-canary.sh` workflow. The production proxy remains disabled/private and canonical Release scanner gates remain `NO` until the separate launch gates are complete.

## Goals

- Make the correct scanner-enabled development build visible and easy to run from the canonical root Xcode project.
- Enable only the signed meal-scan UI and Gemini gates in the canary configuration.
- Use Release optimization, the production App Attest entitlement, the real RevenueCat backend, and the pinned production proxy URL.
- Prevent the convenience scheme from creating a scanner-enabled archive.
- Give the owner a safe local preflight and exact handoff for signing, device selection, sandbox purchase, and the later live canary.
- Preserve the existing cloud rollback, content-free evidence, quota, cache, privacy, and device-lifecycle controls.

## Non-Goals

- Do not enable either canonical Release scanner flag.
- Do not make Cloud Run public, enable the server kill switch, deploy, install, launch, purchase, or call Gemini during staging.
- Do not add a second live-canary implementation or accept an unverified Xcode-built app as machine evidence.
- Do not enable mock scanner data, debug-direct transport, fallback-model routing, or visual similarity.
- Do not attach `PCOS.storekit`; the later physical-device purchase uses Apple's sandbox and the real RevenueCat configuration.
- Do not archive, export, upload, distribute through TestFlight, or submit the canary configuration.
- Do not store Apple credentials, sandbox credentials, private API keys, transaction data, or device passcodes in the repository or handoff output.

## Xcode Configuration

Add a release-typed Xcode build configuration named `ScannerCanary` through the XcodeGen source of truth. The app target uses the same Release optimization, `Info.Release.plist` preprocessing, production entitlements, empty USDA key, and local ignored configuration include as canonical Release.

`Config/ScannerCanary.xcconfig` inherits `Config/Release.xcconfig` and sets exactly this scanner contract:

- `MEAL_SCAN_RELEASE_UI_ENABLED = YES`
- `MEAL_SCAN_RELEASE_GEMINI_ENABLED = YES`
- `MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED = NO`
- `MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED = NO`
- `MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED = NO`
- `MEAL_SCAN_RELEASE_SIMILARITY_ENABLED = NO`

Canonical Release continues to declare each of the six settings exactly once in `project.yml`, all as `NO`, so the audited live harness's source checks remain valid.

Add one shared scheme named `PCOS General Kenobi Scanner Canary`:

- Build: app target only.
- Run: `ScannerCanary`, real RevenueCat billing mode, no local StoreKit configuration.
- Profile and Analyze: `ScannerCanary` where supported.
- Archive: canonical `Release`, never `ScannerCanary`.

The scheme is a signing and manual-run convenience. A physical run must still produce an Apple Development signature, a development provisioning profile containing General Kenobi, `get-task-allow=true`, bundle ID `alex.PCOS`, team `2PW989LA87`, and production App Attest. The existing live harness remains the authority that verifies those properties before a billable request.

## Companion Handoff

Add `scripts/open_general_kenobi_scanner_canary_xcode.sh`. It performs only local, non-mutating-to-cloud preparation:

1. Resolve and pin the clean RC repository root.
2. Require XcodeGen and the canonical root project.
3. Refuse a dirty worktree so the future approved source commit remains unambiguous.
4. Verify the ignored local configuration contains a non-empty RevenueCat public SDK key and the exact pinned proxy URL without printing either value.
5. Run the existing positive-canary dry run, which performs no cloud, device, build, installation, or provider action.
6. Regenerate `PCOS.xcodeproj` from `project.yml`, then refuse to continue if generation changed tracked or untracked files.
7. Read Xcode build settings for both `Release` and `ScannerCanary` and fail unless Release has six `NO` gates while ScannerCanary has only UI and Gemini `YES`.
8. Verify the generated shared scheme has `ScannerCanary` Launch/Profile/Analyze actions, exactly the enabled `-billing.backendMode` and `revenuecat` Launch arguments, no StoreKit configuration, and a `Release` Archive action.
9. Open the canonical root project unless `--no-open` is supplied.

The script prints no credential values and never calls the live canary path. Its final instructions tell the owner to select General Kenobi and the dedicated scheme, allow Xcode to resolve an Apple Development certificate/profile if needed, and use the audited terminal harness for the actual live AI window.

## Live-Test Boundary

Clicking Run in Xcode can validate signing, installation, launch, scanner navigation, camera permissions, and disabled-service behavior. It does not authorize or perform a live Gemini test because the production proxy remains disabled/private.

The real AI scan must still run inside `run-positive-general-kenobi-canary.sh` after fresh owner approval of its exact confirmation value. That workflow owns the sealed source archive, disabled/private staging, device backup, signed-app inspection, temporary App Check-protected public endpoint, content-free evidence windows, quota/provider correlation, and unconditional disabled/private rollback. The Xcode scheme must not bypass or duplicate those controls.

## Owner Handoff

When General Kenobi is available:

1. Power it on, unlock it, enable Developer Mode, and connect or use an already established trusted wireless pairing.
2. Open Xcode with the companion script.
3. Confirm the CycleBalance Apple account/team is selected and let Xcode create or restore an Apple Development certificate and device profile if required.
4. Select `PCOS General Kenobi Scanner Canary` and General Kenobi.
5. Use Product > Run only for local signing/launch rehearsal while the service remains disabled.
6. For the real scanner test, close the rehearsal and run the audited seed command from Terminal with the exact reviewed commit and explicit temporary-public-endpoint approval.
7. Follow the harness prompts for an active monthly or annual sandbox transaction, photo consent, edit, save, exact reuse, recovery cases, and later Scan as New rescan.

No passcode or sandbox password is entered into a script, source file, build setting, or retained evidence.

## Failure Handling

- Missing cable or wireless pairing: staging succeeds, but physical signing/run waits for the device.
- Missing Apple Development identity: the local preflight reports it; Xcode account/certificate setup remains an owner action.
- Missing or wrong local proxy/public SDK configuration: fail before project generation or Xcode launch, without printing values.
- Dirty worktree: fail and identify that the canary requires a reviewed clean commit.
- Scheme/configuration drift: fail before Xcode opens.
- Xcode manual run reaches a disabled service: treat this as the expected safe posture, not a live AI failure.
- Live harness failure: rely on its rollback trap and retained redacted evidence; do not continue manually with a public endpoint.

## Testing

- Source-contract tests prove canonical Release still contains exactly one `NO` declaration for every scanner gate.
- Source-contract tests prove `ScannerCanary` turns on only UI and Gemini and the shared scheme archives with Release.
- Script tests use command shims to prove `--no-open` performs no cloud/device mutation and rejects dirty state, missing configuration, unsafe gate drift, and an enabled Archive action.
- Run `xcodegen generate` and confirm the shared scheme is generated.
- Read `xcodebuild -showBuildSettings` for both configurations and compare the six gate values.
- Build `ScannerCanary` for an iOS simulator with signing disabled to verify compilation and signed-plist preprocessing without claiming physical App Attest success.
- Run the existing positive-canary targeted test suite and dry run unchanged.
- Scan the generated product and diff for private credential material.

## Acceptance Criteria

- The canonical Release build remains scanner-disabled and safe to archive.
- Xcode presents one clearly named General Kenobi canary scheme whose Run action enables only the two approved scanner gates.
- The scheme uses real RevenueCat, no local StoreKit fixture, Release behavior, and production App Attest source entitlements.
- One local script regenerates, validates, and opens the correct project without touching cloud or device state.
- A missing device or signing identity produces an actionable handoff instead of weakening signing checks.
- The documentation states plainly that Xcode Run is not a substitute for the rollback-bounded live AI harness.
- No live endpoint, purchase, provider call, archive, upload, distribution, or submission occurs during staging.
