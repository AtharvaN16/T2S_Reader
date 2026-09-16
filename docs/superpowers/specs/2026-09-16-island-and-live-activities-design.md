# The mock island and the Live Activities — design

**Date:** 2026-09-16
**Owner decisions:** recorded inline, from the brainstorming session of the same day.
**Status:** design proposed; not yet agreed. No code written.

## Why

Two different questions, which today have one answer between them and it is the wrong one
for both.

**In the app:** a chapter finishes rendering and a card slides up from the bottom of the
screen with the book's cover and a Play button (`RootPager.swift:379`). That works. It is
also the only place in the app where something *arrives* rather than being asked for, and
it reads as the same weight as "Could not save a bookmark".

**Outside the app:** nothing. A render started from the Book sheet runs for minutes under
`BGTaskScheduler` (`com.t2s.reader.prepare`) and says nothing at all until you come back and
open the app. The reader who most needs telling — the one who started an eight-chapter batch
and put the phone in their pocket — is the one the app cannot reach.

The owner's starting idea was to move the toasts into the Dynamic Island. Research during
the session established that this is two features, not one, and that the obvious reading of
"use the Dynamic Island" does not work:

> **A Live Activity is not shown while its own app is in the foreground.** It begins showing
> in compact presentation only once the app is backgrounded. Apple's real API cannot produce
> an in-app island effect. Apps that appear to do so (Brink, among others) draw an ordinary
> SwiftUI view at the top of the screen, shaped to look like the island.

So the in-app effect and the out-of-app effect are built from different materials, and the
design below keeps them separate on purpose.

## What exists today

Established by reading the code, not assumed.

| Piece | Where | Job |
|---|---|---|
| `ChapterRenderRunner` | `Sources/T2SApp/Playback/ChapterRenderRunner.swift` | the render queue: `queue: [ChapterRenderJob]`, `hold`, `finishCount`, `lastFinished`, `lastCompletion` |
| `ChapterRenderJob` | same file, :10 | one chapter: `utteranceCount`, `rendered`, `fraction`, `.queued/.running/.ready/.failed` |
| `ToastCenter` / `Toast` | `App/T2SReader/Design/` | the message cards; four families, six messages |
| `AppStatusModel` / `StatusRows` | `Sources/T2SApp/Status/`, `App/T2SReader/Design/StatusBand.swift` | the top strip. **One source registered** (`VoiceStatusSource`, `AppEnvironment.swift:187`); `.render` and `.import` are reserved names with nothing behind them |
| `StatusBandHost` / `PassthroughWindow` | `App/T2SReader/Design/StatusBandWindow.swift` | a `UIWindow` at `.normal + 1` whose `hitTest` returns nil for **every** point |
| `SleepTimer` | `Sources/T2SApp/Playback/SleepTimer.swift` | `active: SleepOption?`, `remainingSeconds`, a private `deadline: Date?`, `caption` |
| `NowPlayingController` | `App/T2SReader/System/NowPlayingController.swift:212` | already publishes title, author, duration and artwork to `MPNowPlayingInfoCenter` |
| `T2SReaderShare` | `App/project.yml:169` | the existing `type: app-extension` target — the pattern a widget extension follows |

Two facts from this table carry most of the design:

- **The render toast is already per-chapter, by decision.** `RootPager.swift:233` watches
  `finishCount` and reads `lastFinished`. The comment records the reversal: "Per chapter, not
  per drain (owner, 2026-09-14). A chapter becoming playable is the event worth a message."
  `lastCompletion` — the queue-level summary — survives unused.
- **The app group already exists.** `T2S_APP_GROUP: group.com.t2s.reader` (`project.yml:16`),
  read back through `T2SAppGroupIdentifier`. A widget extension can join it without inventing
  anything.

## The three pieces

### 1. The mock island — in-app, one message

**What it carries.** Exactly one thing: a chapter has finished rendering. Cover, one bold
line, one quiet line, and a round Play button.

