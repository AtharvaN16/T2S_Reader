#!/usr/bin/env bash
# scripts/check-licenses.sh — fails if any checked-out SPM dependency is copyleft.
# Scope: SPM checkouts only; a binaryTarget or vendored source must be audited by hand (docs/licenses.md).
set -euo pipefail
cd "$(dirname "$0")/.."
swift package resolve >/dev/null
shopt -s nullglob
status=0
for dir in .build/checkouts/*/; do
  name=$(basename "$dir")
  # Glob into an array: with nullglob an unmatched pattern yields an empty array.
  # (A bare `ls` with no arguments would list the cwd and mask a missing file.)
  files=( "$dir"LICENSE* "$dir"COPYING* )
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "NO LICENSE FILE: $name"; status=1; continue
  fi
  file=${files[0]}
  if grep -qiE 'GNU (AFFERO |LESSER )?GENERAL PUBLIC LICENSE' "$file"; then
    echo "COPYLEFT: $name ($file)"; status=1
  else
    echo "ok: $name"
  fi
done
exit $status
