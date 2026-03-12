# Branch Reconciliation Report

Date: 2026-03-12
Working branch: `codex/dirty-tree-reconcile-20260312`
Historical app lineage base: `claude/cyclebalance-ios-app-V9Pz9` (local stale branch pruned)

## Current Branch Matrix (vs current HEAD)

`HEAD-only` = commits in current branch not in target branch.
`Branch-only` = commits in target branch not in current branch.

| Branch | HEAD-only | Branch-only | Status | Recommendation |
|---|---:|---:|---|---|
| `origin/codex/dirty-tree-reconcile-20260312` | 0 | 0 | In sync | Keep |
| `origin/main` | 4 | 10 | Docs-site history diverges from app lineage | Keep for repository default/history; exclude from app merge path |
| `origin/claude/cleanup-github-pages-uxZPG` | 4 | 6 | Docs-site cleanup branch | Keep as historical record; exclude from app merge path |

## Pruned Branches (Completed)

Pruned on 2026-03-12 after confirming no app-lineage dependency.

| Branch | Scope | Reason |
|---|---|---|
| `claude/cyclebalance-ios-app-V9Pz9` | Local | Stale local fallback branch; replaced by codex reconciliation branch |
| `origin/claude/design-app-ux-ui-ivOdh` | Remote | Fully subsumed by app lineage |
| `origin/claude/design-app-ux-ui-nfLxl` | Remote | Fully subsumed by app lineage |
| `origin/claude/parallel-task-agents-Mz4jG` | Remote | Fully subsumed by app lineage |
| `origin/claude/review-and-plan-ux-lsimB` | Remote | Fully subsumed by app lineage |

## Docs-Site Branch Rationale (Retained, Not Merged)

- `origin/main` and `origin/claude/cleanup-github-pages-uxZPG` include website-oriented commits (for `docs/` and related page flow) and are intentionally excluded from app code merge decisions.
- App development continues on `origin/codex/dirty-tree-reconcile-20260312`.

## Cleanup Policy Decision Log

- Tree state is clean for further app development.
- Canonical active development line is the `codex/dirty-tree-reconcile-20260312` branch.
- Dual-tree parity policy remains enforced via `./scripts/check_tree_parity.sh`.
