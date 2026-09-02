#!/usr/bin/env bash
# scripts/check-licenses.sh — fails if any checked-out SPM dependency is copyleft.
set -euo pipefail
cd "$(dirname "$0")/.."
swift package resolve >/dev/null
shopt -s nullglob
status=0
for dir in .build/checkouts/*/; do
  name=$(basename "$dir")
  file=$(ls "$dir"LICENSE* "$dir"COPYING* 2>/dev/null | head -n1 || true)
  if [[ -z "$file" ]]; then
    echo "NO LICENSE FILE: $name"; status=1; continue
  fi
  if grep -qiE 'GNU (AFFERO |LESSER )?GENERAL PUBLIC LICENSE' "$file"; then
    echo "COPYLEFT: $name ($file)"; status=1
  else
    echo "ok: $name"
  fi
done
exit $status
