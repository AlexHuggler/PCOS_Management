#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_PROJECT="$ROOT_DIR/PCOS.xcodeproj"
STALE_NESTED_PROJECT="$ROOT_DIR/PCOS/PCOS.xcodeproj"
PARITY_SCRIPT="$ROOT_DIR/scripts/check_tree_parity.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/open_pcos_xcode.sh [--no-open]

Regenerates the canonical root project, removes stale nested project drift,
verifies source-tree parity, and opens the root Xcode project.

Options:
  --no-open   Skip opening Xcode (useful for CI/scripting checks)
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" != "" && "${1:-}" != "--no-open" ]]; then
  usage
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install with: brew install xcodegen"
  exit 1
fi

cd "$ROOT_DIR"

echo "Generating root project from project.yml..."
xcodegen generate

if [[ -d "$STALE_NESTED_PROJECT" ]]; then
  echo "Removing stale nested project: $STALE_NESTED_PROJECT"
  rm -r "$STALE_NESTED_PROJECT"
fi

echo "Running tree parity check..."
"$PARITY_SCRIPT"

if [[ "${1:-}" == "--no-open" ]]; then
  echo "Setup complete. Skipped opening Xcode."
  exit 0
fi

echo "Opening root project: $ROOT_PROJECT"
open "$ROOT_PROJECT"

