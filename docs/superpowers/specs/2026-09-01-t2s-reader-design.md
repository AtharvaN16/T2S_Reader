# t2s_reader — Design Spec

**Date:** 2026-09-01
**Status:** Draft for review
**Working name:** t2s_reader (TBD)

---

## 1. Overview

An iOS app that turns EPUBs, web articles, and text PDFs into a full
audiobook experience: word-level read-along highlighting, chapters as
episodes, variable speed, sleep timer, exact resume, and offline playback.

It competes with ElevenReader on experience, not on catalog. Where
ElevenReader rents you 10 hours/month of cloud synthesis, this app
synthesizes **on-device, unlimited, offline, for free** — permanently.

### 1.1 The defining constraint

**The app must cost its author nothing to run, at any number of users.**

This is not a preference; it is the axis the entire architecture turns on.
Its consequences:

- **No backend.** No servers, no accounts, no queue workers, no object store.
- **No hosted inference on the author's dime.** Synthesis runs on the
  user's own device.
- **Sync via CloudKit private database only.** Private-DB records bill
  against *each user's* iCloud quota, never the developer's. This is the
  one piece of infrastructure Apple gives away at unlimited scale.
- **Premium cloud voices are BYO-key.** If a user wants top-tier quality,
  they paste their own API key. Their money, not ours.

The only unavoidable cost is the **$99/yr Apple Developer Program**,
required for CloudKit, non-expiring builds, and any distribution. A free
Apple ID cannot ship this app: builds expire after 7 days and iCloud,
Push, App Groups, and Sign in with Apple are all withheld.

### 1.2 Non-goals

- Licensed audiobook catalog (ElevenReader bundles 200K titles — a
  licensing business, not an engineering problem)
- Academic/multi-column PDF extraction, or OCR of scanned PDFs
- DRM'd EPUB (Adobe ADEPT, Readium LCP)
- Voice cloning in v1
- Non-English **on-device** synthesis in v1 (see §7.1 — a licensing
  constraint, not a technical one). BYO-key cloud engines are unconstrained.
- Android, web, Watch
- Any generated/derivative content: no AI hosts, no summaries, no
  "podcast overview." This app reads documents **verbatim**.

---

## 2. Product scope (v1)

### 2.1 Content

| Format | Ingest | Read-along fidelity |
|---|---|---|
| **EPUB** (unencrypted) | Readium Streamer | Full — word-level |
| **Web article** | Share sheet → Readability.js → minimal EPUB | Full — word-level |
| **Text PDF** | Readium Streamer + normalizer | Reduced — see §6.4 |

Web articles are converted to a minimal EPUB at import so that everything
downstream travels a single reflowable code path. PDFs remain PDFs.

### 2.2 Features

