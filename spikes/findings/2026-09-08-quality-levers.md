# Sound quality without changing the model — what moves, what does not

_2026-09-08, on this Mac. Probe: `Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroLeverProbe.swift`
(enabled while `spikes/findings/lever-probe/` exists; WAVs and `report.md` land there, git-ignored),
pitch and pause numbers from `scripts/analyze-wav.swift`, codec round trips from a one-off script. The
owner's question: "we cannot change the model — are there other ways to improve the sound quality?"_

**Answer in short.** Two levers are real and cheap enough to ship (voice blends as new rows; the voice
list ordered by the author's own grades); one does exactly what it claims and is worth the owner's ears
(widening the pitch contour before the decoder); two that sound promising on the web do not survive
measurement on this pipeline (Opus through the system encoder; speech-enhancement models). On the way,
a crash in every debug build, fixed.

## What the model's author says (the ground under every lever)

- Of the 28 English voices, four are graded B- or better: `af_heart` A, `af_bella` A-, `af_nicole` B-,
  `bf_emma` B-. Everything else is C+ down to F+ (`am_adam`). The grade tracks training data: the A
  voices had hours, the D voices minutes. A voice picker that leads with the four is a quality lever
  by itself.
- "Most voices perform best on a goldilocks range of 100–200 tokens out of ~500 possible", with
  "weaknesses on short utterances and rushing on longer ones". The app's packing (`Segmenter.appPackLength`
  160 characters ≈ 157 ids) already sits inside that range — which also says the deferred 30 s bucket
  should not be used to send whole paragraphs in one call, only to spare the sentences past 176 ids
  their seam.

## 1. Voice blends — a new voice is a weighted sum of two style tables

A Kokoro voice is a 510×256 float table (`<name>.bin`, 522 240 bytes), one row per input length; the
engine picks row `len − 1`. The community tools (`nazdridoy/kokoro-tts` and the "voice maker" recipe
sites) make new voices by averaging two tables with weights, row by row. Nothing else changes: the same
model, the same call, the same cost; the render key already carries the voice name, so a blend caches
as its own voice. The probe rendered the four graded voices, three 50/50 blends of `af_heart` with
each of the other three, and one extrapolation past `af_bella` (`heart + 1.5 × (bella − heart)`).

| Render | Audio | Voiced | F0 median | Spread (SD) | 5–95 % range | Pauses ≥150 ms | Impulses | Author's grade |
|---|---|---|---|---|---|---|---|---|
| `af_heart` (the default) | 27.9 s | 43 % | 192 Hz | 4.2 st | 9.9 st | 17 | 3 | A |
| `af_bella` | 29.2 s | 50 % | 195 Hz | 4.5 st | 17.6 st¹ | 16 | 1 | A- |
| `af_nicole` | 39.9 s | 19 % | 152 Hz | 5.7 st | 17.0 st¹ | 20, up to 1.26 s | 13 | B- |
| `bf_emma` | 27.1 s | 44 % | 174 Hz | **2.1 st** | 5.9 st | 13 | 8 | B- |
| Heart + Bella, 50/50 | 28.3 s | 47 % | 194 Hz | 4.5 st | 17.6 st¹ | 15 | 5 | — |
| Heart → Bella, 150 % (extrapolated) | 30.2 s | 51 % | 198 Hz | 3.8 st | 7.5 st | 16 | 2 | — |
| Heart + Nicole, 50/50 | 32.8 s | 32 % | 174 Hz | 5.5 st | 18.5 st¹ | 18 | 14 | — |
| Heart + Emma, 50/50 | 27.1 s | 45 % | 180 Hz | 2.9 st | 7.7 st | 16 | 2 | — |

¹ The 5th percentile sits at 73–92 Hz for these — creak at phrase ends, or the tracker halving; the SD column is the safer number.

What this says:

- **Blending works mechanically and costs nothing**: every blend rendered cleanly (2–5 impulses, the same as its parents), and every measure lands between the parents. It is a way to make new voices, not a way to make a better one than the best parent — a blend of Heart and Bella keeps Heart's placement with Bella's range; a blend with Emma lowers and calms Heart.
- **The grades are about training, not expressiveness.** Emma is graded B- and is the flattest voice measured (2.1 st, half of Heart); Bella (A-) has the widest natural range of the narrator voices. Plan 9's impression that the British voices "read with more movement" does not survive the pitch tracker; if a reader wants movement, Bella is the measured answer.
- **Nicole is not a narrator.** 19 % voiced (breath and whisper), 43 % longer than Heart on the same text, pauses over a second. She also predicts more audio than the 15 s bucket holds for one packed utterance — which found a crash (below).
- **Extrapolation is unpredictable** (it *narrowed* the range and removed the creak): a curiosity, not a product feature.

## 2. Pitch spread — widening the model's own intonation before the decoder

