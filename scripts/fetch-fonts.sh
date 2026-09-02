#!/usr/bin/env bash
# Downloads Inter 4.1 and copies the five static faces the app bundles (spec §2.4.1) plus the OFL
# license into App/Resources/Fonts. The fonts are committed; run this only to refresh them.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -sSL -o "$tmp/inter.zip" https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip
mkdir -p App/Resources/Fonts
for face in Inter-Regular Inter-Medium Inter-SemiBold InterDisplay-ExtraBold InterDisplay-Black; do
  unzip -p "$tmp/inter.zip" "extras/ttf/$face.ttf" > "App/Resources/Fonts/$face.ttf"
done
unzip -p "$tmp/inter.zip" LICENSE.txt > App/Resources/Fonts/LICENSE.txt
ls -la App/Resources/Fonts
