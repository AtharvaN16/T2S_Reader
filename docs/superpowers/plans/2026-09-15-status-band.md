# App Status Band Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the voice warm-up's glow, words and ground a single owner — one status band that any long-running job can drive, that takes its colours from whatever palette it is standing in, and that a screen adopts with one line.

**Architecture:** A `StatusReading` value (what to say), a `StatusSource` protocol with an `AppStatusModel` registry that picks one source at a time by rank, and a `.appStatusBand()` modifier that draws ground + rims + rows. `WarmUpReading`'s phase mapping and its 30 tests do not move. The glow's own drawing does not move.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Suite` / `@Test` / `#expect`), SwiftPM root package `T2S`, XcodeGen for the app target.

**Spec:** `docs/superpowers/specs/2026-09-15-status-band-design.md`

## Global Constraints

- **Owner's direction for this run (2026-09-15):** minimal tests — a test must earn its place; no per-task review; **one review at the end only**. This overrides the skill's default per-task TDD gate. Tasks below state their own verification, which is usually a compile plus `swift test`.
- **Semantic tokens only.** No view names a literal colour (spec §2.4.2). The band names `palette.*`; `Tokens.*` only where the palette itself defines it.
- **The glow's drawing is untouched.** `WarmRamp.bezelRadius` (KVC read), `ditherTile`, `pulse(at:)`, `height` (240), `wash`, `bezel` — all move file verbatim, no edits.
- **Nothing outside the Reader may change appearance.** `ReaderPalette.app` is already the environment default outside the Reader (`ReaderPalette.swift:168`), so the palette swap must be a no-op there.
- **The glow's hue stays the app's blue and green on every paper.** A pop paper's `accent` and `positive` are the same value, so deriving the ending's colour from the paper would silence it.
- **Run `swift test` from the repo root** (macOS, root package only). The app target is built with `scripts/build-app.sh` — **one `xcodebuild` at a time, never two in parallel.**
- **Do not run the app with sound.** Simulator only, `SIMCTL_CHILD_T2S_SILENT=1`.

## Execution waves

Files are disjoint within each wave, so every task in a wave can run in parallel.

| Wave | Tasks | Verified by |
|---|---|---|
| 1 | 1 `StatusReading` · 2 `ReaderPalette` · 3 `TopFade` | `swift test` (Task 1 only) |
| 2 | 4 `AppStatusModel` · 5 `StatusGlow` + `StatusBand` | `swift test` (Task 4 only) |
| 3 | 6 `VoiceStatusSource` · 7 `RootPager` · 8 `ReaderPage` · 9 `SettingsSubpage` | — |
| 4 | 10 build, wire, photograph | `scripts/build-app.sh`, then the simulator |

Waves 1–3 leave the app target non-compiling in between, on purpose: the hosts in wave 3 call a modifier wave 2 creates, and the old views are deleted as the new ones land. Wave 4 is the first honest build. Tasks 1 and 4 are in the SwiftPM package and *are* independently verifiable, which is why they carry the only tests.

---

### Task 1: `StatusReading` — the source-agnostic value

**Files:**
- Create: `Sources/T2SApp/Status/StatusReading.swift`
- Modify: `Sources/T2SApp/Playback/WarmUpReading.swift`
- Test: `Tests/T2SAppTests/WarmUpReadingTests.swift` (add one test; **change nothing that is already there**)

**Interfaces:**
- Produces: `StatusKind` (`.voice`, `.render`, `.import`, with `rank: Int`), `StatusReading` (init + `title`, `messages`, `value`, `progress`, `segments`, `tone`, `collapsesSubtext`, `message(elapsed:)`, `StatusReading.dwell`, `.cycleFloor`, `.stickPoint`), and `WarmUpReading.reading`.
- Consumes: nothing.

- [ ] **Step 1: Create the value**

`Sources/T2SApp/Status/StatusReading.swift`:

