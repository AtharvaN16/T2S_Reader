# Eco Voice Mirrors

## Goal

Make the hosted Kokoro route keep up with playback on the purchased $5 Heroku
Eco plan by running several identical Eco apps and rendering several
utterances at once across them. No tier above Eco, no add-ons, no pinger.

## Why

Measured on 2026-09-11 (`docs/superpowers/evidence/2026-09-11-heroku-eco-measurements.log`):

- One Eco dyno renders at about 2.7x realtime. Playback outruns it.
- Standard-2X at $50 measured 2.55x untuned and 1.96x with two threads and
  the memory arena on. It still loses to playback. A dedicated core starts at
  $250, which is out.
- One app cannot run more than one Eco web dyno (`cannot_update_above_limit`),
  but the Eco fee is an account-wide pool of 1000 dyno-hours shared by every
  Eco app, so four apps with one dyno each cost the same $5.
- Heroku's router spreads requests across dynos; it never splits one. Four
  mirrors give four renders in flight, not one render four times faster.
  Per-utterance latency stays about 14 s; aggregate throughput becomes
  4 / 2.7 = 0.68x, which keeps ahead of playback. Three would be 0.90x,
  too thin a margin for the same $5.

The render scheduler is strictly serial (reader design spec §3.4). Routing
requests across mirrors changes nothing until the scheduler can hold more
than one render in flight. That is the change this spec makes.

## Scope

In: four mirror apps deployed from one script; a configuration that names
several endpoints; a scheduler that renders a bounded batch concurrently
when the engine allows it; an HTTP engine that spreads a batch across
mirrors and keeps long utterances under Eco's ceiling.

Out: server streaming and faster first sound (its own follow-up spec);
streaming `.piece` events from the HTTP engine; any change to utterance
segmentation; any dyno above Eco.

## Server

The service under `Server/HerokuVoice` is unchanged except for one
hardening fix: the validation error for a rejected request body no longer
echoes the request text. It returns a fixed `detail` string.

`scripts/mirrors.sh` deploys the same subtree to N apps and is safe to
re-run:

- Apps are `kokoro-t2s` (the existing primary) and `kokoro-t2s-2` … `-N`.
  Each is created on `heroku-24` with the Python buildpack if absent.
- Every app receives the same `T2S_VOICE_API_KEY`, read from a local
  `0600` file and never printed, plus `MALLOC_ARENA_MAX=2` and
  `PYTHONUNBUFFERED=1`. Neither ONNX tuning variable is set: Eco keeps one
  thread and no arena, the settings its 512 MB survives.
- `log-runtime-metrics` is enabled on each.
- The subtree is split once with `git subtree split` and the resulting
  commit is pushed to every app's remote, so all mirrors run one build.
- Each app is scaled to exactly `web=1:eco`, then verified: `/health`
  returns 200 and an authenticated short render returns `audio/pcm`.

Mirrors are declared identical: same build, same model digests, same key.
Nothing on the client distinguishes their output.

## Client configuration

`HTTPVoiceConfiguration` holds `endpoints: [URL]`, at least one. The first
is the primary; the rest are mirrors. `endpoint` remains as a computed
alias for the first so existing call sites and tests read unchanged, and a
convenience initializer still accepts a single `endpoint:`.

- `validate()` applies the existing rule to every endpoint: HTTPS, a host,
  no credentials, no query, no fragment. Duplicate endpoints are invalid.
- `fingerprint` covers the primary endpoint only. Adding or removing a
  mirror does not change the route's identity, so cached audio survives.
  Changing the primary does, exactly as before.
- `requestRatePerMinute` applies to each endpoint separately.

`CloudVoiceSettings` keeps one `endpointText`, now one URL per line; the
first line is the primary. A stored single-line value parses as one
endpoint, so existing installs are unaffected. The Cloud voices screen's
endpoint field becomes a vertical-axis text field and its caption says
that extra lines are identical mirrors of the first. The Keychain key is
unchanged: one secret, shared by all mirrors.

`RoutedEngine`'s cache key for a built `HTTPVoiceEngine` includes every
endpoint, so editing the mirror list rebuilds the engine even though the
fingerprint is stable.

## Engine concurrency contract

`SynthesisEngine` gains

```swift
func maxConcurrentRenders(for voiceID: String) -> Int
```

with a protocol extension default of 1. `HTTPVoiceEngine` returns its
endpoint count. `RoutedEngine` answers without touching actor state: the
configured endpoint count for a cloud voice ID, 1 for every other route.
The on-device engines keep the default, so the Kokoro path is unchanged
by construction.

## Scheduler

`RenderScheduler` renders a bounded batch instead of one request:

- Each turn of the loop asks the engine for the width of the first pending
  request's voice, takes up to that many requests from the front of
  `pending`, and renders them concurrently. A batch never spans tiers, so
  a new urgent plan waits behind at most one batch of its own tier, never
  behind prepare work. Width 1 is today's behavior, and the existing
  scheduler suite must pass unchanged.
- The arbiter lease is held once for the whole batch, at the tier of its
  first request. Preemption granularity for the cloud route becomes the
  batch; for on-device engines it stays one utterance because their width
  is 1.
