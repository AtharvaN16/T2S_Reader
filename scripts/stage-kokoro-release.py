#!/usr/bin/env python3
"""Assembles a publishable Hugging Face repository from a Core ML Kokoro staging, and writes the
Swift manifest entries the app needs to download it.

Usage:
    /usr/bin/python3 scripts/stage-kokoro-release.py \
        [--src App/Resources/KokoroCoreML-int8] [--out .build/release] [--label int8]

Produces, under --out:

    coreml/…            the .mlpackage stages, at the same relative paths the app already asks for,
                        so switching source is a URL change and not a layout change
    voices/ runtime/    unchanged from the staging
    LICENSE             Apache-2.0 (§4(a): a derivative must carry a copy)
    README.md           the model card, with the front matter the Hub reads
    config.json         empty, so the Hub counts downloads for a `library_name: coreml` repo
    manifest.json       every file with its sha256 and byte count, for anyone pinning the way we do
    KokoroCoreMLManifest.files.swift
                        the generated `File(...)` rows to paste into the app's manifest

WHY THE LAYOUT MATCHES THE UPSTREAM REPO

`KokoroCoreMLManifest.File` addresses each file by `repositoryPath` and resolves it against
`repositoryURL` + the pinned revision. Keeping `coreml/<stage>.mlpackage/Data/com.apple.CoreML/…`
identical to `mattmireles/kokoro-coreml` means the only code changes are the repository URL and the
revision — the 72 paths, the installer, the twin-file dedupe and the compile step are untouched.

Apple's own repos also publish a `compiled/` folder of `.mlmodelc` beside the packages, for Swift
consumers who want to skip the on-device compile. This script deliberately does not: a `.mlmodelc` is
produced by one machine's toolchain and its portability across OS versions rests on precedent rather
than any Apple guarantee, while the `.mlpackage` form compiles anywhere and is what our installer
consumes. Add it later if someone asks.

WHAT IS NOT AUTOMATED

Uploading. That needs the owner's Hugging Face credentials, which belong in their hands and not in a
script: run `hf auth login` once, then the `hf upload` line this script prints when it finishes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

CARD = """---
license: apache-2.0
base_model: hexgrad/Kokoro-82M
base_model_relation: quantized
library_name: coreml
pipeline_tag: text-to-speech
language:
- en
tags:
- coreml
- kokoro
- text-to-speech
- on-device
- ios
- int8
---

# Kokoro-82M for Core ML, {label} weights

