#!/usr/bin/env bash
# Compile proof of the Kokoro app target: T2SReaderKokoro links MLX, so it builds for the device
# only (mlx-swift cannot link against the simulator SDK). Release with ENABLE_DEBUG_DYLIB=NO because
# Xcode's debug-dylib layout leaves the package frameworks in DerivedData and the installed app then
# aborts at launch (spikes/README.md, "Gotchas").
# This produces an unsigned .app. Installing on a phone is done from Xcode with a team selected —
# the recipe is in HANDOFF.
# The first run compiles mlx-swift for iphoneos: 10-15 minutes and about 2 GB of DerivedData.
# Usage: scripts/build-device.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/../App"
xcodegen generate --quiet
set +e
xcodebuild build -scheme T2SReaderKokoro -destination "generic/platform=iOS" \
  -configuration Release \
  -derivedDataPath ../.build/DerivedData-App \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ENABLE_DEBUG_DYLIB=NO "$@" 2>&1 \
  | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" \
  | grep -Ev "/checkouts/.*: warning:|/SourcePackages/.*: warning:"
exit "${PIPESTATUS[0]}"
