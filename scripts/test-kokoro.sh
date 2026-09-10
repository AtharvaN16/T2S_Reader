#!/usr/bin/env bash
# Runs the Packages/T2SKokoro tests on this Mac.
# xcodebuild, not `swift test`: KokoroSwift runs on MLX, and MLX loads a compiled Metal library that
# only a full Xcode build produces and stages next to the binary. The first run compiles mlx-swift's
# C++ and Metal sources and takes 10-20 minutes; later runs are incremental.
# Tests that need the model files are `.enabled(if:)` their presence and are reported as skipped when
# App/Resources/Kokoro is empty (CI, a fresh clone) — run scripts/fetch-kokoro-model.sh to fill it.
#
# -parallel-testing-enabled NO, and swift-testing honours it in-process (suites start and finish one
# at a time, not interleaved): the model-backed tests point KokoroSwift's `Bundle.module` at the test
# bundle by calling `setenv` from `Tests/T2SKokoroTests/Support/PackageResourceBundles.swift`, and a
# `setenv` running while another test reads `ProcessInfo.processInfo.environment` — which
# `KokoroResources.developmentDirectory` does on every call — is a data race on `environ`. Setting the
# variable out here instead would be better, but it cannot reach the test process: xcodebuild forwards
# no environment of its own to a macOS unit-test bundle, and `TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH`
# (the UI-test-runner mechanism) is dropped — verified by passing a deliberately invalid path and
# watching the tests pass anyway. Serial costs about a second on this suite.
#
# The Core ML stages ship as .mlpackage on the development path, so every model-backed engine test
# compiles its own copy into $TMPDIR and leaves it there (~350 MB each; the app bundle is
# precompiled and unaffected). Left alone they fill the disk in a few runs, and a full disk is what
# produced Task 3's nonsense timings, so the leak from earlier runs is swept before this one starts.
# Usage: scripts/test-kokoro.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/../Packages/T2SKokoro"

# Core ML's own runtime cache (distinct from the $TMPDIR compile output below): it caches ~0.9 GB
# of compiled graphs per fresh model path under a test bundle and never reclaims it on its own —
# it filled the disk three times on 2026-09-05. Swept both before and after, so neither this run's
# own accumulation nor an earlier run's leftovers can starve the run that follows.
e5_bundle_cache="$HOME/Library/Caches/com.apple.dt.xctest.tool/com.apple.e5rt.e5bundlecache"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"

set +e
xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -derivedDataPath .build/DerivedData "$@" 2>&1 \
  | grep -E "error:|warning:|Suite |Test run|Executed|TEST (SUCCEEDED|FAILED)|Testing failed|✘|recorded an issue|Expectation failed" \
  | grep -Ev "/checkouts/.*: warning:"
status="${PIPESTATUS[0]}"
rm -rf "${TMPDIR:-/tmp}"/kokoro_*.mlmodelc "$e5_bundle_cache"
exit "$status"
