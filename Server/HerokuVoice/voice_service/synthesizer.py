from __future__ import annotations

import errno
import os
from collections.abc import Callable
from pathlib import Path
from typing import Protocol

import numpy as np
import onnxruntime as ort


class KokoroRuntime(Protocol):
    def create(
        self,
        text: str,
        *,
        voice: str,
        speed: float,
        lang: str,
    ) -> tuple[np.ndarray, int]: ...


KokoroFactory = Callable[[Path, Path], KokoroRuntime]


def split_text(text: str, max_characters: int = 80) -> list[str]:
    if max_characters < 1:
        raise ValueError("max_characters must be positive")

    chunks: list[str] = []
    current = ""
    for word in text.split():
        while len(word) > max_characters:
            if current:
                chunks.append(current)
                current = ""
            chunks.append(word[:max_characters])
            word = word[max_characters:]
        if not word:
            continue
        candidate = word if not current else f"{current} {word}"
        if len(candidate) <= max_characters:
            current = candidate
        else:
            chunks.append(current)
            current = word
    if current:
        chunks.append(current)
    return chunks


def low_memory_session_options() -> ort.SessionOptions:
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    options.enable_cpu_mem_arena = False
    options.enable_mem_pattern = False
    return options


def default_kokoro_factory(model_path: Path, voices_path: Path) -> KokoroRuntime:
    from kokoro_onnx import Kokoro

    session = ort.InferenceSession(
        str(model_path),
        sess_options=low_memory_session_options(),
        providers=["CPUExecutionProvider"],
    )
    return Kokoro.from_session(session, str(voices_path))


class KokoroSynthesizer:
    def __init__(
        self,
        model_path: Path,
        voices_path: Path,
        *,
        kokoro_factory: KokoroFactory = default_kokoro_factory,
    ) -> None:
        for path in (model_path, voices_path):
            if not path.is_file():
                raise FileNotFoundError(errno.ENOENT, os.strerror(errno.ENOENT), str(path))
        self._kokoro = kokoro_factory(model_path, voices_path)

    def synthesize(self, text: str, voice: str) -> tuple[np.ndarray, int]:
        parts: list[np.ndarray] = []
        sample_rate = 24_000
        for index, chunk in enumerate(split_text(text)):
            samples, rate = self._kokoro.create(
                chunk,
                voice=voice,
                speed=1.0,
                lang="en-us",
            )
            if rate != sample_rate:
                raise ValueError("unexpected sample rate")
            if index:
                parts.append(np.zeros(int(sample_rate * 0.08), dtype=np.float32))
            parts.append(np.asarray(samples, dtype=np.float32))
        if not parts:
            raise ValueError("no spoken text")
        return np.concatenate(parts), sample_rate
