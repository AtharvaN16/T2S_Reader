#!/usr/bin/env bash
# Renders the same passages through the shipped fp16 model set and through the int8 candidate that
# scripts/quantize-kokoro-coreml.py builds, and writes both WAVs plus a ranked report to
# spikes/findings/quantization-probe/ — for a human to listen to. Nothing here is played: the WAVs
# are for the owner to open, or to send to a phone.
#
# The probe is a test in Packages/T2SKokoro enabled only while that directory exists, so it never
# runs as part of scripts/test-kokoro.sh.
#
# Needs both stagings:
#   scripts/fetch-kokoro-coreml.sh --app                          -> App/Resources/KokoroCoreML
#   PYTHONPATH=.build/ctlib /usr/bin/python3 \
#     scripts/quantize-kokoro-coreml.py                           -> App/Resources/KokoroCoreML-int8
#
# Takes several minutes and wants room: it compiles two sets of stages (about 350 MB each, kept
# between runs under Packages/T2SKokoro/.build/compiled-stages-*) and Core ML caches roughly 0.9 GB
# of compiled graphs per fresh model path in a cache it never reclaims on its own — twice over here,
# once per set, which is why the sweep below matters more than it does for the single-set probes.
# Usage: scripts/quantization-probe.sh
set -euo pipefail
cd "$(dirname "$0")/.."
out=spikes/findings/quantization-probe
mkdir -p "$out"

e5_bundle_cache="$HOME/Library/Caches/com.apple.dt.xctest.tool/com.apple.e5rt.e5bundlecache"
sweep() { rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"; }
sweep

free_gb=$(df -g / | awk 'NR==2 {print $4}')
if [ "$free_gb" -lt 8 ]; then
  echo "Only ${free_gb} GB free. Two model sets compile and cache here; 8+ GB is the safe floor." >&2
  echo "Clear Xcode's DerivedData (~/Library/Developer/Xcode/DerivedData) and retry." >&2
  exit 1
fi

set +e
( cd Packages/T2SKokoro && xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' \
  -parallel-testing-enabled NO -derivedDataPath .build/DerivedData \
  -only-testing:T2SKokoroTests/KokoroQuantizationProbe 2>&1 ) \
  | tee "$out/xcodebuild.log" \
  | grep -E "error:|Test run|Executed|TEST (SUCCEEDED|FAILED)|Testing failed|^  |^Quantization|^Listen|^[0-9]{2}-" \
  | grep -Ev "/checkouts/.*: warning:"
status="${PIPESTATUS[0]}"
sweep
echo "Output: $out"
ls -la "$out"
exit "$status"
