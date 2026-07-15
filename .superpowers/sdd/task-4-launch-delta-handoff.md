# CycleBalance Meal Scan Synchronized Launch-Delta Handoff

Status: **staging only — no live changes authorized**

This is a staging document, not a live policy edit. It does not authorize publishing website changes, editing App Store Connect, changing live policies, sending outreach, or deploying the scanner. All surfaces below move together only after the release gate is approved.

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
- Alternatives: barcode and manual logging remain available.
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
| Support FAQ | Expand | Keep the existing Gemini privacy answer and add the complete workflow: consent, retention, proxy handling, corrections, rolling/lifetime quotas, exact cache/reuse, barcode, and manual entry. | Support + Product; draft only. |
| Homepage FAQ | Confirmed contradiction | Replace the unqualified claim that health logs stay on-device unless exported with copy that preserves local health-record storage while clearly disclosing the optional explicit-consent fresh-photo provider path. | Web + Privacy/Policy; no deployment authorized. |
| App Privacy | Stage/reconcile | Re-answer data-type, collection, purpose, linkage, and third-party-processing disclosures from the shipped data flow. Do not infer answers from website shorthand. | Privacy/Policy + App Store owner; no App Store Connect edit authorized. |
| Review notes | Stage/reconcile | Give App Review a short test path: open scanner → read/accept consent → use approved fixture → edit draft → save → demonstrate manual/barcode fallback and quota state. | App Store release owner; attach only to the matching build. |
| Live website copy | Staged preview | Keep `/meal-scan` staged until the public build is reachable, then change availability copy only through this synchronized set. Preserve provider, retention, proxy, review-before-save, reuse, and alternatives disclosures. | Web + Product; no deployment authorized. |
| App Store description | Confirmed contradiction | Remove or qualify “No accounts required, no cloud uploads, no ads.” so the description does not deny the explicit-consent fresh-photo provider path; add capability copy only after release/screenshot approval. | App Store owner + Marketing; no metadata edit authorized. |
| App Store copy | Stage/reconcile | Synchronize promotional text, description, keywords, screenshots, and any scanner-specific page with the same verified availability and privacy language. | App Store owner + Marketing; draft only. |

## Surface copy blocks for review

These blocks are starting points for owner review and must not be published independently.

### Privacy Policy

Verify the July 12 live text against the final release behavior; do not replace correct existing coverage wholesale. Reconcile any delta to this fact block: “When you choose photo meal scanning and give explicit consent, CycleBalance sends the fresh image through its proxy to Google Gemini to create an editable draft. Google may retain fresh uploads for up to 55 days for abuse monitoring. The CycleBalance proxy does not retain raw image bytes. Your reviewed meal record and exact reusable version can remain on your device. You can use barcode or manual entry instead.”

### Terms

Verify the July 12 live text against the final release behavior; do not treat Terms as missing. Reconcile any delta to this fact block: “Photo-based meal drafts are starting points that require your review before saving. Photos may not show every ingredient, amount, or preparation detail. Fresh-scan availability is subject to the disclosed rolling and lifetime limits. Barcode, manual entry, and eligible exact local reuse do not use a fresh scan.”

### Support FAQ

Preserve and verify the existing privacy FAQ that names Google Gemini, then expand the support set. Answer in this order: what is sent; when consent appears; what the provider may retain; what the proxy does not retain; what remains local; how to correct/save; how rolling and lifetime limits work; and how to switch to exact reuse/cache, barcode, or manual entry.

### App Privacy

Reconcile the shipped flow with Apple's current App Privacy questions at launch time. Record the rationale and approver for each answer. Do not infer a “not collected” answer from proxy non-retention while a third-party processor may retain fresh uploads.

### Review notes

Use only verified build behavior and test credentials. State where the consent disclosure appears, how to exercise corrections, where the saved local record appears, and what the reviewer should see when a quota is reached. Never ask App Review to use a real personal meal photo.

### Live website copy

Homepage FAQ correction for synchronized review: “CycleBalance health logs are stored on your device unless you export them. If you choose Photo Estimate, a fresh meal image is processed only after explicit consent under the disclosed Google Gemini retention terms.” Verify this draft against final approved policy wording before publication.

Keep the `/meal-scan` staged availability line until the approved version is publicly reachable. At that point, replace only the availability language through the same reviewed change set; do not remove the consent, retention, review, or alternatives disclosures.

### App Store copy

The current description line “No accounts required, no cloud uploads, no ads.” is a confirmed contradiction because it does not disclose the opt-in provider path. Stage a replacement that preserves only verified claims, for example: “No account required and no ads. Photo Estimate sends a fresh meal image to Google Gemini only after you review the disclosure and give explicit consent.” Verify the final sentence against the submitted build, App Privacy answers, and approved policy copy.

Recommended value line after release verification: `Start with a photo. Stay in control. Review an editable meal draft before saving it alongside the context you choose.`

## Apple Campaign Link and Custom Product Page handoff

### Existing page route

1. After release verification, create an Apple Campaign Link whose destination is the existing `symptoms-food-glucose` Custom Product Page.
2. Use a stable, scanner-specific campaign name agreed by Marketing and App Store owners; record the exact generated URL in the launch tracker before using it.
3. Route website and organic scanner assets through that approved link only after the destination screenshots/copy accurately represent the released build.
4. Test the full route on a signed-out device and confirm the expected storefront and destination page before distribution.
5. Record link creation date, owner, destination, placements, and rollback contact. Do not record fabricated baseline or conversion values.

### Optional scanner page

An optional scanner page may be staged as a new Custom Product Page only after release verification, final archived-build screenshots, approved provider/privacy copy, and App Store metadata review. Suggested internal slug: `photo-meal-estimate`; the actual App Store Connect page name and generated link must be captured from the live interface, not invented in advance.

If the optional page is not approved, keep the Campaign Link on `symptoms-food-glucose`. Do not silently redirect campaign placements to the default product page.

### Measurement boundary

Do not invent current performance results or unverified platform algorithm claims. Record only App Store Connect values actually observed after launch, with date range, storefront, page/campaign identifier, and comparison limits. Treat any lift as descriptive unless the test design supports a stronger conclusion.

## Launch-day synchronization checklist

1. Freeze the approved fact block and release/build identifiers.
2. Capture owner sign-off for every row in the surface matrix, including the two confirmed contradiction rows.
3. Update policy/support pages and App Store disclosures/copy within the same coordinated release window.
4. Verify the live website and support links from the submitted/public product page.
5. Verify Campaign Link destination and storefront behavior.
6. Archive screenshots/PDFs of the published wording and App Privacy answers with timestamps.
7. Confirm the homepage FAQ and App Store description no longer make unqualified no-upload claims before any scanner promotion.
8. If any surface is stale or unavailable, hold scanner promotion and revert availability copy to staged/coming-soon posture.

## Rollback trigger

Pause scanner promotion and restore staged availability language if provider handling, retention, proxy behavior, quotas, billing, consent, reviewer access, or public-build availability differs from this approved handoff. Correct every affected surface before resuming.
