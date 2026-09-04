#!/usr/bin/env bash
# Plan 0 Task 8 (spec §7.3 addendum): stages the Core ML Kokoro arm of the throwaway spike harness.
#
# Two things are fetched, both git-ignored and never committed:
#
#   1. Model files — the single 15-second bucket of the Hugging Face model repo
#      `mattmireles/kokoro-coreml`, into spikes/SpikeHarness/Resources/CoreML/ (~178 MB).
#      Layout is preserved (coreml/*.mlpackage, voices/, runtime/) so xcodegen picks the
#      .mlpackage directories up as single resources and Xcode compiles them to .mlmodelc.
#   2. Source — the low-level `KokoroPipeline` Swift package. The repo root has NO Package.swift;
#      the package lives in the `swift/` subdirectory, and SwiftPM cannot consume a subdirectory
#      by URL, so the repo is cloned to spikes/SpikeHarness/.deps/kokoro-coreml at a pinned commit
#      and project.yml references `path: .deps/kokoro-coreml/swift`.
#
# Pins:
#   HF model revision  2e878c6a33c56b40de094ef8237bf15a83d233c5  (files, 2026-07-15)
#   HF manifest rev    32399b333e809044c404c518cb3807a488e8f47d  (hashes, 2026-07-15, two minutes later)
#   GitHub commit      66d8cf5108cce0991b8868b01b4d8a8b2e98881d  (main, 2026-08-28)
#
# Integrity: every model file's sha256 comes from sdk/starter/KokoroRuntimeManifest.json — no
# hashes are hand-copied here except the manifest's own, the single root of trust.
#
# Why two HF revisions: the manifest checked in *at* 2e878c6a is stale. 2e878c6a is the commit
# "Re-export har_post buckets with fixed one-sided iSTFT scaling"; the manifest was only regenerated
# two minutes later, in 32399b33 ("Publish KokoroTTS SDK metadata"), and that one declares
# `hf_revision: 2e878c6a`. The stale copy still lists the pre-fix har_post hashes and fails
# kokoro_decoder_har_post_15s (same byte count, different bytes) — verified 2026-09-03. So take the
# files from 2e878c6a and the hashes from the manifest that describes 2e878c6a. The other three
# packages, the voice and both runtime assets are byte-identical between the two manifests.
#
# Licences: model weights Kokoro-82M (Apache-2.0) as converted by kokoro-coreml (Apache-2.0);
# the Swift package is Apache-2.0. Nothing under spikes/ ships.
#
# Idempotent: files whose sha256 already matches are left alone.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=mattmireles/kokoro-coreml
REV=2e878c6a33c56b40de094ef8237bf15a83d233c5
PKG_COMMIT=66d8cf5108cce0991b8868b01b4d8a8b2e98881d
MANIFEST_REV=32399b333e809044c404c518cb3807a488e8f47d
MANIFEST_PATH=sdk/starter/KokoroRuntimeManifest.json
MANIFEST_SHA256=11e7e71158da599cc01c6515d9ff834ef31ffcef8c3a79e83d84937612e7500b

DEST=spikes/SpikeHarness/Resources/CoreML
DEPS=spikes/SpikeHarness/.deps
PKG_DIR="$DEPS/kokoro-coreml"

# The 15-second bucket: one duration model (<=256 tokens), its F0Ntrain partner, and the two
# decoder halves. Anything longer than 15 s of audio falls back to this bucket and is truncated.
PACKAGES=(
  coreml/kokoro_duration_t256.mlpackage
  coreml/kokoro_f0ntrain_t600.mlpackage
  coreml/kokoro_decoder_pre_15s.mlpackage
  coreml/kokoro_decoder_har_post_15s.mlpackage
)
VOICES=(voices/af_heart.bin)
RUNTIME=(runtime/kokoro-vocab.json runtime/hnsf_weights.json)

sha_of() { shasum -a 256 "$1" | cut -d ' ' -f 1; }

matches() { [[ -f "$1" && "$(sha_of "$1")" == "$2" ]]; }

