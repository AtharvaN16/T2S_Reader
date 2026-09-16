# The app status band — design

**Date:** 2026-09-15
**Owner decisions:** recorded inline, from the brainstorming session of the same day.
**Status:** design agreed; implementation plan to follow.

## Why

The voice warm-up is the app's longest wait and the only one the reader can neither start
nor stop. It has earned a good element: a breathing glow at the screen's edge, three rows of
honest words, and a bar that never goes backwards. None of that is in question here.

What is in question is that the element is not *an* element. It is four views, six hand-placed
call sites, five shared constants and three copies of the same animation, installed
differently on each of the three surfaces that show it — and because every one of those
copies names `Tokens` directly, it is the wrong colour on the one screen that has a palette
of its own.

The owner's report, 2026-09-15: "the warm-up glow in the reader looks weird, it has like a
different color sometimes. It also the progress indicator also has a separate header."

Both are true, both have the same root, and the root is that the element has no owner.

## What exists today

Established by reading the code, not assumed.

### The pieces

| Piece | Where | Job |
|---|---|---|
| `KokoroStatusModel` | `App/T2SReader/System/KokoroComposition.swift` | the state: phase, `readyAt`, `warmUpProgressFloor`, install bytes |
| `WarmUpReading` | `Sources/T2SApp/Playback/WarmUpReading.swift` | a plain value: title, message cycle, value slot, tone, bar segments. 30 tests |
| `WarmRim(edge:)` | `App/T2SReader/Design/WarmUpVeil.swift:279` | the glow — a faint wash and a twice-stroked bezel at the real screen radius, breathing off the wall clock, dithered against 8-bit banding |
| `WarmUpLine(band:)` | `App/T2SReader/Design/WarmUpVeil.swift:419` | the three rows: title / subtext · value / an 88 × 5 segmented bar |
| `TopFade(inset:extra:fade:)` | `App/T2SReader/Design/TopFade.swift:19` | the opaque ground the rows stand on |

`WarmUpVeil.swift` is 639 lines and has been changed in 31 commits. `TopFade.swift` is 112
lines over 9. That churn is not carelessness — nearly every commit fixed a real, reported
defect — but it is the signal that the arrangement, not the drawing, is what keeps failing.

### It is an overlay, and deliberately so

Until 2026-09-12 the glow sat *behind* the pages as an opaque `WarmRamp`, with every ground
bar painting a matching copy of the same ramp into itself so bar and page read as one
surface. That trick holds only while every layer between the veil and the bar is transparent.
Where one was not, the glow was cut off at the bar's foot with nothing in the code to say
why — it cost the Voice page a seam and the Reader its bottom 34 pt.

The fix was to lift the light above everything as `WarmRim`, a glow with no ground under it.
That is the right call and this design keeps it. What it did not do is give the overlay an
owner: each host still installs it by hand.

### The wiring, counted

- **`WarmRim` × 6** — `RootPager.swift:107,114`; `ReaderPage.swift:138,146`;
  `SettingsSubpage.swift:60,64`.
- **`WarmUpLine` × 2** — `RootPager.swift:116`; `ReaderPage.swift:162`.
- **`TopFade` with warm arguments × 2, configured differently in each.** The pager passes
  `warmSolid: 36` / `warmFade: 116` so a scrolling page title reads *through* the ramp; the
  Reader passes `extra: WarmUpLine.bandHeight` fully opaque, because `topBar` brings its own
  ground and picks up where the rows end.
- **Three independent copies of the fade.** `RootPager`, `ReaderPage:127` and
  `ReaderPage:301` each read `WarmUpVeil.isShowing(env)` separately and each apply their own
  `.animation(.easeInOut(duration: WarmUpVeil.fadeOut), value:)`. They have to agree on the
  same frame, or the Reader's title steps down into rows that are not there.
- **Five shared constants** every host must respect: `WarmUpLine.bandHeight` (54),
  `WarmUpVeil.fadeOut` (1.5), `TopFade.warmSolid` (36), `TopFade.warmFade` (116),
  `WarmRamp.height` (240).
- **Gating disagrees.** `RootPager` gates both rims on `!chrome.isSubpageOpen` but leaves
  `WarmUpLine` ungated; `SettingsSubpage` draws its own rims and no line.

### The colour defect

Every part of the element names app tokens: `TopFade` fills `Tokens.ground`, `WarmUpLine`
uses `Tokens.ink` and `Tokens.ink3`, `WarmRim` uses `Tokens.glow` and `Tokens.glowReady`.

The Reader does not paint in app tokens. It paints in `ReaderPalette` — sixteen papers
(`App/T2SReader/Design/ReaderPalette.swift`), set per reader and applied to the page, the
chrome and the Reader's own sheets.

So while the warm-up is up in the Reader, the top `inset + 54` pt is app grey `#F8F8F7`
standing on whatever paper the reader chose. On Sepia (`#F4ECDB`) that is a near-match that
still shows as a seam. On the pop papers it is not close to anything: Cherry is `#FF6B60`,
Sunflower `#FFD028`, Cobalt `#5D97FF`. A white slab across the top of a saturated page, with
a fixed `#0066FF` blue composited over the slab rather than over the paper.

