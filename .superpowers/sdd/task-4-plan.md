# CycleBalance Meal-Scan Marketing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stage an honest, accessible `/meal-scan` landing page and synchronized launch materials without publishing or implying that photo meal scanning is currently live.

**Architecture:** Extend the existing dependency-free Node site validator so the launch contract is executable, then add one static English HTML page and two non-public Markdown handoffs under `.superpowers/sdd`. Reuse existing CycleBalance colors, typography, app icon, navigation, footer links, and App Store URL; add the page to sitemap and `llms.txt` discovery only as staged source content.

**Tech Stack:** Static HTML/CSS, Node.js built-ins, Markdown, existing `tools/validate-site.mjs` checks.

## Global Constraints

- Work only on `codex/cyclebalance-meal-scan-marketing` in the designated worktree.
- Do not publish, push, deploy, alter App Store Connect, or send outreach.
- Preserve the user-owned dirty `PCOS_Management_website_hero_video` worktree.
- Approved lines are exactly `Start with a photo. Stay in control.`, `Meal context, not meal judgment.`, and `From plate to pattern-ready record.`
- Scanner posture is staged/coming after release verification, never publicly live.
- Do not claim diagnosis, treatment, causal insight, exact nutrition, Zero Data Retention, guaranteed accuracy, `cycle-aware nutrition`, or a meal-balance score.
- Paid quota is 10 fresh scans per rolling 24 hours with immutable max 15; trial/sandbox quota is 5 per rolling 24 hours and 25 lifetime.
- Exact cache, barcode, and manual paths are non-billable.

---

### Task 1: Executable launch contract

**Files:**
- Modify: `tools/validate-site.mjs`
- Test: `node tools/validate-site.mjs`

**Interfaces:**
- Consumes: repository root, `docs/meal-scan.html`, `.superpowers/sdd/task-4-social-demo-handoff.md`, `.superpowers/sdd/task-4-launch-delta-handoff.md`, `docs/sitemap.xml`, and `docs/llms.txt`.
- Produces: `validateMealScanLaunch()` failures through the validator's existing `fail(message)` accumulator.

- [x] **Step 1: Add deterministic content assertions before production files exist**

Add helpers with these signatures and behavior:

```js
function requireText(source, label, required) {
  for (const value of required) {
    if (!source.includes(value)) fail(`${label}: missing required text: ${value}`);
  }
}

function forbidText(source, label, forbidden) {
  const normalized = source.toLowerCase();
  for (const value of forbidden) {
    if (normalized.includes(value.toLowerCase())) fail(`${label}: forbidden claim present: ${value}`);
  }
}
```

Implement `validateMealScanLaunch()` so missing artifacts fail independently, the HTML contract checks title/canonical/social URL, approved messages, Photo → Google Gemini consent → editable draft → correction → local save → context, 55-day provider retention, proxy raw-byte non-retention, on-device exact reuse, manual/barcode alternatives, release-verification posture, App Store/support/privacy/terms links and the existing app-icon asset. Reject the exact prohibited marketing phrases. Validate all four organic concepts, the synthetic-fixture label rule, the seven synchronized policy/store surfaces, both quota tiers, non-billable paths, Campaign Link, Custom Product Page, `symptoms-food-glucose`, and optional scanner page instructions in the handoffs. Require `/meal-scan` in sitemap and `llms.txt`.

- [x] **Step 2: Run RED and confirm the contract fails for missing deliverables**

Run: `node tools/validate-site.mjs`

Expected: exit 1 with missing `docs/meal-scan.html`, social/demo handoff, and launch-delta handoff failures.

---

### Task 2: Staged page and handoffs

**Files:**
- Create: `docs/meal-scan.html`
- Create: `.superpowers/sdd/task-4-social-demo-handoff.md`
- Create: `.superpowers/sdd/task-4-launch-delta-handoff.md`
- Modify: `docs/sitemap.xml`
- Modify: `docs/llms.txt`
- Test: `node tools/validate-site.mjs`

**Interfaces:**
- Consumes: the Task 1 content contract and existing `/assets/images/site/cyclebalance-app-icon-96.png`, root-page navigation/footer conventions, and App Store URL.
- Produces: canonical English page `https://cyclebalance.app/meal-scan` and review-only launch artifacts.

- [x] **Step 1: Build the accessible static page**

