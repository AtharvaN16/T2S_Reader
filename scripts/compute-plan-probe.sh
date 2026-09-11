#!/usr/bin/env bash
# Runs the MLComputePlan probe (Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroComputePlanProbe.swift)
# on this Mac: for each requested Core ML stage and compute-unit policy, where Core ML places every
# operation of the stage's MIL program, what each is estimated to cost, and how long the plan took —
# the question from the iPhone 17 Pro, whose CPU plan compiler never finishes
# kokoro_decoder_har_post_15s (docs/HANDOFF.md, 2026-09-10). Needs the Core ML files
# (scripts/fetch-kokoro-coreml.sh --app); only the stages asked for are compiled.
#
# The environment does not reach a macOS unit-test process (see scripts/test-kokoro.sh), so the
# settings are written to spikes/findings/compute-plan-probe/probe.env, which the probe reads. On a
# phone the same names are environment variables; the probe's doc comment has that recipe.
#
# Usage: scripts/compute-plan-probe.sh [--stages a,b|all] [--policies cpu,cpuAndGPU,all] [--timeout seconds] [extra xcodebuild args]
#   defaults: the 15 s generator; cpuAndGPU,cpu,all; 900 s. `all` spends five to nine minutes failing the
#   generator's Neural Engine compile before it falls back, so `--policies cpuAndGPU,cpu` is the quick run.
set -euo pipefail
cd "$(dirname "$0")/.."

stages=""
policies=""
timeout=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stages) stages="$2"; shift 2 ;;
    --policies) policies="$2"; shift 2 ;;
    --timeout) timeout="$2"; shift 2 ;;
    *) break ;;
  esac
done

dir=spikes/findings/compute-plan-probe
mkdir -p "$dir"
{
  echo "# written by scripts/compute-plan-probe.sh on $(date '+%Y-%m-%d %H:%M:%S'); the probe reads KEY=VALUE lines"
  if [[ -n "$stages" ]]; then echo "KOKORO_COMPUTE_PLAN_STAGES=$stages"; fi
  if [[ -n "$policies" ]]; then echo "KOKORO_COMPUTE_PLAN_POLICIES=$policies"; fi
  if [[ -n "$timeout" ]]; then echo "KOKORO_COMPUTE_PLAN_TIMEOUT=$timeout"; fi
} > "$dir/probe.env"

cd Packages/T2SKokoro
# Core ML's runtime cache and the compile output, swept as scripts/test-kokoro.sh sweeps them.
e5_bundle_cache="$HOME/Library/Caches/com.apple.dt.xctest.tool/com.apple.e5rt.e5bundlecache"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc
set +e
xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:T2SKokoroTests/KokoroComputePlanProbe \
  -derivedDataPath .build/DerivedData "$@" 2>&1 \
  | grep -E "error:|kokoro compute plan|Executed|TEST (SUCCEEDED|FAILED)"
status="${PIPESTATUS[0]}"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"
echo "report: $dir/report.md (one ops-<stage>-<policy>.txt per plan beside it)"
exit "$status"