Plan 9 measured Kokoro's delivery at a pitch spread of 3.9–4.4 semitones and called it the model's
own. This pipeline is not a black box, though: the F0Ntrain stage's predicted contour is a plain
array between two Core ML calls, so it can be widened about its own mean in the log domain before
decoder-pre and the harmonic source see it (`KokoroSynthesisRequest.f0Spread`,
`KokoroCoreMLEngine.Options.f0Spread`; 1 leaves the model alone). The literature calls this feature-
level prosody editing and uses factors of 0.5–1.5. The probe rendered `af_heart` at 1.25, 1.5 and 2.0.

| Render | Audio | Voiced | F0 median | Spread (SD) | 5–95 % range | Pauses | Impulses |
|---|---|---|---|---|---|---|---|
| Heart, spread 1.0 (the model) | 27.86 s | 43 % | 192 Hz | 4.2 st | 9.9 st (154–273 Hz) | 17 | 3 |
| Heart, spread 1.25 | 27.85 s | 43 % | 198 Hz | 4.8 st | 12.4 st (152–312 Hz) | 17, same lengths | 7 |
| Heart, spread 1.5 | 27.86 s | 42 % | 205 Hz | 5.2 st | 15.0 st (151–358 Hz) | 17, same lengths | 4 |
| Heart, spread 2.0 | 27.86 s | 40 % | 216 Hz | 5.3 st | 15.5 st (146–358 Hz) | 17, same lengths | 3 |

What this says:

- **The lever does exactly what it claims and nothing else.** Duration is unchanged to the sample,
  every pause is the same length, and clicks do not rise. The spread grows 4.2 → 4.8 → 5.2 st and the
  range 9.9 → 12.4 → 15.0 st; at 2.0 the decoder saturates (5.3 st, the top pinned at 358 Hz) and the
  tracked median has drifted up 24 Hz — the decoder does not follow its F0 input linearly at the top.