```swift
// Sources/T2SApp/Status/StatusReading.swift
import Foundation

/// Which job is speaking. Identity, and the order the band picks between them: the voice
/// outranks everything because it is the one wait the reader can neither start nor stop, and
/// the one that blocks all audio until it ends. A render they asked for can wait its turn.
public enum StatusKind: Sendable, Hashable, CaseIterable {
    case voice, render, `import`

    /// Lower wins. Fixed, not configurable: a precedence a caller can set is a precedence that
    /// disagrees with itself somewhere.
    public var rank: Int {
        switch self {
        case .voice: 0
        case .render: 1
        case .import: 2
        }
    }
}

/// Everything the status band says, worked out from one job's state and nothing else.
///
/// This is `WarmUpReading`'s shape with the Kokoro phases lifted out of it. The warm-up keeps
/// its own phase mapping — that is the part that has been hard-won and tested — and hands one
/// of these over. A second job writes a resolver and says nothing about views.
public struct StatusReading: Sendable, Equatable {
    /// How the band is lit. `waiting` is the blue, `ready` the green, `failed` the amber.
    public enum Tone: Sendable, Hashable { case waiting, ready, failed }

    /// How long one message is held before the next, in seconds.
    public static let dwell: Double = 3.2
    /// Under this many seconds left there is nothing worth cycling: a message would be swapped
    /// once and the wait would be over.
    public static let cycleFloor = 12
    /// Past this much of the bar the cycle stops on its last message and stays there — "almost
    /// done" is the truest thing left, and rotating off it reads as the wait starting over.
    public static let stickPoint = 0.92

    public var kind: StatusKind
    /// Names what is happening. Never moves.
    public var title: String
    /// The cycle in the row beneath the title — the only thing that animates.
    public var messages: [String]
    /// The slot beside it: megabytes, a clock, "3 of 12". Never takes part in the cycle.
    public var value: String?
    /// 0…1 across the whole job, never retreating.
    public var progress: Double
    /// Relative segment widths for the bar. `[1]` is a plain bar.
    public var segments: [Double]
    public var tone: Tone
    /// Whether the subtext row closes rather than holding its height. True only at the very end,
    /// where nothing follows but the fade; every other empty row keeps its height, or the bar
    /// drops 13 pt and is pulled straight back.
    public var collapsesSubtext: Bool

    public init(kind: StatusKind, title: String, messages: [String] = [], value: String? = nil,
                progress: Double, segments: [Double] = [1], tone: Tone = .waiting,
                collapsesSubtext: Bool = false) {
        self.kind = kind
        self.title = title
        self.messages = messages
        self.value = value
        self.progress = min(1, max(0, progress))
        self.segments = segments
        self.tone = tone
        self.collapsesSubtext = collapsesSubtext
    }

    /// Which message is showing, `elapsed` seconds in. Nil when there is nothing to say. Past
    /// ``stickPoint`` the cycle stops on its last message rather than wrapping.
    public func message(elapsed: TimeInterval) -> String? {
        guard !messages.isEmpty else { return nil }
        guard messages.count > 1 else { return messages[0] }
        guard progress < Self.stickPoint else { return messages[messages.count - 1] }
        return messages[Int(max(0, elapsed) / Self.dwell) % messages.count]
    }
}
```

- [ ] **Step 2: Point `WarmUpReading`'s constants at the new single truth**

In `Sources/T2SApp/Playback/WarmUpReading.swift`, replace the three stored constants
(`dwell`, `cycleFloor`, `stickPoint` — currently declared with their own literal values) with
aliases, keeping the doc comments above each:

```swift
    public static let dwell = StatusReading.dwell
    public static let cycleFloor = StatusReading.cycleFloor
    public static let stickPoint = StatusReading.stickPoint
```

Do **not** delete them: `WarmUpReading.cycleFloor` is read by its own `messages` switch.

- [ ] **Step 3: Add the bridge**

At the end of `WarmUpReading`, before the closing brace:

```swift
    /// This wait, as the band's own value. The phases stay here; only the shape crosses over.
    public var reading: StatusReading {
        StatusReading(kind: .voice, title: title, messages: messages, value: value,
                      progress: progress, segments: segments, tone: bandTone,
                      collapsesSubtext: collapsesSubtext)
    }

    private var bandTone: StatusReading.Tone {
        switch tone {
        case .waiting: .waiting
        case .ready: .ready
        case .failed: .failed
        }
    }
```

- [ ] **Step 4: Add the one test that earns its place**

The existing 30 tests all exercise instance members and need **no edits** — they are the
regression guard that the words and timing did not change. Add one test that the bridge carries
them across faithfully. Append inside `@Suite struct WarmUpReadingTests`:

```swift
    // MARK: the bridge to the band

    @Test func theBandReadingCarriesTheSameWordsAndShape() {
        let warm = WarmUpReading(phase: .downloading(received: 123, total: 350), progress: 0.4)
        let reading = warm.reading
        #expect(reading.kind == .voice)
        #expect(reading.title == warm.title)
        #expect(reading.messages == warm.messages)
        #expect(reading.value == warm.value)
        #expect(reading.segments == warm.segments)
        #expect(reading.tone == .waiting)
        #expect(reading.message(elapsed: 0) == warm.message(elapsed: 0))
        #expect(reading.message(elapsed: 4) == warm.message(elapsed: 4))
    }

    @Test func aFailedWaitCrossesOverAsFailed() {
        #expect(WarmUpReading(phase: .failed(.warmUp), progress: 0.8).reading.tone == .failed)
        #expect(WarmUpReading(phase: .ready(buildingBackgroundSet: false), progress: 1).reading.tone == .ready)
    }
```

- [ ] **Step 5: Verify and commit**

Run: `swift test --filter WarmUpReadingTests`
Expected: 32 tests pass, 0 failures. If any of the original 30 fail, the generalisation changed
behaviour — fix the bridge, not the test.

```bash
git add Sources/T2SApp/Status/StatusReading.swift Sources/T2SApp/Playback/WarmUpReading.swift Tests/T2SAppTests/WarmUpReadingTests.swift
git commit -m "The warm-up's reading grows a source-agnostic shape the band can take from any job"
```

---

### Task 2: `ReaderPalette` speaks for the glow

**Files:**
- Modify: `App/T2SReader/Design/ReaderPalette.swift`

**Interfaces:**
- Produces: `ReaderPalette.glow`, `ReaderPalette.glowReady`.
- Consumes: nothing.

- [ ] **Step 1: Add the two members**

Add to the stored properties of `struct ReaderPalette`, after `var positive: Color`:

```swift
    /// The status band's light while a job runs, and the colour its last beat ends on.
    ///
    /// **The app's blue and green on every paper, including the pop ones.** The first cut had
    /// the pop papers take `accent` and `positive` so the light would come from the paper
    /// rather than clash with it — but both of those are `mixed(0.70)` in the pop branch below,
    /// *the same value*, so the ending would have arrived in exactly the colour of the wait and
    /// the whole last beat of a warm-up would have said nothing on six papers. The ending is
    /// carried by hue, and a pop paper has already spent its hue on the page.
    ///
    /// They are members rather than direct `Tokens` reads so that a paper *can* speak for the
    /// light later, with a photograph in hand, without every call site changing again.
    var glow: Color
    var glowReady: Color
```

- [ ] **Step 2: Set them in `init`**

In `init(_ paper: ReaderPaper)`, alongside the other unconditional assignments (beside
`isPop = pop`, before the `if pop {` branch):

```swift
        glow = Tokens.glow
        glowReady = Tokens.glowReady
```

Leave both branches of `if pop` alone — they must not override these.

- [ ] **Step 3: Verify `ReaderPalette.app` inherits them**

`static let app` builds from `ReaderPalette(.paper)` and then overrides individual members. It
assigns no glow, so it inherits `Tokens.glow` / `Tokens.glowReady` — which is exactly what
every screen outside the Reader must keep showing. **No change needed to `app`.** Confirm by
reading it; do not edit it.

- [ ] **Step 4: Commit**

```bash
git add App/T2SReader/Design/ReaderPalette.swift
git commit -m "A paper can speak for the status light, and every one of them says the app's blue"
```

---

### Task 3: `TopFade` takes the colour it paints

**Files:**
- Modify: `App/T2SReader/Design/TopFade.swift`

**Interfaces:**
- Produces: `TopFade(inset:extra:fade:colour:)` — new trailing parameter `colour: Color = Tokens.ground`; `EdgeFade(edge:height:colour:)` likewise.
- Consumes: nothing.

- [ ] **Step 1: Give `TopFade` a colour**

Add the stored property after `var fade: CGFloat = fadeHeight`:

```swift
    /// The ground this paints. `Tokens.ground` is the app's, and is what every caller outside
    /// the Reader wants; the Reader passes its paper, because a band of app grey across the top
    /// of a chosen paper is the seam the owner reported on 2026-09-15.
    var colour: Color = Tokens.ground
```

In `body`, replace `Tokens.ground` with `colour`. Change nothing else — the mask, the
`ignoresSafeArea`, the `warmSolid` / `warmFade` constants and `shape(solidThrough:fade:)` all
stay exactly as they are.

- [ ] **Step 2: Give `EdgeFade` the same**

In `struct EdgeFade`, add after `var height: CGFloat = 28`:

```swift
    /// As `TopFade.colour`: the app's ground unless a caller is standing on its own paper.
    var colour: Color = Tokens.ground
```

and replace `Tokens.ground` with `colour` in its body.

- [ ] **Step 3: Verify no call site breaks**

Both parameters are defaulted, so every existing call compiles unchanged. Confirm with:

Run: `grep -rn "TopFade(\|EdgeFade(" App --include="*.swift"`
Expected: every hit uses labelled arguments already present on the type; none needs editing.

- [ ] **Step 4: Commit**

```bash
git add App/T2SReader/Design/TopFade.swift
git commit -m "The top fade paints the colour it is handed, and by default that is the app's own"
```

---

### Task 4: `AppStatusModel` — one slot, ranked

**Files:**
- Create: `Sources/T2SApp/Status/AppStatusModel.swift`
- Test: `Tests/T2SAppTests/AppStatusModelTests.swift`

**Interfaces:**
- Consumes: `StatusKind`, `StatusReading` (Task 1).
- Produces: `StatusSource` protocol (`var kind: StatusKind`, `func reading(now: Date) -> StatusReading?`), `AppStatusModel` (`register(_:)`, `current(now:) -> StatusReading?`, `var isShowing: Bool`).

**Note on the spec:** the design said `publish(_:for:)`. Pulling turned out to be the better
shape and this plan uses it: the warm-up's clock re-resolves twice a second, and pushing every
tick through an `@Observable` would wake every observer of the model for a number only the band
reads. Sources are registered once and asked for a reading per frame instead.

- [ ] **Step 1: Create the model**

`Sources/T2SApp/Status/AppStatusModel.swift`:

```swift
// Sources/T2SApp/Status/AppStatusModel.swift
import Foundation
import Observation

/// A job that can speak in the status band. Implemented once per job, and it says nothing about
/// views: given the time, either it has something for the reader or it does not.
@MainActor
public protocol StatusSource: AnyObject {
    var kind: StatusKind { get }
    /// This job's state as the band would say it, or nil when the job has nothing to show.
    func reading(now: Date) -> StatusReading?
}

/// The band's one slot.
///
/// **One at a time, and never a queue.** A source that is outranked simply does not show; it is
/// not held to be shown later, because by the time the slot frees a stale wait is not news. The
/// order is `StatusKind.rank` and it is fixed.
///
/// Sources are *pulled*, not pushed. The warm-up's clock re-resolves twice a second and pushing
/// each tick through an `@Observable` would wake every observer of this model for a number only
/// the band reads. `current(now:)` is called from the band's own `TimelineView` instead.
@MainActor
@Observable
public final class AppStatusModel {
    private var sources: [any StatusSource] = []

    public init() {}

    /// Adds a source, replacing any earlier one of the same kind so a re-registration on a view's
    /// second appearance cannot leave two of them answering for one job.
    public func register(_ source: any StatusSource) {
        sources.removeAll { $0.kind == source.kind }
        sources.append(source)
        sources.sort { $0.kind.rank < $1.kind.rank }
    }

    /// What the band shows at `now`: the highest-ranked source with something to say.
    public func current(now: Date) -> StatusReading? {
        for source in sources {
            if let reading = source.reading(now: now) { return reading }
        }
        return nil
    }

    /// Whether anything is showing at all — the band's fade gate, which must be a plain `Bool`
    /// and must not depend on the frame's date. No source's *silence* is time-dependent: the
    /// clock changes a reading's words, never whether there is one.
    public var isShowing: Bool { current(now: Date()) != nil }
}
```

- [ ] **Step 2: Write the tests — this is where the new branching lives**

`Tests/T2SAppTests/AppStatusModelTests.swift`:

```swift
import Foundation
import Testing
@testable import T2SApp

/// The band's one slot, and who gets it. The rank is the whole of the logic, and the case that
/// matters is the one where two jobs want the band at once: the reader must be told about the
/// voice, because it is the wait they cannot end and the one that stops all audio.
@MainActor
@Suite struct AppStatusModelTests {

    private final class Fake: StatusSource {
        let kind: StatusKind
        var reading: StatusReading?
        init(_ kind: StatusKind, showing: Bool) {
            self.kind = kind
            reading = showing ? StatusReading(kind: kind, title: "\(kind)", progress: 0.5) : nil
        }
        func reading(now: Date) -> StatusReading? { reading }
    }

    @Test func theVoiceOutranksARenderThatWantsTheBandAtTheSameTime() {
        let model = AppStatusModel()
        model.register(Fake(.render, showing: true))
        model.register(Fake(.voice, showing: true))
        #expect(model.current(now: Date())?.kind == .voice)
    }

    @Test func aLowerRankedJobTakesTheBandWhenNothingAboveItIsSpeaking() {
        let model = AppStatusModel()
        model.register(Fake(.voice, showing: false))
        model.register(Fake(.render, showing: true))
        #expect(model.current(now: Date())?.kind == .render)
    }

    @Test func nothingShowsWhenNoJobHasAnythingToSay() {
        let model = AppStatusModel()
        model.register(Fake(.voice, showing: false))
        #expect(model.current(now: Date()) == nil)
        #expect(model.isShowing == false)
    }

    @Test func registeringTheSameKindTwiceLeavesOneSourceAnsweringForIt() {
        let model = AppStatusModel()
        model.register(Fake(.voice, showing: true))
        model.register(Fake(.voice, showing: false))
        #expect(model.current(now: Date()) == nil)
    }
}
```

- [ ] **Step 3: Verify and commit**

Run: `swift test --filter AppStatusModelTests`
Expected: 4 tests pass.

```bash
git add Sources/T2SApp/Status/AppStatusModel.swift Tests/T2SAppTests/AppStatusModelTests.swift
git commit -m "One slot for the status band, and the voice outranks whatever else wants it"
```

---

### Task 5: `StatusGlow` and `StatusBand` — the drawing, with one owner

**Files:**
- Create: `App/T2SReader/Design/StatusGlow.swift` (the glow, moved)
- Create: `App/T2SReader/Design/StatusBand.swift` (the rows, the ground, the modifier)
- Delete: `App/T2SReader/Design/WarmUpVeil.swift`

**Interfaces:**
- Consumes: `StatusReading`, `StatusKind`, `AppStatusModel` (Tasks 1, 4); `ReaderPalette.glow` / `.glowReady` (Task 2); `TopFade(colour:)` (Task 3).
- Produces: `StatusGlow` (`fadeOut`, `readyEase`, `isFaked`), `StatusRim(edge:tone:settle:)`, `StatusBand` internals, and `extension View { func appStatusBand() -> some View }`.

**This is the largest task. Read `WarmUpVeil.swift` end to end before changing anything** — its
comments record six separate defects, and they must survive the move.

- [ ] **Step 1: Create `StatusGlow.swift` — the light, moved verbatim**

Move these from `WarmUpVeil.swift` **with their doc comments unchanged**:

- `enum WarmRamp` in full — `height`, `period`, `pulse(at:)`, `bezelRadius`, `wash(pulse:light:)`, `bezel(pulse:light:)`, `ditherTile`. Rename the enum to `StatusRamp`; change nothing inside it.
- `struct WarmRim` → `struct StatusRim`, keeping `body`, `footShortfall(in:)`, `windowHeight` and `rim(shortfall:)` exactly as they are, **including every comment**.

`StatusRim` changes only in where it gets its inputs. Replace its `@Environment(AppEnvironment.self) private var env` and the `WarmUpVeil.*` calls inside `rim(shortfall:)` with passed-in values:

```swift
struct StatusRim: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readerPalette) private var palette
    /// Which edge of the screen the lit rim faces.
    var edge: VerticalEdge = .bottom
    /// Nil while nothing is showing; the band's tone once there is a reading.
    var tone: StatusReading.Tone?
    /// 0…1 into the ending's colour, on the breath's own curve. Zero while the job is running.
    var settle: Double
```

