#!/usr/bin/env python3
"""Compresses the staged fp16 Core ML Kokoro stages to int8 weights, in place of a re-export.

Usage:
    /usr/bin/python3 -m pip install --target .build/ctlib "coremltools==9.0" "numpy<2.1"
    PYTHONPATH=.build/ctlib /usr/bin/python3 scripts/quantize-kokoro-coreml.py [--out DIR] [--dry-run]

Reads  App/Resources/KokoroCoreML            (staged by scripts/fetch-kokoro-coreml.sh --app)
Writes App/Resources/KokoroCoreML-int8       (git-ignored, same layout, loadable by
                                              KokoroCoreMLResources.locate(inDirectory:))

WHAT THIS DOES, AND WHY IT NEEDS NO RE-EXPORT

`coremltools.optimize.coreml.linear_quantize_weights` rewrites each large weight tensor of an
existing .mlpackage into a `constexpr_affine_dequantize` op holding int8 values plus per-channel
scales. Core ML expands them back to float16 when the model loads, so the arithmetic at run time is
unchanged and the Swift runtime needs no changes at all — only the bytes on disk get smaller. The
upstream packages are exported at the iOS 15 opset; this pass lifts them to iOS 16, which our
iOS 18.0 floor accepts. Nothing here needs PyTorch or the upstream export scripts.

Measured on this Mac (2026-09-11): the four distinct stages go from 166 MB of fp16 weights to about
82 MB, i.e. the manifest's ~227 MB of distinct download bytes to roughly 120 MB. See
docs/research/2026-09-11-kokoro-quantization-how-to-and-publishing.md.

WHAT IS DELIBERATELY LEFT IN FLOAT, AND WHY

Three groups, kept out of int8 by op type or by shape rather than by name, because the weight names
in these packages are generated (`weight_101_to_fp16`, `op_416_to_fp16`) and differ between buckets:

  conv_transpose  The generator's two upsamplers (2.62M + 0.39M elements, ~6 MB fp16). Every
                  published 8-bit ONNX Kokoro leaves these float — not by choice, but because
                  onnxruntime structurally cannot quantize ConvTranspose — so no one has evidence
                  either way. Keeping them float costs ~6 MB and removes the one unstudied risk.
  lstm            f0ntrain's prosody LSTM weights, the only float32 tensors in an otherwise fp16
                  export (7.3 MB of a 20.5 MB stage). Our own probe's residual error was dominated
                  by this path when everything was quantized.
  conv_post       The decoder's final convolution, shape (22, 128, 7) — 22 output channels being the
                  iSTFT magnitude+phase pair. This is the one layer two independent people found by
                  experiment: quantizing it "adds a ton of static" that a mel-spectrogram distance
                  metric does not catch (Adrian Lyjak), and the one shipped Core ML port that splits
                  it out keeps it uncompressed for the same reason (laishere/kokoro-coreml). It is
                  ~20 KB, so exempting it is free.

Everything else — ALBERT, the duration and prosody paths, the AdaIN blocks, the generator resblocks
— is quantized, which is what every published 8-bit Kokoro (ONNX, GGUF and the three Core ML ports)
does without reported trouble.

WHY LINEAR int8 AND NOT PALETTIZATION

The bucket variants of a stage share one `weight.bin`, and the app hard-links the identical compiled
copies on the phone (580 MB -> 240 MB, KokoroCoreMLInstall.linkDuplicateWeights). That only survives
if quantizing two buckets from identical input bytes yields identical output bytes. Linear
quantization is a pure function of the weights; k-means palettization depends on the environment
(coremltools picks kmeans1d or scikit-learn depending on what is installed). This script verifies
the property rather than assuming it: every group of stages that shared a weight file before must
still share one after, or it exits non-zero.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_SRC = REPO / "App/Resources/KokoroCoreML"
DEFAULT_OUT = REPO / "App/Resources/KokoroCoreML-int8"

# Op types whose weights stay float. See the header.
EXCLUDED_OP_TYPES = ("conv_transpose", "lstm")
# The decoder's final conv, identified by shape rather than by its generated name.
CONV_POST_SHAPE = (22, 128, 7)


def weights_path(package: Path) -> Path:
    return package / "Data/com.apple.CoreML/weights/weight.bin"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def find_conv_post(metadata) -> list[str]:
    """Names of weights with the decoder's final-conv shape, so buckets are handled alike."""
    return [name for name, meta in metadata.items() if tuple(meta.val.shape) == CONV_POST_SHAPE]


