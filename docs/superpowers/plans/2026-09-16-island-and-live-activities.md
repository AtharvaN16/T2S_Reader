# Mock island and Live Activities — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A black capsule at the top of the screen announces a finished chapter with a Play
button while the app is open, and two Live Activities — render queue progress and the sleep
timer countdown — carry the same news while it is closed.

**Architecture:** All copy and state decisions live as plain `Equatable` value types in the
`T2SApp` SwiftPM target, where `swift test` reaches them on the Mac with no simulator. The
views that draw them — a SwiftUI capsule in its own `UIWindow` above every presentation, and
two WidgetKit Live Activity layouts in a new app-extension target — hold no logic worth
testing and are verified by eye on the simulator. ActivityKit types never enter the package,
because the package builds for macOS and `ActivityKit` does not exist there.

**Tech Stack:** Swift 6 language mode, SwiftUI, Swift Testing (`import Testing`, `@Test`,
`#expect`), ActivityKit + WidgetKit, xcodegen, iOS 18 deployment target.

**Spec:** `docs/superpowers/specs/2026-09-16-island-and-live-activities-design.md`

## Global Constraints

- **Deployment target iOS 18.0** (`App/project.yml:6`). Live Activities (16.1+) and
  interactive Live Activity buttons (17+) are both below this floor; no availability
  checks needed.
- **Swift 6 language mode** on every package target (`Package.swift`). All new types are
  `Sendable`; anything touching `PlayerModel`, `ChapterRenderRunner` or SwiftUI is `@MainActor`.
- **Tests are Swift Testing**, never XCTest. `@Suite struct XTests { @Test func ... }`.
- **No ActivityKit import inside `Sources/`.** The package builds for macOS; `import ActivityKit`
  there breaks `swift test` for everyone. ActivityKit lives only under `App/`.
- **Island cutout numbers are community-measured, not Apple's:** 126 × 37.33 pt, 11 pt from the
  screen top. Apple publishes only the 36 pt compact height. Treat as provisional.
- **Copy is owner-approved and must be reproduced exactly.** "Chapter ready to play",
  "Document ready to play", "Chapter couldn't be rendered", "Couldn't be rendered",
  "<name> has finished rendering".
- **Never play audio on this Mac.** Simulator only, and only with `SIMCTL_CHILD_T2S_SILENT=1`.

## Known environment hazards — read before you debug anything

1. **`scripts/build-app.sh` may fail with "'Document' is ambiguous" (T2SCore vs SwiftSoup).**
   This is pre-existing and unrelated to this work. Do not chase it. If it blocks you, report
   it and fall back to type-checking with `swiftc` as described in Task 10.
2. **Xcode's Metal toolchain license re-locks.** Only the Kokoro scheme needs Metal. If
   `xcodebuild` refuses, the plain `T2SReader` scheme is still buildable.
3. **One `xcodebuild` at a time, machine-wide.** Parallel task agents must not build. Agents
   write code and run `swift test`; the orchestrator runs the single build between waves.
4. **`swift test` takes a lock on `.build`.** Concurrent agents in the shared checkout will
   queue rather than corrupt. That is fine — these suites are small.
5. **The working tree carries uncommitted changes from parallel sessions.** `git add` only the
   exact files your task names. Never `git add -A`, never `git commit -a`.
6. **Check `df -h /` before any build.** The disk fills fast on this Mac.

## Parallelism

Three waves. Everything inside a wave is independent and touches disjoint files — dispatch
every task in a wave in a single message so they run concurrently.

| Wave | Tasks | Shared files? | Builds? |
|---|---|---|---|
| 1 | 1, 2, 3, 4, 5 | none — all disjoint | no, `swift test` only |
| 2 | 6, 7, 8 | none — all disjoint | no |
| 3 | 9 | owns `RootPager.swift` alone | no |
| 4 | 10, then 11 | — | yes, orchestrator only |

Task 5 creates the extension target that Tasks 7 and 8 fill; it declares the shared
`ActivityAttributes` types they both import, which is why it sits in wave 1 rather than
beside them.

## File structure

**Created in `Sources/T2SApp/Island/`** — plain values, `swift test` reaches them:

| File | Responsibility |
|---|---|
| `IslandGeometry.swift` | which devices have an island, and the capsule's measurements |
| `ChapterReadyMessage.swift` | what a finished chapter is called, and who announces it |
| `RenderCardReading.swift` | the render Live Activity's text and numbers, per state |
| `SleepCardReading.swift` | the sleep Live Activity's text and deadline |

**Created under `App/`** — views and ActivityKit, not unit-tested:

| File | Responsibility |
|---|---|
| `App/ActivityShared/RenderActivityAttributes.swift` | the render card's wire format, compiled into app *and* extension |
| `App/ActivityShared/SleepActivityAttributes.swift` | the sleep card's wire format |
| `App/T2SReader/Design/MockIslandCenter.swift` | holds the one message the capsule is showing |
| `App/T2SReader/Design/MockIsland.swift` | draws the capsule (and the plain card fallback) |
| `App/T2SReader/Design/MockIslandWindow.swift` | the `UIWindow` above everything, touchable only inside the capsule |
| `App/T2SReaderActivities/T2SActivitiesBundle.swift` | the extension's `@main` |
| `App/T2SReaderActivities/RenderActivityWidget.swift` | Lock Screen + island layouts for renders |
| `App/T2SReaderActivities/SleepActivityWidget.swift` | Lock Screen + island layouts for the sleep timer |
| `App/T2SReader/System/ActivityDirector.swift` | starts, updates and ends both activities |

**Modified:**

| File | Change |
|---|---|
| `Sources/T2SApp/Playback/SleepTimer.swift` | expose the deadline (Task 4) |
| `App/project.yml` | the new extension target, `NSSupportsLiveActivities` (Task 5) |
| `App/T2SReader/Root/RootPager.swift` | route the announcement; drive the activities (Task 9) |
| `App/T2SReader/AppEnvironment.swift` | own the centre and the director (Task 9) |
| `App/T2SReader/T2SReaderApp.swift` | attach the island window (Task 9) |

---

## Task 1: Island geometry and device identification

**Files:**
- Create: `Sources/T2SApp/Island/IslandGeometry.swift`
- Test: `Tests/T2SAppTests/IslandGeometryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `IslandGeometry.hasIsland(machine: String) -> Bool`,
  `IslandGeometry.currentMachine() -> String`, `IslandGeometry.deviceHasIsland: Bool`,
  and the constants `cutoutWidth`, `cutoutHeight`, `cutoutTop` (all `CGFloat`).

**Why a hardcoded list.** Apple DTS: *"there's no first-party API that provides support for
detecting whether a device has a notch or island."* Both safe-area heuristics
(`safeAreaInsets.bottom > 0`, `safeAreaInsets.top > 20`) broke in iOS 26. Model identifiers
did not. The list fails safe: anything unrecognised is treated as having no island and gets
the plain card.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/T2SAppTests/IslandGeometryTests.swift
import Foundation
import Testing
@testable import T2SApp

@Suite struct IslandGeometryTests {
    @Test func knownIslandDevicesAreRecognised() {
        // iPhone 14 Pro / 14 Pro Max, 15 / 15 Plus, 15 Pro / 15 Pro Max.
        for machine in ["iPhone15,2", "iPhone15,3", "iPhone15,4", "iPhone15,5",
                        "iPhone16,1", "iPhone16,2"] {
            #expect(IslandGeometry.hasIsland(machine: machine), "\(machine) has an island")
        }
    }

    @Test func notchAndOlderDevicesAreNot() {
        // 11 Pro (the owner's test phone), SE 3, and the 16e — which has a notch, not an island.
        for machine in ["iPhone12,3", "iPhone14,6", "iPhone17,5"] {
            #expect(!IslandGeometry.hasIsland(machine: machine), "\(machine) has no island")
        }
    }

    /// The fail-safe, and the whole reason the list is allowed to be incomplete: a phone that
    /// ships after this list was written gets the plain card, not a capsule through its notch.
    @Test func unknownIdentifiersFallBackToNoIsland() {
        #expect(!IslandGeometry.hasIsland(machine: "iPhone99,1"))
        #expect(!IslandGeometry.hasIsland(machine: ""))
        #expect(!IslandGeometry.hasIsland(machine: "arm64"))
    }
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `swift test --filter IslandGeometryTests`
Expected: FAIL — `cannot find 'IslandGeometry' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SApp/Island/IslandGeometry.swift
import CoreGraphics
import Foundation

