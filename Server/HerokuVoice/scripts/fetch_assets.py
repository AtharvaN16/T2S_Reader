from __future__ import annotations

import hashlib
import os
import shutil
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Asset:
    name: str
    url: str
    sha256: str


ASSETS = (
    Asset(
        "kokoro-v1.0.int8.onnx",
        "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/"
        "1939ad2a8e416c0acfeecc08a694d14ef25f2231/onnx/model_quantized.onnx",
        "fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478",
    ),
    Asset(
        "voices-v1.0.bin",
        "https://github.com/thewh1teagle/kokoro-onnx/releases/download/"
        "model-files-v1.1/voices-v1.0.bin",
        "bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d",
    ),
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def install_asset(asset: Asset, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / asset.name
    if target.is_file() and sha256_file(target) == asset.sha256:
        return

    temporary = destination / f".{asset.name}.{os.getpid()}.part"
    try:
        with urllib.request.urlopen(asset.url, timeout=120) as response:
            with temporary.open("wb") as output:
                shutil.copyfileobj(response, output, length=1024 * 1024)
        actual = sha256_file(temporary)
        if actual != asset.sha256:
            raise ValueError(
                f"checksum mismatch for {asset.name}: expected {asset.sha256}, got {actual}"
            )
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    destination = root / "models"
    for asset in ASSETS:
        print(f"Installing pinned asset {asset.name}", flush=True)
        install_asset(asset, destination)
    return 0


if __name__ == "__main__":
    sys.exit(main())
