# Heroku Kokoro Eco Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy an authenticated, native-Python Kokoro speech endpoint on the purchased Heroku Eco plan and prove the existing iOS cloud route can consume its PCM.

**Architecture:** A small FastAPI service owns validation, authentication, single-flight admission, and PCM encoding. A separate `KokoroSynthesizer` owns the ONNX runtime so endpoint tests inject a deterministic fake without downloading the model. Heroku's Python build hook downloads and checksum-verifies pinned model assets into the slug.

**Tech Stack:** Python 3.12, FastAPI, Uvicorn, kokoro-onnx 0.6.1, NumPy, pytest, Heroku Cedar/Eco

**Spec:** `docs/superpowers/specs/2026-09-11-heroku-kokoro-pilot-design.md`

## Global Constraints

- Heroku Eco only; no add-ons, pinger, or automatic tier change.
- Native Heroku Python buildpack; no Docker.
- One Uvicorn process and at most one inference at a time.
- Bearer token, input text, and generated audio are never logged.
- Responses are raw 24 kHz mono signed 16-bit little-endian PCM.
- Model assets are pinned by URL and SHA-256 and downloaded during build.
- The repository's existing unrelated working-tree changes are not modified or committed.

---

### Task 1: HTTP Speech Contract

**Files:**
- Create: `Server/HerokuVoice/voice_service/web.py`
- Create: `Server/HerokuVoice/voice_service/pcm.py`
- Create: `Server/HerokuVoice/tests/test_web.py`

**Interfaces:**
- Consumes: a synthesizer exposing `synthesize(text: str, voice: str) -> tuple[numpy.ndarray, int]`
- Produces: `create_app(synthesizer, api_key, gate=None) -> FastAPI` and `float32_to_pcm16(samples) -> bytes`

- [ ] **Step 1: Write failing endpoint tests**

  Cover health readiness, missing/wrong bearer tokens, exact accepted request shape, rejected model/format/voice/empty or oversized input, little-endian PCM, and `429 Retry-After` while the gate is occupied. The fake synthesizer returns literal samples `[-1.0, 0.0, 0.5, 1.0]`.

- [ ] **Step 2: Verify the tests fail for missing production modules**

  Run: `python3.12 -m pytest Server/HerokuVoice/tests/test_web.py -q`

  Expected: collection fails because `voice_service.web` does not exist.

- [ ] **Step 3: Implement the minimum contract**

  `SpeechRequest` accepts only:

  ```python
  model: Literal["kokoro"]
  input: str = Field(min_length=1, max_length=1000)
  voice: Literal["af_heart"]
  response_format: Literal["pcm"]
  ```

  Authenticate with `secrets.compare_digest`, acquire a nonblocking `threading.Lock`, call the injected synthesizer, require rate `24000`, and return `Response(..., media_type="audio/pcm")`. PCM conversion clips to `[-1, 1]`, maps to signed 16-bit values, and explicitly emits little-endian bytes.

- [ ] **Step 4: Verify the endpoint tests pass**

  Run: `python3.12 -m pytest Server/HerokuVoice/tests/test_web.py -q`

  Expected: all endpoint tests pass.

### Task 2: Pinned Kokoro Runtime and Heroku Build

**Files:**
- Create: `Server/HerokuVoice/voice_service/synthesizer.py`
- Create: `Server/HerokuVoice/voice_service/main.py`
- Create: `Server/HerokuVoice/voice_service/__init__.py`
- Create: `Server/HerokuVoice/scripts/fetch_assets.py`
- Create: `Server/HerokuVoice/tests/test_assets.py`
- Create: `Server/HerokuVoice/tests/test_synthesizer.py`
- Create: `Server/HerokuVoice/requirements.txt`
- Create: `Server/HerokuVoice/requirements-dev.txt`
- Create: `Server/HerokuVoice/.python-version`
- Create: `Server/HerokuVoice/Procfile`
- Create: `Server/HerokuVoice/bin/post_compile`

**Interfaces:**
- Consumes: `create_app` from Task 1 and Heroku config var `T2S_VOICE_API_KEY`
- Produces: importable `voice_service.main:app`, verified files under `models/`, and Heroku's web command

- [ ] **Step 1: Write failing runtime and asset tests**

  Prove that the downloader rejects the wrong digest and atomically installs a file with the expected digest. Prove `KokoroSynthesizer` passes `text`, `voice`, `speed=1.0`, and `lang="en-us"` to an injected Kokoro factory and returns its samples and rate.

- [ ] **Step 2: Verify the new tests fail**

  Run: `python3.12 -m pytest Server/HerokuVoice/tests/test_assets.py Server/HerokuVoice/tests/test_synthesizer.py -q`

  Expected: collection fails because the runtime modules do not exist.

- [ ] **Step 3: Implement runtime and deployment files**

  Pin `kokoro-onnx==0.6.1`, FastAPI, Uvicorn, and compatible transitive versions. Download these release assets and verify their published digests:

  ```text
  kokoro-v1.0.int8.onnx
  sha256 ae315a79b623f244700e4afb9246c46a26066782e049ba174bf3ba433970ee9c
  voices-v1.0.bin
  sha256 bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d
  ```

  `main.py` must fail closed when the API key or assets are absent. `Procfile` binds Uvicorn to `$PORT`, uses one worker, and disables access logging.

- [ ] **Step 4: Verify all service tests pass**

  Run: `python3.12 -m pytest Server/HerokuVoice/tests -q`

  Expected: all service tests pass.

- [ ] **Step 5: Run one real-model smoke render**

  Run the asset fetcher, instantiate `KokoroSynthesizer`, synthesize a short Heart sentence, and verify rate `24000`, nonempty finite samples, and valid PCM output.

### Task 3: Eco Deployment and Live Verification

**Files:**
- Create: `Server/HerokuVoice/README.md`
- Modify: `docs/HANDOFF.md`

**Interfaces:**
- Consumes: tested service from Tasks 1–2 and authenticated Heroku CLI
- Produces: a new personal Cedar app on Eco with endpoint `/v1/audio/speech`

- [ ] **Step 1: Commit only the service, tests, plan, and handoff**

  Check `git diff --cached --check` and ensure none of the pre-existing Core ML, scheduler, playback, or handoff hunks are accidentally staged.

- [ ] **Step 2: Create and configure the Heroku app**

  Create a unique personal app on `heroku-24`, set the Python buildpack, set a generated `T2S_VOICE_API_KEY` without printing it, and deploy only `Server/HerokuVoice`. Scale exactly one `web` process to `eco`.

- [ ] **Step 3: Verify live health and PCM**

  Confirm `/health` returns `200`; an unauthenticated synthesis returns `401`; an authenticated Heart synthesis returns `200`, `audio/pcm`, an even nonzero byte count, and audio duration consistent with 24 kHz mono PCM.

- [ ] **Step 4: Verify Eco memory and pricing boundaries**

  Inspect runtime metrics and logs for R14/R15, boot timeout, request timeout, and actual RSS. Confirm process formation shows one Eco web dyno and no add-ons.

- [ ] **Step 5: Connect the iOS cloud route**

  Enter the endpoint, model `kokoro`, voice `af_heart`, conservative request rate, and bearer token through Cloud voices on each phone. Render a preview and play a document long enough to prove cache fill without an on-device Kokoro request.

- [ ] **Step 6: Handle a failed Eco acceptance test**

  If the dyno exceeds memory or cannot synthesize within the client timeout, scale `web=0`, preserve logs, and report the measured blocker. Do not upgrade.
