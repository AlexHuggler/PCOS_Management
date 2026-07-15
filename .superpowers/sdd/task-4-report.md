# Task 4 — Staged Meal-Scan Website and Marketing Report

Date: 2026-07-14

Branch: `codex/cyclebalance-meal-scan-marketing`

Worktree: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/.worktrees/cyclebalance-meal-scan-marketing`

Implementation commit: `d39a8b467fa7d70ebacc5f20106062fae4783ce6`

## Status

Implemented and committed locally. Nothing was pushed, published, deployed, sent, or changed in App Store Connect. The scanner and all launch materials remain staged behind release verification and synchronized-copy approval.

## Files

- `docs/meal-scan.html` — English responsive landing page with canonical/Open Graph/Twitter metadata, App Store CTA, semantic navigation/footer, consent-first five-step loop, provider/retention/proxy disclosure, local exact reuse, manual/barcode alternatives, staged availability language, synthetic-demo label, and accessible/reduced-motion behavior.
- `tools/validate-site.mjs` — executable Task 4 contract for page metadata/copy/disclosures/links/assets, forbidden claims, both staging handoffs, corrected live-state statuses, sitemap, and `llms.txt`.
- `docs/sitemap.xml` — staged `/meal-scan` route entry.
- `docs/llms.txt` — staged meal-scan preview discovery entry.
- `docs/VALIDATION-REPORT.md` — latest full site/external-reference validation counts and warnings.
- `.superpowers/sdd/task-4-social-demo-handoff.md` — privacy-safe 15-second storyboard, four organic concepts, fixture labeling, and preflight gate.
- `.superpowers/sdd/task-4-launch-delta-handoff.md` — single synchronized policy/support/store/campaign handoff with corrected July 14 live-state status.
- `.superpowers/sdd/task-4-plan.md` — test-first implementation plan and execution checklist.
- `.superpowers/sdd/task-4-report.md` — this evidence report; committed separately after the implementation commit so the report can record that immutable hash.

## RED/GREEN evidence

### Baseline

Command:

```bash
node tools/validate-site.mjs
```

Result before Task 4 changes: exit `0`, `Validation PASS: 0 errors, 0 warnings`.

### Original RED — missing staged deliverables

The validator assertions were added before the page or handoffs.

Command:

```bash
node tools/validate-site.mjs
```

Result: exit `1`, `Validation FAIL: 5 errors, 0 warnings`.

Expected failures:

1. `Meal scan page: missing file docs/meal-scan.html`
2. `Social/demo handoff: missing file .superpowers/sdd/task-4-social-demo-handoff.md`
3. `Launch-delta handoff: missing file .superpowers/sdd/task-4-launch-delta-handoff.md`
4. sitemap missing `https://cyclebalance.app/meal-scan`
5. `llms.txt` missing the staged meal-scan preview line

### Original GREEN — page and handoffs implemented

Command:

```bash
node tools/validate-site.mjs
```

Result: exit `0`, `Validation PASS: 0 errors, 0 warnings`.

### Correction RED — current live-source status

After receiving the verified July 14 source correction, assertions were added before changing the launch handoff.

Command:

```bash
node tools/validate-site.mjs
```

Result: exit `1`, `Validation FAIL: 10 errors, 0 warnings`.

Expected missing assertions covered:

- July 12 Privacy Policy/Terms update status;
- existing Support FAQ Gemini answer and required expansion;
- `Verify/reconcile`, `Expand`, and `Confirmed contradiction` matrix states;
- the homepage claim that health logs stay on-device unless exported; and
- the App Store description line `No accounts required, no cloud uploads, no ads.`

### Correction GREEN

The handoff was updated without editing any live page or App Store surface.

Command:

```bash
node tools/validate-site.mjs
```

Result: exit `0`, `Validation PASS: 0 errors, 0 warnings`.

## Final validation

Fresh pre-commit gate:

```bash
node --check tools/validate-site.mjs && \
node tools/validate-site.mjs --external && \
xmllint --noout docs/sitemap.xml && \
git diff --check && \
curl --silent --show-error --location --output /dev/null --max-time 20 \
  --write-out 'App Store CTA: HTTP %{http_code} -> %{url_effective}\n' \
  'https://apps.apple.com/us/app/cyclebalance/id6760353511'
```

Result: exit `0`.

- JavaScript syntax: PASS.
- Site validation/build/link contract: PASS, `0 errors`, `5 warnings`.
- Sitemap XML: PASS.
- Git whitespace check: PASS.
- App Store CTA: HTTP `200` at `https://apps.apple.com/us/app/cyclebalance/id6760353511`.
- Site counts: 175 HTML files, 174 sitemap URLs, 5,913 internal references, 1,344 hreflang links, 487 JSON-LD blocks, 1,152 image references, and 14 external evidence references.