and inside `rim(shortfall:)`:

```swift
        let showing = tone != nil
        ...
                let ending: Color? = switch tone {
                case .ready: palette.glowReady
                case .failed: Tokens.accent
                case .waiting, .none: nil
                }
                let breath = reduceMotion || StatusGlow.isFaked ? 1 : StatusRamp.pulse(at: context.date)
                let held = tone == .failed ? 0.66 : 1.0
                let pulse = breath + (held - breath) * settle
                let light = palette.glow.mix(with: ending ?? palette.glowReady, by: settle)
```

Everything else in that method — the dither overlay and its long comment, the `scaleEffect`,
the frames, the `padding(edge:, -shortfall)`, `allowsHitTesting`, `accessibilityHidden`, and the
`.animation(.easeInOut(duration: StatusGlow.fadeOut), value: showing)` — is unchanged.

Add the timing constants the rim and the band share:

```swift
/// The status band's timing, in one place, so the ground, the rims and the rows all leave together.
@MainActor
enum StatusGlow {
    /// How long the light takes to go, matched to half a breath so it leaves at the pace it moved.
    static let fadeOut: Double = 1.5
    /// How far into the ending's colour, eased on the same curve the breath uses. The blue takes a
    /// second and a half to breathe in; the ending takes the same to arrive, rather than cutting in
    /// over a quarter-second and reading as a flash (owner, 2026-09-12).
    static let readyEase: Double = 1.4
    /// `T2S_WARMUP=1` fakes a warm-up in the everyday build and holds the pulse still so two
    /// screenshots are comparable.
    static let isFaked = ProcessInfo.processInfo.environment["T2S_WARMUP"] != nil
}
```

- [ ] **Step 2: Create `StatusBand.swift` — the rows and the modifier**

`WarmUpLine`'s drawing moves here as a private `StatusRows` view. Take `body`, `line(_:now:)`,
`subtext(_:value:tint:)` and `bar(_:tint:)` from `WarmUpVeil.swift` **with their comments**, and
change only these things:

- It is handed a `StatusReading` instead of resolving one. Delete `reading(now:)`, `phase(_:now:)`,
  `installPhase(_:now:)`, `secondsLeft(_:now:)`, `isStalled(_:now:)`, `progress(_:now:)` and
  `megabytes(_:)` — **they move to Task 6, which is already written against them.** Do not delete
  them from the repo until Task 6 has landed; this task deletes `WarmUpVeil.swift` wholesale, so
  simply copy them into Task 6's file as part of that task, not this one.
- Colours come from the palette: `tint` becomes `palette.ink` (or `Tokens.accent` when failed),
  `barTint` uses `palette.glowReady` for `.ready` and `palette.ink` for `.waiting`, and the bar's
  unfilled capsule becomes `palette.ink3.opacity(0.6)`.
- The band height constant keeps its name and value and its comment:

```swift
    /// How far below the safe-area inset the three rows reach: 8 of top pad, the 11 pt title's
    /// ~14, the subtext row's 13 over its 2 of pad, and the bar's 5 under its 7.
    static let bandHeight: CGFloat = 54
```

Then the band itself and its modifier:

```swift
/// The status band: ground, both lit rims, and the three rows, laid over whatever the screen has
/// already painted.
///
/// **One layer, on top.** This is the arrangement `WarmUpVeil` arrived at the hard way. The light
/// used to sit *behind* the pages with every ground bar painting a matching copy of the same ramp
/// into itself, which holds only while every layer between the two is transparent; where one was
/// not, the glow was cut off at the bar's foot with nothing in the code to say why. Drawn over the
/// page instead, it needs nothing underneath to cooperate.
///
/// **And one owner.** Every screen used to install this by hand — six `WarmRim`s, two `WarmUpLine`s,
/// two differently-configured `TopFade`s and three separate copies of the same fade animation, which
/// had to agree on the same frame or the Reader's title stepped down into rows that were not there.
/// A host says `.appStatusBand()` and nothing else.
private struct StatusBand: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.readerPalette) private var palette
    /// Whether this host draws the rows, or only the light. A pushed Settings page shows the rims
    /// alone, as it always has.
    var showsRows: Bool

    func body(content: Content) -> some View {
        let showing = env.appStatus.isShowing
        content
            .overlay {
                GeometryReader { geo in
                    TopFade(inset: geo.frame(in: .global).minY,
                            extra: showsRows ? StatusRows.bandHeight : 0,
                            colour: palette.page)
                        .opacity(showing ? 1 : 0)
                }
                .allowsHitTesting(false)
            }
            .overlay { rims }
            .overlay {
                if showsRows {
                    GeometryReader { geo in
                        StatusRows(band: geo.frame(in: .global).minY)
                    }
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: StatusGlow.fadeOut), value: showing)
    }

    /// Both rims read one reading on one frame, so head and foot can never disagree about the
    /// colour they are ending on.
    @ViewBuilder private var rims: some View {
        TimelineView(.animation) { context in
            let reading = env.appStatus.current(now: context.date)
            let settle = env.appStatus.endSettle(now: context.date)
            StatusRim(edge: .top, tone: reading?.tone, settle: settle)
            StatusRim(edge: .bottom, tone: reading?.tone, settle: settle)
        }
    }
}

extension View {
    /// Draws the app's status band over this surface: ground, both lit rims, and the three rows.
    /// `showsRows: false` for a surface that shows the light alone.
    func appStatusBand(showsRows: Bool = true) -> some View {
        modifier(StatusBand(showsRows: showsRows))
    }
}
```

