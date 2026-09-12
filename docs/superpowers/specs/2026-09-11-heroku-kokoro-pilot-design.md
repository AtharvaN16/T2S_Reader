# Heroku Kokoro Eco Pilot

## Goal

Prove that the existing iOS cloud-voice path can use Kokoro without sustained
on-device inference. The pilot runs only on the already-purchased Heroku Eco
plan. It must not create paid add-ons or change dyno tier automatically.

## Scope

This phase deploys a production-shaped pilot service and connects it through
the app's existing Cloud voices settings. It does not yet remove the on-device
Kokoro implementation or make the hosted route the default for every reader.
Those changes depend on measured Eco latency and memory use.

## Service

`Server/HerokuVoice` is a native Heroku Python application, not a Docker image.
It runs FastAPI with one Uvicorn process and `kokoro-onnx` on CPU.

- `GET /health` reports process readiness without exposing configuration.
- `POST /v1/audio/speech` accepts the four fields already sent by
  `HTTPVoiceEngine`: `model`, `input`, `voice`, and `response_format`.
- The only model name is `kokoro`; the initial voice is `af_heart`.
- Successful responses are raw 24 kHz, mono, signed 16-bit little-endian PCM.
- A bearer token stored in a Heroku config var protects synthesis. The token,
  request text, and generated audio are never logged.
- Input length, model, voice, and output format are allowlisted before
  inference. Invalid requests fail without running the model.
- One synthesis runs at a time. A request received while inference is occupied
  gets `429` and `Retry-After`, which the existing iOS client already handles.

## Model and Build

The build uses Python 3.12 and pinned package versions. A Python buildpack
`bin/post_compile` hook downloads the pinned Kokoro v1.0 INT8 ONNX model and
voice table into the slug and verifies both SHA-256 digests. Dyno starts never
download model files from the network.

The INT8 artifact is used because Eco has 512 MB RAM. This is independent of
the Core ML INT8 model that crashed on iOS: inference occurs in Linux ONNX
Runtime, and only PCM reaches the phone. Voice quality, render speed, and peak
RSS are acceptance measurements rather than assumptions.

## iOS Connection

For the pilot, each phone receives the generated endpoint and bearer token
through the existing Cloud voices screen:

- endpoint: the new Heroku app's `/v1/audio/speech`
- model: `kokoro`
- voice: `af_heart`
- request rate: a conservative server-compatible value

The token is stored in the existing Keychain-backed secret store. It is not
committed to the repository or embedded in the app binary.

## Eco Behavior and Acceptance

Eco may sleep after 30 minutes without traffic. The pilot accepts the cold
start and does not add an artificial keepalive. Playback must surface the
existing recoverable cloud error rather than switch narrator automatically.

The deployment is accepted when:

1. Unit tests prove authentication, validation, busy handling, and exact PCM.
2. A local real-model render proves the pinned model and voice assets work.
3. The Eco dyno boots without R14/R15 errors, reports its actual peak RSS, and
   answers health checks.
4. A live synthesis returns valid 24 kHz PCM.
5. Both phones can select the hosted Heart voice and play cached audio without
   invoking the on-device Kokoro route.

If Eco cannot meet memory or latency requirements, the dyno is scaled to zero.
No paid upgrade is performed without a separate decision.
