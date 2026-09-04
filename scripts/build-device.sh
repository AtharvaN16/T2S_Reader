#!/usr/bin/env bash
# Compile proof of the Kokoro app target: T2SReaderKokoro links MLX, so it builds for the device
# only (mlx-swift cannot link against the simulator SDK). Release with ENABLE_DEBUG_DYLIB=NO because
# Xcode's debug-dylib layout leaves the package frameworks in DerivedData and the installed app then
# aborts at launch (spikes/README.md, "Gotchas").
# This produces an unsigned .app. Installing on a phone is done from Xcode with a team selected —
# the recipe is in HANDOFF.
# The first run compiles mlx-swift for iphoneos: 10-15 minutes and about 2 GB of DerivedData.
# When App/Resources/KokoroCoreML is staged (scripts/fetch-kokoro-coreml.sh --app), the build also
# compiles the eight .mlpackage stages into .mlmodelc bundles inside the .app, which is what makes
# Core ML Kokoro the default voice on the phone.
# Usage: scripts/build-device.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/../App"
# Both model directories are git-ignored, so a fresh clone has neither, and xcodegen refuses a
# missing source path outright. Empty is enough to generate a project: the Kokoro target then
# builds an app whose on-device routes report their files missing.
mkdir -p Resources/Kokoro Resources/KokoroCoreML
xcodegen generate --quiet
set +e
xcodebuild build -scheme Phone -destination "generic/platform=iOS" \
  -configuration Release \
  -derivedDataPath ../.build/DerivedData-App \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ENABLE_DEBUG_DYLIB=NO "$@" 2>&1 \
  | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" \
  | grep -Ev "/checkouts/.*: warning:|/SourcePackages/.*: warning:"
exit "${PIPESTATUS[0]}"
