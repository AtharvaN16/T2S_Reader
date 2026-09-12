# Chapter rendering — design

**Date:** 2026-09-12
**Owner decisions:** recorded inline, from the brainstorming session of the same day.
**Status:** design agreed; implementation plan to follow.

## Why

A reader who is about to lose the use of their phone — a flight, a walk with the screen
locked, a commute underground — wants a chapter of audio *on the device now*, and wants to
watch it happen. Today the app has three menu items that claim to do this and a tier that
quietly already does part of it, and no screen anywhere shows what is cached.

This design gives chapter rendering one home, one queue, and one honest account of what is
on the device.

## What exists today

Established by reading, not assumed:

- **`RenderTier.manual` already renders exactly one chapter** — the one containing the
  document's resume position, budgeted to that chapter's own length. It is the lowest of the
  five tiers.
- **`manualRequested` is a single `Bool`** on `PlaybackCoordinator`, for the *loaded*
  document only. This is why Home and the Collection call `player.load(book, play: false)`
  before requesting a render: the side effect is that pressing "Render chapter" on a book you
  are not listening to **silently makes it your current book**, changing the mini-player.
  There is no progress, no confirmation and no completion signal anywhere.
- **`RenderTier.chapterAhead` (Plan 18) already renders the current chapter while you
  listen**, but narrowly: only while something is `playing`, only while frontmost, and not at
  all when `thermalSerious`, `lowPowerMode` or `storeFull`. Its budget is
  `min(max(toChapterEnd, fill.lowerBound), fill.upperBound)` with the fill range fixed at
  `300...300`, so it is **exactly a five-minute rolling window ahead of the playhead**.
- **`PrepareRunner` builds its own `RenderScheduler` but shares the `RenderArbiter`** with the
  player's. The arbiter is therefore already the mechanism that stops two subsystems rendering
  at once, and it leases by `RenderTier` order.
- **`Library.renderSnapshot(for:)` is public** and reports per-utterance `rendered` for any
  document *without loading it*.
- **`AudioStore` has whole-store `stats()` and per-key `remove`** — but no per-document or
  per-chapter byte count. **`Library.evictAudio(for:)` evicts a whole document only.**

## Decisions

| Question | Decision |
|---|---|
| What "one chapter at a time" limits | Queue many, render strictly one at a time |
| Reader menu | Instant: renders the current chapter **to completion** |
| Home row menu | Instant: renders that book's resume chapter (chapter 1 if never played), **without loading it** |
| Collection menu | Opens the Book sheet already in render mode |
| Heat / Low Power Mode | Pause and hold the queue, with a "continue anyway" override |
| Queue lifetime | Survives the sheet; abandoned at app exit |
| While playing | Keeps working, at lowest priority |
| Eviction | Per chapter, plus "evict all" for the book |

## Architecture

### `ChapterRenderRunner`

New, `Sources/T2SApp/Playback/ChapterRenderRunner.swift`, `@MainActor @Observable`, owned by
`AppEnvironment` beside the player.

```
ChapterRenderJob
  documentID: UUID
  chapterIndex: Int
  title: String
  utterances: Range<Int>       // the chapter's span in the timeline
  rendered: Int                // how many of them are in the store
  state: .queued | .running | .ready | .failed(String)
```

The runner holds `queue: [ChapterRenderJob]` and drains it one job at a time. One queue serves
the whole app, not one per book: starting a render while another book's chapters are still
running appends to the same queue rather than starting a second one. A job already queued for
the same chapter is not added twice. Per job it:

1. reads the timeline through `library.currentTimeline(id)` — so it renders **any** document,
   loaded or not;
2. skips utterances the store already holds (this is what makes the Reader's item cooperate
   with `chapterAhead` rather than duplicate it);
3. builds `RenderRequest`s for the rest at `.manual` tier;
4. creates a `RenderScheduler` **sharing the app's existing `RenderArbiter`**;
5. consumes `scheduler.events`, counting `.rendered` for progress and writing `audioRef`s
   back, as `PrepareRunner` does.

### Why the arbiter carries the weight

Sharing it means three of the rules above are not implemented at all, they are inherited:

- **"One at a time"** — the arbiter leases one slot across every scheduler.
- **"Playback wins"** — `.manual` is the lowest tier, so `playAhead` preempts at the next
  boundary.
- **"Don't fight the prepare task"** — prepare and manual already share the slot.

Building the queue anywhere else would mean reimplementing these as new conditionals in a
subsystem that playback depends on. This is the central reason for the shape of this design.

### Why not the coordinator, and why not `PrepareRunner`

The coordinator knows only its loaded document, so it cannot serve Home or the Collection
without the `load()` side effect the owner is removing. `PrepareRunner` is the background
on-charge subsystem — BGTask lifecycle, charge gating, prepare budgets — and a foreground
user-initiated queue would have to bypass most of that, entangling two policies in the one
component that currently keeps overnight rendering safe.

