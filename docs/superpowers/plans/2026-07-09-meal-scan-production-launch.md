# CycleBalance Meal Scan Production Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make CycleBalance's accountless AI meal-photo estimate path production-ready around the cheapest currently callable model, with a tested successor path and fail-closed release gates.

**Architecture:** Keep the iOS app local-first and send one normalized JPEG only after a user chooses Photo Estimate. The Cloud Run proxy remains the sole model caller and enforces Firebase App Check backed by App Attest, RevenueCat access, Firestore quota, model allowlisting, budget controls, and the remote kill switch before inference. Launch on `gemini-2.5-flash-lite`; allow `gemini-3.1-flash-lite` for controlled evaluation before the October 16, 2026 migration deadline.

**Tech Stack:** SwiftUI, Swift Testing, Firebase App Check with App Attest, URLSession, Node.js 20, Cloud Run, Firestore, Secret Manager, RevenueCat API V2, Gemini Developer API structured output.

## Global Constraints

- Do not add `gemini-2.0-flash-lite`; Google shut it down on June 1, 2026.
- Keep `gemini-2.5-flash-lite` as the launch default at `$0.10` input and `$0.40` output per 1M tokens.
- Add `gemini-3.1-flash-lite` only as an allowlisted evaluation/migration target at `$0.25` input and `$1.50` output per 1M tokens.
- Do not add OpenAI Terra or Luna to live routing until representative meal-photo evaluation shows a material quality gain; their token prices are substantially higher.
- Never ship model API keys in the iOS app.
- Do not store raw meal photos on the proxy.
- Keep review-before-save, barcode lookup, and manual entry available.
- Preserve unrelated changes in the dirty worktree.

---

### Task 1: Enforce The Model Lifecycle Policy

**Files:**
- Modify: `cloud/meal-scan-proxy/test/proxy.test.js`
- Modify: `cloud/meal-scan-proxy/src/server.js`
- Modify: `cloud/meal-scan-proxy/README.md`

**Interfaces:**
- Consumes: request field `modelId: string`
- Produces: allowlisted model routing for `gemini-2.5-flash-lite`, `gemini-2.5-flash`, and `gemini-3.1-flash-lite`; unsupported IDs return HTTP 400 with `error = "unsupported_model"` before integrity, entitlement, quota, or provider calls.

- [x] **Step 1: Write failing proxy tests**

```js
test("rejects retired or unknown models before gated services", async () => {
  const calls = [];
  const server = createServer({
    verifyAppIntegrity: async () => { calls.push("integrity"); return true; },
    verifyRevenueCatEntitlement: async () => { calls.push("entitlement"); return true; },
    quotaStore: { checkAndConsume: async () => { calls.push("quota"); return { allowed: true }; } },
    callGemini: async () => { calls.push("gemini"); return successGeminiResponse(); },
  });
  const response = await request(server, { ...validPayload, modelId: "gemini-2.0-flash-lite" });
  assert.equal(response.status, 400);
  assert.equal(response.body.error, "unsupported_model");
  assert.deepEqual(calls, []);
});

test("routes allowlisted Gemini 3.1 Flash-Lite with current cost metadata", async () => {
  const server = createServer({
    verifyAppIntegrity: async () => true,
    verifyRevenueCatEntitlement: async () => true,
    quotaStore: allowQuotaStore(),
    callGemini: async ({ modelId }) => {
      assert.equal(modelId, "gemini-3.1-flash-lite");
      return successGeminiResponse();
    },
  });
  const response = await request(server, { ...validPayload, modelId: "gemini-3.1-flash-lite" }, { "x-firebase-appcheck": "limited-use-token" });
  assert.equal(response.status, 200);
  assert.equal(response.body.usage.estimatedCostUSD, 0.001737);
});
```

- [x] **Step 2: Run `npm test` and verify both new tests fail for the intended reasons.**
- [x] **Step 3: Add the 3.1 price configuration and explicit unsupported-model response.**
- [x] **Step 4: Run `npm test` and verify the complete proxy suite passes.**

### Task 2: Integrate Firebase App Check With App Attest

**Files:**
- Modify: `PCOS/PCOSTests/GeminiMealScanTests.swift`
- Modify: `PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealScanRemote.swift`
- Add: `PCOS/PCOS/Features/Meals/MealScan/Remote/FirebaseMealScanAppCheckTokenProvider.swift`
- Modify: `PCOS/PCOS/App/CycleBalanceApp.swift`
- Modify: `PCOS/PCOS/PCOS.entitlements`
- Modify: `Config/Debug.xcconfig`
- Modify: `Config/Release.xcconfig`