/// Where the Dynamic Island is, and whether this phone has one.
///
/// **There is no API for this.** Apple Developer Technical Support, on the record: "We don't
/// recommend you doing this and there's no first-party API that provides support for detecting
/// whether a device has a notch or island." The two heuristics everyone used —
/// `safeAreaInsets.bottom > 0` and `safeAreaInsets.top > 20` — both stopped working in iOS 26.
/// Model identifiers did not, so that is what this uses.
///
/// The list will go stale every September. That is survivable because it fails in the safe
/// direction: an identifier this file has never heard of is treated as having no island, and
/// the capsule falls back to a plain card under the status bar. A wrong "yes" would draw a
/// black capsule through a notch; a wrong "no" draws a card that looks deliberate.
public enum IslandGeometry {
    /// The cutout, in points. **Community-measured, not published by Apple** — Apple documents
    /// only the 36 pt compact height and the 144 pt expanded maximum. Check these against a
    /// photograph of a real island phone before trusting the alignment.
    public static let cutoutWidth: CGFloat = 126
    public static let cutoutHeight: CGFloat = 37.33
    /// From the top of the screen to the top of the cutout.
    public static let cutoutTop: CGFloat = 11

    /// Every model identifier with a Dynamic Island, newest last.
    ///
    /// Note `iPhone17,5` is deliberately absent: the 16e has a notch.
    public static let islandModels: Set<String> = [
        "iPhone15,2", "iPhone15,3",              // 14 Pro, 14 Pro Max
        "iPhone15,4", "iPhone15,5",              // 15, 15 Plus
        "iPhone16,1", "iPhone16,2",              // 15 Pro, 15 Pro Max
        "iPhone17,3", "iPhone17,4",              // 16, 16 Plus
        "iPhone17,1", "iPhone17,2",              // 16 Pro, 16 Pro Max
    ]

    public static func hasIsland(machine: String) -> Bool { islandModels.contains(machine) }

    /// The identifier of the machine this is running on.
    ///
    /// **`uname` reports the host on a simulator** — "arm64" or "x86_64", never a phone's
    /// identifier — so a simulator run would always take the no-island path and the capsule
    /// could never be seen on the one device available for looking at it. The simulator
    /// publishes the device it is pretending to be in its environment instead.
    public static func currentMachine() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: info.machine)) {
                String(validatingCString: $0) ?? ""
            }
        }
    }

    public static var deviceHasIsland: Bool { hasIsland(machine: currentMachine()) }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `swift test --filter IslandGeometryTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Confirm the current-generation identifiers**

The iPhone 17 family's identifiers are *not* in the list above, because they could not be
confirmed at the time of writing. Look them up against a maintained reference
(`theiphonewiki.com/wiki/Models` or Apple's own support pages), add any that have an island,
and extend `knownIslandDevicesAreRecognised` to cover them. If you cannot confirm one, leave
it out — the fail-safe is correct behaviour, not a bug.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SApp/Island/IslandGeometry.swift Tests/T2SAppTests/IslandGeometryTests.swift
git commit -m "The app can tell an island phone from a notched one, and fails toward the notch"
```

---

## Task 2: What a finished chapter is called, and who says it

**Files:**
- Create: `Sources/T2SApp/Island/ChapterReadyMessage.swift`
- Test: `Tests/T2SAppTests/ChapterReadyMessageTests.swift`

**Interfaces:**
- Consumes: `ChapterRenderJob` (`Sources/T2SApp/Playback/ChapterRenderRunner.swift:10`),
  `ChapterLabel.text(for:ordinal:)` (`Sources/T2SApp/Player/ChapterLabel.swift:8`).
- Produces: `ChapterReadyMessage.make(job:documentTitle:chapterCount:) -> ChapterReadyMessage`
  with fields `title: String`, `detail: String`, `isFailure: Bool`; and
  `Announcement.route(isForeground:) -> Announcement` returning `.island` or `.liveActivity`.

**Where this comes from.** `RootPager.showRenderToast(_:)` (`RootPager.swift:359-388`) works
these rules out inline. Lifting them lets three callers — the toast, the capsule and the Live
Activity — say the same thing, and lets the rules be tested without a simulator. Do not change
the wording; it is owner-approved.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/T2SAppTests/ChapterReadyMessageTests.swift
import Foundation
import Testing
@testable import T2SApp

@Suite struct ChapterReadyMessageTests {
    private func job(_ state: ChapterRenderJob.State, title: String = "4. The Siege of Delhi",
                     index: Int = 3) -> ChapterRenderJob {
        ChapterRenderJob(documentID: UUID(), chapterIndex: index, title: title,
                         utteranceCount: 10, rendered: 10, state: state)
    }

    @Test func aChapterOfABookIsNamedAndNumbered() {
        let message = ChapterReadyMessage.make(job: job(.ready), documentTitle: "India in 1857",
                                               chapterCount: 12)
        #expect(message.title == "Chapter ready to play")
        #expect(message.detail == "Chp 4: The Siege of Delhi has finished rendering")
        #expect(!message.isFailure)
    }

    /// One chapter is not a book with a chapter in it — an article, or an imported PDF — and its
    /// single piece has no name worth printing, so the document's own title stands in.
    @Test func aSingleChapterDocumentUsesItsOwnTitle() {
        let message = ChapterReadyMessage.make(job: job(.ready), documentTitle: "India in 1857",
                                               chapterCount: 1)
        #expect(message.title == "Document ready to play")
        #expect(message.detail == "India in 1857 has finished rendering")
    }

    @Test func aFailureCarriesTheRunnersOwnSentence() {
        let message = ChapterReadyMessage.make(job: job(.failed("The store is full")),
                                               documentTitle: "India in 1857", chapterCount: 12)
        #expect(message.title == "Chapter couldn't be rendered")
        #expect(message.detail == "The store is full")
        #expect(message.isFailure)
    }

    @Test func aSingleChapterFailureDropsTheWordChapter() {
        let message = ChapterReadyMessage.make(job: job(.failed("The store is full")),
                                               documentTitle: "India in 1857", chapterCount: 1)
        #expect(message.title == "Couldn't be rendered")
    }

