# t2s_reader — Design Spec

**Date:** 2026-09-01
**Revised:** 2026-09-02 (rev 3 — see §11 changelog)
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

Deferring accounts and a backend is **reversible** — see §3.7.1 for the
conditions that keep it that way.

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
| **Text PDF** | Readium Streamer + normalizer | Reduced — see §6.1 |

Web articles are converted to a minimal EPUB at import so that everything
downstream travels a single reflowable code path. PDFs remain PDFs.

**The originally fetched HTML is retained alongside the generated EPUB.**
Extraction is lossy and irreversible; keeping the source means a future
Readability upgrade, a decision to preserve images and tables, or a
conversion bug can all be reprocessed. Source URLs are not a substitute —
pages change and die. See §3.7.

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

### 2.3 Library organization — RESOLVED (rev 3)

Resolved by reference-flow review of **Queue — Simple podcasts** (iOS),
which is the visual reference for the whole app (§2.4).

**One ordered Queue is the primary list; a Collection grid is the second
page; there are no tabs.** Everything imported — article, EPUB, PDF — is
queued on import. Queue shows queued documents in user order, with
articles and books as peers. Collection shows every EPUB/PDF as a cover
grid regardless of queue state, so a book archived from the Queue stays
findable. Archive removes from Queue; delete removes from both.

**The Reader is a separate full-screen page, not a region of the player
sheet.** The player sheet is audio chrome; the Reader is text with a
compact control bar. Both observe the same `PlaybackCoordinator`, and
leaving either never stops playback.

### 2.4 Visual direction

Reference: **Queue — Simple podcasts**. Every screen below maps to a
Queue screen; where Queue has no equivalent (the Reader) the same
language is extended. Light and dark are both first-class from the
first commit.

#### 2.4.1 Type

Inter (SIL OFL 1.1, bundled). Tight tracking on display and label text.
Long-form reading text is the one exception and uses normal tracking.
Digits that align or count down use a monospaced face.

| Role | Face | Size / weight | Tracking |
|---|---|---|---|
| Page title | Inter Display | 34 / Black | −0.03em |
| Player title | Inter Display | 26 / ExtraBold, ≤4 lines | −0.025em |
| Section header | Inter | 17 / Semibold | −0.01em |
| Row title | Inter | 17 / Medium, ≤2 lines | −0.01em |
| Pill label | Inter | 15 / Medium | −0.01em |
| Meta | Inter | 13 / Regular | 0 |
| Reader body | Inter | 18 / Regular, 1.5 line height | 0 |
| Timestamps, counts | System monospaced | 13 / Regular | 0 |

All sizes are Dynamic Type relative. Reader body size and line height
are user-adjustable independently of the system text size.

#### 2.4.2 Color

Semantic tokens only; no literal colors in views. The accent hue is the
one tunable (§10); the values below are starting points.

| Token | Light | Dark | Used for |
|---|---|---|---|
| `ground` | #F8F8F7 | #101010 | page background |
| `surface` | #EEEEEC | #1E1E1E | pills, chips, row controls |
| `raised` | #FFFFFF | #1A1A1A | sheets, mini-player, popovers |
| `ink` | #111111 | #F2F2F2 | primary text, selected chips |
| `ink2` | #8A8A8A | #8E8E8E | meta, descriptions |
| `ink3` | #C9C9C7 | #3A3A3A | disabled, unrendered scrubber ticks |
| `accent` | #FF7A1A | #FF8C3A | the one primary action per screen |
| `accentSoft` | accent @ 18% | accent @ 22% | read-along word highlight, soft pills |
| `positive` | #22A559 | #34C070 | rendered / finished states |
| `destructive` | #E5453B | #FF5A50 | archive, delete, discard cache |

Rules: at most one `accent` element per screen. Selected chips are
solid `ink` with `ground` text, never accent. `positive` and
`destructive` appear only on state tags and confirming actions. Dark
mode inverts ground and ink and lifts the accent slightly; it
introduces no new hues.

#### 2.4.3 Surface and spacing

- 8pt grid. 24pt horizontal margins. 28pt between list rows, 40pt
  between sections, 56pt from the safe-area top to a page title.
- **No cards in lists and no hairline dividers.** Rhythm comes from
  white space and type weight alone.
- Pills are fully rounded. Sheets have 28pt top corners. Artwork is 8pt
  radius small, 16pt large.
- Sheets slide up over the page, which dims and scales to ~0.94.

#### 2.4.4 Navigation

