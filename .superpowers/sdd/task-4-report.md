# Task 4 — Non-Public Meal-Scan Marketing Correction Report

Date: 2026-07-14

Branch: `codex/cyclebalance-meal-scan-marketing`

Worktree: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/.worktrees/cyclebalance-meal-scan-marketing`

Original feature commit: `d39a8b467fa7d70ebacc5f20106062fae4783ce6`

Original report commit: `e1ab9242e1c2bd9150bcbbc198748a5a699bc5ed`

Non-public move commit: `191a36ee8dc2e4abd73d689f5d0a3a4d4691885e`

Review-fix implementation commit: `cbc1feeec33b7ccddbf0a4a05da37ec99012a8c3`

## Status and reviewer disposition

All Critical and Important independent-review findings are fixed in the isolated worktree. The corrected materials are ready for local staging/merge review. They are **not ready for publication** because the scanner release, synchronized owner approvals, real Apple Campaign Link inputs, Approved/publicly-visible destination evidence, and signed-out target-storefront verification remain publication-time gates.

Nothing was pushed, published, deployed, sent, posted, or changed in App Store Connect.

| Review finding | Disposition | Evidence |
|---|---|---|
| Critical: preview was inside deployed GitHub Pages `docs` | Fixed | Preview moved to `.superpowers/sdd/staging/meal-scan-preview.html`; `docs/meal-scan.html` is absent; sitemap and `llms.txt` do not advertise `/meal-scan`. |
| Critical: text, button, boundary, and focus contrast failed AA | Fixed | Deterministic validator computes contrast from CSS tokens and enforces 4.5:1 for text plus 3:1 for interface/focus indicators. |
| Important: declining copy incorrectly grouped barcode with local alternatives | Fixed | Copy now says declining skips the photo estimate; manual/exact reuse can stay on-device; barcode lookup is a separate optional network request that does not send the meal photo. |
| Important: Campaign Link handoff/validator was underspecified | Fixed as an executable publication gate | Validator requires numeric `pt`, stable approved `ct`, matching approved `ppid`, Approved/public visibility evidence, and signed-out storefront evidence when publication arguments are supplied. Real values/evidence remain owner inputs. |
| Important: validation date and forbidden-claim checks were brittle | Fixed | Report date is generated dynamically in America/Chicago; claims are normalized across case, whitespace, and dash variants before pattern matching. Final negative fixtures explicitly cover `diagnosing`, `diagnosed`, `guaranteed accurate`, and `100% accurate`. |

## Final green-review minor hardening

The final re-review found no Critical or Important issues and marked non-public staging ready. Both remaining Minor findings were closed without changing the publication posture:

1. `findForbiddenClaims()` now drives both the page check and four deterministic negative fixtures. The diagnosis pattern includes `diagnosing` and `diagnosed`; accuracy patterns reject both `guaranteed accuracy`/`guaranteed accurate` and `100% accurate`.
2. A supplied Campaign Link must have an exact pathname segment `id6760353511`. Host, `pt`, approved `ct`, approved `ppid`, Approved/publicly-visible evidence, and manual signed-out target-storefront evidence requirements remain in force.

RED evidence:

```text
Wrong-app fixture before the app-ID check:
Validation PASS: 0 errors, 0 warnings
RED: wrong App Store app ID was accepted

Claim negative fixtures before the expanded patterns:
Validation FAIL: 3 errors, 0 warnings
- Forbidden-claim negative fixture "diagnosing variant" was not rejected as diagnosis
- Forbidden-claim negative fixture "guaranteed accurate variant" was not rejected as guaranteed accuracy
- Forbidden-claim negative fixture "100% accurate variant" was not rejected as 100% accurate

Handoff contract before the matching documentation update:
Validation FAIL: 1 errors, 0 warnings
- Launch-delta handoff: missing required text: Campaign Link pathname must target CycleBalance app ID `6760353511`.
```

Focused GREEN evidence:

```text
Claim negative fixtures and base contract:
Validation PASS: 0 errors, 0 warnings

Wrong-app fixture after the app-ID check:
Validation FAIL: 1 errors, 0 warnings
- Campaign Link: pathname must target CycleBalance app ID 6760353511

Correct app-path fixture without manual storefront evidence:
Validation FAIL: 1 errors, 0 warnings
- Campaign Link: --signed-out-storefront-verified evidence flag is required

