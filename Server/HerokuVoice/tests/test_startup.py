from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest
from fastapi.testclient import TestClient

from voice_service.main import build_app


class StartupSynthesizer:
    def synthesize(self, text: str, voice: str) -> tuple[np.ndarray, int]:
        return np.array([0.0], dtype=np.float32), 24_000


def test_build_app_fails_closed_without_a_server_api_key(tmp_path) -> None:
    with pytest.raises(ValueError, match="T2S_VOICE_API_KEY"):
        build_app(environ={"T2S_MODEL_DIR": str(tmp_path)})


def test_build_app_loads_only_the_pinned_asset_names(tmp_path) -> None:
    model = tmp_path / "kokoro-v1.0.int8.onnx"
    voices = tmp_path / "voices-v1.0.bin"
    model.write_bytes(b"model")
    voices.write_bytes(b"voices")
    calls: list[tuple[Path, Path]] = []

    def factory(model_path: Path, voices_path: Path) -> StartupSynthesizer:
        calls.append((model_path, voices_path))
        return StartupSynthesizer()

    app = build_app(
        environ={
            "T2S_VOICE_API_KEY": "server-secret",
            "T2S_MODEL_DIR": str(tmp_path),
        },
        synthesizer_factory=factory,
    )

    assert calls == [(model, voices)]
    assert TestClient(app).get("/health").json() == {"status": "ready"}