### Lifetime

App-level, so the queue survives the Book sheet closing, the pager, and continued listening.
App exit abandons it. Nothing is lost mid-chapter: audio is written per utterance as it lands,
so a half-rendered chapter stays half-rendered and re-queueing skips what is cached.

## State machine

A job is `queued`, then `running`, then `ready` or `failed`. The runner itself is idle,
running, or **held**, with a reason:

- **`hot`** — `deviceState.thermalSerious` or `lowPowerMode`. The running scheduler is
  cancelled, the job stays at the head of the queue with what it has rendered, and the runner
  resumes itself when the condition clears. `continueAnyway()` sets an override that ignores
  the condition until the queue drains — deliberately not persisted, so it cannot quietly
  become the permanent setting.
- **`storeFull`** — the scheduler's `.storeFull` event. The queue holds; the reason names
  Settings → Storage. No override: the constraint is real.

Note this is a change of behaviour: `.manual` is currently the one tier that renders in any
power state.

## UI

### Render mode in the Book sheet

The `⋯` beside the Play pill gains **"Render chapters"**, which turns the existing chapter
list into a selection list. Three additions, no new screen:

- **A summary line above the list** — "4 chapters ready · 38 MB" — with **Evict all**. The
  figure is *this book's* rendered audio, not the whole cache; Settings → Storage keeps the
  store-wide total.
- **A trailing state mark on every row**, which is the whole language of the screen:
  - not rendered, unselected → an empty circle
  - selected → a filled check
  - queued → "Queued"
  - running → an SF `waveform` masked by the rendered fraction, **filling left to right**
  - ready → `PositiveCheck`, the tick Home already uses for `isFullyRendered`, plus the
    chapter's size and a visible trash button

  A ready chapter cannot be selected for rendering — there is nothing to render — so its row's
  only action is to evict it. A partly rendered chapter is selectable and renders the
  remainder.
- **`BarButton` at the foot** — the existing full-width black bar for "the one action of a
  step" — reading "Start rendering (3)", shown only once something is selected.

The trash is visible rather than behind a long-press, on the lesson from the bookmarks work of
the same day: a destructive action hidden behind a gesture reads to the owner as absent.

### Entry points

- **Reader `⋯` → "Render chapter"** — enqueues the chapter now playing and renders it **to
  completion**: the whole chapter rather than `chapterAhead`'s five-minute window, continuing
  while paused, while backgrounded, and through heat if overridden.
- **Home row `⋯` → "Render chapter"** — enqueues that book's resume chapter (chapter 1 if
  never played), to completion, as above. **No `load()`**: it stops hijacking the current book.
- **Collection `⋯` → "Render chapter"** — opens the Book sheet in render mode.
- **Book sheet `⋯` → "Render chapters"** — enters render mode.

### Outside the sheet

One toast when the queue drains ("3 chapters ready"), not one per chapter, plus a toast if any
chapter failed. No permanent indicator: the sheet is where this lives.

## Storage and eviction

Two additions:

- **`AudioStore.bytes(for keys: [RenderKey]) async -> Int`** — sums the LRU index's sizes.
  The summary line and each ready row read it.
- **`Library.evictAudio(for id: UUID, chapter: Int)`** — removes that chapter's keys and
  clears only that chapter's `audioRef`s, alongside the existing whole-document form, which
  "Evict all" reuses unchanged.

## Error handling

- **A failed utterance** stores 200 ms of silence and still emits `.rendered` (spec §6), so
  progress advances rather than hanging; the runner counts failures and the row reports gaps.
- **`.storeFull`** holds the queue with a reason naming Settings → Storage.
- **A stale or missing document** skips its job with a message rather than failing the queue.
- **A voice change orphans rendered audio**, because `RenderKey` includes the voice. Each job
  renders with the voice in force when it runs; the summary will simply show less cached than
  expected. Known and not solved here.

## Testing

All package-level, with `FakeEngine` and `AppFixtures` — no simulator:

- the queue drains strictly serially, never two jobs at once
- progress counts `.rendered` and reaches the chapter's utterance count
- utterances already in the store are skipped, so a re-queue after `chapterAhead` renders only
  the remainder
- a thermal event holds the job at the head of the queue with its progress intact, and the
  runner resumes when it clears
- `continueAnyway()` renders through a thermal condition, and the override does not survive
  the queue draining
- `.storeFull` holds the queue
- `AudioStore.bytes(for:)` sums correctly, including for keys not present
- chapter-scoped evict clears that chapter's keys and `audioRef`s and leaves its neighbours
  alone

## Out of scope

- Persisting the queue across launches.
- Re-rendering after a voice change.
- Rendering a whole book in one action. The queue makes it possible chapter by chapter; a
  "render everything" control is a separate decision about how much of a phone's storage an
  app should claim in one tap.