No tab bar. The root is a three-page horizontal pager —
**Collection · Queue · Preferences** — opening on Queue. A three-glyph
indicator under the mini-player shows the current page and is
tappable. A floating **mini-player pill** sits above the indicator on
all three pages: artwork, title, play/pause, skip-forward. It shows the
playing item, or the next queued item with "Play" when idle, and is
hidden only when the Queue is empty. Tap expands it to the player
sheet.

Page titles are dropdowns where a page has views: `Queue ▾` switches
between *Queue* and *Finished*.

#### 2.4.5 Screens

**Queue page.** Title with dropdown, "Search" pill top-right. Subtitle:
item count and remaining time (`14 items · ~6h 20m`). Each row: 16pt
source mark, source name, added-age, and a `positive` check once fully
rendered; row title; then a pill row — `▶ Play  ~12m` (remaining time;
becomes `❚❚ Pause` on the playing row), archive pill, overflow. Tap the
title → Reader page. Tap Play → plays in place. Swipe → Archive. Books
show `Chapter 4 of 12` in the meta line. Empty state: title, a grey
paragraph explaining the share sheet, an "Import" pill.

**Collection page.** Title, `N books` subtitle, `+` button (Files
import). 3-up cover grid, 16pt radius, thin progress bar under each
cover. Tap → **book sheet**: large floating cover, title in Player
style, author, stat row (Chapters · Length `~5h 10m` · Rendered `42%`),
accent "Play" pill, `+ Add to Queue` / `✓ In Queue` pill, then the
chapter list with per-chapter play and progress.

**Player sheet.** Top: 56pt artwork; bookmark, sleep-timer, and
overflow buttons. Source and age line. Player title. Author. A row
`Chapter 3 ▾` opens the chapter list (title and duration per chapter).
A row `Read along →` dismisses the sheet and opens the Reader page.
Scrubber: uniform tick marks — rendered ticks in `ink`, unrendered in
`ink3`, so the render frontier (§3.3) is visible without a legend.
Times below in monospaced; total prefixed `~` until fully rendered.
Control pill: overflow | back 15 · play · forward 30 | speed as a bare
number.

**Reader page.** Separate full-screen page. Entered from a Queue row
title, a chapter in the book sheet, or `Read along` in the player. Back
chevron top-left, chapter title center (tap → chapter list), overflow
right (bookmark, appearance). Body is the Readium navigator at 24pt
margins on `ground`. The active word is decorated with `accentSoft`,
4pt radius; nothing else on the page uses accent. Auto-scroll keeps the
active line in the middle third of the screen; a manual scroll suspends
it and shows a `Back to current` pill until tapped. Tap a sentence →
seek there. Bottom bar pinned over a `ground` fade: tick scrubber, then
back 15 · play · forward 30 · speed. During underrun (§3.6) the play
glyph becomes a ring and a caption reads `catching up…`. PDF uses the
same page with page-level highlight (§6.1).

**Speed picker.** Vertical list, 0.5x–4.0x in 0.1x steps. Rates whose
sustained demand exceeds the §3.6 threshold are drawn in `ink3` with a
one-line footnote. Current rate is checked.

**Sleep timer.** Sheet: sleep glyph, chips `10 · 20 · 30 · 45 · 60 min
· End of chapter`, selected chip solid `ink`, accent "Start" pill, grey
caption noting the timer ends early if the document does.

**Context menu.** Native menu: Archive (`destructive`), Mark as finished
(`positive`), Details, Sleep timer, Change voice, Render whole document.

**Preferences page.** Title. Sections as a header plus rows of title,
grey subtitle, and a right-aligned control: **Voice** (default voice →
voice list with preview), **Playback** (skip intervals, default speed,
autoplay next), **Reading** (text size, line height, theme
System / Light / Dark), **Pronunciation** (→ dictionary list),
**Storage** (cache size, cap, "Render on charge" toggle, evict),
**Cloud voices** (BYO key), **iCloud sync** toggle, links.

**Voice-change warning** (§5): a sheet stating how much rendered audio
will be discarded, with a `destructive` confirm.

---

## 3. Architecture