    /// The rule that matters: exactly one surface speaks, and which one is decided by where the
    /// reader is looking. Never both.
    @Test func exactlyOneSurfaceAnnounces() {
        #expect(Announcement.route(isForeground: true) == .island)
        #expect(Announcement.route(isForeground: false) == .liveActivity)
    }
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `swift test --filter ChapterReadyMessageTests`
Expected: FAIL — `cannot find 'ChapterReadyMessage' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SApp/Island/ChapterReadyMessage.swift
import Foundation

/// Which surface tells the reader a chapter is ready.
///
/// **Never both.** The capsule can only be seen while the app is up; a Live Activity is never
/// shown in the Dynamic Island while its own app is up. So the two are exclusive by nature,
/// and this makes that explicit rather than leaving each call site to remember it.
public enum Announcement: Equatable, Sendable {
    /// The black capsule at the top of the app's own screen.
    case island
    /// The Live Activity, which alerts on the Lock Screen and in the real island.
    case liveActivity

    public static func route(isForeground: Bool) -> Announcement {
        isForeground ? .island : .liveActivity
    }
}

/// What a finished — or failed — chapter is called.
///
/// Lifted verbatim from `RootPager.showRenderToast`, where it was worked out inline and could
/// only be read by the one caller that already had a `DocumentSummary` to hand. The wording is
/// the owner's (2026-09-14): "the sentence, not the label", because "Chapter 4: The Siege of
/// Delhi has finished rendering" says both which one and what happened to it.
public struct ChapterReadyMessage: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var isFailure: Bool

    public init(title: String, detail: String, isFailure: Bool) {
        self.title = title
        self.detail = detail
        self.isFailure = isFailure
    }

    /// - Parameter chapterCount: how many chapters the document has. One means the document is
    ///   its own single piece, and the copy takes the document's title rather than a chapter's.
    public static func make(job: ChapterRenderJob, documentTitle: String,
                            chapterCount: Int) -> ChapterReadyMessage {
        let hasChapters = chapterCount > 1
        if case .failed(let reason) = job.state {
            return ChapterReadyMessage(
                title: hasChapters ? "Chapter couldn't be rendered" : "Couldn't be rendered",
                detail: reason, isFailure: true)
        }
        let name = hasChapters
            ? ChapterLabel.text(for: job.title, ordinal: job.chapterIndex + 1)
            : documentTitle
        return ChapterReadyMessage(
            title: hasChapters ? "Chapter ready to play" : "Document ready to play",
            detail: "\(name) has finished rendering", isFailure: false)
    }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `swift test --filter ChapterReadyMessageTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp/Island/ChapterReadyMessage.swift Tests/T2SAppTests/ChapterReadyMessageTests.swift
git commit -m "A finished chapter's name and sentence live in one tested place, and one surface says them"
```

---

## Task 3: What the render Live Activity says

**Files:**
- Create: `Sources/T2SApp/Island/RenderCardReading.swift`
- Test: `Tests/T2SAppTests/RenderCardReadingTests.swift`

**Interfaces:**
- Consumes: `ChapterRenderJob`, `ChapterRenderRunner.Hold`
  (`Sources/T2SApp/Playback/ChapterRenderRunner.swift:73`).
- Produces: `RenderCardReading.make(jobs:bookTitle:hold:justFinished:) -> RenderCardReading?`
  with fields `headline: String`, `detail: String`, `ready: Int`, `total: Int`,
  `fraction: Double`, `alerts: Bool`, `isFinished: Bool`.

**The state table**, from the spec:

| Situation | headline | detail | alerts |
|---|---|---|---|
| running | the book's title | "3 of 8 chapters ready" | no |
| a chapter just finished | "Chapter 4 is ready" | "3 of 8 chapters ready" | **yes** |
| held | the book's title | the hold's sentence | no |
| all done | "<book> is ready" | "8 chapters ready" | yes |
| nothing to say | — | `make` returns nil | — |

`fraction` is chapters done over chapters asked for — not the running chapter's utterance
fraction. A bar that jumps a whole chapter at a time is honest; one that advances smoothly and
then sits still between chapters is not.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/T2SAppTests/RenderCardReadingTests.swift
import Foundation
import Testing
@testable import T2SApp

@Suite struct RenderCardReadingTests {
    private let book = UUID()

    private func jobs(ready: Int, total: Int) -> [ChapterRenderJob] {
        (0..<total).map { index in
            ChapterRenderJob(documentID: book, chapterIndex: index, title: "Chapter \(index + 1)",
                             utteranceCount: 10, rendered: index < ready ? 10 : 0,
                             state: index < ready ? .ready : .queued)
        }
    }

    @Test func restingSaysHowManyOfHowMany() throws {
        let reading = try #require(RenderCardReading.make(jobs: jobs(ready: 3, total: 8),
                                                          bookTitle: "India in 1857",
                                                          hold: nil, justFinished: nil))
        #expect(reading.headline == "India in 1857")
        #expect(reading.detail == "3 of 8 chapters ready")
        #expect(reading.ready == 3 && reading.total == 8)
        #expect(reading.fraction == 3.0 / 8.0)
        #expect(!reading.alerts)
        #expect(!reading.isFinished)
    }

    @Test func aJustFinishedChapterTakesTheHeadlineAndAlerts() throws {
        let reading = try #require(RenderCardReading.make(jobs: jobs(ready: 4, total: 8),
                                                          bookTitle: "India in 1857", hold: nil,
                                                          justFinished: "Chp 4: The Siege of Delhi"))
        #expect(reading.headline == "Chp 4: The Siege of Delhi is ready")
        #expect(reading.detail == "4 of 8 chapters ready")
        #expect(reading.alerts)
    }

    @Test func theLastOneEndsTheCard() throws {
        let reading = try #require(RenderCardReading.make(jobs: jobs(ready: 8, total: 8),
                                                          bookTitle: "India in 1857", hold: nil,
                                                          justFinished: "Chp 8: Aftermath"))
        #expect(reading.headline == "India in 1857 is ready")
        #expect(reading.detail == "8 chapters ready")
        #expect(reading.fraction == 1)
        #expect(reading.isFinished)
        #expect(reading.alerts)
    }

    /// A hold is not an error and must not alert — the phone being hot is not news worth a buzz.
    @Test func aHoldSaysWhyAndStaysQuiet() throws {
        let hot = try #require(RenderCardReading.make(jobs: jobs(ready: 2, total: 8),
                                                      bookTitle: "India in 1857",
                                                      hold: .hot, justFinished: nil))
        #expect(hot.detail == "Paused while the phone cools")
        #expect(!hot.alerts)

        let full = try #require(RenderCardReading.make(jobs: jobs(ready: 2, total: 8),
                                                       bookTitle: "India in 1857",
                                                       hold: .storeFull, justFinished: nil))
        #expect(full.detail == "Paused — storage is full")

        let paused = try #require(RenderCardReading.make(jobs: jobs(ready: 2, total: 8),
                                                         bookTitle: "India in 1857",
                                                         hold: .byReader, justFinished: nil))
        #expect(paused.detail == "Paused")
    }

    @Test func noJobsMeansNoCard() {
        #expect(RenderCardReading.make(jobs: [], bookTitle: "India in 1857",
                                       hold: nil, justFinished: nil) == nil)
    }
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `swift test --filter RenderCardReadingTests`
Expected: FAIL — `cannot find 'RenderCardReading' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SApp/Island/RenderCardReading.swift
import Foundation

/// Everything the render Live Activity says, worked out from the queue and nothing else.
///
/// This is `StatusReading`'s shape and its reason: a plain value the views cannot disagree
/// with, tested on the Mac without a simulator. It holds no ActivityKit type, because the
/// package builds for macOS and ActivityKit does not exist there.
///
/// **Why the queue and not one chapter.** Away from the phone the question is "is my book
/// ready", not "how is chapter 4". And `BookSheet` commits a multi-select batch, so one
/// activity per chapter would start and end eight times against a system cap on how many can
/// be live at once.
public struct RenderCardReading: Equatable, Sendable {
    public var headline: String
    public var detail: String
    public var ready: Int
    public var total: Int
    /// Chapters done over chapters asked for. Deliberately not the running chapter's utterance
    /// fraction: a bar that steps once a chapter is honest about what it knows, where one that
    /// glides and then stalls between chapters is not.
    public var fraction: Double
    /// Whether this update should break through — expand the island, put a banner on the Lock
    /// Screen, buzz. Only a finished chapter does.
    public var alerts: Bool
    /// The last thing the card will ever say, after which it dismisses itself.
    public var isFinished: Bool

