# CycleBalance Meal-Scan Marketing Implementation Plan

> **For agentic workers:** implement test-first and keep the preview non-public until every release and publication gate is approved.

**Goal:** Stage an honest, WCAG AA meal-scan preview and synchronized launch materials without publishing, deploying, or implying that photo meal scanning is live.

**Architecture:** Keep the preview at `.superpowers/sdd/staging/meal-scan-preview.html`, outside the GitHub Pages `docs` tree. Extend the dependency-free Node validator so it proves merge safety, page content, color contrast, claims, consent/alternative wording, handoff completeness, and an owner-supplied Apple Campaign Link contract. A later, separate publication commit may move the page to `docs/meal-scan.html` and add `/meal-scan` discovery only after all gates pass.

**Tech Stack:** Static HTML/CSS, Node.js built-ins, Markdown, existing `tools/validate-site.mjs` checks.

## Global constraints

- Work only on `codex/cyclebalance-meal-scan-marketing` in the designated worktree.
- Do not publish, push, deploy, edit App Store Connect, or send outreach.
- Preserve unrelated worktrees and user changes.
- Keep `docs/meal-scan.html` absent and keep `/meal-scan` out of `docs/sitemap.xml` and `docs/llms.txt` until a separate approved publication commit.
- Approved lines are exactly `Start with a photo. Stay in control.`, `Meal context, not meal judgment.`, and `From plate to pattern-ready record.`
- Scanner posture is staged/coming after release verification, never publicly live.
- Do not claim diagnosis, treatment, causal insight/conclusion, exact nutrition, Zero Data Retention, guaranteed accuracy, `cycle-aware nutrition`, or a meal-balance score, including punctuation/case variants.
- All text contrast is at least 4.5:1; focus indicators and essential interface boundaries are at least 3:1.
- Declining skips the photo estimate. Manual entry and exact reviewed-meal reuse can remain on-device; barcode lookup is a separate optional network request and does not send the meal photo.
- Paid quota is 10 fresh scans per rolling 24 hours with immutable max 15; trial/sandbox quota is 5 per rolling 24 hours and 25 lifetime. Exact cache, barcode, and manual paths are non-billable.
- Apple provider token (`pt`) and final Custom Product Page ID (`ppid`) are publication-time owner inputs. Never invent or hardcode them.

---

### Task 1: Encode the review requirements and prove RED

**Files:**
- Modify: `tools/validate-site.mjs`
- Test: `node tools/validate-site.mjs`

**Interfaces:**
- Consumes the non-public preview, both Task 4 handoffs, deployed discovery files, current date, and optional publication-time Campaign Link arguments.
- Produces deterministic failures through the existing validator accumulator and refreshes `docs/VALIDATION-REPORT.md`.

- [x] Require the preview under `.superpowers/sdd/staging` and fail if `docs/meal-scan.html` or deployed `/meal-scan` discovery exists.
- [x] Normalize forbidden-claim matching across case, whitespace, and dash variants.
- [x] Compute WCAG contrast from required CSS hex tokens and assert 4.5:1 text plus 3:1 interface/focus minimums.
- [x] Require truthful local/manual/reuse versus optional network-barcode wording and reject the old decline statement.
- [x] Require a current America/Chicago report date rather than a fixed date.
- [x] Require the publication contract: numeric non-empty `pt`; stable non-empty owner-approved `ct`; non-empty `ppid` equal to the approved destination; Approved/publicly-visible `symptoms-food-glucose`; and signed-out target-storefront verification.
- [x] Run RED before production corrections. Observed: `Validation FAIL: 34 errors, 0 warnings`.

---

### Task 2: Correct merge safety, accessibility, consent copy, and handoffs

**Files:**
- Move: `docs/meal-scan.html` → `.superpowers/sdd/staging/meal-scan-preview.html`
- Modify: `.superpowers/sdd/staging/meal-scan-preview.html`
- Modify: `docs/sitemap.xml`
- Modify: `docs/llms.txt`
- Modify: `.superpowers/sdd/task-4-social-demo-handoff.md`
- Modify: `.superpowers/sdd/task-4-launch-delta-handoff.md`

**Interfaces:**
- Produces a reviewable non-public preview and synchronized owner handoffs, not a deployed route.
- Preserves future canonical/social metadata for publication review without making the route discoverable now.

- [x] Move the preview out of `docs` and remove `/meal-scan` from sitemap and LLM discovery.
- [x] Replace low-contrast coral, muted, boundary, and focus colors with deterministic AA tokens.
- [x] Distinguish on-device manual/exact reuse from separate optional network barcode lookup everywhere the alternatives are explained.
- [x] Keep the consent-first Photo → Consent → Correct → Save → Context flow, explicit provider/retention/proxy disclosures, approved messages, synthetic-demo label, semantic structure, and reduced-motion behavior.
- [x] Update the launch handoff with the non-public publication boundary and final Campaign Link contract. Keep `pt` and `ppid` owner-supplied at publication time.
- [x] Update the social/demo handoff so the decline and fallback route is described accurately.
- [x] Run intermediate GREEN. Observed: `Validation PASS: 0 errors, 0 warnings`.

---

### Task 3: Exercise the Campaign Link validator

**Files:**
- Modify: `tools/validate-site.mjs`
- Modify: `.superpowers/sdd/task-4-launch-delta-handoff.md`

- [x] Add optional CLI inputs `--campaign-link`, `--approved-ct`, and `--approved-ppid`, plus evidence flags `--cpp-approved-visible` and `--signed-out-storefront-verified`.
- [x] Reject non-HTTPS/non-Apple URLs, missing or duplicate required query values, nonnumeric `pt`, unstable/empty `ct`, mismatched approved `ct`, mismatched `ppid`, and missing evidence flags.
- [x] Run a synthetic invalid fixture. Observed: `Validation FAIL: 6 errors, 0 warnings`.
- [x] Run a synthetic valid fixture with all evidence flags. Observed: `Validation PASS: 0 errors, 0 warnings`.
- [x] Keep synthetic fixtures out of source defaults and treat the real URL, provider token, and final destination ID as owner-supplied publication inputs.

---

### Task 4: Full verification, report, and correction commit

**Files:**
- Modify: `.superpowers/sdd/task-4-report.md`
- Review: all corrected Task 4 files

- [x] Re-run rendered browser QA at desktop and mobile widths, including page identity, DOM, console, focus/navigation interaction, overflow, and screenshots.
- [x] Run `node --check tools/validate-site.mjs`, base validation, external-reference validation, XML parsing, forbidden-claim search, `git diff --check`, and App Store CTA check.
- [x] Confirm `docs/meal-scan.html` is absent and `/meal-scan` is absent from deployed discovery.
- [x] Record reviewer disposition, exact RED/GREEN evidence, contrast ratios, current counts/date, rendered QA, publication inputs, blockers, and concerns in `.superpowers/sdd/task-4-report.md`.
- [x] Commit the isolated corrections locally. Do not push, publish, or deploy.
- [x] Re-run validation on committed HEAD and report the new hash.

---

### Separate future publication commit — not authorized here

Only after release verification, synchronized owner approvals, an Approved/publicly-visible destination CPP, owner-supplied final Apple values, and signed-out target-storefront verification may a separate commit:

1. move `.superpowers/sdd/staging/meal-scan-preview.html` to `docs/meal-scan.html`;
2. add `https://cyclebalance.app/meal-scan` to `docs/sitemap.xml` and `docs/llms.txt`;
3. update staged availability language to the approved live wording; and
4. rerun the full validator with the actual Campaign Link inputs and evidence flags.
