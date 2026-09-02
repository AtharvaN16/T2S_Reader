#!/usr/bin/env bash
# Regenerates the Xcode project from App/project.yml and builds the app for the iOS simulator.
# Usage: scripts/build-app.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/../App"
xcodegen generate --quiet
set +e
xcodebuild build -scheme T2SReader -destination "generic/platform=iOS Simulator" \
  -derivedDataPath ../.build/DerivedData-App \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "$@" 2>&1 \
  | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" \
  | grep -Ev "/checkouts/.*: warning:|/SourcePackages/.*: warning:"
exit "${PIPESTATUS[0]}"
