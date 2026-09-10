#!/usr/bin/env bash
# Renders one passage under every Core ML compute-unit policy (cpu, cpu+ane, cpu+gpu, all) on this
# Mac and writes the load and render times to spikes/findings/compute-probe/report.md — the
# mechanism behind the app's `kokoro.computeUnits` switch, checked here before it is measured on a
# phone (docs/superpowers/specs/2026-09-08-performance-audit.md §3.7). Needs the Core ML files
# (scripts/fetch-kokoro-coreml.sh --app). Takes several minutes; the per-stage split of every call
# is in the unified log under subsystem com.t2s.reader, category kokoro.timing.
# Usage: scripts/compute-probe.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p spikes/findings/compute-probe
cd Packages/T2SKokoro
e5_bundle_cache="$HOME/Library/Caches/com.apple.dt.xctest.tool/com.apple.e5rt.e5bundlecache"
set +e
xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:T2SKokoroTests/KokoroComputeProbe \
  -derivedDataPath .build/DerivedData "$@" 2>&1 \
  | grep -E "error:|kokoro compute probe|Executed|TEST (SUCCEEDED|FAILED)"
status="${PIPESTATUS[0]}"
rm -rf "$e5_bundle_cache"
echo "report: spikes/findings/compute-probe/report.md"
exit "$status"