- Outcomes are applied in submission order so tests are deterministic. The
  coordinator already tolerates `.rendered` arriving out of plan order (a
  cache hit does that today), so nothing there changes.
- A streaming head request inside a batch still yields its `.piece` events
  as they arrive.
- `storeFull` from any member pauses the scheduler once; the rest of the
  batch finishes, and their outcomes are applied before the pause takes
  effect.
- The real-time factor is recorded per batch: the batch's wall time over
  the sum of the durations actually synthesized in it. Cache hits
  contribute neither time nor duration, and a batch that synthesized
  nothing records no sample. For width 1 that is the value recorded
  today. It is what the coordinator's rate control should see, because
  aggregate throughput, not one mirror's latency, is what keeps playback
  fed.
- Foreground-fill pacing is computed from the last render in a batch. The
  cloud route has no fill rate, and the on-device route has width 1, so
  the two never combine.

## HTTP engine

`HTTPVoiceEngine` owns one `RequestRateLimiter` per endpoint and a pool of
the endpoints free of its own requests. Each request takes a free endpoint
and waits for one when all are busy, so the engine never sends a mirror a
second request while its first is in flight, whatever adds requests beyond
the batch — a long utterance's pieces, a voice preview, a prime. Released
endpoints go to the back, so requests rotate through every mirror.

- A `429` from a mirror defers only that mirror's limiter and moves the
  request on to the next mirror; each mirror is tried at most once per
  request. Only when every mirror has answered `429` does the request
  fail with `rateLimited`, which the scheduler turns into the failure
  silence as before.
- Text longer than `maxRequestCharacters` (180) is split at clause
  boundaries, then whitespace, then a hard cut, using the same rule the
  segmenter applies; that rule moves to a small public helper in
  `T2SCore` that the segmenter now calls. The pieces are sent concurrently
  and their audio concatenated in order. A split request returns no word
  timings; the pilot server never sends any. 180 is chosen because Eco's
  30 s router timeout was measured at about 210 characters.
- `synthesizeStreaming` keeps the protocol default: one piece, then
  finished.

## Failure behavior

Nothing here changes what the reader hears on failure. A request that
fails on every mirror, or a transport error, still yields the 200 ms
failure silence under the utterance's key (reader design spec §6). What
this design removes is the H12 and R14 failures that a long sentence used
to cause, by keeping every request under the measured ceiling.

Eco sleep is still accepted. A batch sent to sleeping mirrors wakes them
all at once, so the first utterance after half an hour idle waits one
dyno boot plus one render, about 35 s, then the route runs at full width.

## Testing

Unit, before any deploy:

- `HTTPVoiceConfiguration`: validation runs over every endpoint; the
  fingerprint ignores mirrors and changes with the primary; the single
  endpoint initializer still works.
- `CloudVoiceSettings`: multi-line text parses in order; a one-line value
  is one endpoint.
- `HTTPVoiceEngine`, with `TestURLProtocol` extended to capture every
  request and answer per host: N concurrent calls reach N distinct
  mirrors; a `429` on one mirror retries once on the next; a 400-character
  input is split into pieces of at most 180 characters at clause
  boundaries, sent concurrently, and concatenated in order.
- `SynthesisEngine`: default width is 1; `RoutedEngine` reports the
  endpoint count for a cloud voice and 1 otherwise, and rebuilds the HTTP
  engine when the mirror list changes.
- `RenderScheduler`, with `FakeEngine` gaining a configurable width and an
  in-flight count: width 4 holds four renders in flight at once; the
  existing suite passes unchanged; `storeFull` inside a batch pauses once;
  the recorded RTF is the batch's.
- `Server/HerokuVoice`: the validation error carries no request text.

Live, on the mirrors:

1. `scripts/mirrors.sh` leaves four apps at `web=1:eco`, each answering
   `/health` and an authenticated render.
2. A phone with four URLs in Cloud voices plays a chapter through with no
   stall after the first utterance.
3. `heroku logs` across all four show no `R14`, `R15`, or `H12` during the
   run, and the measured aggregate throughput is reported.
4. `heroku ps` on each shows exactly one Eco dyno and no add-ons; Eco hours
   consumed by the run are reported.

## Acceptance

Accepted when every unit test above passes, the on-device suites pass
unchanged, and live checks 1 to 4 hold. If aggregate throughput still
cannot keep a chapter playing, every mirror is scaled to `web=0`, the
logs are kept, and the measured blocker is reported. No paid upgrade.

## Constraints

- Eco only. The script refuses any dyno size other than `eco`.
- The Eco pool is 1000 dyno-hours a month across all four apps, and a
  mirror consumes hours only while awake. A few hours of reading a day is
  a few hundred pool hours; keeping four mirrors awake around the clock
  would exceed the pool in about ten days. The live run reports hours
  consumed so the rate is known.
- The bearer token, request text, and audio are never logged, on any
  mirror or in the deploy script.
- `RenderScheduler.swift` and its tests carry uncommitted phone-thermal
  work (foreground-fill pacing). This design is written against that
  working tree. Before implementation the owner chooses whether that work
  is committed first or lands with this one.
