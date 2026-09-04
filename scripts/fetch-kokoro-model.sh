#!/usr/bin/env bash
# Installs the Kokoro-82M weights and the voice styles into App/Resources/Kokoro. Both files are
# git-ignored and must never be committed. An existing correct copy is left alone; otherwise the
# Plan 0 spike harness copy is reused, and only failing that is the file downloaded.
#
# | File                    |        Bytes | SHA-256                                                          |
# |-------------------------|--------------|------------------------------------------------------------------|
# | kokoro-v1_0.safetensors |  327,115,152 | 4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8 |
# | voices.npz              |   14,629,684 | 56dbfa2f2970af2e395397020393d368c5f441d09b3de4e9b77f6222e790f10f |
#
# The weights are Kokoro-82M (Apache-2.0) as packaged by KokoroTestApp (Apache-2.0); see
# docs/licenses.md. The same checksums are the constants in KokoroResources.
set -euo pipefail
cd "$(dirname "$0")/.."

dest=App/Resources/Kokoro
spike=spikes/SpikeHarness/Resources
mkdir -p "$dest"

matches() {
  [[ -f "$1" && "$(shasum -a 256 "$1" | cut -d ' ' -f 1)" == "$2" ]]
}

install_file() {
  local name=$1 sha=$2 url=$3
  if matches "$dest/$name" "$sha"; then
    echo "ok: $name (already installed)"
    return
  fi
  if matches "$spike/$name" "$sha"; then
    echo "copying $name from $spike"
    cp "$spike/$name" "$dest/$name"
  else
    echo "downloading $name"
    # --fail: a 404 must be a download error, not an HTML body that fails the checksum.
    curl --fail -sSL -o "$dest/$name" "$url"
  fi
  if ! matches "$dest/$name" "$sha"; then
    rm -f "$dest/$name"
    echo "checksum mismatch for $name; the bad copy was deleted. Expected $sha" >&2
    exit 1
  fi
  echo "ok: $name"
}

install_file kokoro-v1_0.safetensors \
  4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8 \
  https://media.githubusercontent.com/media/mlalma/KokoroTestApp/main/Resources/kokoro-v1_0.safetensors
install_file voices.npz \
  56dbfa2f2970af2e395397020393d368c5f441d09b3de4e9b77f6222e790f10f \
  https://raw.githubusercontent.com/mlalma/KokoroTestApp/main/Resources/voices.npz

ls -la "$dest"