```
┌──────────────────────────────────────────────────┐
│ UI (SwiftUI)                                     │
│   Queue · Collection · Reader · Player           │
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
              │ HTTPEngine       │  BYO-key
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
  id: UUID                      // client-generated, never a backend key
  title, author, sourceType, sourceURL, coverImage, addedAt
  voiceID?                      // per-document override
  resumePosition: Position      // PERSISTED anchor — see §3.2

Position                        // our own type; Readium never persisted
  resourceHref: String
  progression: Double           // 0…1 within the resource
  charOffset: Int?              // UTF-16 offset, when known
  cssSelector: String?

Timeline                        // one per Document, stored per chapter
  schemaVersion: Int
  segmenterVersion: Int
  chapters: [Chapter]

Chapter
  title, position: Position
  utterances: [Utterance]       // encoded as one compact blob — see §5

Utterance
  index: Int                    // RUNTIME ordinal, not a persisted anchor
  position: Position            // maps back into the source document
  source: String                // original text, verbatim
  spoken: String                // normalized text handed to the engine
  spans: [SpanMap]              // spoken ↔ source mapping — see §4.1
  audioRef: URL?                // nil until rendered
  duration: Duration            // .estimated(Double) | .actual(Double)
                                // ALWAYS at 1x; scaled for display
  wordTimings: [WordTiming]?    // nil until rendered

WordTiming
  spokenRange: Range<Int>       // UTF-16 offsets into `spoken`
  start, end: TimeInterval      // relative to utterance start, at 1x

SpanMap
  sourceRange: Range<Int>       // UTF-16 offsets into `source`
  spokenRange: Range<Int>       // UTF-16 offsets into `spoken`
```

`Range<String.Index>` is deliberately absent — `String.Index` is not
stable across serialization and cannot be persisted. All ranges are
integer UTF-16 offsets.

### 3.2 Positions: persisted vs runtime

**At rest, positions are `Position`. At runtime, positions are
`(utteranceIndex, offset)`.**

These serve different jobs and conflating them is a data-corruption
hazard:

- **`utteranceIndex` is an output of the segmenter.** Improve sentence
  splitting, fix a normalizer rule, or change chunk size, and every index
  shifts. If playheads and bookmarks were persisted as indices, a routine
  app update would silently relocate every user's position mid-book, with
  the original information unrecoverable.
- **`Position` is anchored in the document**, so it survives
  re-segmentation, re-normalization, and engine changes.

On load, the persisted `Position` resolves to `(utteranceIndex, offset)`.
On save, the runtime pair projects back to a `Position`. A
`segmenterVersion` mismatch simply forces re-resolution, which is cheap.

**Why the runtime form is still index-anchored:** absolute seconds are a
*derived, display-only* value computed by summing preceding durations.
Because durations begin as estimates and are replaced by actuals as audio
renders, an absolute-time runtime playhead would drift as the document
renders. Anchoring to the utterance makes that drift impossible.

### 3.3 Two-phase timeline

| Phase | When | Produces | Cost |
|---|---|---|---|
| **1. Segment** | At import, whole document | Every utterance, with `Position` and a *character-count estimate* of duration | ~1–2s for a novel |
| **2. Render** | Lazily, ahead of playhead | Audio + word timings; estimate → actual | ~0.3s per sentence |

Phase 1 gives a scrubbable timeline and a total duration **before a single
sample of audio exists**. Phase 2 fills it in. Seeking to an unrendered
position re-prioritizes the render queue there and begins playback in
roughly a second, at Kokoro's measured throughput.

**Estimates are not cosmetic.** A 10% error on a 12-hour book is 72
minutes. Until a document is fully rendered, total duration and remaining
time are displayed as approximate (`~12h`), and the scrubber is drawn with
an uncertainty treatment past the render frontier.

### 3.4 Render-ahead scheduler

- Maintains a window measured in **playback-seconds at the current rate**,
  not wall-clock audio seconds — see §3.6
- Serial, on a background actor; inference never touches main
- Seek flushes the queue and re-prioritizes at the new position
- Backpressure: idles when the window is full
- Explicit "render whole document" action for flights, best run on charge
- Output encoded to **AAC ~32kbps mono 24kHz ≈ 14 MB/hour**; raw PCM
  (172 MB/hour) is never persisted
- LRU eviction against a user-configurable cache cap
- Concurrency: **one document renders at a time.** Starting playback of a
  second document preempts the first; the first's completed utterances are
  retained.

### 3.5 Playback

`AVAudioEngine → AVAudioPlayerNode → AVAudioUnitTimePitch → mainMixer`

Buffers are scheduled per utterance for gapless playback.
`AVAudioUnitTimePitch.rate` provides 0.5x–4x **with pitch correction**;
`AVQueuePlayer` was rejected because per-item boundaries are audible and
rate handling across items is awkward. Playhead precision comes from
`playerTime`. `AVAudioSession` category `.playback`, mode `.spokenAudio`,
with `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` wired for lock
screen, Control Center, AirPlay, and later CarPlay.

