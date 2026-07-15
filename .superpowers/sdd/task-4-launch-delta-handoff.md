# CycleBalance Meal Scan Synchronized Launch-Delta Handoff

Status: **staging only — no live changes authorized**

This is a staging document, not a live policy edit. It does not authorize publishing website changes, editing App Store Connect, changing live policies, sending outreach, or deploying the scanner. All surfaces below move together only after the release gate is approved.

The preview remains outside the deployed `docs` tree at `.superpowers/sdd/staging/meal-scan-preview.html`. A separate publication commit may move it to `docs/meal-scan.html` and add `/meal-scan` discovery only after every release gate is approved. Until then, `docs/sitemap.xml` and `docs/llms.txt` must not advertise it.

## Current live-state correction — verified July 14, 2026

Privacy Policy and Terms were updated July 12 with detailed Photo Estimate, Google Gemini, cache, and quota language. They are not blank launch surfaces and must be verified/reconciled against the final build instead of treated as wholly missing.

The live Support FAQ currently has one privacy FAQ that names Google Gemini. It needs expansion for the full consent, retention, proxy, correction, quota, cache, barcode, and manual-path workflow.

Two confirmed public-copy contradictions remain:

- the homepage FAQ says health logs stay on-device unless exported, without carving out the explicit-consent fresh-photo provider path; and
- the App Store description still says, “No accounts required, no cloud uploads, no ads.”

This handoff stages the synchronized correction. It does not change those live surfaces.

## Single release gate

The launch owner may schedule the synchronized copy/policy update only after all of the following are evidenced against the same release candidate:

- scanner release verification is complete, including the production provider path and signed distribution build;
- final consent, provider, retention, proxy, local-cache, quota, and fallback behavior match the shipped build;
- RevenueCat/App Store product access is verified for paid, trial, restore, expiry, and offline/error states;
- final screenshots and demo captures come from the approved archived build;
- Privacy/Policy, Product, Support, App Store release, and Marketing owners approve the same wording;
- the public version is available before any copy says or implies that photo meal scanning is live.

If any item changes, stop the launch and update every affected row below before publishing any one surface.

## Shared facts for every surface

- Fresh photo path: Photo → explicit Google Gemini consent → editable draft → user correction → local save → optional context/check-in.
- Provider retention: Google may retain fresh uploads for up to 55 days for abuse monitoring.
- Proxy handling: the CycleBalance proxy does not retain raw image bytes.
- Local reuse: an exact reviewed meal can remain on device and be reused without a fresh provider upload.
- On-device alternatives: manual entry and exact reviewed-meal reuse/cache can remain on device.
- Barcode alternative: barcode lookup is a separate optional network request; it does not send the meal photo.
- Paid: 10 fresh scans per rolling 24 hours (immutable max 15).
- Trial/sandbox: 5 fresh scans per rolling 24 hours and 25 lifetime.
- Exact cache, barcode, and manual paths are non-billable.
- Output posture: an editable starting draft that the user reviews; no medical, causal, precision, score, or guaranteed-result positioning.

These are copy inputs, not permission to expose internal enforcement details beyond what each surface needs. Any quota change requires code/config verification and a full synchronized-surface resync.

## Synchronized surface matrix

