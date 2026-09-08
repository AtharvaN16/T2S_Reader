#!/usr/bin/env bash
# Renders a few passages through the Core ML Kokoro engine with the app's options and writes WAVs plus
# report.md to spikes/findings/audio-probe/quality/: every impulse placed on the token that owns it, the
# seams between pipeline calls, the tails of every call with and without the tail-click removal, what
# hyphens become, and the AAC join between consecutive utterances. For a human to listen to and to
# check the numbers in spikes/findings/2026-09-08-ticks-and-hyphens.md. The probe is a test in
# Packages/T2SKokoro that is enabled only while that directory exists, so it never runs as part of
# scripts/test-kokoro.sh. Needs scripts/fetch-kokoro-coreml.sh --app. Takes several minutes.
# Usage: scripts/quality-probe.sh
set -euo pipefail
cd "$(dirname "$0")/.."
out=spikes/findings/audio-probe/quality
mkdir -p "$out"
# Core ML's runtime cache: see scripts/audio-probe.sh for why it is swept before and after.
e5_bundle_cache="$HOME/Library/Caches/com.apple.dt.xctest.tool/com.apple.e5rt.e5bundlecache"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"

set +e
( cd Packages/T2SKokoro && xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' \
  -parallel-testing-enabled NO -derivedDataPath .build/DerivedData \
  -only-testing:T2SKokoroTests/KokoroQualityProbe 2>&1 ) \
  | tee "$out/xcodebuild.log" \
  | grep -E "error:|Test run|Executed|TEST (SUCCEEDED|FAILED)|Testing failed" \
  | grep -Ev "/checkouts/.*: warning:"
status="${PIPESTATUS[0]}"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"
echo "Output: $out (report.md and the WAVs)"
exit "$status"