Correct CycleBalance app-path fixture with all manual evidence flags:
Validation PASS: 0 errors, 0 warnings
```

All Campaign Link fixtures used synthetic local-only query values. No provider token, final CPP ID, approval state, or storefront result was invented or recorded as a real launch input.

## Corrected files

- `.superpowers/sdd/staging/meal-scan-preview.html` — non-public responsive preview with corrected AA tokens, two-color focus indicator, and truthful alternative-path wording.
- `tools/validate-site.mjs` — merge-safety, discovery, claims plus negative fixtures, contrast, current-date, page/handoff, and app-ID-bound Campaign Link publication checks.
- `docs/sitemap.xml` — removed the premature `/meal-scan` URL.
- `docs/llms.txt` — removed the premature meal-scan discovery line.
- `docs/VALIDATION-REPORT.md` — fresh July 14 full-site/external-reference result.
- `.superpowers/sdd/task-4-launch-delta-handoff.md` — non-public publication boundary, corrected local/network wording, owner-supplied Apple link contract, and required CycleBalance app-ID pathname.
- `.superpowers/sdd/task-4-social-demo-handoff.md` — corrected decline/manual/exact-reuse/network-barcode production note.
- `.superpowers/sdd/task-4-plan.md` — correction-first execution plan and separate future-publication boundary.
- `.superpowers/sdd/task-4-report.md` — this review disposition and evidence record.

## RED/GREEN evidence

### Independent-review RED

After encoding all review findings before correcting the artifacts:

```text
Validation FAIL: 34 errors, 0 warnings
```

The failures covered the deployed page/discovery, absent non-public preview, old decline wording, low-contrast tokens and focus styles, stale date evidence, and missing Campaign Link contract.

### Merge-safety intermediate RED

After moving the file outside `docs`, removing deployed discovery, and making the report date dynamic:

```text
Validation FAIL: 29 errors, 0 warnings
```

The merge-safety/discovery/date failures were gone; accessibility, wording, and handoff contract failures remained.

### Accessibility and wording intermediate RED

After correcting the AA tokens, two-color focus indicator, and local-versus-network wording:

```text
Validation FAIL: 10 errors, 0 warnings
```

Only the Campaign Link handoff contract assertions remained.

### Campaign Link negative fixture

The optional publication validator was exercised with a synthetic malformed link, mismatched approved values, and no evidence flags. The synthetic values were used only in the shell test and are not stored as launch defaults or owner inputs.

```text
Validation FAIL: 6 errors, 0 warnings
- Campaign Link: --cpp-approved-visible evidence flag is required
- Campaign Link: --signed-out-storefront-verified evidence flag is required
- Campaign Link: URL must contain exactly one non-empty ct parameter
- Campaign Link: pt must contain ASCII digits only
- Campaign Link: ct does not match --approved-ct
- Campaign Link: ppid does not match --approved-ppid
```

### Campaign Link positive fixture

The same validator passed with a synthetic HTTPS Apple URL containing one numeric `pt`, one stable `ct` matching `--approved-ct`, one `ppid` matching `--approved-ppid`, and both evidence flags:

```text
Validation PASS: 0 errors, 0 warnings
```

This proves the deterministic contract only. It does **not** claim that a real Campaign Link, provider token, final CPP ID, approval state, or storefront route has been verified.

### Repository GREEN

```text
node tools/validate-site.mjs
Validation PASS: 0 errors, 0 warnings

node tools/validate-site.mjs --external
Validation PASS: 0 errors, 5 warnings
```

## WCAG contrast evidence

The validator calculates these ratios from the staged page's required six-digit CSS tokens. Text thresholds are 4.5:1; essential boundary/focus thresholds are 3:1.

| Pair | Ratio | Threshold | Result |
|---|---:|---:|---|
| White primary-button text / coral | 6.41:1 | 4.5:1 | PASS |
| Coral-dark accent text / cream | 7.73:1 | 4.5:1 | PASS |
| Muted text / paper | 6.24:1 | 4.5:1 | PASS |
| Small muted text / paper | 5.49:1 | 4.5:1 | PASS |
| Edit-chip text / coral-pale | 4.97:1 | 4.5:1 | PASS |
| Interface line / paper | 3.55:1 | 3:1 | PASS |
| Outer focus indicator / cream | 8.69:1 | 3:1 | PASS |
| Inner focus indicator / dark surface | 11.69:1 | 3:1 | PASS |
| Dark-surface boundary / dark surface | 3.17:1 | 3:1 | PASS |

The executable contract also covers the token pairs used on cream, paper, white, sage-pale, and dark footer/principle surfaces, rather than relying only on this representative table.

## Rendered browser QA

The flow under test was: non-public preview loads → meaningful responsive page renders → scoped Primary-navigation `Privacy` link is selected → the intended privacy section becomes the current anchor and visible target.

Environment:

- Local route: `http://127.0.0.1:4173/meal-scan-preview.html`, served from the staging file with assets mapped read-only from `docs`.
- Browser path: Browser plugin available; selected Chrome through the supported browser runtime; no fallback used.
- Desktop viewport override: 1440×900.
- Mobile viewport override: 390×844.

Checks:

| Check | Desktop | Mobile |
|---|---|---|
| URL/title identity | PASS | PASS |
| Meaningful DOM / not blank | PASS | PASS |
| Framework/error overlay | None | None |
| Console warnings/errors | None | None |
| Failed rendered images | 0 | 0 |
| Horizontal overflow | None | None |
| Responsive layout | Full navigation and multi-column composition | Inline nav hidden; hero and process grids collapse to one column; CTAs remain untangled |
| Screenshot evidence | Hero and privacy-anchor states visually inspected | Hero/mobile-first viewport visually inspected |