### 3.6 Render rate coupling and underrun

**Playback rate multiplies synthesis load.** At rate `r`, the app consumes
`r` seconds of audio per wall-clock second, so required throughput is
`RTF × r`. At the CoreML/ANE figure of `RTF ≈ 0.08`, 1x costs an 8% duty
cycle but **4x costs 32%**. If the real figure on the shipping runtime is
`RTF ≈ 0.3` — plausible for the MLX/GPU path in §7.3 on a non-Pro device —
then **4x demands 120% of realtime and cannot be sustained**.

Therefore:

- The render window is denominated in playback-seconds; **changing rate
  resizes it**, so 3x keeps three times the audio buffered.
- The engine reports **measured RTF**, updated as a rolling average.
- Rates whose sustained demand exceeds a safety threshold are **disabled
  in the UI**, with an explanation, rather than offered and then stuttering.
- **Underrun policy:** if the playhead reaches the render frontier,
  playback pauses with a visible "catching up…" state. It does not
  silently drop rate, and it does not stutter.

**Battery is a measured quantity, not an assumed one.** During background
listening the screen is off, so synthesis is the *dominant* power draw,
not a rounding error. §7.3 must produce a real mAh/hour figure at 1x and
at 3x for each candidate runtime before the runtime is chosen.

### 3.7 Reversibility contract

Decisions here are cheap now and unfixable once user data exists. They are
requirements, not preferences.

#### 3.7.1 Backend and accounts stay addable
- **Client-generated `UUID` primary keys.** Never CloudKit record names,
  never autoincrement. A CloudKit identifier must never *be* a domain ID.
- **A real `SyncProvider` protocol**, with CloudKit as one implementation.
  No CloudKit calls outside it.
- **CloudKit's schema must not shape the domain model.** Domain types plus
  a mapping layer, so a future server implements the same protocol.

#### 3.7.2 Readium stays swappable
Readium types — `Locator` above all — are **never persisted and never
synced**. `Position` (§3.1) is our own, converted at the Readium boundary.
Readium's `Locator` is already close to this shape, so the adapter is
thin — but only if written before a year of bookmarks exist in the other
format. This keeps §7.6 (license, Catalyst reach) a recoverable risk.

#### 3.7.3 Derived data stays re-derivable
Rendered audio is cache, never truth. Original article HTML is retained
(§2.1). Source files are never mutated in place. Consequence: changing
engine, voice, normalizer, or segmenter is always a reprocess, never a
migration.

#### 3.7.4 Everything persisted carries a version
`schemaVersion` and `segmenterVersion` on every timeline; a `renderKey`
on every audio file (§5). Free to add now, painful to retrofit.

#### 3.7.5 License hygiene is a ratchet
A GPL dependency that becomes load-bearing forecloses **both** App Store
distribution and the open-source option in §11. Verify Readium and
MisakiSwift terms before they are load-bearing, and add a dependency
license check to CI from the first commit.

---

## 4. Data flow

```
Share sheet / Files / URL
        │
        ▼
   Importer  ──────────────► EPUB in app container
        │                    (+ original HTML retained for articles)
        ▼
   Readium Streamer ───────► Publication
        │
        ▼
   Segmenter               Readium ContentTokenizer + NLTokenizer
        │                  → [source text, Position] per sentence
        ▼
   TextNormalizer          → spoken text + SpanMap[]  (§4.1)
        │
        ▼
   Timeline (phase 1)      estimated durations · persisted
        │
        ▼
   RenderScheduler ───────► SynthesisEngine ──► PCM + word timings
        │                                        │
        │                                        ▼
        │                                   AAC on disk
        ▼
   Timeline (phase 2)      actual durations · word timings on `spoken`
        │
        ▼
   AudioPlayer ──► playhead ──► project spoken→source ──► highlight
```

### 4.1 TextNormalizer and the span mapping

Normalization is what makes the audio listenable, and it is also what
makes read-along hard. **The engine speaks normalized text; Readium
highlights the original document.** When `"Dr. Smith"` becomes
`"Doctor Smith"`, a word timing for "Doctor" has no range in the source —
and this happens in most sentences of a real book.

So normalizer rules are **not** independent string transforms. Each rule
consumes and produces a text-plus-mapping value:

```swift
struct NormalizedText {
  let source: String        // never mutated
  var spoken: String        // current normalized form
  var spans: [SpanMap]      // spoken ranges ↔ source ranges
}

protocol NormalizerRule {
  func apply(_ input: NormalizedText) -> NormalizedText
}
```