**Interfaces:**
- Consumes: `MealScanAppCheckTokenProviding.limitedUseToken()`
- Produces: an `X-Firebase-AppCheck` limited-use token on every uncached remote request; the proxy consumes the token, rejects replay, and pins the Firebase app ID. Release signs with the production App Attest environment.

- [x] **Step 1: Add tests for missing tokens, token-provider failure, App Check rejection, and no Gemini call after a failed gate.**
- [x] **Step 2: Add FirebaseCore and FirebaseAppCheck, configure the provider before `FirebaseApp.configure()`, and inject a limited-use token provider.**
- [x] **Step 3: Verify and consume App Check tokens in the proxy, pin `FIREBASE_APP_ID`, and remove the custom raw App Attest protocol.**
- [x] **Step 4: Add `com.apple.developer.devicecheck.appattest-environment = $(APP_ATTEST_ENVIRONMENT)` with Debug `development` and Release `production`.**
- [x] **Step 5: Run focused proxy and iOS tests and verify they pass.**

### Task 3: Correct Release Privacy And Sample Behavior

**Files:**
- Modify: `PCOS/PCOSTests/InterfaceResilienceTests.swift`
- Modify: `PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift`
- Modify: `PCOS/PCOS/Info.plist`

**Interfaces:**
- Produces: remote-photo disclosure that does not imply on-device-only inference; sample scans appear only when mock scan data is enabled; camera and photo-library purpose strings disclose meal-photo analysis.

- [x] **Step 1: Add source-contract tests requiring remote analysis disclosure and mock-only sample gating.**
- [x] **Step 2: Run the focused interface test and verify failure.**
- [x] **Step 3: Update the two privacy notices, purpose strings, and sample button guard.**
- [x] **Step 4: Run focused interface and localization tests.**

### Task 4: Verify The Integrated App

**Files:**
- Verify only unless generated project membership changes.

- [x] **Step 1: Run `bash -n` on both cloud setup scripts.**
- [x] **Step 2: Run the complete proxy test suite.**
- [x] **Step 3: Resolve Swift packages and run focused Gemini, data-deletion, and interface tests with `xcodebuild`.**
- [x] **Step 4: Build and launch CycleBalance in Simulator, then verify the scanner remains gated in Release posture and the debug preview remains usable.**
- [x] **Step 5: Run `git diff --check` on all touched files.**

### Task 5: Provision And Deploy Fail-Closed

**Files:**
- Use: `cloud/meal-scan-proxy/scripts/bootstrap-gcp.sh`
- Use: `cloud/meal-scan-proxy/scripts/deploy-cloud-run.sh`
- Update after deployment: ignored `Config/LocalSecrets.xcconfig`

- [x] **Step 1: Authenticate `gcloud`, create `cyclebalance-prod-20260710`, and link active billing.**
- [x] **Step 2: Create restricted Gemini and RevenueCat secrets in Secret Manager without writing them to the repo or app.**
- [x] **Step 3: Enable Firestore and deploy the proxy with `MEAL_SCAN_ENABLED=false`, `APP_CHECK_REQUIRED=true`, and Firebase app-ID pinning.**
- [x] **Step 4: Smoke-test the disabled service and exercise integrity, entitlement, quota, cache, timeout, parse, and budget gates with automated tests.**
- [x] **Step 5: Add the observed Cloud Run base URL to ignored local configuration and verify the signed Release plist and production App Attest entitlement.**
- [ ] **Step 6: Run one limited-use App Check request from a physical iPhone.**
- [ ] **Step 7: Enable both server and iOS feature gates only after labeled quality testing and privacy/App Review disclosures are confirmed.**

**Current rollout posture (July 10, 2026):** The dedicated project, billing, `$150` budget, `$120` hard scanner stop, secrets, Firebase App Check, RevenueCat V2 checks, Firestore quotas/cache, and disabled Cloud Run service are deployed and verified. The current App Store build remains correctly hidden/coming soon. Physical-device, labeled-quality, and App Review disclosure gates remain open before public enablement.

## Decision Review

- Coverage: model choice, lifecycle migration, security, privacy, sample behavior, tests, cloud provisioning, and release enablement are all represented.
- No placeholders: production identifiers are documented, while credential values remain only in their approved secret stores.
- Type consistency: the proxy keeps the existing request/response contract and receives Firebase App Check through an injectable client token-provider boundary.