This is exactly "a different color sometimes": on the default Paper the band matches almost
perfectly, so the defect only appears once the reader has changed paper.

`TopFade` does not take a colour parameter at all. There is currently no way to ask it for
one.

### The second header

The Reader's `topBar` pads down by exactly `WarmUpLine.bandHeight` while the wait is up
(`ReaderPage.swift:300`), on the glow's own timing. Two headers therefore stack during a
warm-up: the status band owns the top 54 pt, and the book's title bar sits under it.

The root pager solves the same collision a third way — the title stays put and dissolves
under a 116 pt ramp. `Spacing.titleTop` was 56 for exactly this reason until 2026-09-12, when
the clearance moved into `TopFade` and the title was freed to sit at 40.

### Other renderings of the same idea

Not part of the element, but they show that "a job is running" has no single home:
`WarmingDot` plus "Preparing the voice…" as the Reader's loading placeholder
(`ReaderPage.swift:71`), `PlayerStatusLine`, and the `ProgressBar` / `ChapterBar` /
`CircularProgress` family in `Primitives.swift`.

## Decisions

| Question | Decision |
|---|---|
| Scope | One status surface any long job can drive; the warm-up becomes its first client, not its owner |
| Which jobs ship with it | **Voice only.** Rendering and import are resolvers added later, once the band has been seen to behave |
| Two jobs at once | Never. One slot, one reading; voice outranks everything |
| A displaced job | Does not queue to show later — by then its news is stale |
| Where colour comes from | `@Environment(\.readerPalette)`, which is already `ReaderPalette.app` outside the Reader |
| The glow's hue | Stays the app's blue and green on every paper — a pop paper has no second hue to spare, and the ending is signalled by hue |
| Header collision | The band publishes its height; each host consumes it its own way |
| The glow's internals | Untouched — the bezel radius, the dither, the wall-clock breath all stay as they are |

## Architecture

### `StatusReading`

New, `Sources/T2SApp/Status/StatusReading.swift`, a plain `Sendable` value.

```swift
public struct StatusReading: Sendable, Equatable {
    public enum Tone: Sendable { case waiting, ready, failed }
    public var kind: StatusKind      // .voice, .render, .import — identity, and precedence
    public var title: String         // never moves
    public var messages: [String]    // the cycle beneath it, the only thing that animates
    public var value: String?        // megabytes, or the clock, or "3 of 12"
    public var progress: Double      // 0…1, never retreating
    public var segments: [Double]    // [1] is a plain bar
    public var tone: Tone
}
```

This is `WarmUpReading`'s shape with the Kokoro phases lifted out. The cycle timing
(`dwell`, `cycleFloor`, `stickPoint`) and `message(elapsed:)` move here with it, because they
are properties of a cycling status row and not of a voice.

**`WarmUpReading` stays where it is** and gains one computed `var reading: StatusReading`. Its
`Phase` enum, its two message cycles and all 30 of its tests are untouched. This is the whole
reason to generalise the shape rather than the logic: the warm-up's phase mapping is the part
that has been hard-won and tested, and nothing about it should move.

### `AppStatusModel`

New, `Sources/T2SApp/Status/AppStatusModel.swift`, `@MainActor @Observable`, owned by
`AppEnvironment`.

```swift
@MainActor @Observable
public final class AppStatusModel {
    public private(set) var current: StatusReading?
    public func publish(_ reading: StatusReading?, for kind: StatusKind)
}
```

One slot. `publish` stores per kind and recomputes `current` as the highest-ranked non-nil
reading. Rank is fixed and declared on `StatusKind`: **voice > render > import**.

Voice outranks everything because it is the one wait the reader can neither start nor stop,
and the one that blocks all audio until it ends. A render the reader asked for can wait its
turn; the voice cannot be asked to.

The warm-up's own end beat (`readyAt`, `readyBeatEnded`, the green and amber holds) stays in
`KokoroStatusModel` exactly as it is. The status model is a slot, not a state machine — it
learns nothing about *why* a reading ends, which is what keeps a second client from having to
understand the first one's timing.

### `StatusBand`

New, `App/T2SReader/Design/StatusBand.swift`. One view and one modifier:

```swift
extension View { func appStatusBand() -> some View }
```

It draws, in this order — the order that is known to work, and the reason it is known is
written in `WarmUpVeil`'s own notes:

1. the ground (today's `TopFade`, now palette-coloured),
2. `WarmRim(edge: .top)`,
3. `WarmRim(edge: .bottom)`,
4. the rows.

It owns the single read of "is something showing" and the single
`.animation(.easeInOut(duration: fadeOut), value:)`. The three hand-copied animations and the
six hand-placed rims go.

`WarmRim` and the `WarmRamp` drawing helpers stay in `WarmUpVeil.swift`, which is renamed
`StatusGlow.swift` and loses everything that knows about Kokoro. The file keeps its long
comments; they are the record of six separate defects and are worth more than the tidiness of
deleting them.

**Hosts:** `RootPager`, `ReaderPage`, `SettingsSubpage`, each with one line. The gating
disagreement resolves itself — the modifier makes one decision for all three.

### The header, honestly

The Reader's header is fixed chrome. The root pages' titles scroll inside a `ScrollView`. One
merged header cannot be both, and pretending otherwise is how the current arrangement grew
two constants where it needed one.

So the band publishes its height through a `PreferenceKey`, and each host consumes it in the
way its own layout allows:

- **Reader** — `topBar` offsets by the published height. Two headers become one stack with
  one ground; `.padding(.top, isWarmUpShowing ? WarmUpLine.bandHeight : 0)` and the animation
  beside it go.
- **Root pager** — keeps its ramp, because a scrolling title has to be read *through*
  something rather than pushed. `TopFade.warmSolid` derives from the published height less the
  18 pt that keeps its hard edge off the top of the title.
- **Settings subpage** — unchanged in appearance; it shows rims and no rows today and will
  continue to.

`WarmUpLine.bandHeight`, `TopFade.warmSolid` and the `Spacing.titleTop` clearance history
collapse into one measured number.

**`TopFade.warmFade` (116) stays a hand-tuned constant**, and claiming otherwise would be the
same mistake this design is meant to undo. It is not a clearance — it is how long a ramp has
to be before it reads as smooth rather than as a gradient across one row of text. It was
raised from 76 by eye on the owner's word and has no relationship to the band's height. A
number that was tuned by looking should not be dressed up as a number that was derived.

`TopFade` itself stays a general component: the root pager and `SettingsSubpage` both use it
outside a warm-up, and the band uses it for its ground rather than replacing it.

### Colour

Every colour in the band is read from `@Environment(\.readerPalette)`.

Outside the Reader that environment value is already `ReaderPalette.app`
(`ReaderPalette.swift:168`), which is the app's own greys. **Nothing outside the Reader
changes appearance.** That existing default is the entire reason this is a small change
rather than a repaint.

Inside the Reader: ground becomes `palette.page`, the title and value `palette.ink`, the
subtext `palette.ink2`, the bar's unfilled track `palette.ink3`.

For the light itself, `ReaderPalette` gains two members so that a paper *can* speak for the
glow later:

```swift
var glow: Color        // the wait
var glowReady: Color   // the last beat
```

**Every paper ships with the app's own values** — `Tokens.glow` and `Tokens.glowReady`,
unchanged, on all sixteen. The light stays blue and ends green everywhere.

This was nearly not the decision, and the reason it is worth recording. The first cut had the
pop papers take `palette.accent` for the wait and `palette.positive` for the ending, so the
light would come from the paper rather than clash with it. Both of those are defined as
`mixed(0.70)` in the pop branch of `ReaderPalette.init` — *the same value*. The ending would
have arrived in exactly the colour of the wait, and the whole last beat of the warm-up, which
exists to say "done", would have said nothing at all on six papers.

The glow's ending is carried by hue, and a pop paper has already spent its hue on the page.
So the hue stays the app's. What changes in the Reader is the ground and the lettering, which
is precisely the defect that was reported: a white slab under a blue light on a coloured page.
Blue light falling *on* Cherry may still want tuning — that is what the photographs are for,
and it is a tuning question to answer with a frame in hand rather than a rule to guess at now.

The amber failure ending keeps using `palette.accent`, as it does today via `Tokens.accent`.

## Testing

- **`StatusReading`** — the 30 existing `WarmUpReadingTests` move across unchanged, exercising
  `WarmUpReading.reading` instead of the value directly. They are the guard that the
  generalisation changed no words and no timing.
- **`AppStatusModel`** — new unit tests for precedence: voice displaces render; a displaced
  reading does not reappear when the higher-ranked one clears; publishing nil for one kind
  falls back to the next.
- **The look** — photographed, not asserted. The Reader on three papers (Paper, Sepia,
  Cherry) under `T2S_WARMUP=1`, which fakes a warm-up and holds the pulse still so the frames
  are comparable, plus `T2S_WARMUP=green` and `=failed` for the two endings. The root pager
  and a Settings subpage are photographed before and after as regression frames: those two
  must be pixel-identical, since nothing about their palette changed.

## Out of scope

- **Rendering, import and sync as status clients.** The seam is built and the rank order is
  declared; the resolvers are not written. `ChapterRenderRunner` already exposes everything
  one would need — `queue`, `isWorking`, `hold`, and `fraction` per job — so this is a later
  addition, not a later redesign.
- **`PlayerStatusLine`, `WarmingDot`, `ProgressBar`, `ChapterBar`, `CircularProgress`.** They
  are other renderings of "something is happening", but they are inline marks on rows and
  controls rather than an app-wide band. Folding them in is a separate question.
- **The glow's own drawing.** The bezel radius read through KVC, the dither tile, the breath
  period, the ramp height: all unchanged. Every one of them was measured against a real
  complaint and none of them is what makes this element hard to reuse.
- **The Settings subpage's missing top rim.** `WarmUpVeil` records it as unfinished and
  deliberately not guessed at. It stays that way.