    public init(headline: String, detail: String, ready: Int, total: Int,
                fraction: Double, alerts: Bool, isFinished: Bool) {
        self.headline = headline
        self.detail = detail
        self.ready = ready
        self.total = total
        self.fraction = fraction
        self.alerts = alerts
        self.isFinished = isFinished
    }

    /// - Parameter justFinished: the display name of a chapter that finished on this very
    ///   update, or nil on a resting update. Non-nil is what makes the card alert.
    public static func make(jobs: [ChapterRenderJob], bookTitle: String,
                            hold: ChapterRenderRunner.Hold?,
                            justFinished: String?) -> RenderCardReading? {
        guard !jobs.isEmpty else { return nil }
        let total = jobs.count
        let ready = jobs.filter { if case .ready = $0.state { return true } else { return false } }.count
        let failed = jobs.filter { if case .failed = $0.state { return true } else { return false } }.count
        let settled = ready + failed
        let fraction = Double(settled) / Double(total)
        let tally = "\(ready) of \(total) chapters ready"

        if settled == total {
            return RenderCardReading(headline: "\(bookTitle) is ready",
                                     detail: "\(ready) chapters ready",
                                     ready: ready, total: total, fraction: 1,
                                     alerts: true, isFinished: true)
        }
        if let hold {
            return RenderCardReading(headline: bookTitle, detail: sentence(for: hold),
                                     ready: ready, total: total, fraction: fraction,
                                     alerts: false, isFinished: false)
        }
        if let justFinished {
            return RenderCardReading(headline: "\(justFinished) is ready", detail: tally,
                                     ready: ready, total: total, fraction: fraction,
                                     alerts: true, isFinished: false)
        }
        return RenderCardReading(headline: bookTitle, detail: tally, ready: ready, total: total,
                                 fraction: fraction, alerts: false, isFinished: false)
    }

    /// The hold's own sentence. None of these is an error and none of them alerts: the queue
    /// stopped for a reason the reader either chose or cannot argue with.
    private static func sentence(for hold: ChapterRenderRunner.Hold) -> String {
        switch hold {
        case .byReader: "Paused"
        case .hot: "Paused while the phone cools"
        case .storeFull: "Paused — storage is full"
        }
    }
}
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `swift test --filter RenderCardReadingTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp/Island/RenderCardReading.swift Tests/T2SAppTests/RenderCardReadingTests.swift
git commit -m "The render card's words and numbers are a plain value the queue decides"
```

---

## Task 4: What the sleep timer Live Activity says

**Files:**
- Create: `Sources/T2SApp/Island/SleepCardReading.swift`
- Modify: `Sources/T2SApp/Playback/SleepTimer.swift` (expose the deadline)
- Test: `Tests/T2SAppTests/SleepCardReadingTests.swift`

**Interfaces:**
- Consumes: `SleepOption` (`Sources/T2SApp/Playback/SleepTimer.swift:4`).
- Produces: `SleepCardReading.make(option:deadline:chapterTitle:) -> SleepCardReading?` with
  fields `headline: String`, `detail: String`, `deadline: Date?`; and a new
  `SleepTimer.deadlineDate: Date?` read-only accessor.

**Why the deadline and not a countdown.** A Live Activity can count down from a stored `Date`
by itself, with no update from the app — no wake-ups, no battery cost, no update budget. So
this type hands over the deadline and lets the view tick. `.endOfChapter` has no deadline and
gets a sentence instead.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/T2SAppTests/SleepCardReadingTests.swift
import Foundation
import Testing
@testable import T2SApp

@Suite struct SleepCardReadingTests {
    @Test func aTimedSleepHandsOverItsDeadlineToTickOnItsOwn() throws {
        let deadline = Date(timeIntervalSince1970: 1_000_000)
        let reading = try #require(SleepCardReading.make(option: .minutes(30), deadline: deadline,
                                                         chapterTitle: nil))
        #expect(reading.headline == "Sleep timer")
        #expect(reading.deadline == deadline)
        #expect(reading.detail == "Playback stops when the time is up")
    }

    /// No deadline exists for this one, so the card must not pretend to count anything down.
    @Test func endOfChapterNamesTheChapterAndHasNoClock() throws {
        let reading = try #require(SleepCardReading.make(option: .endOfChapter, deadline: nil,
                                                         chapterTitle: "The Siege of Delhi"))
        #expect(reading.headline == "Sleep timer")
        #expect(reading.detail == "Until the end of The Siege of Delhi")
        #expect(reading.deadline == nil)
    }

    @Test func noTimerMeansNoCard() {
        #expect(SleepCardReading.make(option: nil, deadline: nil, chapterTitle: nil) == nil)
    }

    /// A timed option with no deadline is a contradiction — it must not produce a card that
    /// silently never ends.
    @Test func aTimedOptionWithoutADeadlineIsNoCard() {
        #expect(SleepCardReading.make(option: .minutes(30), deadline: nil, chapterTitle: nil) == nil)
    }
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `swift test --filter SleepCardReadingTests`
Expected: FAIL — `cannot find 'SleepCardReading' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SApp/Island/SleepCardReading.swift
import Foundation

/// Everything the sleep timer's Live Activity says.
///
/// **It hands over a `Date`, not a count.** A Live Activity can count down from a stored date
/// entirely on its own, so a timed sleep costs nothing to keep current: the app never wakes,
/// there is no update budget to manage and no battery to spend. `.endOfChapter` has no such
/// date and says which chapter instead — a card that appeared to be counting toward a moment
/// nobody can name would be lying.
public struct SleepCardReading: Equatable, Sendable {
    public var headline: String
    public var detail: String
    /// When playback stops, for a view that ticks by itself. Nil for `.endOfChapter`.
    public var deadline: Date?

    public init(headline: String, detail: String, deadline: Date?) {
        self.headline = headline
        self.detail = detail
        self.deadline = deadline
    }

    public static func make(option: SleepOption?, deadline: Date?,
                            chapterTitle: String?) -> SleepCardReading? {
        guard let option else { return nil }
        switch option {
        case .minutes:
            // A timed sleep without a deadline cannot be drawn honestly, and a card that showed
            // no end would sit on the Lock Screen until iOS timed it out.
            guard let deadline else { return nil }
            return SleepCardReading(headline: "Sleep timer",
                                    detail: "Playback stops when the time is up",
                                    deadline: deadline)
        case .endOfChapter:
            return SleepCardReading(headline: "Sleep timer",
                                    detail: "Until the end of \(chapterTitle ?? "this chapter")",
                                    deadline: nil)
        }
    }
}
```

- [ ] **Step 4: Expose the deadline on `SleepTimer`**

In `Sources/T2SApp/Playback/SleepTimer.swift`, immediately below
`private var deadline: Date?` (line 31), add:

```swift
    /// The deadline, for a Live Activity that counts down from it without the app waking up.
    /// Read-only: the timer owns when it ends, and nothing outside may move it.
    public var deadlineDate: Date? { deadline }

    /// The chapter the reader was in when an `.endOfChapter` sleep began, for the card that
    /// names it. Nil for a timed sleep.
    public var sleepChapterTitle: String? { chapterTitleAtStart }
```

