from __future__ import annotations

import ctypes
import ctypes.util
import errno
import os
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Protocol

import numpy as np
import onnxruntime as ort


class InputExpansionError(ValueError):
    pass


class TokenizerRuntime(Protocol):
    def phonemize(self, text: str, lang: str) -> str: ...


class KokoroRuntime(Protocol):
    tokenizer: TokenizerRuntime

    def create(
        self,
        text: str,
        *,
        voice: str,
        speed: float,
        lang: str,
        is_phonemes: bool,
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


def _load_malloc_trim() -> Callable[[], None]:
    """glibc's malloc_trim, or a no-op everywhere it does not exist."""
    if not sys.platform.startswith("linux"):
        return lambda: None
    name = ctypes.util.find_library("c")
    if name is None:
        return lambda: None
    try:
        libc = ctypes.CDLL(name, use_errno=False)
        trim = libc.malloc_trim
    except (OSError, AttributeError):
        return lambda: None
    trim.argtypes = [ctypes.c_size_t]
    trim.restype = ctypes.c_int
    return lambda: trim(0)


_malloc_trim = _load_malloc_trim()


def release_memory() -> None:
    """Hand pages freed by the last inference back to the operating system.

    ONNX Runtime frees its per-inference buffers, but glibc keeps the pages
    mapped, so resident size ratchets up across a multi-chunk render and never
    comes back down. The dyno is billed on the high-water mark, not on what is
    live, so the pages are returned between inferences.
    """
    _malloc_trim()


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
        release_memory: Callable[[], None] = release_memory,
    ) -> None:
        for path in (model_path, voices_path):
            if not path.is_file():
                raise FileNotFoundError(errno.ENOENT, os.strerror(errno.ENOENT), str(path))
        self._kokoro = kokoro_factory(model_path, voices_path)
        self._release_memory = release_memory

    def synthesize(self, text: str, voice: str) -> tuple[np.ndarray, int]:
        parts: list[np.ndarray] = []
        sample_rate = 24_000
        phonemes = self._kokoro.tokenizer.phonemize(text, "en-us")
        if len(phonemes) > 600:
            raise InputExpansionError
        for index, chunk in enumerate(split_text(phonemes)):
            samples, rate = self._kokoro.create(
                chunk,
                voice=voice,
                speed=1.0,
                lang="en-us",
                is_phonemes=True,
            )
            if rate != sample_rate:
                raise ValueError("unexpected sample rate")
            if index:
                parts.append(np.zeros(int(sample_rate * 0.08), dtype=np.float32))
            parts.append(np.asarray(samples, dtype=np.float32))
            self._release_memory()
        if not parts:
            raise ValueError("no spoken text")
        return np.concatenate(parts), sample_rate
