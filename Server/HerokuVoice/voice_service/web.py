from __future__ import annotations

import secrets
import threading
from typing import Annotated, Literal, Protocol

import numpy as np
from fastapi import Depends, FastAPI, Header, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field, field_validator
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from .pcm import float32_to_pcm16
from .synthesizer import InputExpansionError


MAX_REQUEST_BYTES = 4096


class Synthesizer(Protocol):
    def synthesize(self, text: str, voice: str) -> tuple[np.ndarray, int]: ...


class SpeechRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: Literal["kokoro"]
    input: str = Field(min_length=1, max_length=400)
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


class SpeechRequestGuard:
    def __init__(self, app: ASGIApp, api_key: str, maximum_bytes: int = MAX_REQUEST_BYTES) -> None:
        self._app = app
        self._authorization = f"Bearer {api_key}".encode()
        self._maximum_bytes = maximum_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["path"] != "/v1/audio/speech":
            await self._app(scope, receive, send)
            return

        headers = {name.lower(): value for name, value in scope["headers"]}
        authorization = headers.get(b"authorization")
        if authorization is None or not secrets.compare_digest(authorization, self._authorization):
            await JSONResponse(
                {"detail": "Unauthorized"},
                status_code=status.HTTP_401_UNAUTHORIZED,
            )(scope, receive, send)
            return

        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            if message["type"] != "http.request":
                continue
            body.extend(message.get("body", b""))
            if len(body) > self._maximum_bytes:
                await JSONResponse(
                    {"detail": "Request too large"},
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                )(scope, receive, send)
                return
            if not message.get("more_body", False):
                break

        replayed = False

        async def replay_body() -> dict[str, object]:
            nonlocal replayed
            if replayed:
                return {"type": "http.request", "body": b"", "more_body": False}
            replayed = True
            return {"type": "http.request", "body": bytes(body), "more_body": False}

        await self._app(scope, replay_body, send)


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
    app.add_middleware(SpeechRequestGuard, api_key=api_key)

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
        except InputExpansionError as error:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Input expands beyond the synthesis limit",
            ) from error
        except Exception as error:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Synthesis unavailable",
            ) from error
        finally:
            synthesis_gate.leave()

    return app
