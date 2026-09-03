#!/usr/bin/env bash
# Runs the Packages/T2SKokoro tests on this Mac.
# xcodebuild, not `swift test`: KokoroSwift runs on MLX, and MLX loads a compiled Metal library that
# only a full Xcode build produces and stages next to the binary. The first run compiles mlx-swift's
# C++ and Metal sources and takes 10-20 minutes; later runs are incremental.
# Tests that need the model files are `.enabled(if:)` their presence and are reported as skipped when
# App/Resources/Kokoro is empty (CI, a fresh clone) — run scripts/fetch-kokoro-model.sh to fill it.
# Usage: scripts/test-kokoro.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/../Packages/T2SKokoro"

set +e
xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData "$@" 2>&1 \
  | grep -E "error:|warning:|Suite |Test run|Executed|TEST (SUCCEEDED|FAILED)|Testing failed" \
  | grep -Ev "/checkouts/.*: warning:"
exit "${PIPESTATUS[0]}"
