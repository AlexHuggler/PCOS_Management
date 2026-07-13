# CycleBalance Meal Scan Device And Review Rollout Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove production App Attest reaches the entitlement gate on a physical iPhone without calling Gemini, then prepare complete App Review materials while returning Cloud Run to private and disabled state.

**Architecture:** An opt-in Release integration test obtains a limited-use Firebase App Check token and sends one valid normalized request with a deliberately invalid StoreKit transaction JWS. A fail-safe shell orchestrator verifies prerequisites, backs up app data, builds current source, registers rollback before cloud mutation, temporarily enables public ingress, runs the expected rejection probe, verifies no model call, and restores private/disabled production state in a trap.

**Tech Stack:** Swift Testing, Firebase App Check/App Attest, XcodeGen, `xcodebuild`, CoreDevice `devicectl`, Bash, Google Cloud CLI, Cloud Run.

## Approval And Safety Boundary

- The owner approved preparing and running the physical probe on July 10-11, 2026.
- A live script still requires `CONFIRM_TEMPORARY_PUBLIC_PROBE=YES`; dry runs do not.
- Never request, read, or handle the device passcode. A locked phone is a hard stop.
- Never use the July 3 build-17 IPA. Generate a fresh Release build from current source.
- Never print App Check, identity, RevenueCat, or Gemini tokens.
- Do not use `-allowProvisioningUpdates` in routine verification. If existing signing cannot build, stop and ask the owner before permitting signing-state changes.
- Do not submit to App Review or increment the build number in this plan.
- Cloud Run must end private with `MEAL_SCAN_ENABLED=false`, even after any failure.
- The negative invalid-JWS probe does not satisfy the positive sandbox-JWS real-device TestFlight gate. That separate release-candidate gate remains open until an entitled sandbox transaction succeeds on a physical device.

### Task 1: Add The Opt-In Physical App Check Test

**Files:**
- Create: `PCOS/PCOSTests/ProductionMealScanAppCheckProbeTests.swift`
- Modify: `project.yml`

- [x] **Step 1: Add a test gated by `RUN_PRODUCTION_MEAL_SCAN_INTEGRATION=1`**

The test obtains a limited-use token from `FirebaseMealScanAppCheckTokenProvider`, prepares one valid normalized JPEG, supplies a deliberately invalid StoreKit transaction JWS, and calls the production proxy without exposing token values.

- [x] **Step 2: Assert HTTP `403`, `error = "premium_entitlement_required"`, and `reason = "storekit_transaction_invalid"`**

Do not print the normalized image hash or any request principal. Any `200`, `mealScanRollingQuota` collection change, `provider_call` scanner event, or `meal_scan_estimate` event is a hard failure.

- [x] **Step 3: Add a Release XcodeGen test scheme with the opt-in environment value**

- [x] **Step 4: Verify the test compiles but remains skipped in ordinary suites**

### Task 2: Add The Fail-Safe Probe Orchestrator

**Files:**
- Create: `cloud/meal-scan-proxy/scripts/run-physical-app-check-probe.sh`

- [x] **Step 1: Implement a side-effect-free `DRY_RUN=true` path**

- [x] **Step 2: Before any mutation, verify project/service identity, budget mode `normal`, initial `MEAL_SCAN_ENABLED=false`, and absence of `allUsers` IAM**

- [ ] **Step 3: Verify `General Kenobi` (`0C663BE9-3804-587C-BD8A-A2B4D38F998A`) is unlocked, paired, in Developer Mode, and can mount its developer disk image**

- [ ] **Step 4: Back up the installed `alex.PCOS` app-data container**

Copy it to `~/Library/Application Support/CycleBalance/DeviceBackups/<UTC timestamp>` with mode `0700`. If CoreDevice backup fails, abort before installation and require the owner to complete an encrypted Finder backup.

- [ ] **Step 5: Build current Release source into temporary directories and inspect the product**

Assert bundle ID `alex.PCOS`, production App Attest entitlement, and the complete production proxy URL. Do not pass `-allowProvisioningUpdates`.

- [x] **Step 6: Register the rollback trap before the first cloud mutation**

- [ ] **Step 7: Temporarily deploy with `MEAL_SCAN_ENABLED=true` and unauthenticated ingress using the reviewed deploy script**

- [ ] **Step 8: Install/run the Release probe, assert `storekit_transaction_invalid`, prove the complete `mealScanRollingQuota` collection is unchanged, and verify the probe revision has no `provider_call` or `meal_scan_estimate` event**

- [ ] **Step 9: In the trap, redeploy disabled/private and verify unauthenticated `403` plus authenticated `503 feature_disabled`**

### Task 3: Verify The Orchestrator Before A Live Probe

- [x] **Step 1: Run `bash -n cloud/meal-scan-proxy/scripts/run-physical-app-check-probe.sh`**

- [x] **Step 2: Run the dry path**

```sh
DRY_RUN=true PROJECT_ID=cyclebalance-prod-20260710 \
  cloud/meal-scan-proxy/scripts/run-physical-app-check-probe.sh
```

Expected: every gate, mutation, and rollback action is listed without changing cloud or device state.

- [ ] **Step 3: Confirm the device is manually unlocked before proceeding**

### Task 4: Run The Approved Physical Probe

- [ ] **Step 1: Execute the live script only after the backup and preflight gates pass**

```sh
CONFIRM_TEMPORARY_PUBLIC_PROBE=YES \
PROJECT_ID=cyclebalance-prod-20260710 \
DEVICE_ID=0C663BE9-3804-587C-BD8A-A2B4D38F998A \
cloud/meal-scan-proxy/scripts/run-physical-app-check-probe.sh
```

- [ ] **Step 2: Record only status codes, safe reason strings, revision names, rollback status, and whether app-data backup completed**

- [ ] **Step 3: Independently verify Cloud Run is private and disabled after the trap exits**

### Task 5: Prepare App Review Materials Without Submitting

**Files:**
- Create: `docs/app_store_meal_scan_review_packet_2026-07-11.md`
- Modify: `AppStoreReadinessChecklist.md`
- Modify: `docs/meal_scan_flash_lite_production_setup.md`

- [x] **Step 1: Draft exact review notes and reviewer test steps**

- [x] **Step 2: Document App Privacy and privacy-policy deltas**

Include user-initiated photo upload disclosure, purpose-limited processing, no raw-image retention on the proxy, local-only reviewed nutrition storage, quotas, and manual/barcode fallbacks.

- [x] **Step 3: Prepare the screenshot checklist and require a build number above `17`**

- [x] **Step 4: Keep all submission and build-number mutations pending separate owner approval**

### Task 6: Final Verification

- [x] **Step 1: Run `git diff --check`**

- [x] **Step 2: Run proxy and budget-controller tests and high-severity audits**

- [x] **Step 3: Regenerate with XcodeGen and run the simulator test suite**

- [x] **Step 4: Build generic-device Release without `-allowProvisioningUpdates`**

- [x] **Step 5: Verify production App Attest configuration, exact repeat matching enabled, similar matching disabled, and Cloud Run private/disabled**

The configuration and safe cloud posture are verified. The physical production App Attest request itself remains Task 4 and is not implied by this checkbox.

- [ ] **Step 6: Commit final physical-probe evidence only after rollback verification**

The implementation and preparation artifacts are already committed after independent private/disabled verification. The device backup path, probe response, side-effect checks, temporary revision, and rollback evidence remain uncommitted because the live physical probe has not run.
