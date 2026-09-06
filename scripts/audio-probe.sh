#!/usr/bin/env bash
# Renders one passage through the Core ML Kokoro engine several ways (and through the MLX engine as
# the control, when the Plan 0 spike weights are present) and writes the WAVs plus a metrics table
# to spikes/findings/audio-probe/ — for a human to listen to. The probe is a test in
# Packages/T2SKokoro that is enabled only while that directory exists, so it never runs as part of
# scripts/test-kokoro.sh. Needs scripts/fetch-kokoro-coreml.sh --app to have staged the Core ML
# files. Takes several minutes: each engine variant compiles the eight stages into $TMPDIR.
# Usage: scripts/audio-probe.sh
set -euo pipefail
cd "$(dirname "$0")/.."
out=spikes/findings/audio-probe
mkdir -p "$out"
# Core ML's own runtime cache (distinct from the $TMPDIR compile output below): it caches ~0.9 GB
# of compiled graphs per fresh model path under a test bundle and never reclaims it on its own —
# it filled the disk three times on 2026-09-05. Swept both before and after, so neither this run's
# own accumulation nor an earlier run's leftovers can starve the run that follows.
e5_bundle_cache="$HOME/Library/Caches/com.apple.dt.xctest.tool/com.apple.e5rt.e5bundlecache"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"

set +e
( cd Packages/T2SKokoro && xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' \
  -parallel-testing-enabled NO -derivedDataPath .build/DerivedData \
  -only-testing:T2SKokoroTests/KokoroAudioProbe 2>&1 ) \
  | tee "$out/xcodebuild.log" \
  | grep -E "error:|Test run|Executed|TEST (SUCCEEDED|FAILED)|Testing failed|^- |^Whole|^Per |^Piece|^Segmenter|^  - |MLX control" \
  | grep -Ev "/checkouts/.*: warning:"
status="${PIPESTATUS[0]}"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"
echo "Output: $out"
ls -la "$out"
exit "$status"
