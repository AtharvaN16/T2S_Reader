# T2S Heroku Voice

Native Python Kokoro service for the T2S Reader Eco pilot. It implements the
OpenAI-compatible request shape already used by `HTTPVoiceEngine` and returns
raw 24 kHz mono PCM.

## Local verification

```bash
uv venv .venv --python 3.12
uv pip install --python .venv/bin/python -r requirements-dev.txt
.venv/bin/python scripts/fetch_assets.py
PYTHONPATH=. .venv/bin/python -m pytest tests -q
```

Run the service with a local secret:

```bash
T2S_VOICE_API_KEY="$(openssl rand -hex 32)" \
  .venv/bin/uvicorn voice_service.main:build_app \
  --factory --host 127.0.0.1 --port 8880 --workers 1 --no-access-log
```

## Heroku

Deploy this directory as the app root with the Heroku Python buildpack. The
`bin/post_compile` hook puts checksum-verified model assets in the slug, so
dyno boots do not contact Hugging Face or GitHub.

Required config:

```text
T2S_VOICE_API_KEY=<random high-entropy value>
```

The pilot formation is exactly one Eco web dyno. Do not add a keepalive,
database, paid add-on, or automatic tier change.

Configure each phone under **Preferences → Cloud voices**:

```text
Endpoint: https://<app>.herokuapp.com/v1/audio/speech
Model: kokoro
Provider voice: af_heart
Request rate: 20/min
API key: the T2S_VOICE_API_KEY value
```

Secrets and input text must not appear in source control or logs.

## Mirrors

One dyno renders at about 2.7x realtime, and one app cannot run more than one web
dyno on the small tiers, so the route runs on several identical apps.
`scripts/mirrors.sh [count]` (default 4) deploys this directory to `kokoro-t2s`,
`kokoro-t2s-m2`, … from one `git subtree split`, sets the same key on each from
`~/.t2s/heroku-voice-key` (mode 0600, never printed), scales each to exactly
`web=1:basic` — a Basic dyno never sleeps, so every mirror stays warm ($7 each;
the owner's decision of 2026-09-12, up to $50 a month) — and verifies health, an
authenticated render, the dyno size, and that there are no add-ons. It is safe to
re-run, and a larger count adds mirrors without touching the existing ones.

The app ships every mirror's `/v1/audio/speech` URL (`CloudVoiceDefaults.pilot`);
the first is the route's identity and the rest are interchangeable with it. The
render scheduler holds one request in flight per mirror.