- [ ] **Step 3: Give the model the ending's ease**

`endSettle(now:)` is the one piece of `WarmUpVeil` that is genuinely shared between the rims and
the rows, and it belongs with the slot rather than with either. Add to `AppStatusModel` (Task 4's
file — **this is the one cross-wave edit in the plan; make it here, and keep it to this one
method**):

```swift
    /// How far into the ending's colour, 0…1, eased on the breath's own curve. Smoothstep, as the
    /// cosine is at its ends, so the ending arrives the way the light moved rather than flashing.
    public func endSettle(now: Date) -> Double {
        guard let endedAt else { return 0 }
        let t = min(1, max(0, now.timeIntervalSince(endedAt) / StatusReading.readyEase))
        return t * t * (3 - 2 * t)
    }

    /// When the showing job began its last beat, set by the source that owns the slot.
    public private(set) var endedAt: Date?
    public func markEnding(at date: Date?) { endedAt = date }
```

and add to `StatusReading`: `public static let readyEase: Double = 1.4`.

- [ ] **Step 4: Delete the old file**

```bash
git rm App/T2SReader/Design/WarmUpVeil.swift
```

Only after Task 6 has copied the resolver out of it. If Task 6 has not landed yet, hold this step
and note it for wave 4.

- [ ] **Step 5: Commit**

```bash
git add App/T2SReader/Design/StatusGlow.swift App/T2SReader/Design/StatusBand.swift Sources/T2SApp/Status/
git commit -m "The glow, the ground and the rows become one band a screen adopts in a line"
```

---

### Task 6: `VoiceStatusSource` — the warm-up as a client

**Files:**
- Create: `App/T2SReader/System/VoiceStatusSource.swift`
- Modify: `App/T2SReader/AppEnvironment.swift`

**Interfaces:**
- Consumes: `StatusSource`, `AppStatusModel`, `StatusReading` (Tasks 1, 4); `KokoroStatusModel`, `PlayerModel`.
- Produces: `VoiceStatusSource(status:player:)`; `AppEnvironment.appStatus`.

- [ ] **Step 1: Move the resolver out of `WarmUpLine`**

Copy these six private methods out of `App/T2SReader/Design/WarmUpVeil.swift` — from the
`// MARK: what the status means` section — **with every comment** into the new file, changing
only `env.kokoroStatus` to `status` and `WarmUpVeil.isHostedSpeaking(env)` to the local check:

`reading(now:)`, `phase(_:now:)`, `installPhase(_:now:)`, `secondsLeft(_:now:)`,
`isStalled(_:now:)`, `progress(_:now:)`, `megabytes(_:)`.

```swift
// App/T2SReader/System/VoiceStatusSource.swift
import Foundation
import SwiftUI
import T2SApp

/// The one-time voice warm-up, as a client of the status band.
///
/// Everything here was `WarmUpLine`'s, and it is the only part of the warm-up that knows about
/// `KokoroStatus`. Moving it off the view is the point: a second job — a render queue, an import —
/// now writes one of these and says nothing at all about drawing.
@MainActor
final class VoiceStatusSource: StatusSource {
    let kind: StatusKind = .voice
    private let status: KokoroStatusModel
    private let player: PlayerModel

    init(status: KokoroStatusModel, player: PlayerModel) {
        self.status = status
        self.player = player
    }

    /// Warming, or holding the beat that ends a warm-up. Nothing about playback: what the reader
    /// is listening to while the stages load is not what decides whether the wait is on screen.
    /// The wait shows for as long as the wait lasts, whichever voice is speaking over it (owner,
    /// 2026-09-13: "I need to be aware of the status").
    func reading(now: Date) -> StatusReading? {
        guard status.status.isWarming || status.isHoldingReadyBeat else { return nil }
        return WarmUpReading(phase: phase(now: now),
                             progress: progress(now: now),
                             afterAnInstall: status.launchIncludedInstall).reading
    }

    /// Whether the hosted voice is the one speaking through this wait.
    private var isHostedSpeaking: Bool { player.routedVoiceID?.hasPrefix("cloud:") == true }

    // ... the six methods, moved verbatim ...
}
```

- [ ] **Step 2: Wire it into `AppEnvironment`**

In `App/T2SReader/AppEnvironment.swift`, beside `let kokoroStatus: KokoroStatusModel`:

```swift
    /// The status band's slot, and the jobs registered to speak in it.
    let appStatus = AppStatusModel()
```

At the end of `init`, after `kokoroStatus` and `player` are both set:

```swift
        appStatus.register(VoiceStatusSource(status: kokoroStatus, player: player))
```

- [ ] **Step 3: Carry the ending's date across**

`KokoroStatusModel.readyAt` is the date the band's `endSettle` needs. In `VoiceStatusSource.reading(now:)`,
before returning, keep the model in step:

