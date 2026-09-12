from __future__ import annotations

import hashlib

import pytest

from scripts.fetch_assets import Asset, install_asset


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def test_install_asset_downloads_and_verifies_the_exact_bytes(tmp_path) -> None:
    payload = b"pinned model bytes"
    source = tmp_path / "source.onnx"
    source.write_bytes(payload)
    destination = tmp_path / "models"

    install_asset(
        Asset("model.onnx", source.as_uri(), digest(payload)),
        destination,
    )

    assert (destination / "model.onnx").read_bytes() == payload
    assert list(destination.glob("*.part")) == []


def test_install_asset_rejects_a_digest_mismatch_without_installing(tmp_path) -> None:
    source = tmp_path / "source.onnx"
    source.write_bytes(b"tampered")
    destination = tmp_path / "models"

    with pytest.raises(ValueError, match="checksum mismatch"):
        install_asset(
            Asset("model.onnx", source.as_uri(), digest(b"expected")),
            destination,
        )

    assert not (destination / "model.onnx").exists()
    assert list(destination.glob("*.part")) == []


def test_install_asset_keeps_an_existing_verified_file_without_network(tmp_path) -> None:
    payload = b"already installed"
    source = tmp_path / "source.onnx"
    source.write_bytes(payload)
    destination = tmp_path / "models"
    asset = Asset("model.onnx", source.as_uri(), digest(payload))
    install_asset(asset, destination)
    source.unlink()

    install_asset(asset, destination)

    assert (destination / "model.onnx").read_bytes() == payload
