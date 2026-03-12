# Branch Reconciliation Report

Date: 2026-03-12
Working branch: `codex/dirty-tree-reconcile-20260312`
Canonical app lineage base: `claude/cyclebalance-ios-app-V9Pz9` (local base; old remote upstream is gone)

## Ahead/Behind Matrix (vs current HEAD)

`HEAD-only` = commits in current branch not in target branch.
`Branch-only` = commits in target branch not in current branch.

| Branch | HEAD-only | Branch-only | Status |
|---|---:|---:|---|
| `origin/main` | 0 | 10 | Diverged to docs-site history |
| `origin/claude/cleanup-github-pages-uxZPG` | 0 | 6 | Docs-site cleanup stream |
| `origin/claude/design-app-ux-ui-ivOdh` | 1 | 0 | Subsumed (feature commit already merged) |
| `origin/claude/design-app-ux-ui-nfLxl` | 10 | 0 | Subsumed |
| `origin/claude/parallel-task-agents-Mz4jG` | 3 | 0 | Subsumed |
| `origin/claude/review-and-plan-ux-lsimB` | 20 | 0 | Subsumed |

## Unique Commit Summaries and Recommendations

### `origin/main`
Branch-only commits include a pivot from iOS app source to GitHub Pages (`docs/index.html`, `docs/CNAME`) and large-scale app-source deletion.

- Representative commits:
  - `1abfcee` Remove iOS app source, keep only GitHub Pages files
  - `72c09fe` Move `index.html` and `CNAME` into `/docs`
  - `ee579cc` Switch form backend from Formspree to FormSubmit.co
- Recommendation: **Exclude from app merge path**.
- Rationale: conflicts with app branch intent (would delete/replace app codebase).

### `origin/claude/cleanup-github-pages-uxZPG`
Branch-only commits are the docs-site cleanup chain that feeds `origin/main`.

- Representative commits:
  - `1abfcee` Remove iOS app source, keep only GitHub Pages files
  - `72c09fe` Move website files to `/docs`
  - `ee579cc` Form backend switch in website page
- Recommendation: **Exclude from app merge path**.
- Rationale: same website-only pivot and app-code deletion pattern.

### `origin/claude/design-app-ux-ui-ivOdh`
No branch-only commits versus current HEAD.

- Recommendation: **No action (already subsumed)**.
- Rationale: feature content is already merged into current lineage.

### `origin/claude/design-app-ux-ui-nfLxl`
No branch-only commits versus current HEAD.

- Recommendation: **No action (already subsumed)**.
- Rationale: current lineage already includes this branch’s feature/fix chain.

### `origin/claude/parallel-task-agents-Mz4jG`
No branch-only commits versus current HEAD.

- Recommendation: **No action (already subsumed)**.
- Rationale: manual test plan/doc commit already merged in current lineage.

### `origin/claude/review-and-plan-ux-lsimB`
No branch-only commits versus current HEAD.

- Recommendation: **No action (already subsumed)**.
- Rationale: review/refactor commits are already integrated in current lineage.

## Cleanup Policy Decision Log

- Canonical code line remains app-first branch history (`claude/cyclebalance-ios-app-V9Pz9` lineage).
- Docs-site branches are intentionally excluded from app merge decisions.
- Dirty tree cleanup proceeds as staged triage (keep bucket, discard bucket, parity-guarded).