Rules compose left to right, each updating `spans`. Projection at playback
time is a binary search: a word timing's `spokenRange` maps to a
`sourceRange`, which combines with the utterance's `Position` to produce
the highlight.

Mapping conventions:
- **Expansion** (`Dr.` → `Doctor`): the whole expanded span maps to the
  whole source token.
- **Deletion** (citations, footnote markers): source range maps to an
  empty spoken range and is skipped during highlighting.
- **Insertion** with no source (rare): maps to a zero-width source point.

Rules, applied in order:
1. Rejoin words hyphenated across line breaks
2. Strip repeated headers/footers and page numbers (PDF: lines recurring
   at the same Y across many pages)
3. Drop footnote markers and inline citations — `[14]` must never become
   "bracket fourteen"
4. Expand abbreviations, ordinals, numerals, units, currency
5. Collapse URLs to a readable form
6. Apply the user's pronunciation dictionary, last, immediately before G2P

---

## 5. Storage and sync

**Local is the source of truth.**

- `SwiftData` — documents, chapters, playheads, bookmarks, dictionary
- App container — source files, retained article HTML, rendered AAC

**Utterances are stored as one compact encoded blob per chapter**, not as
individual rows. A 1,000-page book is ~50K utterances; a 100-document
library would otherwise be millions of rows. Blobs are loaded on demand
and decoded per chapter.

**Rendered audio is cache, never truth** — evictable and re-derivable. Its
filename is a `renderKey` hash over:

```
documentID · utteranceIndex · voiceID · engineID
           · normalizerVersion · segmenterVersion
```

This makes staleness structural: **changing voice automatically
invalidates that document's audio** rather than silently serving the old
voice. The UI must warn before a voice change discards a large rendered
cache.

**Sync is an optional module behind `SyncProvider` (§3.7.1).** CloudKit's
private database syncs documents, positions, bookmarks, and the
pronunciation dictionary — **never rendered audio**, which is large,
device-specific, and cheap to regenerate.

**Conflict policy: furthest-position-wins for playheads**, not
last-write-wins. Two devices listening to the same book must converge on
the further point; last-write-wins rewinds the user, which reads as data
loss. Bookmarks and dictionary entries merge as unioned sets keyed by
UUID. Deletions are tombstoned.

The protocol boundary means the app is fully functional with sync
disabled, and stays buildable on a free Apple ID during development.

---

## 6. Error handling

| Failure | Response |
|---|---|
| DRM'd EPUB | Reject at import with a plain explanation. Never fail silently. |
| Malformed EPUB/PDF | Import what parses; mark unparsed resources skipped and say so. |
| Article extraction yields little text | Show the extraction and let the user accept or cancel before it enters the library. |
| Synthesis fails for one utterance | Log, insert 200ms silence, continue. One bad sentence must never halt a book. |
| Model load fails | Fall back to `AVSpeechSynthesizer` with a clear quality notice. |
| Render frontier reached | Pause with "catching up…" (§3.6). Never stutter. |
| Disk full | Pause rendering, evict LRU, surface the storage manager. |
| Position fails to resolve after re-segmentation | Fall back to chapter start; never to document start. |
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
The render-ahead design assumes iOS permits sustained ANE/GPU inference
while backgrounded under the `audio` capability. Believed true — the app
is legitimately playing audio — but unverified.
**Spike this first: ~2 hours, before any other code.**

**If it is false, this is not a tweak — it is a different product.**
Screen-off listening would only work from *already rendered* audio, so:
- Import would have to render the whole document up front — roughly an
  hour of compute and ~170 MB for a 12-hour book — before first listen
- Render-ahead would run only while the app is foregrounded
- The library would need an explicit, visible "prepared for offline" state
- The two-phase timeline (§3.3) survives; the scheduler (§3.4) does not

That fallback must be costed before committing, not discovered later.

### 7.3 Kokoro runtime: MLX (GPU) vs CoreML (ANE)
`kokoro-ios` uses **MLX Swift**, which runs on the Metal **GPU**, not the
**ANE**. The `0.08` RTF figure quoted for iPhone 16 Pro is a CoreML/ANE
number. GPU inference draws more power and competes with UI rendering.
*Spike: benchmark both paths on device for RTF, sustained thermals,
resident memory, and **mAh/hour at 1x and 3x** (§3.6).*

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
Believed BSD-3, compatible with both App Store distribution and
open-sourcing — **verify before it is load-bearing** (§3.7.5).
Catalyst/macOS support is unverified and deferred. §3.7.2 keeps this
recoverable rather than terminal.