# --fail so a 404 is a download error, not an HTML body that fails the checksum; -L because
# huggingface.co/resolve redirects to the CDN.
hf_get() { curl --fail -sSL -o "$3" "https://huggingface.co/$REPO/resolve/$1/$2"; }

fetch_verified() {
  local path=$1 sha=$2 dest=$3
  if matches "$dest" "$sha"; then
    echo "ok: $path (already installed)"
    return
  fi
  echo "downloading $path"
  mkdir -p "$(dirname "$dest")"
  hf_get "$REV" "$path" "$dest"
  if ! matches "$dest" "$sha"; then
    rm -f "$dest"
    echo "checksum mismatch for $path; the bad copy was deleted. Expected $sha" >&2
    exit 1
  fi
  echo "ok: $path"
}

# ---------------------------------------------------------------- manifest (root of trust)
manifest=$(mktemp -t KokoroRuntimeManifest)
trap 'rm -f "$manifest"' EXIT
echo "fetching $MANIFEST_PATH @ ${MANIFEST_REV:0:12}"
hf_get "$MANIFEST_REV" "$MANIFEST_PATH" "$manifest"
if ! matches "$manifest" "$MANIFEST_SHA256"; then
  echo "manifest checksum mismatch: got $(sha_of "$manifest"), expected $MANIFEST_SHA256" >&2
  exit 1
fi

# Emits "<sha256> <hf path> <path under $DEST>" per file. Package files keep their in-package
# relative path so the .mlpackage directory is reassembled exactly as published.
plan=$(python3 - "$manifest" "${PACKAGES[@]}" -- "${VOICES[@]}" -- "${RUNTIME[@]}" <<'PY'
import json, sys

manifest_path, *rest = sys.argv[1:]
packages, voices, runtime = [], [], []
bucket = packages
for arg in rest:
    if arg == "--":
        bucket = voices if bucket is packages else runtime
        continue
    bucket.append(arg)

manifest = json.load(open(manifest_path))
by_path = {p["path"]: p for p in manifest["model_packages"]}
voice_shas = {v["path"]: v["sha256"] for v in manifest["voices"]}
asset_shas = {a["path"]: a["sha256"] for a in manifest["runtime_assets"].values()}

missing = [p for p in packages + voices + runtime
           if p not in by_path and p not in voice_shas and p not in asset_shas]
if missing:
    sys.exit("manifest does not list: " + ", ".join(missing))

for pkg in packages:
    for f in by_path[pkg]["files"]:
        print(f["sha256"], f"{pkg}/{f['path']}", f"{pkg}/{f['path']}")
for v in voices:
    print(voice_shas[v], v, v)
for a in runtime:
    print(asset_shas[a], a, a)
PY
)

# ---------------------------------------------------------------- model files
mkdir -p "$DEST"
while read -r sha path rel; do
  [[ -z "$sha" ]] && continue
  fetch_verified "$path" "$sha" "$DEST/$rel"
done <<< "$plan"

# ---------------------------------------------------------------- the Swift package
if [[ -d "$PKG_DIR/.git" ]]; then
  if [[ "$(git -C "$PKG_DIR" rev-parse HEAD)" == "$PKG_COMMIT" ]]; then
    echo "ok: kokoro-coreml @ ${PKG_COMMIT:0:12} (already checked out)"
  else
    echo "fetching kokoro-coreml @ ${PKG_COMMIT:0:12}"
    git -C "$PKG_DIR" fetch --quiet origin "$PKG_COMMIT"
    git -C "$PKG_DIR" checkout --quiet "$PKG_COMMIT"
  fi
else
  echo "cloning kokoro-coreml"
  mkdir -p "$DEPS"
  rm -rf "$PKG_DIR"
  git clone --quiet "https://github.com/$REPO.git" "$PKG_DIR"
  git -C "$PKG_DIR" checkout --quiet "$PKG_COMMIT"
fi
test -f "$PKG_DIR/swift/Package.swift" || { echo "$PKG_DIR/swift/Package.swift is missing" >&2; exit 1; }

echo
echo "$DEST:"
find "$DEST" -mindepth 1 -maxdepth 2 -print | sort
echo
du -sh "$DEST" "$PKG_DIR"
