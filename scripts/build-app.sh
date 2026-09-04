#!/usr/bin/env bash
# Regenerates the Xcode project from App/project.yml and builds the app for the iOS simulator.
# Signs ad hoc: an unsigned simulator build has no application-group entitlement, so the app cannot
# open the shared library it imports into and dies at launch. CI has no keychain and only needs the
# compile, so there it stays unsigned.
# The Kokoro target is not built here — it cannot link for the simulator; see scripts/build-device.sh.
# Usage: scripts/build-app.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/../App"
# Both model directories are git-ignored, so a fresh clone has neither, and xcodegen refuses a
# missing source path outright. Empty is enough to generate a project: the Kokoro target then
# builds an app whose on-device routes report their files missing.
mkdir -p Resources/Kokoro Resources/KokoroCoreML
xcodegen generate --quiet
if [[ -n "${CI:-}" ]]; then
  signing=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
else
  signing=(CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-)
fi
set +e
xcodebuild build -scheme T2SReader -destination "generic/platform=iOS Simulator" \
  -derivedDataPath ../.build/DerivedData-App \
  "${signing[@]}" "$@" 2>&1 \
  | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" \
  | grep -Ev "/checkouts/.*: warning:|/SourcePackages/.*: warning:"
exit "${PIPESTATUS[0]}"