**Must have**
- Word-level highlight synced to audio, with auto-scroll
- Chapter list; chapters behave as episodes (skip, jump, per-chapter progress)
- 0.5x–4x speed with pitch correction
- Sleep timer (incl. "end of chapter")
- Exact resume, per document
- Lock screen / Control Center / AirPlay via Now Playing
- Offline by default — no network needed for any core function
- Share Extension: send a URL or file from any app
- Voice picker (Kokoro's preset voices), settable globally and per document
- Pronunciation dictionary — user-editable overrides for names and jargon

**Should have**
- Bookmarks and highlights (Readium supports these cheaply)
- Live Activity showing chapter and progress
- App Intents / Siri: "resume my book"
- Spotlight indexing of the library
- Storage manager: per-document cache size, evict rendered audio
- **BYO-key cloud engine** — a generic HTTP adapter behind `SynthesisEngine`;
  the user pastes their own key (Alibaba / Replicate / DeepInfra) to reach
  Qwen3-TTS quality, voice cloning, and non-English. Their cost, not ours.

**Deferred**
- CarPlay (v1.1 — start the entitlement request early; Apple approval is
  the long pole, not the code)
- Mac, iPad-specific layouts (v1 is iPhone, adaptive enough to be usable
  on iPad)

### 2.3 Deferred UI decision

**Library organization is unresolved and deliberately deferred.** EPUBs
want a cover grid with progress rings; saved articles want a dense,
reorderable queue with auto-advance. Options: two tabs, one filtered list,
or one primary with the other second-class. Current lean is two tabs. To
be settled from reference flows before UI work begins; it does not affect
anything below §5.

---

## 3. Architecture

```
┌──────────────────────────────────────────────────┐
│ UI (SwiftUI)                                     │
│   Library · Reader (Readium Navigator) · Player  │
└────────────┬─────────────────────────────────────┘
             │ observes
┌────────────▼─────────────────────────────────────┐
│ PlaybackCoordinator                              │
│   owns the playhead · drives highlight + scroll  │
└──┬──────────────────┬────────────────────────┬───┘
   │                  │                        │
┌──▼───────────┐ ┌────▼──────────────┐ ┌───────▼────────┐
│ AudioPlayer  │ │ RenderScheduler   │ │ TimelineStore  │
│ AVAudioEngine│ │ render-ahead queue│ │ SwiftData      │
└──────────────┘ └────┬──────────────┘ └────────────────┘
                      │
              ┌───────▼──────────┐
              │ SynthesisEngine  │  ← protocol
              ├──────────────────┤
              │ KokoroEngine     │  built-in, on-device
              │ HTTPEngine       │  BYO-key, later
              │ FakeEngine       │  tests
              └──────────────────┘

┌──────────────────────────────────────────────────┐
│ Ingest                                           │
│  EPUBImporter · ArticleImporter · PDFImporter    │
│         └── Segmenter ── TextNormalizer          │
└──────────────────────────────────────────────────┘
```

Each module is independently testable and depends only on protocols
belonging to layers below it.

### 3.1 Core domain model

```swift
Document
  id, title, author, sourceType, sourceURL, coverImage, addedAt
  voiceID?                      // per-document override
  playhead: Playhead

Timeline                        // one per Document
  chapters: [Chapter]
  utterances: [Utterance]       // flat, globally ordered

Chapter
  title, startUtteranceIndex, locator

Utterance
  index: Int                    // stable, global
  text: String                  // normalized, ready to speak
  locator: Locator              // Readium position, for highlight + resume
  audioRef: URL?                // nil until rendered
  duration: Duration            // .estimated(TimeInterval)
                                // .actual(TimeInterval)
  wordTimings: [WordTiming]?    // nil until rendered

WordTiming
  textRange: Range<String.Index>   // into Utterance.text
  start, end: TimeInterval         // relative to utterance start

Playhead
  utteranceIndex: Int
  offset: TimeInterval          // within that utterance
```

### 3.2 Two decisions that carry the design

**Decision 1 — the canonical playhead is `(utteranceIndex, offset)`, never
absolute seconds.**

Absolute time is a *derived, display-only* value computed by summing
preceding durations. Because durations start as estimates and are replaced
by actuals as audio renders, any absolute-time playhead would silently
drift as the document renders. Anchoring to utterance index makes drift
mathematically impossible — resume, seek, and highlight all stay exact,
and only the scrubber's cosmetic position shifts as estimates firm up.

**Decision 2 — the timeline is built in two phases.**

| Phase | When | Produces | Cost |
|---|---|---|---|
| **1. Segment** | At import, whole document | Every utterance, with locator and a *character-count estimate* of duration | ~1–2s for a novel |
| **2. Render** | Lazily, ahead of playhead | Audio + word timings; estimate → actual | ~0.3s per sentence |

Phase 1 gives a scrubbable timeline and a total duration **before a single
sample of audio exists**. Phase 2 fills it in. Seeking to an unrendered
position re-prioritizes the render queue there and begins playback in
roughly a second, because Kokoro runs ~12x realtime.

This is what lets the app feel like streaming while behaving like a file.

### 3.3 Render-ahead scheduler

- Maintains a window of **~3 minutes of audio ahead of the playhead**
- Serial, on a background actor; ANE/GPU-bound work never touches main
- Seek flushes the queue and re-prioritizes at the new position
- Backpressure: idles when the window is full — ANE duty cycle lands
  around **8%**, making battery impact negligible next to the screen
- Explicit "render whole document" action for flights, best run on charge
- Output encoded to **AAC ~32kbps mono 24kHz ≈ 14 MB/hour**; raw PCM would
  be 172 MB/hour and is never persisted
- LRU eviction against a user-configurable cache cap

### 3.4 Playback

`AVAudioEngine → AVAudioPlayerNode → AVAudioUnitTimePitch → mainMixer`

Buffers are scheduled per utterance for gapless playback.
`AVAudioUnitTimePitch.rate` provides 0.5x–4x **with pitch correction**;
`AVQueuePlayer` was rejected because per-item boundaries are audible and
rate handling across items is awkward. Playhead precision comes from
`playerTime`. `AVAudioSession` category `.playback`, mode `.spokenAudio`,
with `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` wired for lock
screen, Control Center, AirPlay, and later CarPlay.

### 3.5 Highlighting

Playhead → current utterance → binary search its `wordTimings` → text range
→ `Locator` → Readium **Decoration**.

- Throttled to ~10 Hz; the navigator is a `WKWebView` and will not thank
  us for more
- Auto-scroll fires only when the active word leaves the viewport
- Manual scroll suppresses auto-scroll for ~5s, then a "jump to playing"
  affordance appears
- If `wordTimings` are absent (unrendered, or PDF), fall back to
  utterance-level highlight

---

## 4. Data flow

```
Share sheet / Files / URL
        │
        ▼
   Importer  ──────────────► EPUB in app container
        │                    (articles synthesized from Readability output)
        ▼
   Readium Streamer ───────► Publication
        │
        ▼
   Segmenter               uses Readium ContentTokenizer + NLTokenizer
        │                  → [text, locator] per sentence
        ▼
   TextNormalizer          numbers, abbreviations, citations, URLs,
        │                  footnote markers, pronunciation dictionary
        ▼
   Timeline (phase 1)      estimated durations · persisted
        │
        ▼
   RenderScheduler ───────► SynthesisEngine ──► PCM + word timings
        │                                        │
        │                                        ▼
        │                                   AAC on disk
        ▼
   Timeline (phase 2)      actual durations · word timings
        │
        ▼
   AudioPlayer ──► playhead ──► Decoration highlight + auto-scroll
```

### 4.1 TextNormalizer

A pipeline of small, independently testable rules applied *before*
synthesis. Without it the app is unusable; with it, it sounds edited.

- Rejoin words hyphenated across line breaks
- Strip repeated headers/footers and page numbers (PDF: detect lines
  recurring at the same Y across many pages)
- Drop or defer footnote markers and inline citations — `[14]` must not
  become "bracket fourteen"
- Expand abbreviations, ordinals, numerals, units, currency
- Collapse URLs to a readable form
- Apply the user's pronunciation dictionary last, immediately before G2P

---

## 5. Storage and sync

**Local is the source of truth.**

- `SwiftData` — documents, timelines, playheads, bookmarks, dictionary
- App container — source files and rendered AAC
- Rendered audio is **cache, never truth**: evictable and always
  re-derivable from the source

**Sync is an optional module behind a protocol.** `CloudKit` private
database syncs documents, playheads, bookmarks, and the pronunciation
dictionary — **never rendered audio**, which is large, device-specific,
and cheap to regenerate. The protocol boundary means the app is fully
functional with sync disabled, and stays buildable on a free Apple ID
during development.

---

## 6. Error handling

| Failure | Response |
|---|---|
| DRM'd EPUB | Reject at import with a plain explanation. Never fail silently. |
| Malformed EPUB/PDF | Import what parses; mark unparsed resources skipped and say so. |
| Article extraction yields little text | Show the extraction and let the user accept or cancel before it enters the library. |
| Synthesis fails for one utterance | Log, insert 200ms silence, continue. One bad sentence must never halt a book. |
| Model load fails | Fall back to `AVSpeechSynthesizer` with a clear quality notice. |
| Disk full | Pause rendering, evict LRU, surface the storage manager. |
| Playhead past end of timeline | Clamp; mark document finished. |

### 6.1 PDF read-along caveat

Readium's decoration support on the PDF navigator is unverified. If
word-level highlighting on PDF proves unavailable, **v1 ships PDF as
audio-first with page-level sync** and full read-along lands on EPUB and
web articles only. Given PDFs are the third-ranked format, this is an
acceptable v1 outcome and is called out here rather than discovered later.

---

## 7. Risks and required spikes

Ranked by how much of the architecture they invalidate.

### 7.1 espeak-ng is GPL-3 — RESOLVED, with a scope cost
Kokoro's weights are Apache 2.0, but its fallback G2P, espeak-ng, is GPL-3
and cannot ship on the App Store. **Mitigation:** use **Misaki** (MIT),
Kokoro's default G2P, via **MisakiSwift**. `mlalma/kokoro-ios` is MIT and
bundles it. **Cost:** English only in v1, since Misaki's non-English
coverage degrades to espeak. *Spike: verify MisakiSwift's coverage and
quality against reference Misaki output.*

### 7.2 Background compute under the `audio` background mode — BLOCKING
The whole render-ahead design assumes iOS permits sustained ANE/GPU
inference while backgrounded under the `audio` capability. Believed true —
the app is legitimately playing audio — but unverified, and if false the
architecture must change to render-whole-document-on-import.
**Spike this first: ~2 hours, before any other code.**

### 7.3 Kokoro runtime: MLX (GPU) vs CoreML (ANE)
`kokoro-ios` uses **MLX Swift**, which runs on the Metal **GPU**, not the
**ANE**. The 0.08 RTF figure quoted for iPhone 16 Pro is a CoreML/ANE
number. GPU inference draws more power and competes with UI rendering.
*Spike: benchmark both paths on device for RTF, sustained thermals, and
resident memory.*

### 7.4 Word timings must survive the chosen runtime
Alignments come from Kokoro's `duration_proj`. The
`Kokoro-82M-v1.0-ONNX-timestamped` build exposes them directly; the MLX
path may not, and the **streaming** ONNX API definitively does not.
Read-along is a core feature, so this constrains runtime choice.
*Spike: confirm per-token `start_ts`/`end_ts` are retrievable in the
chosen Swift runtime.*

### 7.5 Memory footprint
Published figures for Kokoro range from 80 MB (int8 on disk) to 833 MB
(runtime) to "2–3 GB VRAM" — different runtimes and quantizations, all
quoted as if comparable. iOS jetsam does not care which. *Spike: measure
resident memory on a non-Pro device.*

### 7.6 Readium license and platform reach
Believed BSD-3, which is compatible with both App Store distribution and
open-sourcing — **verify before committing**, as the whole reader shell
rests on it. Catalyst/macOS support is unverified and deferred.

---

## 8. Testing strategy

**The key move: `SynthesisEngine` is a protocol, and `FakeEngine` returns
silence of a precisely known duration with synthetic word timings.** This
makes the entire timeline, scheduler, player, and highlight pipeline
deterministic and fast to test, with no model and no audio hardware.

| Layer | Approach |
|---|---|
| TextNormalizer | Table-driven: input → expected spoken form. Every rule isolated. |
| Segmenter | Golden tests over real EPUBs; assert locator round-trip stability |
| Timeline | Property tests: seek round-trips; replacing an estimate with an actual never moves the playhead |
| RenderScheduler | Fake engine + virtual clock: window invariants, seek flush, backpressure |
| Player | Fake engine: verify playhead against known silence durations |
| Highlight | Given a playhead, assert the exact decorated range |
| Kokoro | Snapshot **phonemes**, not audio — audio is not bit-reproducible |
| End-to-end | A short real EPUB through the full pipeline on device |

---

## 9. Build order

1. **Spike §7.2** (background compute) — blocks everything
2. **Spikes §7.3–7.5** (runtime, timings, memory) — picks the engine
3. Ingest + Segmenter + TextNormalizer, with golden tests
4. Timeline + TimelineStore, with `FakeEngine`
5. RenderScheduler + AudioPlayer — audio-only, no UI polish
6. Readium reader view + Decoration highlighting + auto-scroll
7. KokoroEngine, replacing `FakeEngine`
8. Library UI (**resolve §2.3 first**), Share Extension, player chrome
9. Now Playing, sleep timer, speed, pronunciation dictionary, BYO-key
   HTTP engine
10. CloudKit sync
11. Live Activity, App Intents, Spotlight
12. v1.1: CarPlay, Mac

Steps 3–6 are fully testable with no model present. Kokoro lands at step 7
against a pipeline that is already proven.

---

## 10. Open questions

1. **Library organization** (§2.3) — two tabs, or one list? Deferred to
   reference-flow review.
2. **App name.**
3. **Distribution** — App Store one-time fee, open source, or both.
   Affects nothing above, but the license choice must be compatible with
   Readium, Kokoro, and MisakiSwift.
