#!/usr/bin/env bash
# Fetches the soundscape loops named in App/Resources/Soundscapes/soundscapes-manifest.json — CC0
# Freesound field recordings, already cut to ~32 s AAC loops by the ambiently project
# (github.com/abhinandansharma/ambiently, MIT; the recordings themselves are CC0) — from that
# repository at the commit the manifest pins, and stages each as
# App/Resources/Soundscapes/soundscape-<id>.m4a, which App/project.yml bundles flat into the app.
# The project's credits file is kept beside the manifest for the record. No key, no account, no
# processing: the loop's seam and its loudness are handled in the app when a file is loaded
# (soundscape design §4.2). A file already staged is kept; pass --force to fetch again.
# Usage: scripts/fetch-soundscapes.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
manifest=App/Resources/Soundscapes/soundscapes-manifest.json
out=App/Resources/Soundscapes
force=0
[[ "${1:-}" == "--force" ]] && force=1
mkdir -p "$out"
read -r repo commit path < <(python3 -c "
import json
s = json.load(open('$manifest'))['source']
print(s['repository'].replace('https://github.com/', ''), s['commit'], s['path'])")
base="https://raw.githubusercontent.com/$repo/$commit/$path"
fetched=0
kept=0
while read -r id file; do
  dest="$out/soundscape-$id.m4a"
  if [[ -f "$dest" && $force -eq 0 ]]; then kept=$((kept + 1)); continue; fi
  curl -fsSL --retry 3 -o "$dest" "$base/$file"
  echo "fetched $dest ($(du -k "$dest" | cut -f1) KB)"
  fetched=$((fetched + 1))
done < <(python3 -c "
import json
for r in json.load(open('$manifest'))['recordings']:
    print(r['id'], r['file'])")
if [[ ! -f "$out/soundscapes-credits.json" || $force -eq 1 ]]; then
  curl -fsSL --retry 3 -o "$out/soundscapes-credits.json" "$base/CREDITS.json"
fi
echo "soundscapes: $fetched fetched, $kept kept"
