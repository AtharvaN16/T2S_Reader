from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike


def float32_to_pcm16(samples: ArrayLike) -> bytes:
    values = np.asarray(samples, dtype=np.float32)
    if values.ndim != 1 or values.size == 0 or not np.isfinite(values).all():
        raise ValueError("invalid audio samples")

    clipped = np.clip(values, -1.0, 1.0)
    scaled = np.where(clipped < 0, clipped * 32768.0, clipped * 32767.0)
    return np.rint(scaled).astype("<i2", copy=False).tobytes()