Use semantic `header`, `nav`, `main`, ordered process content, disclosure section, alternatives section, FAQ, and `footer`; include a skip link, visible focus styles, reduced-motion behavior, responsive grid breakpoints, and the existing app icon. The hero copy is:

```html
<p class="eyebrow">Staged preview · Coming after release verification</p>
<h1>Start with a photo. <span>Stay in control.</span></h1>
<p class="hero-copy">Turn a meal photo into an editable starting draft, review every detail, and decide what belongs in your local record.</p>
```

The flow must visibly enumerate Photo, Consent, Correct, Save, and Context. The trust disclosure must say that consent is explicit before sending a fresh upload to Google Gemini; Google may retain fresh uploads for up to 55 days for abuse monitoring; the CycleBalance proxy does not retain raw image bytes; exact reviewed-meal reuse can remain on device; and barcode/manual logging remain available.

- [x] **Step 2: Write the privacy-safe 15-second social/demo handoff**

Use four timed beats—Photo, Consent, Correct, Save—and all four approved organic concept titles. Require the exact on-frame label `Demonstration using synthetic meal details — not a testimonial or accuracy result.` and prohibit raw personal health data, usernames, dates, symptoms, glucose, cycle phase, metadata-bearing photos, testimonials, and accuracy evidence.

- [x] **Step 3: Write one synchronized launch-delta handoff**

Use one release gate and one owner/status table covering Privacy Policy, Terms, Support FAQ, App Privacy, review notes, live website copy, and App Store copy. Include the exact quota values and non-billable paths. Stage Campaign Link routing to the existing `symptoms-food-glucose` Custom Product Page, with a scanner-specific page only after approved assets/copy and release verification; make clear that no performance or platform-algorithm claims are available.

Current-state correction: Privacy Policy and Terms already received detailed Photo Estimate/Gemini/cache/quota language on July 12, so mark them verify/reconcile; expand the single Gemini privacy answer currently in Support FAQ; and treat the homepage FAQ's unqualified on-device-only statement plus the App Store description's `No accounts required, no cloud uploads, no ads.` line as confirmed contradictions to resolve in the synchronized launch set.

- [x] **Step 4: Add page discovery records**

Add this sitemap entry before the blog index and a matching key-page line in `llms.txt`:

```xml
<url>
  <loc>https://cyclebalance.app/meal-scan</loc>
  <lastmod>2026-07-14</lastmod>
  <changefreq>monthly</changefreq>
  <priority>0.7</priority>
</url>
```

- [x] **Step 5: Run GREEN**

Run: `node tools/validate-site.mjs`

Expected: `Validation PASS: 0 errors, 0 warnings` and updated report counts that include the new HTML page and URL.

---

### Task 3: Verification, review, report, and commits

**Files:**
- Create: `.superpowers/sdd/task-4-report.md`
- Review: all Task 1 and Task 2 files

**Interfaces:**
- Consumes: complete staged artifacts and fresh command output.
- Produces: implementation commit, evidence report, report commit, and compact status contract.

- [x] **Step 1: Run full local checks**

Run:

```bash
node --check tools/validate-site.mjs
node tools/validate-site.mjs
git diff --check
```

Expected: all exit 0; validator reports zero errors and warnings.

- [x] **Step 2: Self-review exact requirements and scope**

Inspect `git diff --stat`, `git diff`, `git status --short`, and verify that no file outside the designated worktree changed. Search the page for prohibited phrases and confirm the feature is consistently described as staged.

- [x] **Step 3: Commit implementation**

```bash
git add tools/validate-site.mjs docs/meal-scan.html docs/sitemap.xml docs/llms.txt docs/VALIDATION-REPORT.md .superpowers/sdd/task-4-plan.md .superpowers/sdd/task-4-social-demo-handoff.md .superpowers/sdd/task-4-launch-delta-handoff.md
git commit -m "feat: stage meal scan launch materials"
```

- [x] **Step 4: Write and commit the report**

Record files, exact RED/GREEN commands and outputs, final verification commands/results, implementation commit, scope self-review, and any concerns in `.superpowers/sdd/task-4-report.md`, then commit it with `docs: add meal scan marketing task report`.

- [x] **Step 5: Verify committed state**

Run `node tools/validate-site.mjs && git status --short --branch && git log -2 --oneline` and return only status, current commit hash, one-line validation summary, and concerns.