The five warnings are automated-access responses from pre-existing evidence references, not the meal-scan page: four HTTP `403` responses and one HTTP `412` response. They are preserved in `docs/VALIDATION-REPORT.md` for manual verification; there were no broken-link errors.

## Rendered and accessibility QA

Local browser route: `http://127.0.0.1:4173/meal-scan.html`. The local Python static server does not rewrite extensionless routes, so `/meal-scan` returned the server's expected 404; the repository validator separately proved that the public canonical and sitemap route resolve to `docs/meal-scan.html` under the site's extensionless mapping.

Browser checks:

- Desktop override: 1440×900; rendered client viewport 1425×900.
- Mobile override: 390×844; rendered client viewport 375×844.
- Page title: `Meal Scan Preview — CycleBalance`.
- Meaningful DOM present; no framework/error overlay.
- Console warnings/errors: none.
- Horizontal overflow: none at either viewport.
- Mobile layout: primary inline links hidden, hero and step grids collapsed to one column, CTA controls remained readable and untangled.
- Interaction: the unique Primary navigation `Privacy` link moved to `#privacy`; `Privacy, in plain language.` rendered at the top of the viewport.
- Semantic audit: one `h1`, one `main`, labeled Primary and Footer navigation, zero images missing `alt`, zero unnamed links, zero duplicate IDs, and zero broken hash targets.
- Canonical observed in the DOM: `https://cyclebalance.app/meal-scan`.

## Source and claims self-review

- All three approved positioning lines are present verbatim.
- The page shows Photo → explicit Google Gemini Consent → editable draft/Correct → local Save → optional Context.
- Google retention up to 55 days for abuse monitoring, proxy raw-byte non-retention, on-device exact reviewed-meal reuse, and manual/barcode alternatives are stated plainly.
- App Store CTAs are explicitly for the current app; scanner availability is repeatedly marked staged/coming after release verification.
- A page-only forbidden-claim search returned no matches for diagnosis, treatment, causal insight, exact nutrition, Zero Data Retention, guaranteed accuracy, `cycle-aware nutrition`, or either meal-balance-score spelling.
- Synthetic UI/meal details are labeled `Demonstration using synthetic meal details — not a testimonial or accuracy result.`
- The social handoff includes the exact 15-second Photo → Consent → Correct → Save sequence and all four approved organic concepts.
- The launch handoff keeps the exact paid/trial quotas and marks exact cache, barcode, and manual paths non-billable.
- Privacy Policy and Terms are correctly `Verify/reconcile`, not treated as missing; Support FAQ is `Expand`; homepage FAQ and App Store description are `Confirmed contradiction`.
- Campaign Link/Custom Product Page instructions route to `symptoms-food-glucose` first and keep the optional scanner page gated; no results or platform-algorithm claims were invented.
- Staged implementation changed only the eight implementation files listed above. It did not edit `docs/index.html`, `docs/privacy.html`, `docs/terms.html`, `docs/support.html`, the user-owned hero-video worktree, or any live external surface.

## Exact publication blockers

Do not publish, deploy, update App Store metadata, or distribute campaign assets until all of the following are true:

1. Scanner release verification is complete against the production provider path and matching signed distribution build.
2. Final consent, provider retention, proxy handling, local cache/reuse, quota, billing/access, error, and fallback behavior match the approved copy.
3. RevenueCat/App Store paid, trial, restore, expiry, and offline/error states are verified for the release.
4. Final screenshots and demo captures come from the approved archived build and pass the synthetic-fixture/privacy preflight.
5. Privacy Policy and Terms are reconciled against final behavior; Support FAQ is expanded; App Privacy and review notes are synchronized.
6. The homepage FAQ no longer makes an unqualified on-device-only claim that hides the opt-in fresh-photo provider path.
7. The App Store description no longer says `No accounts required, no cloud uploads, no ads.` without qualifying the fresh-photo provider path.
8. Product, Privacy/Policy, Support, App Store release, Web, and Marketing owners approve the same fact block and availability language.
9. The public scanner build is reachable before `/meal-scan`, App Store copy, Campaign Links, Custom Product Pages, or social assets imply availability.
10. The Apple Campaign Link is created and verified against `symptoms-food-glucose`; any optional scanner page has approved archived-build assets and metadata.

## Concerns

- Five pre-existing external evidence references block automated verification with HTTP 403/412 and remain manual-review items; no Task 4 link failed.
- Extensionless routing depends on the production static-host convention; Python's basic local server was therefore used only at `/meal-scan.html`, while the repository link mapper validated `/meal-scan`.
- Independent subagent review was attempted but unavailable because all agent slots were occupied by higher-priority release tasks. Fresh source, claims, rendered-browser, accessibility, link, XML, syntax, and diff self-review were completed instead.
- Publication remains intentionally blocked by the ten gates above. No live action was taken.