> **Owner, 2026-09-16:** no live progress in the capsule. "It will take too much space, and
> this is something the book sheet rendering box handles. The only benefit of the rendering
> done in mock island is whichever page you are on, you can actually see it."

That is the whole case for it, and it is a good one: the Book sheet's progress box only
exists while the Book sheet is open. The capsule reaches you on Home, in the Collection, in
the queue, in the Reader.

**Shape.** A black capsule whose top edge sits at the real island's top edge — **126 × 37.33
pt, 11 pt from the top of the screen** — so it begins as the island and grows downward. Those
numbers are community-measured, not published by Apple; Apple documents only the 36 pt
compact height and the 144 pt expanded maximum. They must be checked against a photograph
before anyone trusts them.
Cover on the left, two lines in the middle, Play on the right. It shrinks back into the
island when dismissed or when its four seconds are up.

**Where it lives, and the one thing that blocks it.** It must be above every presentation —
the Reader is a `fullScreenCover`, the Book sheet is a sheet — which is the same problem the
status band already solved with a `UIWindow` at `.normal + 1`. The capsule takes a second
window at `.normal + 2`.

But `PassthroughWindow` returns nil from `hitTest` for every point, deliberately: without
that the band would eat the Reader's tap-to-hide-chrome, the pager's page swipe and every
pushed Settings page's back-swipe. **A capsule with a Play button cannot use it.** The
capsule's window needs selective hit-testing — nil everywhere except inside the capsule's
own rect — which is a new window, not a change to the band's.

> **Owner, 2026-09-16:** the warm-up band is not to be touched. This design does not touch it.
> The two will look like strangers until someone reconciles them; that is deliberately left
> for later.

**Non-island devices.** Same cover, same words, same Play button — but a plain rounded card
that slides down from under the status bar. No pretending to be hardware that is not there.
This was the owner's own instinct in the first message of the session and it is right.

**The detection problem, which is the real risk.** To sit at 11 pt from the top the code must
know the device has an island; 11 pt on a notch phone puts the capsule through the notch.
Apple DTS, on the record: *"We don't recommend you doing this and there's no first-party API
that provides support for detecting whether a device has a notch or island."* Both community
heuristics — `safeAreaInsets.bottom > 0` and `safeAreaInsets.top > 20` — **broke in iOS 26.**

**Decision: match on `utsname.machine` model identifiers** (`iPhone15,2`…), not safe-area
arithmetic. It is unglamorous, it survived iOS 26, and it fails safe: an unrecognised
identifier falls through to the plain top card. Cost is a list topped up each September, in
one file, with a test that fails loudly when the list and the fallback disagree.

**Seeing it.** The owner's phone is an iPhone 11 Pro — notch, no island — so this can only be
judged on the simulator, which has island devices and needs no signing at all.

### 2. The render Live Activity — out of the app

**Why the queue and not the chapter.** The question you ask away from the phone is not "how
is chapter 4?" but "is my book ready?". And `BookSheet.swift:734` sends a multi-select batch
(`chapters: picked`), so eight chapters would mean eight activities starting and ending in
sequence — a card that vanishes and reappears eight times, against a system cap on concurrent
activities. One activity per batch has a clean beginning and a clean end, which is the shape
ActivityKit is built around.

**Its life.**

| Moment | The card says |
|---|---|
| Batch committed | "The Siege of Delhi — 0 of 8 chapters ready", progress bar at 0 |
| Resting | "… — 3 of 8 chapters ready" |
| A chapter finishes | flashes "Chapter 4 is ready", island expands, banner on the Lock Screen |
| A few seconds later | back to resting, now "4 of 8" |
| Batch done | "The Siege of Delhi is ready", then dismisses itself |
| Held (`Hold.hot` / `.storeFull` / `.byReader`) | the hold's own sentence, bar frozen, no alert |

The flash is an *alerting* update — ActivityKit's own mechanism, not a hack.

