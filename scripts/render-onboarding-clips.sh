#!/usr/bin/env bash
# Renders the onboarding's pre-recorded clips with the app's own Core ML Kokoro engine and stages
# them for the app bundle. The render is `OnboardingClipProbe` in Packages/T2SKokoro, enabled only
# while spikes/findings/onboarding-clips/ exists (created here), so scripts/test-kokoro.sh never
# runs it. It reads the lines and voices from App/Resources/Onboarding/onboarding-manifest.json.
#
# Output, per clip: a 24 kHz WAV and a word-timing JSON in spikes/findings/onboarding-clips/ — the
# WAVs are for a human to listen to — and, on success, an AAC .m4a plus the JSON copied into
# App/Resources/Onboarding/, which App/project.yml bundles flat into the app.
#
# Needs scripts/fetch-kokoro-coreml.sh --app to have staged the Core ML files. The first run builds
# the package's DerivedData (10–20 minutes) and compiles the eight stages (about 5 minutes); later
# runs are the render alone. Nothing here plays audio.
# Usage: scripts/render-onboarding-clips.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/.."
out=spikes/findings/onboarding-clips
bundle=App/Resources/Onboarding
mkdir -p "$out" "$bundle"

# Core ML's own runtime cache, swept before and after as scripts/audio-probe.sh does: it caches
# ~0.9 GB of compiled graphs per fresh model path under a test bundle and never reclaims it.
e5_bundle_cache="$HOME/Library/Caches/com.apple.dt.xctest.tool/com.apple.e5rt.e5bundlecache"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"

set +e
( cd Packages/T2SKokoro && xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' \
  -parallel-testing-enabled NO -derivedDataPath .build/DerivedData \
  -only-testing:T2SKokoroTests/OnboardingClipProbe "$@" 2>&1 ) \
  | tee "$out/xcodebuild.log" \
  | grep -E "error:|Test run|Executed|TEST (SUCCEEDED|FAILED)|Testing failed|^- onboarding" \
  | grep -Ev "/checkouts/.*: warning:"
status="${PIPESTATUS[0]}"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"
if [[ "$status" -ne 0 ]]; then
  echo "Render failed (status $status); see $out/xcodebuild.log"
  exit "$status"
fi

# AAC at 64 kb/s mono: transparent for speech at 24 kHz, and nine clips come to well under a megabyte.
converted=0
for wav in "$out"/onboarding-*.wav; do
  [[ -e "$wav" ]] || continue
  name="$(basename "${wav%.wav}")"
  afconvert -f m4af -d aac -b 64000 "$wav" "$bundle/$name.m4a"
  cp "$out/$name.json" "$bundle/$name.json"
  converted=$((converted + 1))
done
echo "Staged $converted clips in $bundle:"
ls -la "$bundle"
