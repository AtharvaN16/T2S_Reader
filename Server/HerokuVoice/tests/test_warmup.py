from __future__ import annotations

import numpy as np

from voice_service.main import WARM_UP_TEXT, build_app


class RecordingSynthesizer:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []

    def synthesize(self, text: str, voice: str) -> tuple[np.ndarray, int]:
        self.calls.append((text, voice))
        return np.zeros(2, dtype=np.float32), 24_000


class FailingSynthesizer(RecordingSynthesizer):
    def synthesize(self, text: str, voice: str) -> tuple[np.ndarray, int]:
        super().synthesize(text, voice)
        raise RuntimeError("cold")


def test_startup_renders_once_so_the_first_request_is_warm() -> None:
    made: list[RecordingSynthesizer] = []

    def factory(_model, _voices):
        synthesizer = RecordingSynthesizer()
        made.append(synthesizer)
        return synthesizer

    build_app({"T2S_VOICE_API_KEY": "k"}, synthesizer_factory=factory)

    assert made[0].calls == [(WARM_UP_TEXT, "af_heart")]


def test_a_failed_warm_up_does_not_stop_the_app() -> None:
    app = build_app({"T2S_VOICE_API_KEY": "k"}, synthesizer_factory=lambda _m, _v: FailingSynthesizer())

    assert app is not None