- [ ] **Step 5: Run the test and watch it pass**

Run: `swift test --filter SleepCardReadingTests`
Expected: PASS, 4 tests.

- [ ] **Step 6: Run the existing sleep timer tests to be sure nothing moved**

Run: `swift test --filter SleepTimer`
Expected: PASS (or "no tests matched", which is also fine — this step is a check, not a gate).

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SApp/Island/SleepCardReading.swift Sources/T2SApp/Playback/SleepTimer.swift Tests/T2SAppTests/SleepCardReadingTests.swift
git commit -m "The sleep card hands a deadline to a view that can count on its own"
```

---

## Task 5: The extension target and the two wire formats

**Files:**
- Create: `App/ActivityShared/RenderActivityAttributes.swift`
- Create: `App/ActivityShared/SleepActivityAttributes.swift`
- Modify: `App/project.yml` (new target; `NSSupportsLiveActivities`; embed the extension)

**Interfaces:**
- Consumes: nothing. The `ContentState`s hold primitives on purpose, so this task does not wait
  on Tasks 3 and 4 and the two can be written at the same time.
- Produces: `RenderActivityAttributes` (`ContentState`: `headline`, `detail`, `ready`, `total`,
  `fraction`, `isFinished`; attributes: `bookTitle`, `coverPath`) and
  `SleepActivityAttributes` (`ContentState`: `headline`, `detail`, `deadline`; attributes:
  `bookTitle`).

**No tests.** These are data declarations with no behaviour. A test would assert that a struct
has the fields it visibly has. The compiler is the test, and Task 10 is where they are proven.

- [ ] **Step 1: Write the render attributes**

```swift
// App/ActivityShared/RenderActivityAttributes.swift
import ActivityKit
import Foundation

/// The render card's wire format — the only type the app and the widget extension both hold.
///
/// It lives under `App/` and not in the package because the package builds for macOS, where
/// `ActivityKit` does not exist; one import here would break `swift test` for every target.
/// `App/ActivityShared` is listed by both the app target and the extension, the same way
/// `T2SReader/Shared` is already shared with `T2SReaderShare`.
///
/// The fields are primitives rather than a `RenderCardReading`, so this file compiles with no
/// dependency on the package at all.
struct RenderActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var headline: String
        var detail: String
        var ready: Int
        var total: Int
        var fraction: Double
        var isFinished: Bool
    }

    /// Fixed for the life of the activity — a batch is one book.
    var bookTitle: String
    /// Library-relative path to the cover, or nil. The extension resolves it through the shared
    /// app group; a cover it cannot find simply is not drawn.
    var coverPath: String?
}
```

- [ ] **Step 2: Write the sleep attributes**

```swift
// App/ActivityShared/SleepActivityAttributes.swift
import ActivityKit
import Foundation

/// The sleep timer card's wire format.
///
/// `deadline` is the whole point: a Live Activity view can count down from a `Date` on its own,
/// so a timed sleep needs no update between starting and firing. Nil means `.endOfChapter`,
/// which has no moment to count toward and must not appear to be counting.
struct SleepActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var headline: String
        var detail: String
        var deadline: Date?
    }

    var bookTitle: String
}
```

- [ ] **Step 3: Add the extension target to `App/project.yml`**

Add to the app target's `info.properties` (beside `UIBackgroundModes`, `project.yml:93`):

```yaml
        NSSupportsLiveActivities: true
```

Add to the app target's `dependencies` (beside `- target: T2SReaderShare`, `project.yml:67`):

```yaml
      - target: T2SReaderActivities
        embed: true
```

Add to the app target's `sources`, so the app can build the attributes it sends:

```yaml
      - path: ActivityShared
```

Add a new target beside `T2SReaderShare` (`project.yml:169`):

```yaml
  T2SReaderActivities:
    type: app-extension
    platform: iOS
    sources:
      - path: T2SReaderActivities
      - path: ActivityShared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(T2S_BUNDLE_ID).activities
        INFOPLIST_KEY_CFBundleDisplayName: t2s
        CODE_SIGN_ENTITLEMENTS: T2SReaderActivities/T2SReaderActivities.entitlements
    info:
      path: T2SReaderActivities/Info.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
```

- [ ] **Step 4: Give the extension the app group**

The extension needs the app group to reach cover images in the shared container. Create
`App/T2SReaderActivities/T2SReaderActivities.entitlements` with exactly this — it is
`App/T2SReader/T2SReader.entitlements` verbatim, and the `$(T2S_APP_GROUP)` reference is what
lets a second developer's `Local.xcconfig` substitute their own group:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>$(T2S_APP_GROUP)</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 5: Create a placeholder source so xcodegen accepts the path**

xcodegen refuses a missing source path. Task 7 fills this directory; for now:

```bash
mkdir -p App/T2SReaderActivities
printf '// Filled by Task 7.\n' > App/T2SReaderActivities/.keep.swift
```

- [ ] **Step 6: Regenerate and confirm the project is valid**

```bash
cd App && xcodegen generate --quiet && cd ..
git diff --stat App/T2SReader.xcodeproj/project.pbxproj
```

Expected: the pbxproj changes and xcodegen exits 0. **Do not build here** — builds belong to
Task 10, one at a time.

- [ ] **Step 7: Commit**

```bash
git add App/ActivityShared App/T2SReaderActivities App/project.yml App/T2SReader.xcodeproj/project.pbxproj
git commit -m "A widget extension target, and the two shapes the app and it agree on"
```

---

## Task 6: The mock island

**Files:**
- Create: `App/T2SReader/Design/MockIslandCenter.swift`
- Create: `App/T2SReader/Design/MockIsland.swift`
- Create: `App/T2SReader/Design/MockIslandWindow.swift`

**Interfaces:**
- Consumes: `IslandGeometry` (Task 1), `ChapterReadyMessage` (Task 2), and the existing
  `BookCover`, `CircleGlyph`, `Tokens`, `Spacing`, `typeRole` from `App/T2SReader/Design/`.
- Produces: `MockIslandCenter` (`@MainActor @Observable`, `show(_:cover:action:)`, `dismiss()`,
  `message`, `cover`, `action`) and `MockIslandHost.attach(to:)`.

**Why its own window.** The capsule must sit above the Reader (a `fullScreenCover`) and the
Book sheet, which is the same problem `StatusBandHost` solved with a `UIWindow` at
`.normal + 1`. **But `PassthroughWindow.hitTest` returns nil for every point on purpose** — the
band would otherwise eat the Reader's tap-to-hide-chrome, the pager's page swipe and every
pushed Settings page's back-swipe. A capsule with a live Play button cannot use that window.
This one takes `.normal + 2` and answers `hitTest` only inside the capsule's own rect.

The warm-up band is not touched. That is the owner's instruction, 2026-09-16.

- [ ] **Step 1: Write the centre**

```swift
// App/T2SReader/Design/MockIslandCenter.swift
import SwiftUI
import T2SApp
import UIKit

/// The one message the capsule is showing, and what its Play button does.
///
/// Four seconds, restarted by a second message — the same timing as `ToastCenter`, so an
/// announcement reads the same wherever it is drawn.
@MainActor
@Observable
final class MockIslandCenter {
    private(set) var message: ChapterReadyMessage?
    private(set) var cover: ToastContent.Cover?
    /// What the Play button does; nil when the message carries none (a failure).
    private(set) var action: (() -> Void)?
    private var dismissal: Task<Void, Never>?