```swift
        // The beat is one date, so the rims and the rows turn on the same frame.
        if status.readyAt != appStatus?.endedAt { appStatus?.markEnding(at: status.readyAt) }
```

Give `VoiceStatusSource` a `weak var appStatus: AppStatusModel?` set by `register` — or simpler,
pass the model into the initialiser and hold it `unowned`. Pick one and use it consistently.

- [ ] **Step 4: Commit**

```bash
git add App/T2SReader/System/VoiceStatusSource.swift App/T2SReader/AppEnvironment.swift
git commit -m "The warm-up becomes the band's first client rather than its owner"
```

---

### Task 7: `RootPager` adopts the band

**Files:**
- Modify: `App/T2SReader/Root/RootPager.swift:100-116`

- [ ] **Step 1: Replace the hand-placed stack**

Delete the whole `if !chrome.isSubpageOpen { ... }` block that contains `TopFade(inset:extra:fade:)`,
`WarmRim(edge: .top)` and `WarmRim(edge: .bottom)`, and the `WarmUpLine(band:)` line below it.

The pager keeps its own non-warm `TopFade` — a root page needs a top edge whether or not a job is
running. Replace the deleted block with:

```swift
                if !chrome.isSubpageOpen {
                    TopFade(inset: geo.safeAreaInsets.top,
                            extra: warming ? TopFade.warmSolid : 0,
                            fade: warming ? TopFade.warmFade : TopFade.fadeHeight)
                        .animation(.easeInOut(duration: StatusGlow.fadeOut), value: warming)
                }
```

with `let warming = env.appStatus.isShowing` above it, and apply `.appStatusBand()` to the
`ZStack` itself rather than nesting it inside.

**`TopFade.warmSolid` derives from the band now; `warmFade` does not.** Change `warmSolid` in
`TopFade.swift` to `StatusRows.bandHeight - 18` — the 18 pt is what keeps its hard edge off the top
of a page title. Leave `warmFade` at its tuned 116: it is how long a ramp must be to read as smooth,
was raised from 76 by eye, and has no relationship to the band's height.

- [ ] **Step 2: Commit**

```bash
git add App/T2SReader/Root/RootPager.swift App/T2SReader/Design/TopFade.swift
git commit -m "The root pager adopts the status band and keeps its own ramp for a scrolling title"
```

---

### Task 8: `ReaderPage` adopts the band, and loses its second header

