#!/usr/bin/env bash
# Fetches the onboarding's book covers from Standard Ebooks — public-domain paintings with
# Standard Ebooks' own typography, released CC0 — for every book in
# App/Resources/Onboarding/onboarding-manifest.json that names a `standardEbooks` path, and stages
# each as App/Resources/Onboarding/onboarding-cover-<id>.jpg at 600 px wide (the rising card is
# 280 pt tall, so 600 px covers a 3x screen), which App/project.yml bundles flat into the app.
#
# Each book page redirects to its canonical path (a translator or illustrator segment may be
# added), and the cover is that path's `downloads/cover.jpg`. A cover already staged is kept;
# pass --force to fetch again. Polite: one request at a time with a short pause.
# Usage: scripts/fetch-onboarding-covers.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
manifest=App/Resources/Onboarding/onboarding-manifest.json
out=App/Resources/Onboarding
force=0
[[ "${1:-}" == "--force" ]] && force=1
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetched=0
kept=0
missing=0
while IFS=$'\t' read -r id path; do
  [[ -z "$path" ]] && continue
  target="$out/onboarding-cover-$id.jpg"
  if [[ -s "$target" && "$force" -eq 0 ]]; then kept=$((kept + 1)); continue; fi
  canonical="$(curl -s -o /dev/null -w '%{redirect_url}' -A 'Mozilla/5.0' "https://standardebooks.org/ebooks/$path")"
  [[ -z "$canonical" ]] && canonical="https://standardebooks.org/ebooks/$path"
  code="$(curl -s -o "$tmp/$id.jpg" -w '%{http_code}' -A 'Mozilla/5.0' "$canonical/downloads/cover.jpg")"
  if [[ "$code" != "200" ]]; then
    echo "missing: $id ($code at $canonical/downloads/cover.jpg)"
    missing=$((missing + 1))
    continue
  fi
  sips --resampleWidth 600 -s format jpeg -s formatOptions 78 "$tmp/$id.jpg" --out "$target" >/dev/null
  echo "fetched: $id"
  fetched=$((fetched + 1))
  sleep 0.5
done < <(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
for b in m["books"]:
    print(b["id"] + "\t" + b.get("standardEbooks", ""))
' "$manifest")

echo "Covers: $fetched fetched, $kept kept, $missing missing."
[[ "$missing" -eq 0 ]]
