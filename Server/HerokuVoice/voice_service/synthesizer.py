from __future__ import annotations

import errno
import os
from collections.abc import Callable
from pathlib import Path
from typing import Protocol

import numpy as np


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


def default_kokoro_factory(model_path: Path, voices_path: Path) -> KokoroRuntime:
    from kokoro_onnx import Kokoro

    return Kokoro(str(model_path), str(voices_path))


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
        return self._kokoro.create(
            text,
            voice=voice,
            speed=1.0,
            lang="en-us",
        )
