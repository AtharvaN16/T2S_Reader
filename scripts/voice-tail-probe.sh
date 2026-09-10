#!/usr/bin/env bash
# Renders the same utterances through every one of the 28 Core ML Kokoro voices and reports, for each
# pipeline call's tail, the shape of the burst the pipeline leaves there, whether the shipped
# KokoroCoreMLTailClick removes it, and what is left; then streams one utterance per voice down the
# app's own path and measures the joins. Writes report.md (and WAVs of the tails left in) to
# spikes/findings/voice-tail-probe/. The probe is a test in Packages/T2SKokoro that is enabled only
# while that directory exists, so it never runs as part of scripts/test-kokoro.sh. Needs
# scripts/fetch-kokoro-coreml.sh --app. Takes several minutes.
# Usage: scripts/voice-tail-probe.sh
set -euo pipefail
cd "$(dirname "$0")/.."
out=spikes/findings/voice-tail-probe
mkdir -p "$out"
# Core ML's runtime cache: see scripts/audio-probe.sh for why it is swept before and after.
e5_bundle_cache="$HOME/Library/Caches/com.apple.dt.xctest.tool/com.apple.e5rt.e5bundlecache"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"

set +e
( cd Packages/T2SKokoro && xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' \
  -parallel-testing-enabled NO -derivedDataPath .build/DerivedData \
  -only-testing:T2SKokoroTests/KokoroVoiceTailProbe 2>&1 ) \
  | tee "$out/xcodebuild.log" \
  | grep -E "error:|voice-tail-probe:|Test run|Executed|TEST (SUCCEEDED|FAILED)|Testing failed" \
  | grep -Ev "/checkouts/.*: warning:"
status="${PIPESTATUS[0]}"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"
echo "Output: $out (report.md and the WAVs)"
exit "$status"