    func show(_ message: ChapterReadyMessage, cover: ToastContent.Cover?,
              action: (() -> Void)?) {
        dismissal?.cancel()
        self.cover = cover
        self.action = action
        withAnimation(.spring(duration: 0.4)) { self.message = message }
        UIAccessibility.post(notification: .announcement, argument: message.title)
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissal?.cancel()
        action = nil
        withAnimation(.spring(duration: 0.35)) { message = nil }
    }
}
```

- [ ] **Step 2: Write the capsule**

```swift
// App/T2SReader/Design/MockIsland.swift
import SwiftUI
import T2SApp

/// A black capsule that begins as the Dynamic Island and grows downward.
///
/// **It is not a Live Activity and could not be one.** iOS never shows an app's own Live
/// Activity in the Dynamic Island while that app is in the foreground, so the in-app effect has
/// to be drawn by hand. This is that drawing.
///
/// On a phone with no island there is nothing to grow out of, so the same content is drawn as a
/// plain rounded card below the status bar. No pretending to be hardware that is not there.
struct MockIsland: View {
    @Environment(AppEnvironment.self) private var env
    var message: ChapterReadyMessage
    var cover: ToastContent.Cover?
    var action: (() -> Void)?
    var onDismiss: () -> Void

    /// Collapsed, the capsule is exactly the cutout. Expanded it keeps the cutout's width as its
    /// corner radius so the two silhouettes are continuous.
    private var hasIsland: Bool { IslandGeometry.deviceHasIsland }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: hasIsland ? IslandGeometry.cutoutHeight : 22,
                                 style: .continuous)
                    .fill(.black)
            )
            .padding(.horizontal, hasIsland ? 10 : Spacing.margin)
            .padding(.top, hasIsland ? IslandGeometry.cutoutTop : 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .transition(.scale(scale: 0.4, anchor: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(message.title), \(message.detail)")
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            if let cover {
                BookCover(relativePath: cover.relativePath, paths: env.paths, height: 40,
                          title: cover.title, isPDF: cover.isPDF)
                    .accessibilityHidden(true)
            } else {
                CircleGlyph(systemName: message.isFailure ? "exclamationmark" : "checkmark",
                            tint: .black, fill: .white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(message.title).typeRole(.pill).foregroundStyle(.white)
                Text(message.detail).typeRole(.meta).foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                Spacer(minLength: 8)
                Button(action: action) {
                    CircleGlyph(systemName: "play.fill", tint: .black, fill: .white)
                }
                .accessibilityLabel("Play")
            }
        }
    }
}
```

- [ ] **Step 3: Write the window**

```swift
// App/T2SReader/Design/MockIslandWindow.swift
import SwiftUI
import UIKit

/// A window that is touchable *only* where the capsule is.
///
/// `PassthroughWindow` (the status band's, `StatusBandWindow.swift:15`) refuses every touch,
/// which is right for a band that is only ever read. This capsule has a Play button, so it must
/// claim touches inside itself and refuse them everywhere else: a window that claimed the whole
/// screen would eat the Reader's tap-to-hide-chrome, the pager's page swipe and every pushed
/// Settings page's back-swipe, exactly as the band's doc comment warns.
final class IslandWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        // The hosting controller's own root view covers the screen and is not a control. Anything
        // deeper is the capsule or something on it.
        return hit === rootViewController?.view ? nil : hit
    }
}

/// The capsule's window, one level above the status band's, for the life of the app.
@MainActor
enum MockIslandHost {
    private static var window: IslandWindow?

    /// Idempotent — safe to call from `onAppear`, which can run again.
    static func attach(to environment: AppEnvironment) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState != .unattached })
        else { return }
        let host = UIHostingController(rootView: MockIslandRoot().environment(environment))
        host.view.backgroundColor = .clear
        let created = IslandWindow(windowScene: scene)
        created.rootViewController = host
        created.windowLevel = .normal + 2
        created.backgroundColor = .clear
        created.isHidden = false
        window = created
    }
}

/// What the window draws: whatever the centre is holding, and nothing when it holds nothing.
private struct MockIslandRoot: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if let message = env.island.message {
                MockIsland(message: message, cover: env.island.cover, action: env.island.action,
                           onDismiss: { env.island.dismiss() })
            }
        }
        .ignoresSafeArea()
    }
}
```

- [ ] **Step 4: Type-check what can be type-checked**

These views need the app target to compile, which Task 10 does. For now, confirm the package
still builds and nothing you wrote broke it:

Run: `swift build`
Expected: builds clean. (The three files above are not in the package and are not compiled by
this command — that is expected. This step only proves you did not damage `Sources/`.)

- [ ] **Step 5: Commit**

```bash
git add App/T2SReader/Design/MockIslandCenter.swift App/T2SReader/Design/MockIsland.swift App/T2SReader/Design/MockIslandWindow.swift
git commit -m "A black capsule that grows out of the island, in a window that only answers where it is"
```

---

## Task 7: The two Live Activity layouts

**Files:**
- Create: `App/T2SReaderActivities/T2SActivitiesBundle.swift`
- Create: `App/T2SReaderActivities/RenderActivityWidget.swift`
- Create: `App/T2SReaderActivities/SleepActivityWidget.swift`
- Delete: `App/T2SReaderActivities/.keep.swift` (the placeholder from Task 5)

**Interfaces:**
- Consumes: `RenderActivityAttributes`, `SleepActivityAttributes` (Task 5).
- Produces: the extension's `@main`. Nothing in the app imports these.

**No tests.** These are layouts. Task 10 photographs them.

Every Live Activity must supply all four presentations — Lock Screen, compact leading, compact
trailing and minimal — or iOS refuses to show it.

- [ ] **Step 1: Write the bundle**

```swift
// App/T2SReaderActivities/T2SActivitiesBundle.swift
import SwiftUI
import WidgetKit

@main
struct T2SActivitiesBundle: WidgetBundle {
    var body: some Widget {
        RenderActivityWidget()
        SleepActivityWidget()
    }
}
```

- [ ] **Step 2: Write the render layout**

```swift
// App/T2SReaderActivities/RenderActivityWidget.swift
import ActivityKit
import SwiftUI
import WidgetKit

/// The render queue, on the Lock Screen and in the real Dynamic Island.
///
/// The Lock Screen has room for the bar the mock island deliberately has not got — which is the
/// whole division of labour: in the app the Book sheet's progress box already shows the work, so
/// the capsule only announces the finish; out of the app nothing else is telling anyone
/// anything, so this carries the count and the bar.
struct RenderActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RenderActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(context.state.headline).font(.headline)
                Text(context.state.detail).font(.subheadline).foregroundStyle(.secondary)
                ProgressView(value: context.state.fraction).tint(.primary)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.7))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform").font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.ready)/\(context.state.total)")
                        .font(.title3).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.headline).font(.headline)
                        ProgressView(value: context.state.fraction).tint(.white)
                    }
                }
            } compactLeading: {
                Image(systemName: "waveform")
            } compactTrailing: {
                Text("\(context.state.ready)/\(context.state.total)").monospacedDigit()
            } minimal: {
                Image(systemName: "waveform")
            }
        }
    }
}
```

- [ ] **Step 3: Write the sleep layout**

```swift
// App/T2SReaderActivities/SleepActivityWidget.swift
import ActivityKit
import SwiftUI
import WidgetKit

