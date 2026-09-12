from __future__ import annotations

import logging
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
    warm_up(synthesizer)
    return create_app(synthesizer, api_key=api_key)


WARM_UP_TEXT = "Ready."


def warm_up(synthesizer: Synthesizer) -> None:
    """One short render before the first request.

    The first inference pays for the runtime's lazy setup — the phonemizer, the
    session's first run — and on a dyno that had just booted it pushed the first
    real request past the router's 30 s. A failure here is logged by type only
    and the app still serves; the first request then pays it, as before.
    """
    try:
        synthesizer.synthesize(WARM_UP_TEXT, "af_heart")
    except Exception as error:  # noqa: BLE001 - the app must come up either way
        logging.getLogger("voice_service").warning("warm-up render failed: %s", type(error).__name__)