| Surface | Current status | Staged launch delta | Owner/gate |
|---|---|---|---|
| Privacy Policy | Verify/reconcile | Diff the July 12 Photo Estimate/Gemini/cache/quota language against the final build; preserve correct text and reconcile consent, 55-day provider retention, proxy raw-byte non-retention, local reviewed records/cache, and alternatives. | Privacy/Policy; no live edit authorized. |
| Terms | Verify/reconcile | Diff the July 12 Photo Estimate/Gemini/cache/quota language against final behavior; reconcile user review responsibility, limitations, provider processing, quota/fair-use rules, and the wellness-tool boundary. | Privacy/Policy; no live edit authorized. |
| Support FAQ | Expand | Keep the existing Gemini privacy answer and add the complete workflow: consent, retention, proxy handling, corrections, rolling/lifetime quotas, on-device manual/exact reuse, and the separate optional network barcode lookup. | Support + Product; draft only. |
| Homepage FAQ | Confirmed contradiction | Replace the unqualified claim that health logs stay on-device unless exported with copy that preserves local health-record storage while clearly disclosing the optional explicit-consent fresh-photo provider path. | Web + Privacy/Policy; no deployment authorized. |
| App Privacy | Stage/reconcile | Re-answer data-type, collection, purpose, linkage, and third-party-processing disclosures from the shipped data flow. Do not infer answers from website shorthand. | Privacy/Policy + App Store owner; no App Store Connect edit authorized. |
| Review notes | Stage/reconcile | Give App Review a short test path: open scanner → read/accept consent → use approved fixture → edit draft → save → demonstrate on-device manual/exact reuse, the separate optional network barcode lookup, and quota state. | App Store release owner; attach only to the matching build. |
| Live website copy | Non-public staged preview | Keep the preview outside deployed `docs` until the public build is reachable. A separate reviewed publication commit may then move it into `docs`, add discovery, and change availability copy through this synchronized set. | Web + Product; no deployment authorized. |
| App Store description | Confirmed contradiction | Remove or qualify “No accounts required, no cloud uploads, no ads.” so the description does not deny the explicit-consent fresh-photo provider path; add capability copy only after release/screenshot approval. | App Store owner + Marketing; no metadata edit authorized. |
| App Store copy | Stage/reconcile | Synchronize promotional text, description, keywords, screenshots, and any scanner-specific page with the same verified availability and privacy language. | App Store owner + Marketing; draft only. |

## Surface copy blocks for review

These blocks are starting points for owner review and must not be published independently.

### Privacy Policy

Verify the July 12 live text against the final release behavior; do not replace correct existing coverage wholesale. Reconcile any delta to this fact block: “When you choose photo meal scanning and give explicit consent, CycleBalance sends the fresh image through its proxy to Google Gemini to create an editable draft. Google may retain fresh uploads for up to 55 days for abuse monitoring. The CycleBalance proxy does not retain raw image bytes. Your reviewed meal record, exact reusable version, and manual entries can remain on your device. Barcode lookup is a separate optional network request and does not send the meal photo.”

### Terms

Verify the July 12 live text against the final release behavior; do not treat Terms as missing. Reconcile any delta to this fact block: “Photo-based meal drafts are starting points that require your review before saving. Photos may not show every ingredient, amount, or preparation detail. Fresh-scan availability is subject to the disclosed rolling and lifetime limits. Manual entry and eligible exact local reuse do not use a fresh scan and can remain on device. Barcode lookup is a separate optional network request and does not send the meal photo.”

### Support FAQ

Preserve and verify the existing privacy FAQ that names Google Gemini, then expand the support set. Answer in this order: what is sent; when consent appears; what the provider may retain; what the proxy does not retain; what remains local; how to correct/save; how rolling and lifetime limits work; how to switch to on-device manual/exact reuse; and how the separate optional network barcode lookup behaves.

### App Privacy

Reconcile the shipped flow with Apple's current App Privacy questions at launch time. Record the rationale and approver for each answer. Do not infer a “not collected” answer from proxy non-retention while a third-party processor may retain fresh uploads.

### Review notes

Use only verified build behavior and test credentials. State where the consent disclosure appears, how to exercise corrections, where the saved local record appears, and what the reviewer should see when a quota is reached. Never ask App Review to use a real personal meal photo.

### Live website copy

Homepage FAQ correction for synchronized review: “CycleBalance health logs are stored on your device unless you export them. If you choose Photo Estimate, a fresh meal image is processed only after explicit consent under the disclosed Google Gemini retention terms.” Verify this draft against final approved policy wording before publication.

Keep the non-public preview outside `docs` until the approved version is publicly reachable. At that point, use a separate reviewed publication commit to move the file into `docs`, add sitemap/LLM discovery, and replace only the availability language through the same synchronized change set; do not remove the consent, retention, review, or alternatives disclosures.

### App Store copy

