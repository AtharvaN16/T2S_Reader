from __future__ import annotations

import numpy as np
import pytest
from fastapi.testclient import TestClient

from voice_service.web import SynthesisGate, create_app


class FakeSynthesizer:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []

    def synthesize(self, text: str, voice: str) -> tuple[np.ndarray, int]:
        self.calls.append((text, voice))
        return np.array([-1.0, 0.0, 0.5, 1.0], dtype=np.float32), 24_000


def make_client(
    synthesizer: FakeSynthesizer | None = None,
    gate: SynthesisGate | None = None,
) -> tuple[TestClient, FakeSynthesizer]:
    engine = synthesizer or FakeSynthesizer()
    return TestClient(create_app(engine, api_key="pilot-secret", gate=gate)), engine


def valid_request() -> dict[str, str]:
    return {
        "model": "kokoro",
        "input": "Hello from Heart.",
        "voice": "af_heart",
        "response_format": "pcm",
    }


def test_health_reports_readiness_without_auth_or_configuration() -> None:
    client, _ = make_client()

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ready"}
    assert "pilot-secret" not in response.text


@pytest.mark.parametrize(
    "authorization",
    [None, "Bearer wrong-secret", "Basic pilot-secret", "Bearer"],
)
def test_speech_rejects_missing_or_wrong_bearer_token(authorization: str | None) -> None:
    client, engine = make_client()
    headers = {} if authorization is None else {"Authorization": authorization}

    response = client.post("/v1/audio/speech", headers=headers, json=valid_request())

    assert response.status_code == 401
    assert response.json() == {"detail": "Unauthorized"}
    assert engine.calls == []


def test_speech_checks_authentication_before_parsing_the_body() -> None:
    client, engine = make_client()

    response = client.post(
        "/v1/audio/speech",
        headers={"Content-Type": "application/json"},
        content=b'{"input":',
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Unauthorized"}
    assert engine.calls == []


def test_speech_rejects_an_oversized_body_before_json_parsing() -> None:
    client, engine = make_client()

    response = client.post(
        "/v1/audio/speech",
        headers={
            "Authorization": "Bearer pilot-secret",
            "Content-Type": "application/json",
        },
        content=b"{" + (b"x" * 4096) + b"}",
    )

    assert response.status_code == 413
    assert response.json() == {"detail": "Request too large"}
    assert engine.calls == []


def test_speech_returns_exact_little_endian_pcm_contract() -> None:
    client, engine = make_client()

    response = client.post(
        "/v1/audio/speech",
        headers={"Authorization": "Bearer pilot-secret"},
        json=valid_request(),
    )

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/pcm"
    assert response.content == bytes([0x00, 0x80, 0x00, 0x00, 0x00, 0x40, 0xFF, 0x7F])
    assert engine.calls == [("Hello from Heart.", "af_heart")]


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("model", "other"),
        ("voice", "af_sarah"),
        ("response_format", "wav"),
        ("input", ""),
        ("input", " \n\t "),
        ("input", "x" * 401),
    ],
)
def test_speech_rejects_values_outside_the_pilot_contract(field: str, value: str) -> None:
    client, engine = make_client()
    body = valid_request()
    body[field] = value

    response = client.post(
        "/v1/audio/speech",
        headers={"Authorization": "Bearer pilot-secret"},
        json=body,
    )

    assert response.status_code == 422
    assert engine.calls == []


def test_speech_rejects_unknown_request_fields() -> None:
    client, engine = make_client()
    body = valid_request()
    body["instructions"] = "Leak this into a log"

    response = client.post(
        "/v1/audio/speech",
        headers={"Authorization": "Bearer pilot-secret"},
        json=body,
    )

    assert response.status_code == 422
    assert engine.calls == []


def test_speech_returns_retry_after_without_queuing_when_busy() -> None:
    gate = SynthesisGate()
    assert gate.try_enter()
    client, engine = make_client(gate=gate)

    try:
        response = client.post(
            "/v1/audio/speech",
            headers={"Authorization": "Bearer pilot-secret"},
            json=valid_request(),
        )
    finally:
        gate.leave()

    assert response.status_code == 429
    assert response.headers["retry-after"] == "2"
    assert response.json() == {"detail": "Synthesis busy"}
    assert engine.calls == []


class WrongRateSynthesizer(FakeSynthesizer):
    def synthesize(self, text: str, voice: str) -> tuple[np.ndarray, int]:
        self.calls.append((text, voice))
        return np.array([0.0], dtype=np.float32), 22_050


def test_speech_hides_invalid_engine_output() -> None:
    client, _ = make_client(WrongRateSynthesizer())

    response = client.post(
        "/v1/audio/speech",
        headers={"Authorization": "Bearer pilot-secret"},
        json=valid_request(),
    )

    assert response.status_code == 503
    assert response.json() == {"detail": "Synthesis unavailable"}