**Files:**
- Modify: `App/T2SReader/Reader/ReaderPage.swift` — lines 120-165 (the stack), 232-234 (`isWarmUpShowing`), 287-301 (`topBar`'s step-down), 69-74 (the placeholder)

- [ ] **Step 1: Delete the hand-placed stack**

Remove the `GeometryReader { TopFade(...) }`, both `WarmRim(...)` lines and the
`GeometryReader { WarmUpLine(band:) }` from `body`'s `ZStack` (lines ~123-164), **keeping the
comments about why the order is what it is** by moving them to the `.appStatusBand()` call.

Apply the modifier to the `ZStack`, after `.environment(\.readerPalette, palette)` so the band
inherits the page's paper — this is the whole fix for the colour the owner reported:

```swift
        .environment(\.readerPalette, palette)
        // The band takes the page's paper from the environment line above, so the ground it lays
        // under its rows is this book's paper rather than the app's grey. A band of `Tokens.ground`
        // across the top of a chosen paper is the seam the owner reported (2026-09-15): near enough
        // to miss on Paper, and a white slab on Cherry.
        .appStatusBand()
```

- [ ] **Step 2: Take the step-down out of `topBar`**

Delete these two lines from the end of `topBar` (~lines 300-301):

```swift
        .padding(.top, isWarmUpShowing ? WarmUpLine.bandHeight : 0)
        .animation(.easeInOut(duration: WarmUpVeil.fadeOut), value: isWarmUpShowing)
```

and replace them with one that reads the band's own published height:

```swift
        // One header, not two. The bar used to pad down by exactly the band's height while a wait
        // was up, on the glow's own timing, so a warm-up stacked the status band above the book's
        // title bar (owner, 2026-09-15). It reads the band's height from the environment now, so
        // there is one number and one animation rather than two of each kept in step by hand.
        .padding(.top, statusBandHeight)
        .animation(.easeInOut(duration: StatusGlow.fadeOut), value: statusBandHeight)
```

with `@Environment(\.statusBandHeight) private var statusBandHeight` on the view, and that key
declared in `StatusBand.swift`:

```swift
private struct StatusBandHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }

extension EnvironmentValues {
    /// How far a host's own chrome must stand off the top while the band is showing. Zero when it
    /// is not, so a screen that reads it needs no gate of its own.
    var statusBandHeight: CGFloat {
        get { self[StatusBandHeightKey.self] }
        set { self[StatusBandHeightKey.self] = newValue }
    }
}
```

set by the modifier: `.environment(\.statusBandHeight, showing && showsRows ? StatusRows.bandHeight : 0)`.

- [ ] **Step 3: Delete `isWarmUpShowing`**

Remove the computed property at line ~234 and its doc comment. Nothing reads it after step 2.

- [ ] **Step 4: Put the loading placeholder on the palette**

At line ~71, `WarmingDot()` and "Preparing the voice…" are drawn in `Tokens.glow` on a paper page.
Change the text's `foregroundStyle(Tokens.glow)` to `foregroundStyle(palette.glow)` and leave
`WarmingDot` alone — it is used outside the Reader too.

- [ ] **Step 5: Commit**

```bash
git add App/T2SReader/Reader/ReaderPage.swift App/T2SReader/Design/StatusBand.swift
git commit -m "The Reader's status stands on the book's own paper, and there is one header again"
```

---

### Task 9: `SettingsSubpage` adopts the band

**Files:**
- Modify: `App/T2SReader/Design/SettingsSubpage.swift:44-64`

- [ ] **Step 1: Replace both rims with the modifier**

Delete `.overlay { WarmRim(edge: .top) }` and `.overlay { WarmRim(edge: .bottom) }`, keeping the
long comments above each by moving them to the new call. Keep the measured `TopFade` overlay
exactly as it is — its `offset(y: -top)` is load-bearing and the comment explains why.

Add, as the last modifier:

```swift
            // The light alone: a pushed page has never shown the rows, and the root pager draws
            // them over the push. `showsRows: false` keeps that as it was.
            //
            // The rim anchors itself to the window's edges and is *not* given the measured shift
            // its neighbour above uses. Both together was one shift too many: the rim's own
            // `ignoresSafeArea` already reaches the window's top, so the offset took the lit edge
            // another status bar past it, off the screen, leaving the sides lit and the top gone
            // (owner, 2026-09-12, twice on the Voice page).
            .appStatusBand(showsRows: false)
```

- [ ] **Step 2: Commit**

```bash
git add App/T2SReader/Design/SettingsSubpage.swift
git commit -m "A pushed Settings page takes the band's light through the same door as everything else"
```

---

### Task 10: Build, reconcile, photograph

**Files:** whatever the build says.

- [ ] **Step 1: The root package**

Run: `swift test`
Expected: all green, with 36 more tests than before (32 in `WarmUpReadingTests`, 4 in
`AppStatusModelTests`).

- [ ] **Step 2: The app**

Run: `scripts/build-app.sh`
Expected: BUILD SUCCEEDED. This is the first honest compile of the App target — waves 1-3 leave it
broken on purpose. Fix what it reports; the likely fallout is leftover references to `WarmUpVeil`,
`WarmRim`, `WarmRamp` or `WarmUpLine`. Find them with:

```bash
grep -rn "WarmUpVeil\|WarmRim\|WarmRamp\|WarmUpLine" App --include="*.swift"
```

Expected after the fix: no hits outside a comment recording the old name.

- [ ] **Step 3: Photograph the fix**

The Reader on three papers under a faked warm-up, per the recipe in
`~/.claude/.../memory/photographing-render-mode.md`, on the private sim, with
`SIMCTL_CHILD_T2S_SILENT=1` — **never with sound**.

- Paper (the default): must be indistinguishable from the previous build.
- Sepia: the band's ground must be the sepia page, not app grey.
- Cherry: the band's ground must be Cherry; judge whether the app's blue on it needs tuning and
  report with the frame, do not tune it here.
- Plus `T2S_WARMUP=green` and `T2S_WARMUP=failed` on Paper, for the two endings.

- [ ] **Step 4: Regression frames**

Home and a pushed Settings subpage under `T2S_WARMUP=1`. Both must be **pixel-identical** to the
previous build — nothing about their palette changed, and `ReaderPalette.app` resolves to the same
`Tokens` values they used before. A difference here means the palette swap was not the no-op it
must be.

- [ ] **Step 5: Commit and hand over for the single review**

```bash
git add -A
git commit -m "The status band builds, and the Reader's is the colour of the book"
```

---

## Self-review

**Spec coverage.** `StatusReading` → Task 1. `AppStatusModel` + precedence → Task 4. One modifier,
three hosts → Tasks 5, 7, 8, 9. Colour from the palette → Tasks 2, 3, 5, 8. The glow's hue staying
the app's → Task 2. Header collision, published height → Tasks 5, 7, 8. Voice as the only client →
Task 6. Testing → Tasks 1, 4, 10. Out-of-scope items are absent, as intended.

**Two deviations from the spec, both deliberate and both recorded above:**
1. Sources are *pulled* (`current(now:)`), not pushed (`publish(_:for:)`) — Task 4, step 1.
2. The 30 existing tests need **no edits at all**; the spec said they would be rewritten to go
   through `.reading`. They only ever touched instance members, so leaving them untouched is both
   less work and a better regression guard — Task 1, step 4.

**Known rough edge, to settle during execution, not now:** Task 6 step 3 has `VoiceStatusSource`
reaching back into `AppStatusModel` to carry `readyAt` across. Two shapes are offered; whoever
implements it picks one. If it turns out ugly in the writing, the alternative is for `endSettle` to
take the date as an argument from the band and for `AppStatusModel` to hold no date at all.

**Type consistency checked:** `StatusRamp` (not `WarmRamp`), `StatusRim`, `StatusRows`,
`StatusGlow.fadeOut`, `StatusReading.readyEase`, `StatusRows.bandHeight`, `appStatusBand(showsRows:)`,
`AppStatusModel.current(now:)` / `.isShowing` / `.endSettle(now:)` / `.markEnding(at:)` / `.register(_:)`
are spelled the same in every task that names them.