def quantize(package: Path, destination: Path, cto) -> dict:
    import coremltools as ct

    model = ct.models.MLModel(str(package), skip_model_load=True)
    metadata = cto.get_weights_metadata(model, weight_threshold=2048)
    excluded_names = find_conv_post(metadata)

    config = cto.OptimizationConfig(
        global_config=cto.OpLinearQuantizerConfig(
            mode="linear_symmetric", dtype="int8", granularity="per_channel"
        ),
        op_type_configs={op: None for op in EXCLUDED_OP_TYPES},
        op_name_configs={name: None for name in excluded_names},
    )

    started = time.monotonic()
    compressed = cto.linear_quantize_weights(model, config)
    compressed.save(str(destination))
    elapsed = time.monotonic() - started

    before = weights_path(package).stat().st_size
    after = weights_path(destination).stat().st_size
    return {
        "before": before,
        "after": after,
        "seconds": elapsed,
        "excluded_names": excluded_names,
        "excluded_op_types": [
            op for op in EXCLUDED_OP_TYPES
            if any(child.op_type == op for meta in metadata.values() for child in meta.child_ops)
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src", type=Path, default=DEFAULT_SRC)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--dry-run", action="store_true", help="report what would be excluded, write nothing")
    args = parser.parse_args()

    try:
        import coremltools.optimize.coreml as cto
    except ImportError:
        print("coremltools is missing. Install it first:\n"
              '  /usr/bin/python3 -m pip install --target .build/ctlib "coremltools==9.0" "numpy<2.1"\n'
              "then re-run with PYTHONPATH=.build/ctlib", file=sys.stderr)
        return 1

    packages = sorted((args.src / "coreml").glob("*.mlpackage"))
    if not packages:
        print(f"No .mlpackage under {args.src / 'coreml'} — run scripts/fetch-kokoro-coreml.sh --app first.",
              file=sys.stderr)
        return 1

    # Which stages shared a weight file before: the property the hard-link dedupe depends on.
    groups_before: dict[str, list[str]] = {}
    for package in packages:
        groups_before.setdefault(sha256(weights_path(package)), []).append(package.name)

    if args.dry_run:
        import coremltools as ct
        print(f"{len(packages)} stages, {len(groups_before)} distinct weight files\n")
        for package in packages:
            model = ct.models.MLModel(str(package), skip_model_load=True)
            metadata = cto.get_weights_metadata(model, weight_threshold=2048)
            names = find_conv_post(metadata)
            kinds = sorted({child.op_type for meta in metadata.values() for child in meta.child_ops})
            print(f"  {package.name}\n    consumers: {', '.join(kinds)}"
                  f"\n    conv_post by shape {CONV_POST_SHAPE}: {names or 'none'}")
        return 0

    (args.out / "coreml").mkdir(parents=True, exist_ok=True)
    results = {}
    for index, package in enumerate(packages, start=1):
        destination = args.out / "coreml" / package.name
        shutil.rmtree(destination, ignore_errors=True)
        print(f"[{index}/{len(packages)}] {package.name} ...", flush=True)
        results[package.name] = quantize(package, destination, cto)
        row = results[package.name]
        print(f"    {row['before'] / 1e6:7.1f} MB -> {row['after'] / 1e6:7.1f} MB  "
              f"({row['after'] / row['before']:.0%}, {row['seconds']:.0f} s)"
              + (f"  kept float: {', '.join(row['excluded_names'])}" if row["excluded_names"] else ""))

    for folder in ("voices", "runtime"):
        source = args.src / folder
        if source.is_dir():
            shutil.rmtree(args.out / folder, ignore_errors=True)
            shutil.copytree(source, args.out / folder)

    # The hard-link property: stages that shared a weight file must still share one.
    groups_after: dict[str, list[str]] = {}
    for package in packages:
        groups_after.setdefault(sha256(weights_path(args.out / "coreml" / package.name)), []).append(package.name)

    shared_before = {tuple(sorted(names)) for names in groups_before.values()}
    shared_after = {tuple(sorted(names)) for names in groups_after.values()}

    before_total = sum(row["before"] for row in results.values())
    after_total = sum(row["after"] for row in results.values())
    distinct_before = sum(results[names[0]]["before"] for names in groups_before.values())
    distinct_after = sum(results[names[0]]["after"] for names in groups_after.values())

    print(f"\n  all stages      {before_total / 1e6:7.1f} MB -> {after_total / 1e6:7.1f} MB")
    print(f"  distinct bytes  {distinct_before / 1e6:7.1f} MB -> {distinct_after / 1e6:7.1f} MB"
          f"   ({len(groups_before)} -> {len(groups_after)} distinct weight files)")

    if shared_before != shared_after:
        print("\nFAILED: the sharing groups changed, so the phone's hard-link dedupe would break.",
              file=sys.stderr)
        print(f"  before: {sorted(shared_before)}\n  after:  {sorted(shared_after)}", file=sys.stderr)
        return 1

    print("\n  sharing groups unchanged — the hard-link dedupe still applies.")
    print(f"\nWrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
