from __future__ import annotations

import os
from collections.abc import Callable, Mapping
from pathlib import Path

from fastapi import FastAPI

from .synthesizer import KokoroSynthesizer
from .web import Synthesizer, create_app


SynthesizerFactory = Callable[[Path, Path], Synthesizer]


def build_app(
    environ: Mapping[str, str] | None = None,
    synthesizer_factory: SynthesizerFactory = KokoroSynthesizer,
) -> FastAPI:
    environment = os.environ if environ is None else environ
    api_key = environment.get("T2S_VOICE_API_KEY", "")
    if not api_key.strip():
        raise ValueError("T2S_VOICE_API_KEY is required")

    default_model_dir = Path(__file__).resolve().parents[1] / "models"
    model_dir = Path(environment.get("T2S_MODEL_DIR", str(default_model_dir)))
    synthesizer = synthesizer_factory(
        model_dir / "kokoro-v1.0.int8.onnx",
        model_dir / "voices-v1.0.bin",
    )
    return create_app(synthesizer, api_key=api_key)
