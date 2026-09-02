#!/usr/bin/env bash
# Runs the iOS-only Packages/T2SReadium tests on an iPhone simulator.
# Usage: scripts/test-readium.sh [extra xcodebuild args]
# Env:   SIMULATOR_ID=<udid> to pick a simulator; otherwise the first available iPhone is used.
set -euo pipefail
cd "$(dirname "$0")/../Packages/T2SReadium"

if [[ -z "${SIMULATOR_ID:-}" ]]; then
  SIMULATOR_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
devs = [d for r in sorted(runtimes) for d in runtimes[r] if d.get("isAvailable") and "iPhone" in d["name"]]
print(devs[-1]["udid"] if devs else "")')
  if [[ -z "$SIMULATOR_ID" ]]; then
    echo "no available iPhone simulator; install one in Xcode > Settings > Components" >&2
    exit 1
  fi
fi

echo "simulator: $SIMULATOR_ID"
set +e
xcodebuild test -scheme T2SReadium -destination "id=$SIMULATOR_ID" \
  -derivedDataPath .build/DerivedData "$@" 2>&1 \
  | grep -E "error:|warning:|Suite |Test run|Executed|TEST (SUCCEEDED|FAILED)|Testing failed" \
  | grep -Ev "/checkouts/.*: warning:"
exit "${PIPESTATUS[0]}"