Interaction result:

- The Primary-navigation `Privacy` locator resolved to exactly one link before the click.
- After selection, the URL hash was `#privacy`.
- `Privacy, in plain language.` was the target heading and rendered 147 px from the viewport top.

Semantic/accessibility audit:

- one `h1`, one `main`, one labeled Primary navigation, and one labeled Footer navigation;
- zero images missing `alt`, zero failed images, zero unnamed links, zero duplicate IDs, and zero broken hash targets;
- canonical observed as `https://cyclebalance.app/meal-scan` for the future publication route;
- desktop/mobile screenshots showed readable corrected color usage, unclipped content, and no visible overlap.

## Full validation

Fresh correction gate:

```sh
node --check tools/validate-site.mjs
node tools/validate-site.mjs
node tools/validate-site.mjs --external
xmllint --noout docs/sitemap.xml
git diff --check
test ! -e docs/meal-scan.html
! rg -n 'https://cyclebalance\.app/meal-scan' docs/sitemap.xml docs/llms.txt
! rg -ni 'diagnos(is|e|ed|es|ing|tic)|treat(ment|s|ed|ing)?|causal[[:space:]]+(insight|conclusion)|exact[[:space:]]+nutrition(al)?|zero[[:space:]]+data[[:space:]]+retention|guaranteed[[:space:]]+accur(acy|ate)|100[[:space:]]*%[[:space:]]+accurate|cycle-aware[[:space:]]+nutrition|meal-?balance[[:space:]]+score' .superpowers/sdd/staging/meal-scan-preview.html
curl --silent --show-error --location --output /dev/null --max-time 20 \
  --write-out 'App Store CTA: HTTP %{http_code} -> %{url_effective}\n' \
  'https://apps.apple.com/us/app/cyclebalance/id6760353511'
```

Results:

- JavaScript syntax: PASS.
- Base site/content contract: PASS, `0 errors`, `0 warnings`.
- External-reference validation: PASS, `0 errors`, `5 warnings`.
- Sitemap XML: PASS.
- Git whitespace check: PASS.
- Merge safety: PASS; `docs/meal-scan.html` is absent.
- Deployed discovery safety: PASS; `/meal-scan` is absent from sitemap and `llms.txt`.
- Normalized forbidden-claim search and four built-in negative fixtures: PASS; no page matches and all fixtures were rejected.
- App Store CTA: HTTP `200` at `https://apps.apple.com/us/app/cyclebalance/id6760353511`.
- Current validation-report date: `2026-07-14` in America/Chicago.
- Site counts: 174 HTML files, 173 sitemap URLs, 5,895 internal references, 1,344 hreflang links, 486 JSON-LD blocks, 1,146 image references, and 14 external evidence references.

The five warnings are pre-existing automated-access responses from evidence sources: four HTTP 403 responses and one HTTP 412 response. They are preserved in `docs/VALIDATION-REPORT.md`; no reference returned 404/410 and no Task 4 link failed.

## Publication contract and blockers

The preview remains intentionally non-public. A separate publication commit may move it to `docs/meal-scan.html` and add sitemap/LLM discovery only after all of the following are true:

1. Scanner release verification passes against the production provider path and matching signed distribution build.
2. Final consent, Google retention, proxy handling, local cache/reuse, quotas, billing/access, error states, and fallback behavior match the synchronized copy.
3. RevenueCat/App Store paid, trial, restore, expiry, and offline/error states are verified.
4. Final screenshots/demo captures come from the approved archived build and pass privacy/synthetic-fixture preflight.
5. Privacy Policy and Terms are reconciled, Support FAQ is expanded, and App Privacy/review notes match the same release.
6. The homepage FAQ and App Store description contradictions are removed or correctly qualified.
7. Product, Privacy/Policy, Support, App Store release, Web, and Marketing owners approve one fact block and availability posture.
8. `symptoms-food-glucose` is confirmed Approved and publicly visible in the target storefront with dated evidence.
9. The authorized owner supplies the real numeric Apple provider token (`pt`) and final approved destination ID (`ppid`); Marketing/App Store owners approve one stable campaign token (`ct`). No invented source defaults are allowed.
10. The final Apple-generated link pathname targets app ID `6760353511`, passes `--campaign-link`, `--approved-ct`, `--approved-ppid`, `--cpp-approved-visible`, and `--signed-out-storefront-verified`, and a signed-out device lands on the intended CPP in the target storefront.
11. The public scanner build is reachable before website, store, Campaign Link, CPP, or social copy implies availability.

## Remaining concerns

- Real App Store Connect CPP approval/visibility, real owner-supplied link values, and signed-out target-storefront routing were not verified in this local correction. They remain explicit publication blockers, not implied passes.
- The five pre-existing external evidence URLs that returned 403/412 still require manual review.
- The staged file preserves future canonical/social metadata, but it is outside the deployed tree and undiscoverable. Publication must happen as a separate reviewed commit that adds the deployed file and discovery together.
- No live action was taken.
