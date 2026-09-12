from __future__ import annotations

from pathlib import Path

import numpy as np
import onnxruntime as ort

from voice_service.synthesizer import (
    KokoroSynthesizer,
    low_memory_session_options,
    split_text,
)


class FakeKokoro:
    def __init__(self) -> None:
        self.calls: list[dict[str, object]] = []

    def create(
        self,
        text: str,
        *,
        voice: str,
        speed: float,
        lang: str,
    ) -> tuple[np.ndarray, int]:
        self.calls.append(
            {
                "text": text,
                "voice": voice,
                "speed": speed,
                "lang": lang,
            }
        )
        return np.array([0.25, -0.25], dtype=np.float32), 24_000


def test_synthesizer_loads_pinned_paths_and_uses_the_server_voice_contract(tmp_path) -> None:
    model = tmp_path / "model.onnx"
    voices = tmp_path / "voices.bin"
    model.write_bytes(b"model")
    voices.write_bytes(b"voices")
    fake = FakeKokoro()
    factory_calls: list[tuple[Path, Path]] = []

    def factory(model_path: Path, voices_path: Path) -> FakeKokoro:
        factory_calls.append((model_path, voices_path))
        return fake

    synthesizer = KokoroSynthesizer(model, voices, kokoro_factory=factory)
    samples, rate = synthesizer.synthesize("Read this.", "af_heart")

    assert factory_calls == [(model, voices)]
    assert fake.calls == [
        {
            "text": "Read this.",
            "voice": "af_heart",
            "speed": 1.0,
            "lang": "en-us",
        }
    ]
    assert rate == 24_000
    np.testing.assert_array_equal(samples, np.array([0.25, -0.25], dtype=np.float32))


def test_synthesizer_fails_before_loading_when_an_asset_is_missing(tmp_path) -> None:
    missing_model = tmp_path / "missing.onnx"
    voices = tmp_path / "voices.bin"
    voices.write_bytes(b"voices")
    factory_called = False

    def factory(model_path: Path, voices_path: Path) -> FakeKokoro:
        nonlocal factory_called
        factory_called = True
        return FakeKokoro()

    try:
        KokoroSynthesizer(missing_model, voices, kokoro_factory=factory)
    except FileNotFoundError as error:
        assert error.filename == str(missing_model)
    else:
        raise AssertionError("missing model was accepted")

    assert not factory_called


def test_split_text_bounds_every_inference_without_losing_words() -> None:
    text = " ".join(["abcdefghij"] * 30)

    chunks = split_text(text, max_characters=120)

    assert len(chunks) == 3
    assert all(1 <= len(chunk) <= 120 for chunk in chunks)
    assert " ".join(chunks) == text


def test_split_text_bounds_a_single_unbroken_token() -> None:
    text = "x" * 251

    chunks = split_text(text, max_characters=120)

    assert [len(chunk) for chunk in chunks] == [120, 120, 11]
    assert "".join(chunks) == text


def test_synthesizer_renders_long_input_as_bounded_calls(tmp_path) -> None:
    model = tmp_path / "model.onnx"
    voices = tmp_path / "voices.bin"
    model.write_bytes(b"model")
    voices.write_bytes(b"voices")
    fake = FakeKokoro()
    synthesizer = KokoroSynthesizer(
        model,
        voices,
        kokoro_factory=lambda _model, _voices: fake,
    )
    text = " ".join(["abcdefghij"] * 30)

    samples, rate = synthesizer.synthesize(text, "af_heart")

    assert rate == 24_000
    assert len(fake.calls) == 5
    assert all(len(str(call["text"])) <= 80 for call in fake.calls)
    assert " ".join(str(call["text"]) for call in fake.calls) == text
    assert len(samples) > sum(2 for _ in fake.calls)


def test_eco_session_uses_one_thread_without_retained_cpu_arenas() -> None:
    options = low_memory_session_options()

    assert options.intra_op_num_threads == 1
    assert options.inter_op_num_threads == 1
    assert options.execution_mode == ort.ExecutionMode.ORT_SEQUENTIAL
    assert options.enable_cpu_mem_arena is False
    assert options.enable_mem_pattern is False