**Alerting frequency — an assumption, flagged.** The owner's instruction is that a finished
chapter is announced by the Live Activity whenever the app is closed, which implies **every**
chapter alerts. That is what this design specifies. It also means an eight-chapter batch
buzzes eight times in a pocket. The quieter alternative — alert only on the last, update the
number silently for the rest — is one boolean per update and can be changed after the first
time anyone lives with it. **This needs the owner's confirmation before implementation.**

**Who announces a finished chapter.** Never both.

> **Owner, 2026-09-16:** "we will be using live activity for when the app is closed and the
> mock island for when the app is open."

`scenePhase` is already threaded through `RootPager.swift:46` and `:259`. Foreground → the
mock island speaks, the card updates silently. Backgrounded → the card alerts, no toast is
queued up to ambush the reader on return.

**No server needed.** The app is awake during its own background render, so it updates its own
activity.

### 3. The sleep timer Live Activity

The cheapest good thing in this document. `SleepTimer` already stores a `deadline: Date`, and
a Live Activity can count down from a stored date **with no updates at all** — the app never
wakes, there is no battery cost and no update budget to manage. "Sleeps in 12:34" on the Lock
Screen, with a button to add five minutes or stop.

And it is the one feature where being out of the app is guaranteed: phone face-down, screen
off, someone falling asleep.

`SleepOption.endOfChapter` has no deadline, so that variant reads "Until the end of
Chapter 4" with no countdown and no ticking.

## What this deliberately does not do

- **Does not touch the warm-up band.** Owner's instruction.
- **Does not add render progress to the band.** `.render` stays a reserved name.
- **Drops the voice-download Live Activity.** Considered and cut (owner, 2026-09-16) — it
  fires once per install, which does not repay an extension target on its own.
- **Does not duplicate Now Playing.** `NowPlayingController` already gives the Lock Screen and
  the island the cover, title and duration during playback, free. Apple's guidance is not to
  rebuild media playback as a Live Activity, and a hand-built copy would be worse.
- **Moves no other toast.** Bookmarks keep their two pills and their place near the thumb;
  "Voice model removed" keeps its sentence and its Download button; the failures stay
  ordinary. The island silhouette holds one glyph, two lines and one button, and nothing else
  in the app fits that budget.

## Cost, honestly

One widget extension target, added to `App/project.yml` the way `T2SReaderShare` is, and
regenerated with `xcodegen generate`. It needs its own App ID, which costs nothing in money
but one slot from the free team's budget of ten per seven days — **and only on the day it is
installed on the phone.** The simulator needs no signing, so pieces 2 and 3 can be built and
watched working before any ID is spent.

Piece 1 needs no extension at all.

The views that draw a Live Activity only compile inside a widget extension, so those cannot
be written in the app target and moved later. Everything else — the state that describes what
the card shows, and the object that decides when to start, update and end it — is plain Swift
in `T2SApp`, testable with no extension present.

## Testing

- **Plain values, tested in `T2SApp`:** the card's contents for every state in the table above
  — resting, flashing, held, done — as a pure function of `ChapterRenderRunner`'s queue. This
  is the `StatusReading` pattern and it is the bulk of the logic.
- **The model-identifier list:** a test that every identifier in the island list is an island
  device and that an unknown identifier returns the plain-card fallback.
- **Foreground/background exclusivity:** a test that a finished chapter produces exactly one
  announcement, and which one depends on `scenePhase`.
- **On the simulator:** the capsule, on an island device, filmed with the existing
  video → frames → ffmpeg tile recipe.
- **Not tested here:** the capsule's alignment against real hardware. That needs an island
  phone and belongs to a device spike.

## Order of work

1. **The mock island.** Self-contained, no extension, no App ID, visible on the simulator
   immediately.
2. **The render Live Activity.** Pays for the extension target.
3. **The sleep timer Live Activity.** Nearly free once the target exists.

## Open question

The alerting frequency in piece 2 — every chapter, or only the last. Specified as every
chapter, per the owner's instruction; flagged because eight buzzes in a pocket is a different
experience from one, and it is a one-line change either way.