- **1.25 is the candidate** (the range Bella has naturally, on Heart's voice); 1.5 reaches 358 Hz on a
  female voice, which is where "lively" turns "shrill". Nothing here says wider *sounds* better — the
  literature's 0.5–1.5 band is for editing, not a target — so this is the owner's ears' call:
  `spikes/findings/lever-probe/01-heart.wav` against `09-heart-spread-1.25.wav` and `10-heart-spread-1.5.wav`.
- If it ships, it is part of the render identity (a new value re-renders the book), a small enum in
  Preferences rather than a slider, and off by default until the listen says otherwise.

## Found on the way: a crash in every debug build

Rendering `af_nicole` on the passage's 197-id utterance predicted 16.7 s of audio for the 15 s bucket.
The engine handles that (`KokoroCoreMLError.audioTruncated` → re-split, Plan 9 Task 1), but the vendored
pipeline asserted first, in DEBUG builds only — and the performance audit found the Phone scheme runs
Debug. So a reader who chose Nicole (or any slow voice) and reached a long sentence took the app down.
Fixed on this branch: the assertion is gone (the engine's check is the contract) and
`aSlowVoiceOnAPackedUtteranceRendersInsteadOfAsserting` renders that utterance in pieces.

Also on the way: two sessions running the Kokoro tests at once compile the eight stages onto the same
fixed paths in the shared temporary directory and sweep them out from under each other ("The model is
not found at URL …" at the first load, twice today), and each sweep of the shared Core ML plan cache
costs the other run a five-minute recompile that fills the disk. The test support now keeps a private
APFS clone of the compiled stages under the package's `.build`, keyed by model revision, and reuses it
across runs.

### The spread check — 1.25 on the voices Heart is not

Before 1.25 became the default for every voice, the four voices Heart is not: a wide natural range,
a low male voice, a British voice, a breathy one. Same passage, model's own delivery against 1.25:

| Voice | Spread (SD) | 5–95 % range | Top of range | Pauses | Impulses |
|---|---|---|---|---|---|
| Bella | 4.5 → 4.7 st | 17.6 → 18.7 st | 253 → 273 Hz | 16, identical | 1 → 1 |
| Michael (male) | 3.4 → 3.9 st | 10.1 → 12.3 st | 160 → 176 Hz | 15, identical | 4 → 2 |
| Emma (British) | 2.1 → 2.5 st | 5.9 → 7.4 st | 212 → 229 Hz | 13, identical | 8 → 7 |
| Nicole (breathy) | 5.7 → 5.5 st | 17.0 → 17.0 st | 195 → 205 Hz | 20, identical | 13 → 10 |

Nothing saturates (Heart at 2.0 pinned at 358 Hz; the highest top here is 273 Hz), no pause moves, no
click count rises. The owner's listen: 1.25 "sounds good … feels more alive"; three presets
"unnecessarily complicated" — so 1.25 is the fixed default (`Delivery`), not a setting.

### The A/B — where the clicks the owner still heard come from

After the fixes the owner heard "clicks between sentences and abrupt endings" in the app and in the
first Desktop files. Every measure here said the fixed renders were clean, so the passage was rendered
four ways for the owner's ears: as Plan 9 left it (no tail-click removal, no seam trim), with the
removal only, as the app renders today, and today plus 1.25. The owner: **A has clicks after
"Humbug", "sparkled" and "poor enough"** — the three tail bursts Plan 11 measured, to the word —
**B, C and D have none.** So the fix works and the seam trim and the delivery add nothing; the app was
playing audio the current engine did not render. Why that could happen: the render key's engine
component is `RoutedEngine.engineID`, the constant `routed-v1`, and neither Plan 11 fix changed any
component of the key. Audio rendered by a build without the fix is valid cache to a build with it.
The delivery tag on the voice route changes every Kokoro key, so this update re-renders every book;
the rule going forward is in spec §5: a change that alters an engine's audio must change the key.

## 3. The cache codec — Opus is not a lever on this platform

The web comparison is real (Opus at 64 kbps is rated like AAC at 96 kbps for speech), and Plan 9's
probe found AAC capped at 64 kbps here because the encoder refuses 96 kbps at 24 kHz mono. Measured
on this Mac with `AVAudioFile` and `kAudioFormatOpus` in a CAF container, the Plan 9 paragraph render
(26.96 s) as the source:

| Codec, requested | Actual bitrate | File | SNR against the render |
|---|---|---|---|
| AAC 64 kbps (the cache today) | 74 kbps | 249 KB | 21.7–23.6 dB |
| Opus 32 kbps | 104 kbps | 350 KB | 8.6 dB |
| Opus 48 kbps | 120 kbps | 404 KB | 8.9 dB |
| Opus 64 kbps | 136 kbps | 458 KB | 10.2 dB |

The system Opus encoder ignores `AVEncoderBitRateKey`, `AVEncoderBitRatePerChannelKey` and the
constant-bitrate strategy: every file came out at 104–136 kbps and larger than the AAC one. SNR is
not a perceptual measure for Opus (it does not preserve the waveform), so the decoded WAVs are in
`spikes/findings/lever-probe/codec-*.wav` for the owner's ears — but the file-size premise ("the same
budget, better sound") fails outright, and controlling the bitrate would mean bundling libopus through a
third-party package and writing a second codec path. The performance audit's recommendation #4 (play
the live path from the in-memory render, not the cache) removes the cache from the first listen of
every utterance anyway, which is the better fix for what the cache costs.

## 4. Speech enhancement models — the wrong problem

DeepFilterNet and its kin are small enough for a phone (about 112 K parameters, real time on a
Raspberry Pi 4) and genuinely improve *recordings*: they remove noise and reverberation. Kokoro's
output has neither. What it lacks is movement, and no enhancement model adds that; the literature on
"enriching" synthetic speech is about prosody modelling inside the TTS system, not a filter after it.
Not pursued.

## 5. Mastering — real, generic, small

Loudness normalisation to a target (the voices differ in level: see the `rms` column above), a gentle
high-shelf, a hint of room tone. Standard practice, pure DSP on a pipeline that already does its own
DSP, and nothing about it is specific to what is wrong with Kokoro's delivery. Worth a task once the
blends are in, not before.

## Ruled out on the way

- Bracket "emotion tags" (`[whisper]`, `(excited)`) that two blogs recommend: Kokoro reads plain text;
  MisakiSwift's only markup is the inline phoneme override. Verified against the G2P source.
- Kokoro's own `speed` input instead of the time-pitch unit at 1.25–2×: real, but every rate would be
  a separate render and cache; a later question.
- The MLX route on A14+ phones (one call up to 510 ids, clean tails): the performance audit's #14
  argues MLX out of the phone build; its quality measured the same as Core ML's in Plan 9 (pitch spread
  4.1 vs 3.9 st).

## Decision

- **Ship the crash fix** (this branch): the assertion removal, its regression test, the private
  compiled stages for tests.
- **Delivery 1.25, fixed, on the voice route** (`Delivery`, `KokoroVoiceID.spread`): the owner chose it
  over three presets. Every Kokoro render key changes; stored voice choices do not.
- **Blends are not shipped**: the owner heard the curated ones as "all good, too subtle to tell apart".
  The mechanism stays in the lever probe.
- **Order the voice list by the author's grade**: the four B- and better voices first, the D and F voices
  under "More voices". The cheapest quality lever in the app.
- **Not**: Opus through the system encoder; enhancement models; extrapolated blends.
- **Complementary, in the other plan**: the performance audit's #4 (play the live path from the render,
  not the 64 kbps cache) is a quality win as much as a latency one.

Every number above is a proxy; the WAVs in `spikes/findings/lever-probe/` are for the owner's ears.
