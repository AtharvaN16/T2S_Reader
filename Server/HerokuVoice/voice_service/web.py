from __future__ import annotations

import secrets
import threading
from typing import Annotated, Literal, Protocol

import numpy as np
from fastapi import Depends, FastAPI, Header, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field, field_validator

from .pcm import float32_to_pcm16


class Synthesizer(Protocol):
    def synthesize(self, text: str, voice: str) -> tuple[np.ndarray, int]: ...


class SpeechRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: Literal["kokoro"]
    input: str = Field(min_length=1, max_length=1000)
    voice: Literal["af_heart"]
    response_format: Literal["pcm"]

    @field_validator("input")
    @classmethod
    def require_spoken_text(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("input must contain spoken text")
        return value


class SynthesisGate:
    def __init__(self) -> None:
        self._lock = threading.Lock()

    def try_enter(self) -> bool:
        return self._lock.acquire(blocking=False)

    def leave(self) -> None:
        self._lock.release()


def create_app(
    synthesizer: Synthesizer,
    api_key: str,
    gate: SynthesisGate | None = None,
) -> FastAPI:
    if not api_key:
        raise ValueError("T2S_VOICE_API_KEY is required")

    synthesis_gate = gate or SynthesisGate()
    app = FastAPI(
        title="T2S Kokoro Voice",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )

    def authorize(authorization: Annotated[str | None, Header()] = None) -> None:
        expected = f"Bearer {api_key}"
        if authorization is None or not secrets.compare_digest(authorization, expected):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ready"}

    @app.post("/v1/audio/speech")
    def speech(request: SpeechRequest, _: None = Depends(authorize)) -> Response:
        if not synthesis_gate.try_enter():
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Synthesis busy",
                headers={"Retry-After": "2"},
            )

        try:
            samples, sample_rate = synthesizer.synthesize(request.input, request.voice)
            if sample_rate != 24_000:
                raise ValueError("unexpected sample rate")
            return Response(content=float32_to_pcm16(samples), media_type="audio/pcm")
        except Exception as error:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Synthesis unavailable",
            ) from error
        finally:
            synthesis_gate.leave()

    return app