The current description line “No accounts required, no cloud uploads, no ads.” is a confirmed contradiction because it does not disclose the opt-in provider path. Stage a replacement that preserves only verified claims, for example: “No account required and no ads. Photo Estimate sends a fresh meal image to Google Gemini only after you review the disclosure and give explicit consent.” Verify the final sentence against the submitted build, App Privacy answers, and approved policy copy.

Recommended value line after release verification: `Start with a photo. Stay in control. Review an editable meal draft before saving it alongside the context you choose.`

## Apple Campaign Link and Custom Product Page handoff

### Existing page route

Publication-time owner inputs: Apple provider token (`pt`) and final approved Custom Product Page ID (`ppid`); do not hardcode or invent either value.

1. After release verification, confirm in App Store Connect that `symptoms-food-glucose` is Approved and publicly visible in the target storefront. Capture dated evidence and the final Apple-provided destination ID.
2. At publication time, the authorized owner supplies the Apple provider token (`pt`) and approved destination ID (`ppid`). Keep both out of staging copy and source defaults.
3. Marketing and the App Store owner approve one stable scanner-specific campaign token (`ct`) before link creation. Keep that same non-empty token across the approved placements so reporting remains attributable.
4. Validate the final Apple-generated Campaign Link against this contract:
   - `pt`: non-empty ASCII digits only (`^[0-9]+$`);
   - `ct`: stable, non-empty approved campaign token exactly equal to the owner-approved value;
   - `ppid`: non-empty and exactly equal to the approved destination ID for `symptoms-food-glucose`.
5. Run the deterministic publication check with the actual owner-supplied values:

   The validator invocation requires `--campaign-link`, `--approved-ct`, `--approved-ppid`, `--cpp-approved-visible`, and `--signed-out-storefront-verified`.

   ```sh
   node tools/validate-site.mjs \
     --campaign-link '<APPLE_GENERATED_CPP_URL>' \
     --approved-ct '<APPROVED_CAMPAIGN_TOKEN>' \
     --approved-ppid '<APPROVED_CPP_ID>' \
     --cpp-approved-visible \
     --signed-out-storefront-verified
   ```

6. On a signed-out device, open the exact generated link in the target storefront and confirm that it lands on the approved `symptoms-food-glucose` Custom Product Page rather than the default product page.
7. Before distribution, record the exact generated URL, creation date, owner, approved `ct`, final `ppid`, target storefront, signed-out verification evidence, placements, and rollback contact. Do not record fabricated baseline or conversion values.

### Optional scanner page

An optional scanner page may be staged as a new Custom Product Page only after release verification, final archived-build screenshots, approved provider/privacy copy, and App Store metadata review. Suggested internal slug: `photo-meal-estimate`; the actual App Store Connect page name, final `ppid`, provider token, and generated link are publication-time owner inputs that must be captured from the live interface, not invented or hardcoded in advance.

If the optional page is not approved, keep the Campaign Link on `symptoms-food-glucose`. Do not silently redirect campaign placements to the default product page.

### Measurement boundary

Do not invent current performance results or unverified platform algorithm claims. Record only App Store Connect values actually observed after launch, with date range, storefront, page/campaign identifier, and comparison limits. Treat any lift as descriptive unless the test design supports a stronger conclusion.

## Launch-day synchronization checklist

1. Freeze the approved fact block and release/build identifiers.
2. Capture owner sign-off for every row in the surface matrix, including the two confirmed contradiction rows.
3. Update policy/support pages and App Store disclosures/copy within the same coordinated release window.
4. Verify the live website and support links from the submitted/public product page.
5. Verify the Campaign Link contract (`pt`, stable `ct`, approved `ppid`), Approved/publicly-visible CPP status, and signed-out target-storefront behavior with dated evidence.
6. Archive screenshots/PDFs of the published wording and App Privacy answers with timestamps.
7. Confirm the homepage FAQ and App Store description no longer make unqualified no-upload claims before any scanner promotion.
8. If any surface is stale or unavailable, hold scanner promotion and revert availability copy to staged/coming-soon posture.

## Rollback trigger

Pause scanner promotion and restore staged availability language if provider handling, retention, proxy behavior, quotas, billing, consent, reviewer access, or public-build availability differs from this approved handoff. Correct every affected surface before resuming.
