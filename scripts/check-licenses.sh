#!/usr/bin/env bash
# scripts/check-licenses.sh — fails if any checked-out SPM dependency is copyleft.
# Scope: SPM checkouts of the root package and every package under Packages/; a binaryTarget or
# vendored source must be audited by hand (docs/licenses.md).
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob
status=0

check_package() {
  local pkg=$1
  echo "== $pkg"
  (cd "$pkg" && swift package resolve >/dev/null)
  for dir in "$pkg"/.build/checkouts/*/; do
    local name; name=$(basename "$dir")
    # Glob into an array: with nullglob an unmatched pattern yields an empty array.
    local files=( "$dir"LICENSE* "$dir"COPYING* )
    if [[ ${#files[@]} -eq 0 ]]; then
      echo "NO LICENSE FILE: $name"; status=1; continue
    fi
    if grep -qiE 'GNU (AFFERO |LESSER )?GENERAL PUBLIC LICENSE' "${files[0]}"; then
      echo "COPYLEFT: $name (${files[0]})"; status=1
    else
      echo "ok: $name"
    fi
  done
}

check_package .
for pkg in Packages/*/; do
  check_package "${pkg%/}"
done
exit $status