The [mattmireles/kokoro-coreml](https://huggingface.co/mattmireles/kokoro-coreml) staged export of
[hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), with its weights compressed from
float16 to 8-bit. Same stages, same bucket layout, same inputs and outputs — only smaller.

|                          | float16 | this repo |
| ------------------------ | ------: | --------: |
| distinct weight bytes    | {before_mb:.0f} MB | {after_mb:.0f} MB |
| compiled on device       | 578 MB | 326 MB |

## What changed

Post-training weight quantization with `coremltools.optimize.coreml.linear_quantize_weights`
(coremltools 9.0, `mode="linear_symmetric"`, `dtype=int8`, `granularity="per_channel"`) applied to
the published float16 `.mlpackage` files. No re-export from PyTorch, so the graphs are byte-for-byte
the upstream ones apart from the weight encoding. Core ML expands the weights back to float16 when
the model loads, so nothing about how you call these models changes.

Three groups of weights are deliberately **left in float**, selected by operation type and shape so
that every bucket variant is treated identically:

- the generator's two `conv_transpose` upsamplers — no published 8-bit Kokoro quantizes these,
  because `onnxruntime` structurally cannot, so there is no evidence either way and they are cheap
  to keep;
- the generator's final convolution (`conv_post`, shape `22×128×7`) — the one layer independent
  reports agree adds audible static when quantized, and it is about 20 KB;
- the prosody stage's LSTM weights, the only float32 tensors in the upstream export.

Bucket variants of a stage still share byte-identical weight files after quantization, so a consumer
that de-duplicates identical weights keeps that saving.

## Quality

Judged against the float16 export it was built from, not against PyTorch:

- prosody and decoder stages agree at cosine ≥ 0.9999;
- the duration model shifts about 1% of phonemes by one 12.5 ms frame — 0.025 s across 13.1 s of
  speech;
- in a blind A/B over the passages where spectral measurements showed the largest difference, a
  listener did not identify the quantized renders as worse, and picked one as "livelier".

The renders are not sample-identical to float16 and are not meant to be. Timing moves by tens of
milliseconds on some phonemes.

## Using it

The stages take phonemes, not text: bring your own G2P (`misaki`, or `MisakiSwift` on Apple
platforms). `runtime/kokoro-vocab.json` maps phoneme characters to token ids and
`runtime/hnsf_weights.json` carries the harmonic-source weights. The pipeline that drives these
stages is [mattmireles/kokoro-coreml](https://github.com/mattmireles/kokoro-coreml)'s
`KokoroPipeline`; the stage split, the buckets and the tensor contract are all upstream's.

`manifest.json` lists every file with its SHA-256 and byte count, for pinning.

## Credits and licence

Apache-2.0, inherited. In order: [hexgrad](https://huggingface.co/hexgrad) trained and released
Kokoro-82M; [yl4579](https://github.com/yl4579) authored the StyleTTS 2 architecture it builds on;
[mattmireles](https://huggingface.co/mattmireles) did the Core ML conversion and the staged export
this repo compresses; the voice files are hexgrad's, repacked by
[onnx-community](https://huggingface.co/onnx-community). This repo adds the quantization and nothing
else. Not affiliated with or endorsed by any of them, or by Apple.

Kokoro-82M was trained on permissive and non-copyrighted audio. Its card records these Creative
Commons Attribution sources, reproduced here as its licence asks:

| Source | Duration | Licence |
| ------ | -------- | ------- |
| [Koniwa](https://github.com/koniwa/koniwa) `tnc` | <1h | CC BY 3.0 |
| [SIWIS](https://datashare.ed.ac.uk/handle/10283/2353) | <11h | CC BY 4.0 |
"""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def swift_rows(entries: list[dict]) -> str:
    """The app's manifest rows. `repositoryPath` is omitted where it equals the local path."""
    lines = [
        "// Generated by scripts/stage-kokoro-release.py — paste into KokoroCoreMLManifest.files.",
        "public static let files: [File] = [",
    ]
    for entry in entries:
        lines.append(
            f'    File("{entry["path"]}", '
            f'sha256: "{entry["sha256"]}", byteCount: {entry["byteCount"]}),'
        )
    lines.append("]")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src", type=Path, default=REPO / "App/Resources/KokoroCoreML-int8")
    parser.add_argument("--out", type=Path, default=REPO / ".build/release")
    parser.add_argument("--label", default="int8")
    parser.add_argument("--reference", type=Path, default=REPO / "App/Resources/KokoroCoreML",
                        help="the float16 staging, for the size comparison in the card")
    args = parser.parse_args()

    if not (args.src / "coreml").is_dir():
        print(f"No coreml/ under {args.src}; run scripts/quantize-kokoro-coreml.py first.")
        return 1

    shutil.rmtree(args.out, ignore_errors=True)
    args.out.mkdir(parents=True)
    for folder in ("coreml", "voices", "runtime"):
        source = args.src / folder
        if source.is_dir():
            shutil.copytree(source, args.out / folder)

    shutil.copy(REPO / "Packages/KokoroPipeline/LICENSE", args.out / "LICENSE")
    (args.out / "config.json").write_text("")

    entries = []
    for path in sorted(args.out.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(args.out).as_posix()
        if relative in {"config.json", "LICENSE", "README.md", "manifest.json"}:
            continue
        entries.append({"path": relative, "sha256": sha256(path), "byteCount": path.stat().st_size})

    def distinct_weight_bytes(root: Path) -> int:
        seen: dict[str, int] = {}
        for weight in sorted(root.rglob("weight.bin")):
            seen.setdefault(sha256(weight), weight.stat().st_size)
        return sum(seen.values())

    before = distinct_weight_bytes(args.reference) if args.reference.is_dir() else 0
    after = distinct_weight_bytes(args.src)

    (args.out / "manifest.json").write_text(json.dumps({
        "source": "mattmireles/kokoro-coreml@2e878c6a33c56b40de094ef8237bf15a83d233c5",
        "quantization": {
            "tool": "coremltools 9.0 linear_quantize_weights",
            "mode": "linear_symmetric", "dtype": "int8", "granularity": "per_channel",
            "kept_float": ["conv_transpose", "lstm", "conv_post (22,128,7)"],
        },
        "files": entries,
    }, indent=2) + "\n")

    (args.out / "README.md").write_text(CARD.format(
        label=args.label, before_mb=before / 1e6, after_mb=after / 1e6
    ))
    (args.out / "KokoroCoreMLManifest.files.swift").write_text(swift_rows(entries))

    total = sum(entry["byteCount"] for entry in entries)
    print(f"Staged {len(entries)} files ({total / 1e6:.1f} MB) into {args.out}")
    print(f"  distinct weight bytes: {before / 1e6:.1f} MB -> {after / 1e6:.1f} MB")
    print("\nTo publish (the upload needs your credentials, so it is not scripted here):")
    print("  pip install -U huggingface_hub        # once; brings hf_xet")
    print("  hf auth login                         # once")
    print(f"  hf repos create <namespace>/kokoro-coreml-{args.label}")
    print(f"  hf upload <namespace>/kokoro-coreml-{args.label} {args.out} .")
    print("\nThen pin the commit it lands on and paste KokoroCoreMLManifest.files.swift into")
    print("Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLManifest.swift.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
