#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_CANONICAL_DIR="$ROOT_DIR/CycleBalance"
APP_ACTIVE_DIR="$ROOT_DIR/PCOS/PCOS"
TEST_CANONICAL_DIR="$ROOT_DIR/CycleBalanceTests"
TEST_ACTIVE_DIR="$ROOT_DIR/PCOS/PCOSTests"
STALE_NESTED_PROJECT="$ROOT_DIR/PCOS/PCOS.xcodeproj"

if [[ -d "$STALE_NESTED_PROJECT" ]]; then
  echo "Stale nested project detected at: $STALE_NESTED_PROJECT"
  echo "Use only the root project: $ROOT_DIR/PCOS.xcodeproj"
  echo "Remove the nested project to avoid plist/build-setting drift."
  exit 1
fi

for required_dir in "$APP_CANONICAL_DIR" "$APP_ACTIVE_DIR" "$TEST_CANONICAL_DIR" "$TEST_ACTIVE_DIR"; do
  if [[ ! -d "$required_dir" ]]; then
    echo "Missing required directory: $required_dir"
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

list_swift_files() {
  local base_dir="$1"
  find "$base_dir" -type f -name '*.swift' | sed "s#^${base_dir}/##" | LC_ALL=C sort
}

normalize_test_imports() {
  local file_path="$1"
  sed -E 's/@testable import (PCOS|CycleBalance)/@testable import APP_TARGET/' "$file_path"
}

status=0

list_swift_files "$APP_CANONICAL_DIR" > "$TMP_DIR/app_canonical_manifest.txt"
list_swift_files "$APP_ACTIVE_DIR" > "$TMP_DIR/app_active_manifest.txt"

comm -23 "$TMP_DIR/app_canonical_manifest.txt" "$TMP_DIR/app_active_manifest.txt" > "$TMP_DIR/app_only_in_canonical.txt"
comm -13 "$TMP_DIR/app_canonical_manifest.txt" "$TMP_DIR/app_active_manifest.txt" > "$TMP_DIR/app_only_in_active.txt"
comm -12 "$TMP_DIR/app_canonical_manifest.txt" "$TMP_DIR/app_active_manifest.txt" > "$TMP_DIR/app_common_manifest.txt"

if [[ -s "$TMP_DIR/app_only_in_canonical.txt" || -s "$TMP_DIR/app_only_in_active.txt" ]]; then
  status=1
  echo "App source manifest drift detected:"
  if [[ -s "$TMP_DIR/app_only_in_canonical.txt" ]]; then
    echo "- Only in CycleBalance/:"
    sed 's/^/  - /' "$TMP_DIR/app_only_in_canonical.txt"
  fi
  if [[ -s "$TMP_DIR/app_only_in_active.txt" ]]; then
    echo "- Only in PCOS/PCOS/:"
    sed 's/^/  - /' "$TMP_DIR/app_only_in_active.txt"
  fi
fi

: > "$TMP_DIR/app_content_drift.txt"
while IFS= read -r rel_path; do
  if ! cmp -s "$APP_CANONICAL_DIR/$rel_path" "$APP_ACTIVE_DIR/$rel_path"; then
    echo "$rel_path" >> "$TMP_DIR/app_content_drift.txt"
  fi
done < "$TMP_DIR/app_common_manifest.txt"

if [[ -s "$TMP_DIR/app_content_drift.txt" ]]; then
  status=1
  echo "App source content drift detected:"
  sed 's/^/  - /' "$TMP_DIR/app_content_drift.txt"
fi

list_swift_files "$TEST_CANONICAL_DIR" > "$TMP_DIR/test_canonical_manifest.txt"
list_swift_files "$TEST_ACTIVE_DIR" > "$TMP_DIR/test_active_manifest.txt"

comm -23 "$TMP_DIR/test_canonical_manifest.txt" "$TMP_DIR/test_active_manifest.txt" > "$TMP_DIR/test_only_in_canonical.txt"
comm -13 "$TMP_DIR/test_canonical_manifest.txt" "$TMP_DIR/test_active_manifest.txt" > "$TMP_DIR/test_only_in_active.txt"
comm -12 "$TMP_DIR/test_canonical_manifest.txt" "$TMP_DIR/test_active_manifest.txt" > "$TMP_DIR/test_common_manifest.txt"

if [[ -s "$TMP_DIR/test_only_in_canonical.txt" || -s "$TMP_DIR/test_only_in_active.txt" ]]; then
  status=1
  echo "Test source manifest drift detected:"
  if [[ -s "$TMP_DIR/test_only_in_canonical.txt" ]]; then
    echo "- Only in CycleBalanceTests/:"
    sed 's/^/  - /' "$TMP_DIR/test_only_in_canonical.txt"
  fi
  if [[ -s "$TMP_DIR/test_only_in_active.txt" ]]; then
    echo "- Only in PCOS/PCOSTests/:"
    sed 's/^/  - /' "$TMP_DIR/test_only_in_active.txt"
  fi
fi

: > "$TMP_DIR/test_content_drift.txt"
while IFS= read -r rel_path; do
  canonical_tmp="$TMP_DIR/canonical_test.swift"
  active_tmp="$TMP_DIR/active_test.swift"
  normalize_test_imports "$TEST_CANONICAL_DIR/$rel_path" > "$canonical_tmp"
  normalize_test_imports "$TEST_ACTIVE_DIR/$rel_path" > "$active_tmp"

  if ! cmp -s "$canonical_tmp" "$active_tmp"; then
    echo "$rel_path" >> "$TMP_DIR/test_content_drift.txt"
  fi
done < "$TMP_DIR/test_common_manifest.txt"

if [[ -s "$TMP_DIR/test_content_drift.txt" ]]; then
  status=1
  echo "Test source content drift detected (excluding @testable import target name):"
  sed 's/^/  - /' "$TMP_DIR/test_content_drift.txt"
fi

if [[ "$status" -ne 0 ]]; then
  echo "Tree parity check failed."
  exit 1
fi

app_count=$(wc -l < "$TMP_DIR/app_canonical_manifest.txt" | tr -d '[:space:]')
test_count=$(wc -l < "$TMP_DIR/test_canonical_manifest.txt" | tr -d '[:space:]')

echo "Tree parity check passed."
echo "- App Swift files: $app_count"
echo "- Test Swift files: $test_count"