---

## 8. Testing strategy

**The key move: `SynthesisEngine` is a protocol, and `FakeEngine` returns
silence of a precisely known duration with synthetic word timings.** This
makes the entire timeline, scheduler, player, and highlight pipeline
deterministic and fast to test, with no model and no audio hardware.

| Layer | Approach |
|---|---|
| TextNormalizer | Table-driven: input → expected spoken form, every rule isolated. **Plus: every spoken range projects back to a non-empty source range** |
| Segmenter | Golden tests over real EPUBs; `Position` round-trip stability |
| Re-segmentation | Change `segmenterVersion`, assert every persisted `Position` still resolves within tolerance |
| Timeline | Property tests: seek round-trips; replacing an estimate with an actual never moves the playhead |
| RenderScheduler | Fake engine + virtual clock: window invariants, seek flush, backpressure, **rate-change resizing and underrun** |
| Player | Fake engine: verify playhead against known silence durations |
| Highlight | Given a playhead, assert the exact decorated **source** range |
| Sync | Two simulated devices: assert furthest-position-wins, tombstones, merges |
| Kokoro | Snapshot **phonemes**, not audio — audio is not bit-reproducible |
| End-to-end | A short real EPUB through the full pipeline on device |

---

## 9. Build order

1. **Spike §7.2** (background compute) — blocks everything, incl. whether
   §3.4 exists at all
2. **Spikes §7.3–7.5** (runtime, timings, memory, battery) — picks the engine
3. Ingest + Segmenter + TextNormalizer **with span mapping**, golden tests
4. Timeline + TimelineStore + `Position` resolution, with `FakeEngine`
5. RenderScheduler + AudioPlayer — audio-only, no UI polish
6. Readium reader view + Decoration highlighting + auto-scroll
7. KokoroEngine, replacing `FakeEngine`
8. Queue, Collection, Player, and Reader pages per §2.3–§2.4; Share
   Extension
9. Now Playing, sleep timer, speed + rate coupling, pronunciation
   dictionary, BYO-key HTTP engine
10. CloudKit sync behind `SyncProvider`
11. Live Activity, App Intents, Spotlight
12. v1.1: CarPlay, Mac

Steps 3–6 are fully testable with no model present. Kokoro lands at step 7
against a pipeline that is already proven.

---

## 10. Open questions

1. **App name.**
2. **Distribution** — App Store one-time fee, open source, or both. The
   license choice must be compatible with Readium, Kokoro, MisakiSwift,
   and Inter (§3.7.5).
3. **Accent hue** (§2.4.2) — orange is inherited from the reference;
   settle it on a device, in both themes, before UI work begins.

---

## 11. Changelog

**rev 3 (2026-09-02)** — UI resolution pass.

- **§2.3** resolved: one ordered Queue as the primary list, a Collection
  cover grid as the second pager page, no tabs. The Reader is a separate
  full-screen page, not part of the player sheet.
- **§2.4** added: visual direction from reference-flow review of Queue —
  type scale (Inter, tight tracking), semantic color tokens for light and
  dark, spacing, navigation, and a per-screen mapping.
- **§3** diagram, **§9** step 8, and **§10** updated to match.

**rev 2 (2026-09-01)** — review pass. Substantive changes:

- **§4.1** rewritten: normalizer now carries a `SpanMap` so word timings on
  normalized text project back to source ranges. As previously specified,
  read-along would have broken on most sentences.
- **§3.2** split: `Position` is persisted, `(utteranceIndex, offset)` is
  runtime-only. Previously a segmenter improvement would have silently
  relocated every user's playhead.
- **§3.6** added: playback rate multiplies synthesis load; window is
  denominated in playback-seconds; explicit underrun policy; battery
  reclassified from assumed-negligible to measured.
- **§3.7** added: reversibility contract (backend addable, Readium
  swappable, derived data re-derivable, versioning, license hygiene).
- **§3.1** ranges changed to integer UTF-16 offsets — `String.Index` is
  not persistable.
- **§5** added: per-chapter utterance blobs, `renderKey` cache
  invalidation on voice change, furthest-position-wins conflict policy.
- **§7.2** fallback architecture spelled out rather than hand-waved.
- **§2.1** original article HTML now retained; dead cross-reference in the content table fixed.
- **§3.3** duration estimates reclassified as user-visible, not cosmetic.
