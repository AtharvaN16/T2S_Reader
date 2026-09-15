#!/usr/bin/env bash
# Fetches a cover for every book in App/Resources/Onboarding/onboarding-manifest.json from Open
# Library — the edition's published cover, as the empty shelf's three are (the owner, 2026-09-14:
# "beautiful covers from popular books") — and stages each as
# App/Resources/Onboarding/onboarding-cover-<id>.jpg at 600 px wide (the settled hero is 280 pt
# tall, so 600 px covers a 3x screen), which App/project.yml bundles flat into the app.
#
# Each book is looked up by its manifest `title` and `author` through Open Library's search and the
# first result's cover is taken; a book may pin a different one with `coverID` (an Open Library
# cover id, the number in covers.openlibrary.org/b/id/<id>-L.jpg) when the first is a poor edition.
# A cover already staged is kept; pass --force to fetch again. Polite: one request at a time with a
# short pause.
# Usage: scripts/fetch-onboarding-covers.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
manifest=App/Resources/Onboarding/onboarding-manifest.json
out=App/Resources/Onboarding
force=0
[[ "${1:-}" == "--force" ]] && force=1
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ua='t2s_reader cover fetch (github.com/AtharvaN16/T2S_Reader)'

fetched=0
kept=0
missing=0
while IFS=$'\t' read -r id title author pinned; do
  target="$out/onboarding-cover-$id.jpg"
  if [[ -s "$target" && "$force" -eq 0 ]]; then kept=$((kept + 1)); continue; fi
  cover="$pinned"
  search() {   # title, author (may be empty) → first cover id, or nothing
    curl -s -A "$ua" -G 'https://openlibrary.org/search.json' \
      --data-urlencode "title=$1" ${2:+--data-urlencode "author=$2"} \
      --data-urlencode 'fields=cover_i' --data-urlencode 'limit=5' \
      | python3 -c 'import json, sys
docs = json.load(sys.stdin).get("docs", [])
ids = [d["cover_i"] for d in docs if d.get("cover_i")]
print(ids[0] if ids else "")'
  }
  # By title and author first; by title alone when the author is catalogued under another
  # spelling (Tolstoy is "Lev" there).
  [[ -z "$cover" ]] && cover="$(search "$title" "$author")"
  [[ -z "$cover" ]] && cover="$(search "$title" "")"
  if [[ -z "$cover" ]]; then
    echo "missing: $id (no cover on Open Library for \"$title\")"
    missing=$((missing + 1))
    continue
  fi
  # -L: the cover service answers with a redirect to its image host.
  code="$(curl -sL -A "$ua" -o "$tmp/$id.jpg" -w '%{http_code}' "https://covers.openlibrary.org/b/id/$cover-L.jpg?default=false")"
  if [[ "$code" != "200" || ! -s "$tmp/$id.jpg" ]]; then
    echo "missing: $id ($code for cover $cover)"
    missing=$((missing + 1))
    continue
  fi
  sips --resampleWidth 600 -s format jpeg -s formatOptions 78 "$tmp/$id.jpg" --out "$target" >/dev/null
  echo "fetched: $id (cover $cover)"
  fetched=$((fetched + 1))
  sleep 0.5
done < <(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
for b in m["books"]:
    print("\t".join([b["id"], b["title"], b["author"], str(b.get("coverID", ""))]))
' "$manifest")

echo "Covers: $fetched fetched, $kept kept, $missing missing."
[[ "$missing" -eq 0 ]]
