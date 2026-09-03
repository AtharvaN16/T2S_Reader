#!/usr/bin/env bash
# Vendors Mozilla Readability 0.6.0 (Apache-2.0) into App/Resources/Readability. Committed; re-run to bump.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p App/Resources/Readability
curl -sSL -o App/Resources/Readability/Readability.js https://raw.githubusercontent.com/mozilla/readability/0.6.0/Readability.js
curl -sSL -o App/Resources/Readability/LICENSE https://raw.githubusercontent.com/mozilla/readability/0.6.0/LICENSE.md
head -3 App/Resources/Readability/Readability.js
grep -m1 -i "apache" App/Resources/Readability/LICENSE