/// The sleep timer.
///
/// `Text(timerInterval:)` counts down from the stored date **without the app updating it**, so
/// this card costs nothing to keep current — no wake-ups, no update budget, no battery. An
/// `.endOfChapter` sleep has no date and shows its sentence instead, because a clock ticking
/// toward a moment nobody can name would be a lie.
struct SleepActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.headline).font(.headline)
                    countdown(context.state)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.7))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "moon.zzz.fill").font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state).font(.title3)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.bookTitle).font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "moon.zzz.fill")
            } compactTrailing: {
                countdown(context.state)
            } minimal: {
                Image(systemName: "moon.zzz.fill")
            }
        }
    }

    @ViewBuilder
    private func countdown(_ state: SleepActivityAttributes.ContentState) -> some View {
        if let deadline = state.deadline {
            Text(timerInterval: Date.now...deadline, countsDown: true)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text(state.detail).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 4: Remove the placeholder and regenerate**

```bash
rm App/T2SReaderActivities/.keep.swift
cd App && xcodegen generate --quiet && cd ..
```

- [ ] **Step 5: Commit**

```bash
git add App/T2SReaderActivities App/T2SReader.xcodeproj/project.pbxproj
git commit -m "Lock Screen and island layouts for a running render and a sleeping book"
```

---

## Task 8: The director

**Files:**
- Create: `App/T2SReader/System/ActivityDirector.swift`

**Interfaces:**
- Consumes: `RenderCardReading` (Task 3), `SleepCardReading` (Task 4),
  `RenderActivityAttributes`, `SleepActivityAttributes` (Task 5).
- Produces: `ActivityDirector` (`@MainActor`, `final class`) with
  `updateRender(_ reading: RenderCardReading?, bookTitle: String, coverPath: String?)`,
  `updateSleep(_ reading: SleepCardReading?, bookTitle: String)`, and `endAll()`.

**No tests.** Everything decidable was decided in Tasks 3 and 4 and is tested there. What is
left is ActivityKit calls, which can only be exercised on a device or simulator — Task 10.

- [ ] **Step 1: Write the director**

```swift
// App/T2SReader/System/ActivityDirector.swift
import ActivityKit
import Foundation
import T2SApp

/// Starts, updates and ends the app's Live Activities.
///
/// One object for both so there is one place that knows whether an activity exists, and one
/// place that decides an update should break through. A reading with `alerts` set gets an
/// `AlertConfiguration`, which is what expands the island and puts a banner on the Lock Screen;
/// everything else changes the card silently under the reader's thumb.
///
/// Nothing here decides *what* the card says. That is `RenderCardReading` and
/// `SleepCardReading`, which are plain values and are tested.
@MainActor
final class ActivityDirector {
    private var render: Activity<RenderActivityAttributes>?
    private var sleep: Activity<SleepActivityAttributes>?

    private var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    // MARK: Renders

    func updateRender(_ reading: RenderCardReading?, bookTitle: String, coverPath: String?) {
        guard enabled else { return }
        guard let reading else {
            Task { await endRender() }
            return
        }
        let state = RenderActivityAttributes.ContentState(
            headline: reading.headline, detail: reading.detail, ready: reading.ready,
            total: reading.total, fraction: reading.fraction, isFinished: reading.isFinished)

        if let render {
            // `AlertConfiguration`'s title and body are `LocalizedStringResource`, which is
            // `ExpressibleByStringInterpolation` — so an interpolated runtime string compiles,
            // but becomes its own localization key. That is correct here (the text is already
            // composed and there is no catalogue to look it up in); if the compiler objects,
            // the fix is an explicit `LocalizedStringResource(stringLiteral:)`, not a rewrite.
            let alert: AlertConfiguration? = reading.alerts
                ? AlertConfiguration(title: "\(reading.headline)", body: "\(reading.detail)",
                                     sound: .default)
                : nil
            Task {
                await render.update(ActivityContent(state: state, staleDate: nil), alertConfiguration: alert)
                // The last thing it will ever say stays up briefly, then clears itself rather
                // than sitting on the Lock Screen for the system's default four hours.
                if reading.isFinished { await endRender(after: .seconds(8)) }
            }
            return
        }

        guard !reading.isFinished else { return }
        let attributes = RenderActivityAttributes(bookTitle: bookTitle, coverPath: coverPath)
        render = try? Activity.request(attributes: attributes,
                                       content: ActivityContent(state: state, staleDate: nil),
                                       pushType: nil)
    }

    private func endRender(after delay: Duration = .zero) async {
        guard let render else { return }
        self.render = nil
        if delay > .zero { try? await Task.sleep(for: delay) }
        await render.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: Sleep

    func updateSleep(_ reading: SleepCardReading?, bookTitle: String) {
        guard enabled else { return }
        guard let reading else {
            Task { await endSleep() }
            return
        }
        let state = SleepActivityAttributes.ContentState(
            headline: reading.headline, detail: reading.detail, deadline: reading.deadline)
        if let sleep {
            Task { await sleep.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        sleep = try? Activity.request(attributes: SleepActivityAttributes(bookTitle: bookTitle),
                                      content: ActivityContent(state: state, staleDate: nil),
                                      pushType: nil)
    }

    private func endSleep() async {
        guard let sleep else { return }
        self.sleep = nil
        await sleep.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: Teardown

    func endAll() {
        Task {
            await endRender()
            await endSleep()
        }
    }
}
```

- [ ] **Step 2: Confirm the package is undamaged**

Run: `swift build`
Expected: builds clean. (This file is not in the package; the step proves you broke nothing.)

- [ ] **Step 3: Commit**

```bash
git add App/T2SReader/System/ActivityDirector.swift
git commit -m "One object knows whether a card is live, and which update is worth a buzz"
```

---

## Task 9: Wiring

**Files:**
- Modify: `App/T2SReader/AppEnvironment.swift`
- Modify: `App/T2SReader/T2SReaderApp.swift`
- Modify: `App/T2SReader/Root/RootPager.swift:233-235` and `:359-388`

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: nothing new. This is the task that makes the other eight visible.

**Runs alone.** It is the only task that touches `RootPager.swift`, and every earlier task's
file is disjoint from it.

- [ ] **Step 1: Give the environment the centre and the director**

In `App/T2SReader/AppEnvironment.swift`, beside the existing `toasts` property, add:

```swift
    let island = MockIslandCenter()
    let activities = ActivityDirector()
```

- [ ] **Step 2: Attach the island window at launch**

In `App/T2SReader/T2SReaderApp.swift`, in the `.onAppear` closure, immediately after
`StatusBandHost.attach(to: environment)`:

```swift
                        // The capsule, one level above the band's window. Same reason the band
                        // has one — it must be over the Reader's full-screen cover — but this
                        // one answers touches inside itself, because it carries a Play button.
                        MockIslandHost.attach(to: environment)
```

- [ ] **Step 3: Route the finished-chapter announcement**

Replace the body of `showRenderToast(_:)` in `RootPager.swift:359` so it builds the message
once and sends it to whichever surface is live. Keep the method name — the `onChange` at
`:233` already calls it.

```swift
    /// The one message a finished chapter earns, sent to exactly one surface.
    ///
    /// App on screen: the capsule at the top says it, wherever in the app the reader is — which
    /// is the whole reason it exists, since the Book sheet's progress box only exists while that
    /// sheet is open. App backgrounded: the Live Activity alerts instead. Never both (owner,
    /// 2026-09-16).
    private func showRenderToast(_ job: ChapterRenderJob) {
        guard let book = env.libraryModel.summaries.first(where: { $0.id == job.documentID }) else { return }
        let cover = ToastContent.Cover(relativePath: book.document.coverImagePath,
                                       title: book.document.title,
                                       isPDF: book.document.sourceType == .pdf)
        let chapters = env.libraryModel.progress(for: book.id)?.chapterCount ?? 0
        let message = ChapterReadyMessage.make(job: job, documentTitle: book.document.title,
                                               chapterCount: chapters)
        let play: (() -> Void)? = message.isFailure
            ? nil
            : { playRendered(book, chapter: chapters > 1 ? job.chapterIndex : nil) }

        switch Announcement.route(isForeground: scenePhase == .active) {
        case .island:
            env.island.show(message, cover: cover, action: play)
        case .liveActivity:
            updateRenderActivity(justFinished: message.isFailure ? nil : message.detail)
        }
    }

    /// Pushes the queue's current state to the Live Activity. `justFinished` is what makes the
    /// update break through: a chapter landing is the only thing worth a banner.
    private func updateRenderActivity(justFinished: String?) {
        let jobs = env.chapterRenderer.queue
        let book = jobs.first.flatMap { job in
            env.libraryModel.summaries.first { $0.id == job.documentID }
        }
        let title = book?.document.title ?? ""
        let reading = RenderCardReading.make(jobs: jobs, bookTitle: title,
                                             hold: env.chapterRenderer.hold,
                                             justFinished: justFinished)
        env.activities.updateRender(reading, bookTitle: title,
                                    coverPath: book?.document.coverImagePath)
    }
```

- [ ] **Step 4: Keep the card current while the queue moves**

Add beside the existing `onChange(of: env.chapterRenderer.finishCount)` at `RootPager.swift:233`:

```swift
        // The card follows the queue even when nothing finished — a batch starting, a hold
        // arriving, the last job leaving. `justFinished: nil` keeps every one of these silent.
        .onChange(of: env.chapterRenderer.queue.count) { _, _ in updateRenderActivity(justFinished: nil) }
        .onChange(of: env.chapterRenderer.hold) { _, _ in updateRenderActivity(justFinished: nil) }
```

- [ ] **Step 5: Drive the sleep card**

Add beside them:

```swift
        // The sleep card needs no updates while it counts — the view ticks from the deadline on
        // its own — so this fires only when the timer starts, changes or is cancelled.
        .onChange(of: env.sleepTimer.active) { _, option in
            let reading = SleepCardReading.make(option: option,
                                                deadline: env.sleepTimer.deadlineDate,
                                                chapterTitle: env.sleepTimer.sleepChapterTitle)
            env.activities.updateSleep(reading, bookTitle: env.player.current?.document.title ?? "")
        }
```

- [ ] **Step 6: Confirm the package still passes**

Run: `swift test`
Expected: PASS. Nothing in this task touched `Sources/`, so a failure here means an earlier
task regressed and must be fixed before Task 10.

- [ ] **Step 7: Commit**

```bash
git add App/T2SReader/AppEnvironment.swift App/T2SReader/T2SReaderApp.swift App/T2SReader/Root/RootPager.swift
git commit -m "A finished chapter reaches the capsule or the Lock Screen, and never both at once"
```

---

## Task 10: Build it and look at it

**Files:** none — this task changes nothing. It proves the previous nine.

Run by the orchestrator alone. **One `xcodebuild` at a time, machine-wide.**

- [ ] **Step 1: Check there is room**

```bash
df -h /
```

If free space is under ~5 GB, stop and say so rather than starting a build that will fill the
disk.

- [ ] **Step 2: Build**

```bash
scripts/build-app.sh
```

Expected: succeeds. **If it fails with "'Document' is ambiguous"**, that is the known
pre-existing break (T2SCore vs SwiftSoup) and is not yours. Report it and fall back to
type-checking the new views with `swiftc -typecheck` against the iOS SDK, as recorded in the
`xcode-27-metal-toolchain` note.

- [ ] **Step 3: Run it on an island simulator**

The capsule can only be judged on a device with an island, and the owner's phone is an
iPhone 11 Pro, which has none. Boot an iPhone 16 Pro simulator and install:

`scripts/build-app.sh` writes to `.build/DerivedData-App` (see its `-derivedDataPath`), so
the bundle is where that find command reports:

```bash
APP=$(find .build/DerivedData-App/Build/Products -name 'T2SReader.app' -maxdepth 3 | head -1)
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true
xcrun simctl install booted "$APP"
SIMCTL_CHILD_T2S_SILENT=1 xcrun simctl launch booted com.t2s.reader
```

Never unmute. Never play audio on this Mac.

- [ ] **Step 4: Photograph the capsule against the real island**

Import a document, render a chapter from the Book sheet, and screenshot the moment the capsule
appears:

```bash
xcrun simctl io booted screenshot /tmp/island-capsule.png
```

Check, by eye, against the screenshot: does the capsule's top edge meet the island's top edge,
and is its width sensible beside the cutout? **The 126 × 37.33 / 11 pt figures are
community-measured, not Apple's.** If they are wrong, this is where it shows — adjust the three
constants in `IslandGeometry` and shoot it again.

- [ ] **Step 5: Photograph the fallback**

```bash
xcrun simctl boot "iPhone SE (3rd generation)" 2>/dev/null || true
```

Install and repeat. Expect a plain rounded card under the status bar and **no** black capsule
jammed into a notch. This is the fail-safe from Task 1 doing its job.

- [ ] **Step 6: Photograph the Live Activities**

Background the app while a batch renders (swipe up to the home screen, lock the device with
`xcrun simctl ui booted appearance` unchanged) and screenshot the Lock Screen. Then start a
sleep timer and do the same. Confirm the countdown ticks with the app backgrounded and **no
update from the app** — that is the whole claim of Task 4.

- [ ] **Step 7: Commit the evidence**

```bash
mkdir -p docs/superpowers/evidence/2026-09-16-island
cp /tmp/island-*.png docs/superpowers/evidence/2026-09-16-island/
git add docs/superpowers/evidence/2026-09-16-island
git commit -m "What the capsule and the two cards actually look like"
```

---

## Task 11: One review, at the end

**Files:** none.

The owner asked for a single reviewer at the end rather than a gate between tasks. Dispatch one
subagent with the whole diff.

- [ ] **Step 1: Collect the diff**

The base is the commit this plan's first task branched from — `430d933` (the spec commit) at
the time of writing. Confirm it, then:

```bash
BASE=430d933
git log --oneline $BASE..HEAD
git diff $BASE..HEAD --stat
```

- [ ] **Step 2: Dispatch one reviewer**

Give it the spec (`docs/superpowers/specs/2026-09-16-island-and-live-activities-design.md`),
this plan, and the full diff. Ask specifically for:

1. **Does anything announce a finished chapter twice?** The single most likely defect: a path
   where both the capsule and the Live Activity fire.
2. **Can the island window swallow a touch it should not?** `IslandWindow.hitTest` must refuse
   everything outside the capsule, or the Reader loses tap-to-hide-chrome and the pager loses
   its page swipe.
3. **Does any file under `Sources/` import ActivityKit?** It must not — the package builds for
   macOS.
4. **Does the capsule's fallback path ever draw on a notch device?**
5. **Is any owner-approved string altered?** The four render headlines and the "has finished
   rendering" sentence.

- [ ] **Step 3: Apply what survives**

Use the superpowers:receiving-code-review skill. Verify each finding before implementing it;
push back on any that are wrong.

---

## Still open — needs the owner, not the implementer

**Alerting frequency.** This plan alerts on **every** finished chapter (`RenderCardReading`
sets `alerts` whenever `justFinished` is non-nil), following the owner's instruction that the
Live Activity announces finished chapters while the app is closed. An eight-chapter batch
therefore buzzes eight times in a pocket.

The quieter alternative — alert only on the batch's last chapter — is a one-line change in
`RenderCardReading.make`: replace `alerts: true` in the `justFinished` branch with
`alerts: false`. The test `aJustFinishedChapterTakesTheHeadlineAndAlerts` would flip with it.

Do not change it without the owner saying so.
