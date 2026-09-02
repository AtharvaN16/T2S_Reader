# Plan 4b: Reader, Playback Controls, and Preferences Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the v1 surface on top of Plan 4a: the read-along Reader page (Readium navigator with the active word decorated, auto-scroll, tap-to-seek, a compact control bar), the speed picker with unavailable rates, the sleep timer, autoplay-next, the Preferences page (voice, playback, reading appearance, pronunciation dictionary, storage manager with prepare budget), and the voice-change warning.

**Architecture:** Logic keeps living in the root-package target `T2SApp` (`ReaderModel`, `ReaderPreferences`, `SpeedPickerModel`, `SleepTimer`, `QueueContinuation`, `StorageModel`, `VoiceCatalog`), tested with `swift test` on macOS and free of Readium and UIKit. The app target hosts Readium's `EPUBNavigatorViewController` and `PDFNavigatorViewController` inside `UIViewControllerRepresentable`s, converts between `Position`/`HighlightRange` and `Locator` only through `LocatorMapping`, and renders the pages from spec §2.4.5. Word highlighting is a Readium decoration whose locator carries the word's text quote and the block's CSS selector; auto-scroll and tap hit-testing use small scripts run through the navigator's `evaluateJavaScript`. PDF is audio-first with page-level sync (spec §6.1).

**Tech Stack:** Swift 6, SwiftUI, Observation, AVFoundation (`AVSpeechSynthesisVoice` catalog), Readium swift-toolkit 3.11.0 (`ReadiumNavigator`, `ReadiumAdapterGCDWebServer`, `ReadiumStreamer`, `ReadiumShared`), WebKit through Readium, UserDefaults for preferences. iOS 18; macOS 15 for `swift test`.

**Spec:** `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (rev 7). Sections §2.2 (speed, sleep timer, voice picker, pronunciation dictionary, storage manager), §2.3 (Reader as a separate page), §2.4.1–§2.4.5 (Reader page, speed picker, sleep timer, context menu, Preferences page, voice-change warning), §3.4 (cache cap), §3.4.1 (budget, visible state), §3.6 (unavailable rates, catching up), §3.7.2, §5 (voice change invalidates audio), §6, §6.1, §9 steps 6 and 9.

## Global Constraints

- **Reader page** (spec §2.4.5): a separate full-screen page entered from a Queue row title, a chapter in the book sheet, or `Read along →` in the player. Back chevron top-left, chapter title center (tap → chapter list), overflow right (bookmark, appearance). Body is the Readium navigator at 24pt margins on `ground`. The active word is decorated with `accentSoft`, 4pt radius; nothing else on the page uses accent. Auto-scroll keeps the active line in the middle third; a manual scroll suspends it and shows a `Back to current` pill until tapped. Tap a sentence → seek there. Bottom bar pinned over a `ground` fade: tick scrubber, then back 15 · play · forward 30 · speed. During underrun the play glyph becomes a ring and a caption reads `catching up…`. PDF uses the same page with page-level highlight.
- **Reader body type** (spec §2.4.1): Inter 18 / Regular, 1.5 line height, normal tracking; size and line height user-adjustable independently of the system text size.
- **Speed picker** (spec §2.4.5): vertical list 0.5x–4.0x in 0.1x steps; rates whose sustained demand exceeds the §3.6 threshold drawn in `ink3` with a one-line footnote; the current rate checked. A rate is available when it is at most the highest entry of `PlaybackCoordinator.availableRates`.
- **Sleep timer** (spec §2.4.5): chips `10 · 20 · 30 · 45 · 60 min · End of chapter`, selected chip solid `ink`, accent "Start" pill, a grey caption that the timer ends early if the document does. It pauses playback when it fires.
- **Context menu** (spec §2.4.5): Archive (`destructive`), Mark as finished (`positive`), Details, Sleep timer, Change voice, Render whole document.
- **Preferences page** (spec §2.4.5): sections Voice (default voice → list with preview), Playback (skip intervals, default speed, autoplay next), Reading (text size, line height, theme System / Light / Dark), Pronunciation (→ dictionary list), Storage (prepare budget 1 h · 3 h · 8 h · Everything, prepared amount and last run, cache size and cap, evict), Cloud voices (BYO key — placeholder until Plan 5), iCloud sync toggle (disabled until Plan 6), links.
- **Voice change** (spec §5): changing voice invalidates that document's rendered audio structurally; the UI warns with how much rendered audio will be discarded, with a `destructive` confirm, before evicting and switching. Per-document override lives in `Document.voiceID`; the default voice is a preference. Until Plan 5, voices are the system voices (`AVSpeechSynthesisVoice`) and the engine resolves a voice identifier or falls back to the language default.
- **Evicting audio** (Plan 3 hand-off): `Library.evictAudio` only runs for a document that is not currently loaded in the player; for the loaded document the model reloads it after eviction. Prepare-on-charge visible state shows the prepared amount across the Queue and the last time Prepare ran.
- **Readium at the boundary** (spec §3.7.2): only the reader hosting files in the app target import `ReadiumNavigator`/`ReadiumShared`; `T2SApp` stays Readium-free; positions persist as `Position`, never as `Locator`.
- **Playback ownership** (spec §3): the Reader observes the same `PlayerModel`/`PlaybackCoordinator` as the player sheet; leaving the Reader never stops playback.
- Design rules from Plan 4a's constraints still bind (tokens only, type roles, spacing, no cards or dividers, one accent per screen). Swift 6; Swift Testing; every public type `Sendable` or `@MainActor`; app builds with `scripts/build-app.sh`; commit after every task with the message given.

## Verified toolchain facts (do not re-derive)

- Readium 3.11.0 navigator: `EPUBNavigatorViewController(publication:initialLocation:config:httpServer:)` with `Configuration(preferences:defaults:editingActions:contentInset:fontFamilyDeclarations:…)`; `EPUBPreferences { backgroundColor: Color?, fontFamily: FontFamily?, fontSize: Double?, lineHeight: Double?, scroll: Bool?, textColor: Color?, theme: Theme? }` submitted with `submitPreferences(_:)`; `HTMLFontFamilyDeclaration(fontFamily:alternates:fontFaces:)` with `CSSFontFace` for bundled fonts; `DecorableNavigator.apply(decorations:in:)`, `Decoration(id:locator:style: .highlight(tint:isActive:))`, `observeDecorationInteractions(inGroup:onActivated:)`; `Navigator.go(to:options:) async -> Bool` (`NavigatorGoOptions(animated:)`), `currentLocation`, `VisualNavigator.firstVisibleElementLocator() async`, `VisualNavigatorDelegate.navigator(_:didTapAt:)`, `NavigatorDelegate.navigator(_:locationDidChange:)`, `evaluateJavaScript(_:) async -> Result<Any, Error>` on the EPUB navigator. `GCDHTTPServer(assetRetriever:)` from `ReadiumAdapterGCDWebServer`.
- `PDFNavigatorViewController(publication:initialLocation:config:delegate:) throws` is a `VisualNavigator` but **not** a `DecorableNavigator`: no word decorations on PDF; page-level sync only (spec §6.1), by `go(to:)` with a `Locator` whose `locations.position` is the 1-based page and `progression` the page start.
- Plan 3 `Position` rules: EPUB `resourceHref` is the normalized resource key with `cssSelector` when known; PDF `resourceHref == "source.pdf"`, `progression == pageIndex / pageCount`. `LocatorMapping.locator(for: HighlightRange, in:)` yields a locator with `text.before/highlight/after` and the CSS selector; `LocatorMapping.position(for: Locator)` normalizes the href.
- Plan 4a API: `AppEnvironment { paths, store, audioStore, library, coordinator, libraryModel, player, importModel, audioSession, deviceMonitor }`; `PlayerModel { current, state, isPlaying, isCatchingUp, elapsed, total, chapters, chapterIndex, scrubber, renderError, load(_:play:), togglePlay, skip(by:), seek(fraction:), seek(toChapter:), setRate, renderWholeDocument, tick, persistRenderedChapters, addBookmark }`; `LibraryModel { summaries, queue, finished, collection, progress(for:), archive, enqueue, move, markFinished, delete, refresh }`; `ImportModel`; views `QueuePage`, `QueueRow`, `BookSheet`, `PlayerSheet`, `ControlPill`, `ChapterList`, `TickScrubber`, `AddSheet(onImported:)`, `DetailsSheet`; design `Tokens`, `TypeRole`, `Spacing`, `Pill`, `PageTitle`, `Artwork`, `ProgressBar`, `PositiveCheck`.
- `SystemSpeechEngine` resolves `request.voiceID` with `AVSpeechSynthesisVoice(identifier:)` and falls back to the language voice; the coordinator uses `document.voiceID ?? "default"` for both the request and the render key, so a per-document voice change changes every key (spec §5) and the default voice must be applied by the environment (`PlaybackCoordinator` has no default-voice input; Task 8 adds one through `Document.voiceID` at load).
- `RateLimits.allRates` is the coarse list `[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0]`; `PlaybackCoordinator.availableRates` is the subset whose `measuredRTF × rate ≤ 0.8` (safety factor), all of them until an RTF is measured; `setRate(_:)` clamps to `[0.5, maxSustainableRate]` without snapping, so 0.1-step rates from the picker are honoured. The spec's picker (0.1 steps) therefore builds its own row list and marks a row available when `rate ≤ availableRates.max()`.

## File structure

```
Sources/T2SApp/
  Reader/ReaderModel.swift                   following state, active highlight, tap-to-seek resolution
  Reader/SourceHit.swift                     what a tap on the page reports (resource, block text, offset)
  Preferences/ReaderPreferences.swift        text size, line height, theme, skip intervals, default speed, autoplay
  Preferences/VoiceCatalog.swift             voice list abstraction (protocol + system implementation lives in the app)
  Playback/SpeedPickerModel.swift
  Playback/SleepTimer.swift
  Playback/QueueContinuation.swift           autoplay next
  Storage/StorageModel.swift                 cache size/cap, per-document eviction, prepare budget, prepared amount
Tests/T2SAppTests/…                          one suite per model
App/T2SReader/
  Reader/PublicationCache.swift              opens Readium publications once per document; shared HTTP server
  Reader/EPUBReaderView.swift                UIViewControllerRepresentable + coordinator (decorations, scroll, taps)
  Reader/PDFReaderView.swift                 page-level sync
  Reader/ReaderPage.swift                    chrome, body, bottom bar, Back to current, appearance sheet
  Reader/ReaderScripts.swift                 the two JS snippets (scroll-to-decoration, hit-test)
  Player/SpeedPicker.swift, SleepTimerSheet.swift
  Preferences/PreferencesPage.swift (replaced), VoiceListPage.swift, PronunciationPage.swift, StoragePage.swift, AppearanceSheet.swift
  Player/VoiceChangeSheet.swift
  System/SystemVoiceCatalog.swift
  routing edits in QueuePage, BookSheet, PlayerSheet, ControlPill, AddSheet call sites, T2SReaderApp
```

---
### Task 1: `ReaderModel` and tap-to-seek resolution (`T2SApp`)

**Files:**
- Create: `Sources/T2SApp/Reader/SourceHit.swift`, `Sources/T2SApp/Reader/ReaderModel.swift`
- Create: `Tests/T2SAppTests/ReaderModelTests.swift`

**Interfaces:**
- Consumes: `PlayerModel` (`coordinator`, `chapters`, `chapterIndex`, `current`, `isCatchingUp`), `PlaybackCoordinator.highlight`, `HighlightRange`, `Timeline`, `Playhead`, `PDFDocumentReader.resourceHref`.
- Produces: `public struct SourceHit { resourceHref, blockText, offsetInBlock, pageIndex: Int? }`; `@MainActor @Observable public final class ReaderModel { init(player:); isFollowing; activeHighlight; chapterTitle; suspendFollowing(); resumeFollowing(); seek(to hit:) async -> Bool; static func utteranceIndex(for:in:) -> Int? ; static func normalized(_:) -> String }`.

The page's JavaScript reports a tap as the tapped block's text and the caret offset inside it (`SourceHit`); Readium's own segment text is whitespace-normalized, so matching collapses whitespace on both sides before locating the utterance whose `source` contains the tap. PDF taps carry only a page.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SAppTests/ReaderModelTests.swift
import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SLibrary
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct ReaderModelTests {
    func utterance(_ text: String, href: String, offset: Int, progression: Double = 0) -> Utterance {
        let n = text.utf16.count
        return Utterance(position: Position(resourceHref: href, progression: progression, charOffset: offset), source: text, spoken: text,
                         spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], duration: .estimated(1))
    }

    var epubTimeline: Timeline {
        Timeline(chapters: [Chapter(title: "One", position: Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0), utterances: [
            utterance("First sentence.", href: "OEBPS/ch1.xhtml", offset: 0),
            utterance("Second sentence here.", href: "OEBPS/ch1.xhtml", offset: 16),
            utterance("Another block.", href: "OEBPS/ch1.xhtml", offset: 38),
        ])])
    }

    @Test func resolvesTheUtteranceUnderTheTap() {
        let t = epubTimeline
        let block = "First sentence. Second sentence here."
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: block, offsetInBlock: 3), in: t) == 0)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: block, offsetInBlock: 20), in: t) == 1)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: block, offsetInBlock: 15), in: t) == 1) // on the gap: next start ≤ offset wins
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: "Another block.", offsetInBlock: 5), in: t) == 2)
    }

    @Test func whitespaceIsNormalizedOnBothSides() {
        let t = epubTimeline
        let raw = "  First   sentence.\n\n  Second\tsentence here.  "
        #expect(ReaderModel.normalized(raw) == "First sentence. Second sentence here.")
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: raw, offsetInBlock: 4), in: t) == 0)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: raw, offsetInBlock: 26), in: t) == 1)
    }

    @Test func unknownTextOrResourceYieldsNil() {
        let t = epubTimeline
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch9.xhtml", blockText: "First sentence.", offsetInBlock: 0), in: t) == nil)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: "Not in the book.", offsetInBlock: 0), in: t) == nil)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: "", offsetInBlock: 0), in: t) == nil)
    }

    @Test func pdfTapsResolveByPage() {
        let href = PDFDocumentReader.resourceHref
        let t = Timeline(chapters: [Chapter(title: "Doc", position: Position(resourceHref: href, progression: 0), utterances: [
            utterance("Page one.", href: href, offset: 0, progression: 0),
            utterance("Page two, first.", href: href, offset: 10, progression: 0.5),
            utterance("Page two, second.", href: href, offset: 27, progression: 0.5),
        ])])
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: href, blockText: "", offsetInBlock: 0, pageIndex: 1), in: t) == 1)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: href, blockText: "", offsetInBlock: 0, pageIndex: 0), in: t) == 0)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: href, blockText: "", offsetInBlock: 0, pageIndex: 5), in: t) == nil)
    }

    @Test func seekingAndFollowing() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        let reader = ReaderModel(player: player)
        #expect(reader.isFollowing)
        #expect(reader.chapterTitle == "Chapter 1")
        reader.suspendFollowing()
        #expect(!reader.isFollowing)
        let hit = SourceHit(resourceHref: "OEBPS/ch2.xhtml", blockText: "Sentence number 2 here.", offsetInBlock: 3)
        #expect(await reader.seek(to: hit))
        #expect(player.coordinator.playhead.utteranceIndex == 2)
        #expect(reader.isFollowing)                                         // a tap re-engages following
        #expect(reader.chapterTitle == "Chapter 2")
        #expect(await reader.seek(to: SourceHit(resourceHref: "nope", blockText: "x", offsetInBlock: 0)) == false)
        #expect(reader.activeHighlight?.utteranceIndex == 2)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ReaderModelTests`
Expected: compile error, `ReaderModel` not found.

- [ ] **Step 3: Implement**

```swift
// Sources/T2SApp/Reader/SourceHit.swift
import Foundation

/// What a tap on the page reports: the resource, the tapped block's text, and the UTF-16 caret
/// offset inside it. PDF taps carry only the page (spec §6.1: page-level sync).
public struct SourceHit: Hashable, Sendable {
    /// The normalized resource key, as persisted in `Position.resourceHref`.
    public var resourceHref: String
    public var blockText: String
    public var offsetInBlock: Int
    public var pageIndex: Int?

    public init(resourceHref: String, blockText: String, offsetInBlock: Int, pageIndex: Int? = nil) {
        self.resourceHref = resourceHref
        self.blockText = blockText
        self.offsetInBlock = offsetInBlock
        self.pageIndex = pageIndex
    }
}
```

```swift
// Sources/T2SApp/Reader/ReaderModel.swift
import Foundation
import Observation
import T2SCore
import T2SLibrary

/// The Reader page's state over the shared player (spec §2.3: both observe the same coordinator).
/// Following = auto-scroll keeps the active line in view; a manual scroll suspends it; a tap on a
/// sentence seeks there and re-engages following.
@MainActor
@Observable
public final class ReaderModel {
    public let player: PlayerModel
    public private(set) var isFollowing = true

    public init(player: PlayerModel) { self.player = player }

    public var activeHighlight: HighlightRange? { player.coordinator.highlight }
    public var isCatchingUp: Bool { player.isCatchingUp }

    public var chapterTitle: String {
        if let i = player.chapterIndex, player.chapters.indices.contains(i) { return player.chapters[i].title }
        return player.current?.document.title ?? ""
    }

    public func suspendFollowing() { isFollowing = false }
    public func resumeFollowing() { isFollowing = true }

    /// Tap a sentence → seek there (spec §2.4.5). False when the tap matches no utterance.
    public func seek(to hit: SourceHit) async -> Bool {
        guard let timeline = player.coordinator.timeline, let index = Self.utteranceIndex(for: hit, in: timeline) else { return false }
        await player.coordinator.seek(to: Playhead(utteranceIndex: index))
        isFollowing = true
        return true
    }

    /// Whitespace runs collapse to one space and the ends are trimmed, the way Readium's segments are.
    public static func normalized(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The utterance under a tap: same resource, `source` contained in the block's normalized text,
    /// and the tap's normalized offset inside it (or the nearest earlier one; PDF: first utterance
    /// of the tapped page).
    public static func utteranceIndex(for hit: SourceHit, in timeline: Timeline) -> Int? {
        var index = 0
        var candidates: [(index: Int, utterance: Utterance)] = []
        for chapter in timeline.chapters {
            for u in chapter.utterances {
                if u.position.resourceHref == hit.resourceHref { candidates.append((index, u)) }
                index += 1
            }
        }
        guard !candidates.isEmpty else { return nil }

        if let page = hit.pageIndex {
            let pages = candidates.map(\.utterance.position.progression)
            guard let count = pageCount(from: pages) else { return nil }
            let target = Double(page) / Double(count)
            return candidates.first { abs($0.utterance.position.progression - target) < 1e-9 }?.index
        }

        let block = normalized(hit.blockText)
        guard !block.isEmpty else { return nil }
        let prefix = String(hit.blockText.utf16.prefix(max(0, hit.offsetInBlock)).map { Character(UnicodeScalar($0) ?? " ") })
        let offset = normalized(prefix).utf16.count
        let blockNS = block as NSString
        var located: [(index: Int, start: Int, length: Int)] = []
        for c in candidates {
            let source = normalized(c.utterance.source)
            guard !source.isEmpty else { continue }
            let r = blockNS.range(of: source)
            if r.location != NSNotFound { located.append((c.index, r.location, r.length)) }
        }
        guard !located.isEmpty else { return nil }
        if let inside = located.first(where: { $0.start <= offset && offset < $0.start + $0.length }) { return inside.index }
        if let before = located.filter({ $0.start <= offset }).max(by: { $0.start < $1.start }) { return before.index }
        return located.min(by: { $0.start < $1.start })?.index
    }

    /// PDF positions are `pageIndex / pageCount`; the count is recoverable from the smallest positive step.
    private static func pageCount(from progressions: [Double]) -> Int? {
        let distinct = Set(progressions).sorted()
        guard distinct.count > 1 else { return distinct.first == 0 ? 1 : nil }
        let step = zip(distinct, distinct.dropFirst()).map { $1 - $0 }.min() ?? 0
        guard step > 0 else { return nil }
        return Int((1 / step).rounded())
    }
}
```

The prefix mapping goes through UTF-16 code units so `offsetInBlock` (a JavaScript caret offset, which is UTF-16) lands on the same code-unit axis; a split surrogate at the caret degrades to a space, which cannot change which utterance is found.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ReaderModelTests`
Expected: 5 tests passed. In `pdfTapsResolveByPage` the progressions `[0, 0.5, 0.5]` give a page count of 2, so page 1 → the first utterance at 0.5 and page 5 → nil.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp/Reader Tests/T2SAppTests/ReaderModelTests.swift
git commit -m "T2SApp: ReaderModel with following state and tap-to-seek resolution"
```

---

### Task 2: `ReaderPreferences` and the voice catalog contract (`T2SApp`)

**Files:**
- Create: `Sources/T2SApp/Preferences/ReaderPreferences.swift`, `Sources/T2SApp/Preferences/VoiceCatalog.swift`
- Create: `Tests/T2SAppTests/ReaderPreferencesTests.swift`

**Interfaces:**
- Consumes: `AppPaths.prepareBudgetKey`, `UserDefaults`.
- Produces: `public enum ReaderTheme: String, CaseIterable { system, light, dark }`; `@MainActor @Observable public final class ReaderPreferences { init(defaults:); textScale; lineHeight; theme; skipBackSeconds; skipForwardSeconds; defaultRate; autoplayNext; defaultVoiceID: String?; prepareBudgetSeconds; static let textScaleRange, lineHeightRange, skipBackOptions, skipForwardOptions, prepareBudgetOptions; reset() }`; `public struct VoiceOption: Hashable, Sendable, Identifiable { id, name, language, isDefault }`, `public protocol VoiceCatalog: Sendable { func voices() -> [VoiceOption] }`, `VoiceOption.systemDefault`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SAppTests/ReaderPreferencesTests.swift
import Foundation
import Testing
@testable import T2SApp

@MainActor
@Suite struct ReaderPreferencesTests {
    func fresh() -> UserDefaults {
        let suite = "t2s-prefs-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func defaultsMatchTheSpec() {
        let p = ReaderPreferences(defaults: fresh())
        #expect(p.textScale == 1.0 && p.lineHeight == 1.5 && p.theme == .system)
        #expect(p.skipBackSeconds == 15 && p.skipForwardSeconds == 30)
        #expect(p.defaultRate == 1.0 && p.autoplayNext)
        #expect(p.defaultVoiceID == nil)
        #expect(p.prepareBudgetSeconds == 3 * 3600)
        #expect(ReaderPreferences.prepareBudgetOptions.map(\.seconds) == [3600, 3 * 3600, 8 * 3600, .infinity])
    }

    @Test func valuesPersistAndClamp() {
        let d = fresh()
        let p = ReaderPreferences(defaults: d)
        p.textScale = 9
        p.lineHeight = 0.1
        p.theme = .dark
        p.skipBackSeconds = 30
        p.skipForwardSeconds = 45
        p.defaultRate = 1.5
        p.autoplayNext = false
        p.defaultVoiceID = "com.apple.voice.compact.en-US.Samantha"
        p.prepareBudgetSeconds = .infinity
        #expect(p.textScale == ReaderPreferences.textScaleRange.upperBound)
        #expect(p.lineHeight == ReaderPreferences.lineHeightRange.lowerBound)
        let again = ReaderPreferences(defaults: d)
        #expect(again.textScale == ReaderPreferences.textScaleRange.upperBound && again.lineHeight == ReaderPreferences.lineHeightRange.lowerBound)
        #expect(again.theme == .dark && again.skipBackSeconds == 30 && again.skipForwardSeconds == 45)
        #expect(again.defaultRate == 1.5 && !again.autoplayNext)
        #expect(again.defaultVoiceID == "com.apple.voice.compact.en-US.Samantha")
        #expect(again.prepareBudgetSeconds == .infinity)
        again.reset()
        #expect(again.textScale == 1.0 && again.theme == .system && again.defaultVoiceID == nil && again.prepareBudgetSeconds == 3 * 3600)
    }

    @Test func voiceOptionDefault() {
        #expect(VoiceOption.systemDefault.id == "default" && VoiceOption.systemDefault.isDefault)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ReaderPreferencesTests`
Expected: compile error.

- [ ] **Step 3: Implement**

```swift
// Sources/T2SApp/Preferences/ReaderPreferences.swift
import Foundation
import Observation

public enum ReaderTheme: String, CaseIterable, Sendable { case system, light, dark }

/// User preferences behind the Preferences page (spec §2.4.5) and the Reader's appearance, stored in
/// `UserDefaults`. Reader body size and line height are independent of the system text size
/// (spec §2.4.1), hence a scale over the 18pt base rather than a Dynamic Type category.
@MainActor
@Observable
public final class ReaderPreferences {
    public static let textScaleRange: ClosedRange<Double> = 0.8...1.6
    public static let lineHeightRange: ClosedRange<Double> = 1.3...1.8
    public static let skipBackOptions = [10, 15, 30]
    public static let skipForwardOptions = [15, 30, 45]
    public struct BudgetOption: Hashable, Sendable {
        public var label: String
        public var seconds: TimeInterval
    }
    /// Spec §3.4.1: 1 h · 3 h · 8 h · Everything.
    public static let prepareBudgetOptions = [
        BudgetOption(label: "1 hour", seconds: 3600), BudgetOption(label: "3 hours", seconds: 3 * 3600),
        BudgetOption(label: "8 hours", seconds: 8 * 3600), BudgetOption(label: "Everything", seconds: .infinity),
    ]

    private let defaults: UserDefaults
    private enum Key {
        static let textScale = "reader.textScale", lineHeight = "reader.lineHeight", theme = "reader.theme"
        static let skipBack = "playback.skipBack", skipForward = "playback.skipForward", rate = "playback.defaultRate"
        static let autoplay = "playback.autoplayNext", voice = "voice.default"
    }

    public var textScale: Double { didSet { textScale = Self.textScaleRange.clamped(textScale); defaults.set(textScale, forKey: Key.textScale) } }
    public var lineHeight: Double { didSet { lineHeight = Self.lineHeightRange.clamped(lineHeight); defaults.set(lineHeight, forKey: Key.lineHeight) } }
    public var theme: ReaderTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    public var skipBackSeconds: Int { didSet { defaults.set(skipBackSeconds, forKey: Key.skipBack) } }
    public var skipForwardSeconds: Int { didSet { defaults.set(skipForwardSeconds, forKey: Key.skipForward) } }
    public var defaultRate: Double { didSet { defaults.set(defaultRate, forKey: Key.rate) } }
    public var autoplayNext: Bool { didSet { defaults.set(autoplayNext, forKey: Key.autoplay) } }
    /// nil = the engine's language default ("default" in render keys).
    public var defaultVoiceID: String? { didSet { defaults.set(defaultVoiceID, forKey: Key.voice) } }
    /// `.infinity` = Everything. Stored as a Double; `AppPaths.prepareBudgetKey` is shared with the coordinator wiring.
    public var prepareBudgetSeconds: TimeInterval { didSet { defaults.set(prepareBudgetSeconds, forKey: AppPaths.prepareBudgetKey) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        textScale = Self.textScaleRange.clamped(defaults.object(forKey: Key.textScale) as? Double ?? 1.0)
        lineHeight = Self.lineHeightRange.clamped(defaults.object(forKey: Key.lineHeight) as? Double ?? 1.5)
        theme = ReaderTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        skipBackSeconds = defaults.object(forKey: Key.skipBack) as? Int ?? 15
        skipForwardSeconds = defaults.object(forKey: Key.skipForward) as? Int ?? 30
        defaultRate = defaults.object(forKey: Key.rate) as? Double ?? 1.0
        autoplayNext = defaults.object(forKey: Key.autoplay) as? Bool ?? true
        defaultVoiceID = defaults.string(forKey: Key.voice)
        prepareBudgetSeconds = defaults.object(forKey: AppPaths.prepareBudgetKey) as? Double ?? 3 * 3600
    }

    public func reset() {
        textScale = 1.0
        lineHeight = 1.5
        theme = .system
        skipBackSeconds = 15
        skipForwardSeconds = 30
        defaultRate = 1.0
        autoplayNext = true
        defaultVoiceID = nil
        prepareBudgetSeconds = 3 * 3600
    }
}

extension ClosedRange where Bound == Double {
    func clamped(_ v: Double) -> Double { Swift.min(upperBound, Swift.max(lowerBound, v)) }
}
```

```swift
// Sources/T2SApp/Preferences/VoiceCatalog.swift
import Foundation

/// A selectable voice (spec §2.2 voice picker). Until Plan 5, the app fills this from
/// `AVSpeechSynthesisVoice`; `systemDefault` maps to the engine's language fallback.
public struct VoiceOption: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var language: String
    public var isDefault: Bool

    public init(id: String, name: String, language: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.language = language
        self.isDefault = isDefault
    }

    public static let systemDefault = VoiceOption(id: "default", name: "System default", language: "en", isDefault: true)
}

public protocol VoiceCatalog: Sendable {
    /// `systemDefault` first, then the device's voices.
    func voices() -> [VoiceOption]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ReaderPreferencesTests`
Expected: 3 tests passed. Note `defaults.set(nil, forKey:)` removes the key, so `defaultVoiceID = nil` round-trips as nil.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp/Preferences Tests/T2SAppTests/ReaderPreferencesTests.swift
git commit -m "T2SApp: ReaderPreferences over UserDefaults; VoiceCatalog contract"
```

---

### Task 3: Speed picker model, sleep timer, autoplay-next (`T2SApp`)

**Files:**
- Create: `Sources/T2SApp/Playback/SpeedPickerModel.swift`, `Sources/T2SApp/Playback/SleepTimer.swift`, `Sources/T2SApp/Playback/QueueContinuation.swift`
- Create: `Tests/T2SAppTests/SpeedPickerModelTests.swift`, `Tests/T2SAppTests/SleepTimerTests.swift`, `Tests/T2SAppTests/QueueContinuationTests.swift`

**Interfaces:**
- Consumes: `RateLimits.allRates`, `PlayerModel`, `LibraryModel`, `ReaderPreferences.autoplayNext`.
- Produces: `public struct SpeedPickerModel { static let rates: [Double] (0.5…4.0 in 0.1 steps); rows: [Row { rate, label, isAvailable, isCurrent }]; footnote: String?; static func make(current:maxRate:) ; static func label(for:) }`; `public enum SleepOption { minutes(Int), endOfChapter }` with `static let all`; `@MainActor @Observable public final class SleepTimer { init(player:clock:); active; remainingSeconds; caption; start(_:); cancel(); tick() }`; `@MainActor @Observable public final class QueueContinuation { init(player:library:preferences:); advanceIfFinished() async -> Bool }`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SAppTests/SpeedPickerModelTests.swift
import Testing
import T2SCore
@testable import T2SApp

@Suite struct SpeedPickerModelTests {
    @Test func rowsCoverEveryRateAndMarkAvailability() {
        #expect(SpeedPickerModel.rates.count == 36 && SpeedPickerModel.rates.first == 0.5 && SpeedPickerModel.rates.last == 4.0)
        let m = SpeedPickerModel.make(current: 1.5, maxRate: 2.0)
        #expect(m.rows.count == 36)
        #expect(m.rows.first?.label == "0.5x" && m.rows.last?.label == "4x")
        #expect(m.rows.first { abs($0.rate - 1.5) < 0.001 }?.isCurrent == true)
        #expect(m.rows.filter(\.isCurrent).count == 1)
        #expect(m.rows.first { abs($0.rate - 2.0) < 0.001 }?.isAvailable == true)
        #expect(m.rows.first { abs($0.rate - 2.1) < 0.001 }?.isAvailable == false)
        #expect(m.footnote == "Rates above 2x can't be sustained on this device right now.")
        #expect(SpeedPickerModel.make(current: 1.0, maxRate: 4.0).footnote == nil)
        #expect(SpeedPickerModel.label(for: 1.0) == "1x" && SpeedPickerModel.label(for: 1.25) == "1.3x" && SpeedPickerModel.label(for: 0.5) == "0.5x")
    }
}
```

```swift
// Tests/T2SAppTests/SleepTimerTests.swift
import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct SleepTimerTests {
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        func advance(_ s: TimeInterval) { now = now.addingTimeInterval(s) }
    }

    func makePlayer(_ f: AppFixtures) throws -> PlayerModel {
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        return PlayerModel(coordinator: coordinator, library: f.library)
    }

    @Test func minutesCountDownAndPause() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let player = try makePlayer(f)
        await player.load(try #require(try await f.store.summary(id: id)), play: true)
        let clock = Clock()
        let timer = SleepTimer(player: player) { clock.now }
        #expect(timer.active == nil && timer.caption == nil)
        timer.start(.minutes(10))
        #expect(timer.active == .minutes(10) && timer.remainingSeconds == 600 && timer.caption == "Ends in 10:00")
        clock.advance(599)
        timer.tick()
        #expect(player.isPlaying && timer.caption == "Ends in 0:01")
        clock.advance(2)
        timer.tick()
        #expect(!player.isPlaying && timer.active == nil && timer.caption == nil)
    }

    @Test func endOfChapterStopsWhenTheChapterChanges() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let player = try makePlayer(f)
        await player.load(try #require(try await f.store.summary(id: id)), play: true)
        let timer = SleepTimer(player: player) { Date() }
        timer.start(.endOfChapter)
        #expect(timer.caption == "Until the end of Chapter 1")
        timer.tick()
        #expect(player.isPlaying)
        await player.seek(toChapter: 1)
        timer.tick()
        #expect(!player.isPlaying && timer.active == nil)
    }

    @Test func cancelAndDocumentEnd() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let player = try makePlayer(f)
        await player.load(try #require(try await f.store.summary(id: id)), play: true)
        let timer = SleepTimer(player: player) { Date() }
        timer.start(.minutes(60))
        timer.cancel()
        #expect(timer.active == nil)
        timer.start(.minutes(60))
        await player.skip(by: 10_000)                                       // finishes the document
        timer.tick()
        #expect(timer.active == nil)
    }
}
```

```swift
// Tests/T2SAppTests/QueueContinuationTests.swift
import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct QueueContinuationTests {
    func fresh() -> UserDefaults {
        let suite = "t2s-prefs-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func advancesToTheNextQueuedDocumentWhenFinished() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake(), b = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        let library = LibraryModel(library: f.library)
        await library.refresh()
        let prefs = ReaderPreferences(defaults: fresh())
        let continuation = QueueContinuation(player: player, library: library, preferences: prefs)

        await player.load(try #require(try await f.store.summary(id: a)), play: true)
        #expect(await continuation.advanceIfFinished() == false)             // still playing
        await player.skip(by: 10_000)
        #expect(player.state == .finished)
        #expect(await continuation.advanceIfFinished())
        #expect(player.current?.id == b && player.isPlaying)
        await player.skip(by: 10_000)
        #expect(await continuation.advanceIfFinished() == false)             // nothing after b
        #expect(player.current?.id == b)

        prefs.autoplayNext = false
        await player.load(try #require(try await f.store.summary(id: a)), play: true)
        await player.skip(by: 10_000)
        #expect(await continuation.advanceIfFinished() == false)
        #expect(player.current?.id == a)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "SpeedPickerModelTests|SleepTimerTests|QueueContinuationTests"`
Expected: compile errors.

- [ ] **Step 3: Implement**

```swift
// Sources/T2SApp/Playback/SpeedPickerModel.swift
import Foundation
import T2SCore

/// Spec §2.4.5 speed picker: every rate 0.5x–4.0x, unavailable ones (spec §3.6) marked with a footnote.
public struct SpeedPickerModel: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        public var rate: Double
        public var label: String
        public var isAvailable: Bool
        public var isCurrent: Bool
        public var id: Double { rate }
    }

    public var rows: [Row]
    public var footnote: String?

    /// 0.5x…4.0x in 0.1x steps (spec §2.4.5), built once so 0.1-step arithmetic never drifts.
    public static let rates: [Double] = (5...40).map { Double($0) / 10 }

    /// `maxRate` is the coordinator's `availableRates.max()` (the highest sustainable rate, spec §3.6).
    public static func make(current: Double, maxRate: Double) -> SpeedPickerModel {
        let rows = rates.map { rate in
            Row(rate: rate, label: label(for: rate), isAvailable: rate <= maxRate + 0.001,
                isCurrent: abs(rate - current) < 0.001)
        }
        let highest = rows.filter(\.isAvailable).map(\.rate).max()
        let footnote = rows.contains { !$0.isAvailable }
            ? "Rates above \(label(for: highest ?? 0)) can't be sustained on this device right now." : nil
        return SpeedPickerModel(rows: rows, footnote: footnote)
    }

    /// "1x", "1.5x", "0.5x" — one decimal at most, the bare number of spec §2.4.5.
    public static func label(for rate: Double) -> String {
        let rounded = (rate * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))x" : String(format: "%.1fx", rounded)
    }
}
```

```swift
// Sources/T2SApp/Playback/SleepTimer.swift
import Foundation
import Observation

public enum SleepOption: Hashable, Sendable {
    case minutes(Int)
    case endOfChapter

    /// Spec §2.4.5 chips.
    public static let all: [SleepOption] = [.minutes(10), .minutes(20), .minutes(30), .minutes(45), .minutes(60), .endOfChapter]

    public var chipLabel: String {
        switch self {
        case .minutes(let m): return "\(m) min"
        case .endOfChapter: return "End of chapter"
        }
    }
}

/// Spec §2.4.5: pauses playback when the time is up or the chapter ends; ends early if the document does.
/// Driven by the app's 10 Hz ticker; the clock is injected so tests do not wait.
@MainActor
@Observable
public final class SleepTimer {
    public private(set) var active: SleepOption?
    public private(set) var remainingSeconds: TimeInterval?

    private let player: PlayerModel
    private let clock: @Sendable () -> Date
    private var deadline: Date?
    private var chapterAtStart: Int?

    public init(player: PlayerModel, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.player = player
        self.clock = clock
    }

    public var caption: String? {
        switch active {
        case .minutes:
            guard let remainingSeconds else { return nil }
            return "Ends in \(DurationFormatter.clock(remainingSeconds))"
        case .endOfChapter:
            guard let c = chapterAtStart else { return nil }
            return "Until the end of \(player.chapters.indices.contains(c) ? player.chapters[c].title : "this chapter")"
        case nil: return nil
        }
    }

    public func start(_ option: SleepOption) {
        active = option
        switch option {
        case .minutes(let m):
            deadline = clock().addingTimeInterval(TimeInterval(m * 60))
            remainingSeconds = TimeInterval(m * 60)
            chapterAtStart = nil
        case .endOfChapter:
            deadline = nil
            remainingSeconds = nil
            chapterAtStart = player.chapterIndex
        }
    }

    public func cancel() {
        active = nil
        deadline = nil
        remainingSeconds = nil
        chapterAtStart = nil
    }

    public func tick() {
        guard let active else { return }
        if player.state == .finished { cancel(); return }
        switch active {
        case .minutes:
            guard let deadline else { return }
            let left = deadline.timeIntervalSince(clock())
            if left <= 0 { fire() } else { remainingSeconds = left }
        case .endOfChapter:
            if let c = chapterAtStart, let now = player.chapterIndex, now != c { fire() }
        }
    }

    private func fire() {
        if player.isPlaying { player.coordinator.pause() }
        cancel()
    }
}
```

```swift
// Sources/T2SApp/Playback/QueueContinuation.swift
import Foundation
import Observation

/// "Autoplay next" (spec §2.4.5 Playback): when the loaded document finishes, load and play the
/// next queued document after it. Call from the ticker or on a state change.
@MainActor
@Observable
public final class QueueContinuation {
    private let player: PlayerModel
    private let library: LibraryModel
    private let preferences: ReaderPreferences

    public init(player: PlayerModel, library: LibraryModel, preferences: ReaderPreferences) {
        self.player = player
        self.library = library
        self.preferences = preferences
    }

    /// True when it advanced.
    public func advanceIfFinished() async -> Bool {
        guard preferences.autoplayNext, player.state == .finished, let current = player.current else { return false }
        await library.refresh()
        let queue = library.queue
        guard let i = queue.firstIndex(where: { $0.id == current.id }), i + 1 < queue.count else { return false }
        await player.load(queue[i + 1], play: true)
        return player.current?.id == queue[i + 1].id
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "SpeedPickerModelTests|SleepTimerTests|QueueContinuationTests"`
Expected: 5 tests passed. `QueueContinuation` refreshes the library first because finishing a document does not remove it from the Queue by itself (marking finished is a user action, spec §2.4.5); the next item is simply the next row.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp/Playback Tests/T2SAppTests
git commit -m "T2SApp: speed picker rows, sleep timer, autoplay-next continuation"
```

---
### Task 4: Readium hosting — publication cache, EPUB and PDF reader views (app target)

**Files:**
- Create: `App/T2SReader/Reader/PublicationCache.swift`, `App/T2SReader/Reader/ReaderScripts.swift`, `App/T2SReader/Reader/EPUBReaderView.swift`, `App/T2SReader/Reader/PDFReaderView.swift`, `App/T2SReader/Reader/ReaderError.swift`

**Interfaces:**
- Consumes: `ReaderModel`, `SourceHit`, `ReaderPreferences`, `HighlightRange`, `LocatorMapping.locator(for:in:)`, `LocatorMapping.position(for:)`, `Tokens`, `LibraryPaths.sourceURL(_:type:)`; Readium as listed in the verified facts.
- Produces: `@MainActor final class PublicationCache { init(); httpServer; func publication(for id: UUID, at url: URL) async throws -> Publication; func release(_ id: UUID) }`; `enum ReaderError: Error { cannotOpen(String) }`; `enum ReaderScripts { static let hitTest: String; static func scrollIntoMiddle(selector: String) -> String }`; `struct EPUBReaderView: UIViewControllerRepresentable` and `struct PDFReaderView: UIViewControllerRepresentable`, both taking `(publication:, reader: ReaderModel, preferences: ReaderPreferences, timeline: Timeline, onTap: (SourceHit?) -> Void)`.

Readium's source for exact initializer labels is checked out at `Packages/T2SReadium/.build/checkouts/swift-toolkit/Sources` after `scripts/check-licenses.sh` has run (or under `.build/DerivedData-App/SourcePackages/checkouts/swift-toolkit` after `scripts/build-app.sh`). Three spots below say "check": `CSSFontFace`'s initializer (`Navigator/EPUB/CSS/HTMLFontFamilyDeclaration.swift`), Readium's `Color` raw value (`Navigator/Preferences/Types.swift`, `public struct Color: RawRepresentable`), and the highlight decoration template's corner radius (`Navigator/EPUB/HTMLDecorationTemplate.swift`). Use what the source says; do not guess.

- [ ] **Step 1: Cache, error, scripts**

```swift
// App/T2SReader/Reader/ReaderError.swift
enum ReaderError: Error, Equatable {
    case cannotOpen(String)
}
```

```swift
// App/T2SReader/Reader/PublicationCache.swift
import Foundation
import ReadiumAdapterGCDWebServer
import ReadiumShared
import ReadiumStreamer

/// Opens a Readium publication once per document and serves it to the navigator through one
/// shared HTTP server. Readium types stay inside the reader files (spec §3.7.2).
@MainActor
final class PublicationCache {
    let httpServer: GCDHTTPServer
    private let httpClient = DefaultHTTPClient()
    private let assetRetriever: AssetRetriever
    private let opener: PublicationOpener
    private var open: [UUID: Publication] = [:]

    init() {
        assetRetriever = AssetRetriever(httpClient: httpClient)
        httpServer = GCDHTTPServer(assetRetriever: assetRetriever)
        opener = PublicationOpener(parser: DefaultPublicationParser(
            httpClient: httpClient, assetRetriever: assetRetriever, pdfFactory: DefaultPDFDocumentFactory()))
    }

    func publication(for id: UUID, at url: URL) async throws -> Publication {
        if let cached = open[id] { return cached }
        guard let fileURL = FileURL(url: url) else { throw ReaderError.cannotOpen("not a file URL") }
        let asset: Asset
        switch await assetRetriever.retrieve(url: fileURL) {
        case .success(let a): asset = a
        case .failure(let error): throw ReaderError.cannotOpen("\(error)")
        }
        switch await opener.open(asset: asset, allowUserInteraction: false) {
        case .success(let publication):
            open[id] = publication
            return publication
        case .failure(let error):
            throw ReaderError.cannotOpen("\(error)")
        }
    }

    func release(_ id: UUID) { open[id] = nil }
}
```

```swift
// App/T2SReader/Reader/ReaderScripts.swift
/// The two scripts the EPUB reader runs through the navigator's `evaluateJavaScript`.
enum ReaderScripts {
    /// Reports the block under a viewport point: its text and the caret offset inside it
    /// (both UTF-16, as JavaScript counts), or null when the point is not on text.
    static func hitTest(x: Double, y: Double) -> String {
        """
        (function () {
          var range = document.caretRangeFromPoint(\(x), \(y));
          if (!range) { return null; }
          var node = range.startContainer;
          var blocks = ['P','H1','H2','H3','H4','H5','H6','LI','BLOCKQUOTE','DIV','SECTION','TD','DD','DT','PRE','FIGCAPTION','ARTICLE'];
          var block = node.nodeType === 1 ? node : node.parentElement;
          while (block && blocks.indexOf(block.tagName) < 0) { block = block.parentElement; }
          if (!block) { return null; }
          var offset = 0, found = false;
          var walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT, null);
          while (walker.nextNode()) {
            var t = walker.currentNode;
            if (t === node) { offset += range.startOffset; found = true; break; }
            offset += t.textContent.length;
          }
          if (!found && node.nodeType === 1) { offset = 0; }
          return { text: block.textContent, offset: offset };
        })();
        """
    }

    /// Scrolls the block matching `selector` so it sits in the middle third of the viewport when it
    /// is not already there (spec §2.4.5 auto-scroll). Returns true when it scrolled.
    static func scrollIntoMiddle(selector: String) -> String {
        let escaped = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return """
        (function () {
          var el = document.querySelector('\(escaped)');
          if (!el) { return false; }
          var r = el.getBoundingClientRect();
          var h = window.innerHeight;
          var mid = (r.top + r.bottom) / 2;
          if (mid >= h / 3 && mid <= 2 * h / 3 && r.top >= 0 && r.bottom <= h) { return false; }
          el.scrollIntoView({ block: 'center', behavior: 'smooth' });
          return true;
        })();
        """
    }
}
```

- [ ] **Step 2: The EPUB reader view**

```swift
// App/T2SReader/Reader/EPUBReaderView.swift
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import T2SApp
import T2SCore
import T2SReadium
import UIKit

/// Hosts Readium's EPUB navigator in scroll mode with Inter, decorates the active word with
/// `accentSoft`, auto-scrolls while following, and reports taps as `SourceHit`s.
struct EPUBReaderView: UIViewControllerRepresentable {
    let publication: Publication
    let reader: ReaderModel
    let preferences: ReaderPreferences
    let timeline: Timeline
    let httpServer: GCDHTTPServer
    let onTap: (SourceHit?) -> Void

    static let decorationGroup = "t2s"

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        let initial = reader.activeHighlight.flatMap { LocatorMapping.locator(for: $0, in: timeline) }
        let config = EPUBNavigatorViewController.Configuration(
            preferences: Self.preferences(from: preferences, colorScheme: context.environment.colorScheme),
            contentInset: [.compact: (top: Spacing.margin, bottom: 120), .regular: (top: Spacing.margin, bottom: 120)],
            fontFamilyDeclarations: [Self.interDeclaration()]
        )
        // If the navigator initializer throws (a restricted publication), the page shows ReaderError instead; see ReaderPage.
        let navigator = try! EPUBNavigatorViewController(publication: publication, initialLocation: initial, config: config, httpServer: httpServer)
        navigator.delegate = context.coordinator
        context.coordinator.navigator = navigator
        return navigator
    }

    func updateUIViewController(_ navigator: EPUBNavigatorViewController, context: Context) {
        let coordinator = context.coordinator
        // Appearance
        let prefs = Self.preferences(from: preferences, colorScheme: context.environment.colorScheme)
        if prefs != coordinator.lastPreferences {
            coordinator.lastPreferences = prefs
            navigator.submitPreferences(prefs)
        }
        // Active word decoration
        let highlight = reader.activeHighlight
        if highlight != coordinator.lastHighlight {
            coordinator.lastHighlight = highlight
            var decorations: [Decoration] = []
            if let highlight, let locator = LocatorMapping.locator(for: highlight, in: timeline) {
                decorations.append(Decoration(id: "active", locator: locator, style: .highlight(tint: UIColor(Tokens.accentSoft), isActive: false)))
            }
            navigator.apply(decorations: decorations, in: Self.decorationGroup)
            if reader.isFollowing, let selector = highlight?.position.cssSelector {
                coordinator.scrollToBlock(selector)
            }
        } else if reader.isFollowing, !coordinator.wasFollowing, let selector = highlight?.position.cssSelector {
            coordinator.scrollToBlock(selector)                 // "Back to current" tapped
        }
        coordinator.wasFollowing = reader.isFollowing
    }

    func makeCoordinator() -> Coordinator { Coordinator(reader: reader, timeline: timeline, onTap: onTap) }

    /// Reader body: Inter 18 × scale, line height 1.5 by default (spec §2.4.1); theme from preferences,
    /// colors from the tokens (check `Color(rawValue:)` in Readium's Types.swift for the hex form).
    static func preferences(from p: ReaderPreferences, colorScheme: ColorScheme) -> EPUBPreferences {
        let dark = p.theme == .dark || (p.theme == .system && colorScheme == .dark)
        var prefs = EPUBPreferences()
        prefs.fontFamily = "Inter"
        prefs.fontSize = p.textScale
        prefs.lineHeight = p.lineHeight
        prefs.scroll = true
        prefs.theme = dark ? .dark : .light
        prefs.backgroundColor = ReadiumNavigator.Color(rawValue: dark ? 0x101010 : 0xF8F8F7)
        prefs.textColor = ReadiumNavigator.Color(rawValue: dark ? 0xF2F2F2 : 0x111111)
        return prefs
    }

    /// The bundled Inter faces, served to the web view (check `CSSFontFace`'s initializer labels).
    static func interDeclaration() -> AnyHTMLFontFamilyDeclaration {
        func face(_ name: String, weight: CSSFontWeight) -> CSSFontFace? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf"), let file = FileURL(url: url) else { return nil }
            return CSSFontFace(fontFamily: "Inter", style: .normal, weight: weight).addingSource(file: file)
        }
        let faces = [face("Inter-Regular", weight: .standard(.normal)), face("Inter-Medium", weight: .standard(.medium)),
                     face("Inter-SemiBold", weight: .standard(.semiBold))].compactMap { $0 }
        return CSSFontFamilyDeclaration(fontFamily: "Inter", alternates: [.sansSerif], fontFaces: faces).eraseToAnyHTMLFontFamilyDeclaration()
    }

    @MainActor
    final class Coordinator: NSObject, EPUBNavigatorDelegate {
        let reader: ReaderModel
        let timeline: Timeline
        let onTap: (SourceHit?) -> Void
        weak var navigator: EPUBNavigatorViewController?
        var lastPreferences: EPUBPreferences?
        var lastHighlight: HighlightRange?
        var wasFollowing = true
        private var programmaticScrollUntil = Date.distantPast

        init(reader: ReaderModel, timeline: Timeline, onTap: @escaping (SourceHit?) -> Void) {
            self.reader = reader
            self.timeline = timeline
            self.onTap = onTap
        }

        func scrollToBlock(_ selector: String) {
            guard let navigator else { return }
            programmaticScrollUntil = Date().addingTimeInterval(1.0)
            Task { _ = await navigator.evaluateJavaScript(ReaderScripts.scrollIntoMiddle(selector: selector)) }
        }

        // A location change we did not cause is the user scrolling: suspend following (spec §2.4.5).
        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            if Date() > programmaticScrollUntil, reader.isFollowing { reader.suspendFollowing() }
        }

        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            guard let epub = self.navigator, let href = epub.currentLocation?.href.string else { onTap(nil); return }
            Task {
                let result = await epub.evaluateJavaScript(ReaderScripts.hitTest(x: point.x, y: point.y))
                guard case .success(let value) = result, let dict = value as? [String: Any],
                      let text = dict["text"] as? String, let offset = dict["offset"] as? Int else { onTap(nil); return }
                onTap(SourceHit(resourceHref: ReadiumDocumentReader.resourceKey(href), blockText: text, offsetInBlock: offset))
            }
        }

        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}
        func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {}
    }
}
```

`ReadiumDocumentReader.resourceKey` must be `public` for this (it is internal today): make it `public static func resourceKey(_:)` in `Packages/T2SReadium/Sources/T2SReadium/ReadiumDocumentReader.swift` as part of this task (one-word change; run `scripts/test-readium.sh` once). `EPUBNavigatorDelegate` may require more members than shown (it inherits `SelectableNavigatorDelegate` and `ViewportObservingNavigatorDelegate`); add empty implementations for whatever the compiler asks, nothing more.

- [ ] **Step 3: The PDF reader view**

```swift
// App/T2SReader/Reader/PDFReaderView.swift
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import T2SApp
import T2SCore
import T2SLibrary
import UIKit

/// PDF is audio-first with page-level sync (spec §6.1): the navigator follows the active
/// utterance's page; a tap reports the visible page.
struct PDFReaderView: UIViewControllerRepresentable {
    let publication: Publication
    let reader: ReaderModel
    let timeline: Timeline
    let onTap: (SourceHit?) -> Void

    func makeUIViewController(context: Context) -> PDFNavigatorViewController {
        let navigator = try! PDFNavigatorViewController(publication: publication, initialLocation: nil, delegate: context.coordinator)
        context.coordinator.navigator = navigator
        return navigator
    }

    func updateUIViewController(_ navigator: PDFNavigatorViewController, context: Context) {
        let page = reader.activeHighlight.map { Self.pageIndex(for: $0.position.progression, in: timeline) }
        if reader.isFollowing, let page, page != context.coordinator.lastPage, let link = publication.readingOrder.first {
            context.coordinator.lastPage = page
            let count = Self.pageCount(in: timeline)
            let locator = Locator(href: link.url(), mediaType: .pdf,
                                  locations: Locator.Locations(progression: Double(page) / Double(max(1, count)), position: page + 1))
            Task { _ = await navigator.go(to: locator, options: NavigatorGoOptions(animated: true)) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    static func pageCount(in timeline: Timeline) -> Int {
        var progressions: Set<Double> = []
        for c in timeline.chapters { for u in c.utterances { progressions.insert(u.position.progression) } }
        let sorted = progressions.sorted()
        guard sorted.count > 1 else { return 1 }
        let step = zip(sorted, sorted.dropFirst()).map { $1 - $0 }.min() ?? 1
        return step > 0 ? Int((1 / step).rounded()) : 1
    }

    static func pageIndex(for progression: Double, in timeline: Timeline) -> Int {
        Int((progression * Double(pageCount(in: timeline))).rounded())
    }

    @MainActor
    final class Coordinator: NSObject, PDFNavigatorDelegate {
        let onTap: (SourceHit?) -> Void
        weak var navigator: PDFNavigatorViewController?
        var lastPage: Int?

        init(onTap: @escaping (SourceHit?) -> Void) { self.onTap = onTap }

        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            guard let position = self.navigator?.currentLocation?.locations.position else { onTap(nil); return }
            onTap(SourceHit(resourceHref: PDFDocumentReader.resourceHref, blockText: "", offsetInBlock: 0, pageIndex: position - 1))
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {}
        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}
    }
}
```

- [ ] **Step 4: Build and commit**

Run: `scripts/build-app.sh` and `scripts/test-readium.sh` (for the `resourceKey` access change).
Expected: `** BUILD SUCCEEDED **`; 12 Readium tests pass. Delegate conformance gaps and the three "check" spots are the expected compile-time adjustments; report each with the diagnostic.

```bash
git add App/T2SReader/Reader Packages/T2SReadium
git commit -m "App: Readium hosting — publication cache, EPUB reader view with decorations and auto-scroll, PDF page sync"
```

---

### Task 5: Reader page, appearance sheet, and routing (app target)

**Files:**
- Create: `App/T2SReader/Reader/ReaderPage.swift`, `App/T2SReader/Reader/ReaderControls.swift`, `App/T2SReader/Preferences/AppearanceSheet.swift`
- Modify: `App/T2SReader/AppEnvironment.swift` (add `publications: PublicationCache`, `preferences: ReaderPreferences`, `readerModel: ReaderModel`), `App/T2SReader/Root/RootPager.swift` (owns `readerDocument` and the full-screen cover), `App/T2SReader/Queue/QueuePage.swift` and `Queue/QueueRow.swift` (title tap → Reader), `App/T2SReader/Collection/BookSheet.swift` (chapter tap → Reader), `App/T2SReader/Player/PlayerSheet.swift` (`Read along →` row), `App/T2SReader/Import/AddSheet.swift` call sites (imported → Reader)

**Interfaces:**
- Consumes: Task 4 views, `ReaderModel`, `ReaderPreferences`, `PlayerModel`, `TickScrubber`, `ChapterList`, `Pill`, `Tokens`, `Spacing`, `LibraryPaths.sourceURL`.
- Produces: `ReaderPage(summary:)`, `ReaderControls`, `AppearanceSheet`; a single `openReader(_ summary:)` closure in the SwiftUI environment (`ReaderRoute` environment value) that every entry point calls.

Spec §2.4.5 Reader page: back chevron top-left, chapter title center (tap → chapter list), overflow right (bookmark, appearance). Body: navigator at 24pt margins on `ground`. Bottom bar pinned over a `ground` fade: tick scrubber, then back 15 · play · forward 30 · speed. During underrun the play glyph becomes a ring and a caption reads `catching up…`. A manual scroll shows `Back to current`. Tap a sentence → seek. Entering the Reader starts playback of that document if it is not already the loaded one (spec rev 7 import outcome; a Queue row's title tap behaves the same).

- [ ] **Step 1: Environment and route**

In `AppEnvironment` add `let publications = PublicationCache()`, `let preferences: ReaderPreferences`, and `let readerModel: ReaderModel`; initialize `preferences = ReaderPreferences()` and `readerModel = ReaderModel(player: player)` in `init`. Add to `Root/RootPager.swift`:

```swift
/// Every entry point opens the Reader through this closure (spec §2.4.5 lists three of them).
struct ReaderRoute {
    var open: (DocumentSummary) -> Void
}

private struct ReaderRouteKey: EnvironmentKey {
    static let defaultValue = ReaderRoute(open: { _ in })
}

extension EnvironmentValues {
    var readerRoute: ReaderRoute {
        get { self[ReaderRouteKey.self] }
        set { self[ReaderRouteKey.self] = newValue }
    }
}
```

and in `RootPager`: `@State private var readerDocument: DocumentSummary?`, `.environment(\.readerRoute, ReaderRoute { readerDocument = $0 })` on the pager, and `.fullScreenCover(item: $readerDocument) { ReaderPage(summary: $0) }`. Replace the interim "open the player sheet" behaviour: `QueueRow.onOpen` → `readerRoute.open(summary)`; `BookSheet` chapter tap → load + seek then `readerRoute.open(live)` (dismiss the sheet first); `AddSheet` `onImported` closures → `readerRoute.open(imported)`; `PlayerSheet` gains a `Read along →` row (Row title style, chevron) that dismisses the sheet and calls the route. `MiniPlayer`'s expand still opens the player sheet.

- [ ] **Step 2: Reader page, controls, appearance**

```swift
// App/T2SReader/Reader/ReaderControls.swift
import SwiftUI
import T2SApp

/// back 15 · play · forward 30 · speed (spec §2.4.5 Reader bottom bar). Skip amounts come from preferences.
struct ReaderControls: View {
    @Environment(AppEnvironment.self) private var env
    var onSpeed: () -> Void

    var body: some View {
        let player = env.player
        let prefs = env.preferences
        HStack(spacing: 0) {
            Spacer()
            control("gobackward.\(prefs.skipBackSeconds)", "Back \(prefs.skipBackSeconds) seconds") { Task { await player.skip(by: -Double(prefs.skipBackSeconds)) } }
            Button { Task { await player.togglePlay() } } label: {
                Group {
                    if player.isCatchingUp { ProgressView().progressViewStyle(.circular).tint(Tokens.ink) }
                    else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 26, weight: .semibold)) }
                }
                .frame(width: 56, height: 56).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            control("goforward.\(prefs.skipForwardSeconds)", "Forward \(prefs.skipForwardSeconds) seconds") { Task { await player.skip(by: Double(prefs.skipForwardSeconds)) } }
            Spacer()
            Button(action: onSpeed) {
                Text(SpeedPickerModel.label(for: player.coordinator.rate)).typeRole(.mono).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed")
        }
        .foregroundStyle(Tokens.ink)
        .padding(.horizontal, 8)
        .frame(height: 56)
    }

    private func control(_ glyph: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
```

SF Symbols exist for `gobackward.10/15/30/45/60/75/90` and `goforward.10/15/30/45/60/75/90`, which covers the preference options.

```swift
// App/T2SReader/Preferences/AppearanceSheet.swift
import SwiftUI
import T2SApp

/// Reading appearance (spec §2.4.5 Preferences → Reading; also the Reader's overflow "appearance").
struct AppearanceSheet: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var prefs = env.preferences
        VStack(alignment: .leading, spacing: Spacing.section) {
            Text("Appearance").typeRole(.sectionHeader).foregroundStyle(Tokens.ink).padding(.top, Spacing.section)
            VStack(alignment: .leading, spacing: 12) {
                Text("Text size").typeRole(.meta).foregroundStyle(Tokens.ink2)
                Slider(value: $prefs.textScale, in: ReaderPreferences.textScaleRange, step: 0.1).tint(Tokens.ink)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Line height").typeRole(.meta).foregroundStyle(Tokens.ink2)
                Slider(value: $prefs.lineHeight, in: ReaderPreferences.lineHeightRange, step: 0.1).tint(Tokens.ink)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme").typeRole(.meta).foregroundStyle(Tokens.ink2)
                HStack(spacing: 8) {
                    ForEach(ReaderTheme.allCases, id: \.self) { theme in
                        Pill(label: theme.rawValue.capitalized, style: prefs.theme == theme ? .selected : .soft) { prefs.theme = theme }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .background(Tokens.raised)
        .presentationDetents([.medium])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}
```

```swift
// App/T2SReader/Reader/ReaderPage.swift
import ReadiumShared
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

struct ReaderPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var summary: DocumentSummary

    @State private var publication: Publication?
    @State private var timeline: Timeline?
    @State private var error: String?
    @State private var chromeVisible = true
    @State private var showChapters = false
    @State private var showAppearance = false
    @State private var showSpeed = false
    @State private var bookmarkSaved = false

    var body: some View {
        let reader = env.readerModel
        ZStack {
            Tokens.ground.ignoresSafeArea()
            if let publication, let timeline {
                Group {
                    if summary.document.sourceType == .pdf {
                        PDFReaderView(publication: publication, reader: reader, timeline: timeline, onTap: handleTap)
                    } else {
                        EPUBReaderView(publication: publication, reader: reader, preferences: env.preferences, timeline: timeline,
                                       httpServer: env.publications.httpServer, onTap: handleTap)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            } else if let error {
                Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive).padding(Spacing.margin)
            } else {
                ProgressView().tint(Tokens.ink)
            }

            VStack(spacing: 0) {
                topBar.opacity(chromeVisible ? 1 : 0)
                Spacer()
                if !reader.isFollowing {
                    Pill(label: "Back to current", glyph: "text.line.first.and.arrowtriangle.forward", style: .selected) { reader.resumeFollowing() }
                        .padding(.bottom, 12)
                }
                bottomBar.opacity(chromeVisible ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        }
        .task(id: summary.id) { await open() }
        .onDisappear { Task { await env.player.persistRenderedChapters() } }
        .sheet(isPresented: $showChapters) { ChapterList() }
        .sheet(isPresented: $showAppearance) { AppearanceSheet() }
        .sheet(isPresented: $showSpeed) { SpeedPicker() }
        .onChange(of: env.player.coordinator.playhead) { _, _ in bookmarkSaved = false }
    }

    private var topBar: some View {
        HStack {
            icon("chevron.left", "Back") { dismiss() }
            Spacer()
            Button { showChapters = true } label: {
                Text(env.readerModel.chapterTitle).typeRole(.rowTitle).lineLimit(1).foregroundStyle(Tokens.ink)
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button { Task { bookmarkSaved = await env.player.addBookmark() } } label: {
                    Label(bookmarkSaved ? "Bookmarked" : "Bookmark", systemImage: bookmarkSaved ? "bookmark.fill" : "bookmark")
                }
                Button { showAppearance = true } label: { Label("Appearance", systemImage: "textformat.size") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.ink)
                    .frame(width: 36, height: 36).background(Tokens.surface, in: Circle())
            }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, Spacing.grid)
        .background(Tokens.ground.opacity(0.94))
    }

    private var bottomBar: some View {
        let player = env.player
        return VStack(spacing: 10) {
            TickScrubber(model: player.scrubber) { fraction in Task { await player.seek(fraction: fraction) } }
            if player.isCatchingUp { Text("catching up…").typeRole(.meta).foregroundStyle(Tokens.ink2) }
            ReaderControls { showSpeed = true }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, 16)
        .padding(.bottom, Spacing.grid)
        .background(
            LinearGradient(colors: [Tokens.ground.opacity(0), Tokens.ground, Tokens.ground], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func icon(_ glyph: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.ink)
                .frame(width: 36, height: 36).background(Tokens.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func handleTap(_ hit: SourceHit?) {
        Task {
            if let hit, await env.readerModel.seek(to: hit) { return }
            withAnimation { chromeVisible.toggle() }
        }
    }

    /// Loads (and starts) the document if it is not the loaded one, then opens its publication.
    private func open() async {
        if env.player.current?.id != summary.id { await env.player.load(summary, play: true) }
        timeline = env.player.coordinator.timeline
        do {
            publication = try await env.publications.publication(for: summary.id, at: env.paths.sourceURL(summary.id, type: summary.document.sourceType))
        } catch {
            self.error = "This document can't be displayed: \(error)"
        }
    }
}
```

`SpeedPicker` arrives in Task 6; for this task create `App/T2SReader/Player/SpeedPicker.swift` containing a placeholder `struct SpeedPicker: View { var body: some View { Text("Speed").typeRole(.rowTitle).padding(Spacing.margin) } }`.

- [ ] **Step 3: Build, smoke-run, commit**

Run: `scripts/build-app.sh`
Expected: `** BUILD SUCCEEDED **`. Then on the simulator: import an article, tap its title in the Queue → the Reader opens, the voice starts, the active word is highlighted and the page follows; scroll by hand → `Back to current` appears; tap a sentence → playback jumps there. Record what you saw (this is the plan's manual check; `bookmarkSaved` and the appearance sheet are quick to try too).

```bash
git add App
git commit -m "App: Reader page with decorated read-along, auto-scroll, tap-to-seek, appearance sheet, and routing"
```

---
### Task 6: Speed picker, sleep timer, default rate and voice on load, ticker wiring (app target + `PlayerModel.defaultVoiceID`)

**Files:**
- Modify: `Sources/T2SApp/Player/PlayerModel.swift` (add `public var defaultVoiceID: String?` applied in `load` when the document has no override), `Tests/T2SAppTests/PlayerModelTests.swift` (one test)
- Replace: `App/T2SReader/Player/SpeedPicker.swift` (placeholder from Task 5)
- Create: `App/T2SReader/Player/SleepTimerSheet.swift`
- Modify: `App/T2SReader/AppEnvironment.swift` (add `sleepTimer`, `continuation`; apply `preferences.defaultRate` and `defaultVoiceID`; read the prepare budget into `CoordinatorConfiguration`), `App/T2SReader/System/PlaybackTicker.swift` (tick the sleep timer; advance the queue when finished), `App/T2SReader/Player/ControlPill.swift` (speed opens the picker), `App/T2SReader/Player/PlayerSheet.swift` (sleep-timer button enabled; `Read along →` from Task 5 stays), `App/T2SReader/Queue/QueueRow.swift` (context menu "Sleep timer"), `App/T2SReader/Root/RootPager.swift` (apply rate/voice preference changes)

**Interfaces:**
- Consumes: `SpeedPickerModel`, `SleepTimer`, `SleepOption`, `QueueContinuation`, `ReaderPreferences`, `PlayerModel`.
- Produces: `SpeedPicker` sheet, `SleepTimerSheet`, `AppEnvironment.sleepTimer`, `.continuation`; `PlayerModel.defaultVoiceID`.

- [ ] **Step 1: Default voice on load (model + test)**

Append to `PlayerModelTests`:

```swift
    @Test func defaultVoiceAppliesOnlyWithoutAnOverride() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let player = try makePlayer(f)
        player.defaultVoiceID = "com.apple.voice.compact.en-US.Samantha"
        let summary = try #require(try await f.store.summary(id: id))
        await player.load(summary, play: false)
        #expect(player.coordinator.document?.voiceID == "com.apple.voice.compact.en-US.Samantha")
        var overridden = summary.document
        overridden.voiceID = "custom"
        try await f.store.update(overridden)
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        #expect(player.coordinator.document?.voiceID == "custom")
        #expect(try await f.store.document(id: id)?.voiceID == "custom")        // the default is never persisted
    }
```

In `PlayerModel` add `/// The Preferences default voice; applied at load to documents without a per-document override (spec §2.2). Never persisted.` `public var defaultVoiceID: String?` and, in `load`, replace `coordinator.load(summary.document, timeline: timeline)` with:

```swift
            var document = summary.document
            if document.voiceID == nil { document.voiceID = defaultVoiceID }
            coordinator.load(document, timeline: timeline)
```

Run: `swift test --filter PlayerModelTests` — expected: all pass (the earlier suite plus this one).

- [ ] **Step 2: Sheets**

```swift
// App/T2SReader/Player/SpeedPicker.swift
import SwiftUI
import T2SApp

/// Spec §2.4.5: vertical list 0.5x–4.0x in 0.1x steps; unsustainable rates in `ink3` with a footnote.
struct SpeedPicker: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let model = SpeedPickerModel.make(current: env.player.coordinator.rate, maxRate: env.player.coordinator.availableRates.max() ?? 4.0)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Speed").typeRole(.sectionHeader).foregroundStyle(Tokens.ink).padding(.top, Spacing.section).padding(.bottom, 20)
                ForEach(model.rows) { row in
                    Button {
                        env.player.setRate(row.rate)
                        env.preferences.defaultRate = row.rate
                        dismiss()
                    } label: {
                        HStack {
                            Text(row.label).typeRole(.rowTitle).foregroundStyle(row.isAvailable ? Tokens.ink : Tokens.ink3)
                            Spacer()
                            if row.isCurrent { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.ink) }
                        }
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!row.isAvailable)
                }
                if let footnote = model.footnote {
                    Text(footnote).typeRole(.meta).foregroundStyle(Tokens.ink2).padding(.top, 16)
                }
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}
```

```swift
// App/T2SReader/Player/SleepTimerSheet.swift
import SwiftUI
import T2SApp

/// Spec §2.4.5: sleep glyph, chips, selected chip solid `ink`, accent "Start", grey caption.
struct SleepTimerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var selected: SleepOption = .minutes(30)

    var body: some View {
        let timer = env.sleepTimer
        VStack(alignment: .leading, spacing: Spacing.section) {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz").font(.system(size: 17, weight: .semibold))
                Text("Sleep timer").typeRole(.sectionHeader)
            }
            .foregroundStyle(Tokens.ink)
            .padding(.top, Spacing.section)
            if let caption = timer.caption {
                Text(caption).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                Pill(label: "Cancel timer", style: .soft) { timer.cancel(); dismiss() }
            } else {
                FlowChips(options: SleepOption.all, selected: $selected)
                Pill(label: "Start", glyph: "play.fill", style: .accent) { timer.start(selected); dismiss() }
                Text("The timer ends early if the document does.").typeRole(.meta).foregroundStyle(Tokens.ink2)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .background(Tokens.raised)
        .presentationDetents([.medium])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}

/// Wrapping row of chips.
private struct FlowChips: View {
    var options: [SleepOption]
    @Binding var selected: SleepOption

    var body: some View {
        let rows = [Array(options.prefix(3)), Array(options.dropFirst(3))]
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r], id: \.self) { option in
                        Pill(label: option.chipLabel, style: option == selected ? .selected : .soft) { selected = option }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Wiring**

`AppEnvironment`: add `let sleepTimer: SleepTimer` and `let continuation: QueueContinuation`; in `init`, after `player` and `libraryModel`: `sleepTimer = SleepTimer(player: player)`, `continuation = QueueContinuation(player: player, library: libraryModel, preferences: preferences)`, then `player.defaultVoiceID = preferences.defaultVoiceID` and `coordinator.setRate(preferences.defaultRate)`. In `live()`, read the budget: `let budget = UserDefaults.standard.object(forKey: AppPaths.prepareBudgetKey) as? Double ?? 3 * 3600` and pass `configuration: CoordinatorConfiguration(prepareBudgetSeconds: budget.isFinite ? budget : 365 * 24 * 3600)` to the coordinator ("Everything" is a year of listening).

`PlaybackTicker`: inside the loop, after `player.tick()`, add `sleepTimer.tick()` every iteration (the modifier gains `sleepTimer` and `continuation` parameters, and `RootPager` passes `env.sleepTimer`/`env.continuation`), and `if player.state == .finished { _ = await continuation.advanceIfFinished() }` — guard with a local flag so it fires once per finish (reset when the state leaves `.finished`).

`RootPager`: `.onChange(of: env.preferences.defaultVoiceID) { _, v in env.player.defaultVoiceID = v }` and `.onChange(of: env.preferences.defaultRate) { _, r in env.player.setRate(r) }`.

`ControlPill`: replace the speed `Menu` with a button that calls a new `onSpeed: () -> Void` parameter; `PlayerSheet` presents `SpeedPicker()` from it and enables the sleep-timer button (`moon.zzz.fill` while `env.sleepTimer.active != nil`) presenting `SleepTimerSheet()`. `QueueRow`'s context menu gains `Button { showSleep = true } label: { Label("Sleep timer", systemImage: "moon.zzz") }` with a `.sheet(isPresented: $showSleep) { SleepTimerSheet() }` on the row.

- [ ] **Step 4: Build, test, commit**

Run: `scripts/build-app.sh && swift test`
Expected: build succeeds; the root suite passes with the new PlayerModel test.

```bash
git add Sources/T2SApp/Player/PlayerModel.swift Tests/T2SAppTests/PlayerModelTests.swift App
git commit -m "App: speed picker and sleep timer sheets; default rate and voice from preferences; autoplay next"
```

---

### Task 7: Preferences page — voices, playback, reading, pronunciation, storage (app target + `T2SApp` models)

**Files:**
- Create: `Sources/T2SApp/Preferences/PronunciationModel.swift`, `Sources/T2SApp/Storage/StorageModel.swift`
- Create: `Tests/T2SAppTests/PronunciationModelTests.swift`, `Tests/T2SAppTests/StorageModelTests.swift`
- Create: `App/T2SReader/System/SystemVoiceCatalog.swift`, `App/T2SReader/Preferences/VoiceListPage.swift`, `App/T2SReader/Preferences/PronunciationPage.swift`, `App/T2SReader/Preferences/StoragePage.swift`
- Replace: `App/T2SReader/Preferences/PreferencesPage.swift`
- Modify: `App/T2SReader/AppEnvironment.swift` (add `voices: any VoiceCatalog`, `pronunciation: PronunciationModel`, `storage: StorageModel`), `App/T2SReader/Queue/DetailsSheet.swift` (add a "Reprocess" pill)

**Interfaces:**
- Consumes: `LibraryStore.pronunciations/upsert/deletePronunciation`, `PronunciationEntry`, `Library.evictAudio/reprocess`, `AudioStore.stats/setCapacity`, `AudioStoreStats`, `LibraryModel`, `PlayerModel`, `ReaderPreferences`, `VoiceCatalog`, `AppearanceSheet` (Task 5), `SpeedPickerModel.label`.
- Produces: `@MainActor @Observable public final class PronunciationModel { init(store:); entries; refresh(); save(term:replacement:caseSensitive:id:); delete(id:) }`; `@MainActor @Observable public final class StorageModel { init(library:audioStore:player:libraryModel:defaults:); stats; capacityOptions; setCapacity(_:); rows; preparedSeconds; lastPrepareRun; evict(_:) async; static let lastPrepareRunKey }`; `SystemVoiceCatalog: VoiceCatalog`; the pages.

- [ ] **Step 1: Models with tests**

```swift
// Tests/T2SAppTests/PronunciationModelTests.swift
import Foundation
import Testing
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct PronunciationModelTests {
    @Test func saveListEditDelete() async throws {
        let f = try AppFixtures()
        let model = PronunciationModel(store: f.store)
        await model.refresh()
        #expect(model.entries.isEmpty)
        await model.save(term: "nginx", replacement: "engine x", caseSensitive: true, id: nil)
        await model.save(term: "Kokoro", replacement: "ko-ko-ro", caseSensitive: false, id: nil)
        #expect(model.entries.map(\.term) == ["Kokoro", "nginx"])
        let id = model.entries[0].id
        await model.save(term: "Kokoro", replacement: "koh-koh-roh", caseSensitive: false, id: id)
        #expect(model.entries.first { $0.id == id }?.replacement == "koh-koh-roh")
        await model.save(term: "   ", replacement: "x", caseSensitive: false, id: nil)   // ignored
        #expect(model.entries.count == 2)
        await model.delete(id: id)
        #expect(model.entries.map(\.term) == ["nginx"])
        #expect(model.lastError == nil)
    }
}
```

```swift
// Tests/T2SAppTests/StorageModelTests.swift
import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct StorageModelTests {
    func fresh() -> UserDefaults {
        let suite = "t2s-storage-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func statsRowsAndEviction() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake(), b = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        let library = LibraryModel(library: f.library)
        let defaults = fresh()
        let storage = StorageModel(library: f.library, audioStore: f.audio, player: player, libraryModel: library, defaults: defaults)

        await player.load(try #require(try await f.store.summary(id: a)), play: false)
        await player.coordinator.waitForRenderIdle()
        await player.persistRenderedChapters()
        await storage.refresh()
        #expect(storage.stats.entries == 3 && storage.stats.bytes > 0)
        #expect(storage.rows.map(\.summary.id) == [a, b] || storage.rows.map(\.summary.id) == [b, a])
        #expect(storage.rows.first { $0.summary.id == a }?.renderedFraction == 1)
        #expect(storage.preparedSeconds > 0)
        #expect(storage.lastPrepareRun == nil)

        await storage.setCapacity(1_000_000)
        #expect(storage.stats.capacityBytes == 1_000_000)
        #expect(defaults.integer(forKey: AppPaths.audioCapacityKey) == 1_000_000)

        await storage.evict(a)                                              // the loaded document: evicted, then reloaded paused
        #expect(player.current?.id == a && player.state == .paused)
        #expect(try await f.store.summary(id: a)?.renderedCount == 0)
        #expect(await f.audio.stats().entries == 0)

        defaults.set(Date(timeIntervalSince1970: 1_700_000_000), forKey: StorageModel.lastPrepareRunKey)
        await storage.refresh()
        #expect(storage.lastPrepareRun == Date(timeIntervalSince1970: 1_700_000_000))
    }
}
```

```swift
// Sources/T2SApp/Preferences/PronunciationModel.swift
import Foundation
import Observation
import T2SCore
import T2SStore

/// The pronunciation dictionary (spec §2.2, §4.1 rule 6). Edits apply to documents imported or
/// reprocessed from now on; the Details sheet offers "Reprocess" for existing ones.
@MainActor
@Observable
public final class PronunciationModel {
    public private(set) var entries: [PronunciationEntry] = []
    public private(set) var lastError: String?
    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func refresh() async {
        do { entries = try await store.pronunciations(); lastError = nil } catch { lastError = "\(error)" }
    }

    /// Blank terms are ignored; `id` nil adds, otherwise replaces.
    public func save(term: String, replacement: String, caseSensitive: Bool, id: UUID?) async {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !r.isEmpty else { return }
        do {
            try await store.upsert(PronunciationEntry(id: id ?? UUID(), term: t, replacement: r, caseSensitive: caseSensitive))
            lastError = nil
        } catch { lastError = "\(error)" }
        await refresh()
    }

    public func delete(id: UUID) async {
        do { try await store.deletePronunciation(id: id); lastError = nil } catch { lastError = "\(error)" }
        await refresh()
    }
}
```

```swift
// Sources/T2SApp/Storage/StorageModel.swift
import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

/// Preferences → Storage (spec §2.4.5, §3.4.1): cache size and cap, per-document eviction, the
/// prepared amount across the Queue, and when Prepare last ran.
@MainActor
@Observable
public final class StorageModel {
    public struct Row: Hashable, Sendable, Identifiable {
        public var summary: DocumentSummary
        public var renderedFraction: Double
        public var id: UUID { summary.id }
    }

    public static let lastPrepareRunKey = "prepare.lastRun"
    public static let capacityOptions: [Int] = [512 * 1024 * 1024, 1024 * 1024 * 1024, 2 * 1024 * 1024 * 1024, 4 * 1024 * 1024 * 1024]

    public private(set) var stats = AudioStoreStats(bytes: 0, entries: 0, capacityBytes: 0)
    public private(set) var rows: [Row] = []
    public private(set) var preparedSeconds: TimeInterval = 0
    public private(set) var lastPrepareRun: Date?
    public private(set) var lastError: String?

    private let library: Library
    private let audioStore: any AudioStore
    private let player: PlayerModel
    private let libraryModel: LibraryModel
    private let defaults: UserDefaults

    public init(library: Library, audioStore: any AudioStore, player: PlayerModel, libraryModel: LibraryModel, defaults: UserDefaults = .standard) {
        self.library = library
        self.audioStore = audioStore
        self.player = player
        self.libraryModel = libraryModel
        self.defaults = defaults
    }

    public func refresh() async {
        stats = await audioStore.stats()
        await libraryModel.refresh()
        rows = libraryModel.summaries.map { s in
            Row(summary: s, renderedFraction: s.utteranceCount > 0 ? Double(s.renderedCount) / Double(s.utteranceCount) : 0)
        }
        preparedSeconds = libraryModel.queue.reduce(0) { acc, s in
            acc + (s.utteranceCount > 0 ? s.totalSeconds * Double(s.renderedCount) / Double(s.utteranceCount) : 0)
        }
        lastPrepareRun = defaults.object(forKey: Self.lastPrepareRunKey) as? Date
    }

    public func setCapacity(_ bytes: Int) async {
        defaults.set(bytes, forKey: AppPaths.audioCapacityKey)
        await audioStore.setCapacity(bytes: bytes)
        await refresh()
    }

    /// Plan 3 hand-off: the loaded document is reloaded (paused) after eviction so the player never
    /// writes back audio refs to files that are gone.
    public func evict(_ id: UUID) async {
        let wasCurrent = player.current?.id == id
        do {
            try await library.evictAudio(for: id)
            lastError = nil
        } catch { lastError = "\(error)" }
        if wasCurrent, let summary = try? await library.store.summary(id: id) {
            await player.load(summary, play: false)
        }
        await refresh()
    }
}
```

Run: `swift test --filter "PronunciationModelTests|StorageModelTests"` — expected: 2 tests passed (`waitForRenderIdle` renders the three fake sentences, so 3 store entries).

- [ ] **Step 2: Pages**

```swift
// App/T2SReader/System/SystemVoiceCatalog.swift
import AVFoundation
import T2SApp

/// The device's English system voices (until Plan 5 brings Kokoro's presets), best quality first.
struct SystemVoiceCatalog: VoiceCatalog {
    func voices() -> [VoiceOption] {
        let system = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
            .map { VoiceOption(id: $0.identifier, name: "\($0.name) · \($0.language)", language: $0.language) }
        return [.systemDefault] + system
    }

    /// Speaks a short sample through the system synthesizer (the voice list's preview).
    @MainActor
    static func preview(_ option: VoiceOption, synthesizer: AVSpeechSynthesizer) {
        let utterance = AVSpeechUtterance(string: "This is how I sound reading your book.")
        utterance.voice = AVSpeechSynthesisVoice(identifier: option.id) ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}
```

```swift
// App/T2SReader/Preferences/VoiceListPage.swift
import AVFoundation
import SwiftUI
import T2SApp

/// Preferences → Voice (spec §2.4.5): the default voice, with preview. Also used by the per-document
/// voice change (Task 8) through `selection`/`onSelect`.
struct VoiceListPage: View {
    @Environment(AppEnvironment.self) private var env
    var selection: String?
    var onSelect: (VoiceOption) -> Void
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        let options = env.voices.voices()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(text: "Voice")
                ForEach(options) { option in
                    HStack(spacing: 12) {
                        Button { onSelect(option) } label: {
                            HStack {
                                Text(option.name).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(1)
                                Spacer()
                                if (selection ?? VoiceOption.systemDefault.id) == option.id {
                                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.ink)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { SystemVoiceCatalog.preview(option, synthesizer: synthesizer) } label: {
                            Image(systemName: "play.circle").font(.system(size: 20)).foregroundStyle(Tokens.ink2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Preview")
                    }
                    .frame(height: 44)
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
        .navigationBarBackButtonHidden(false)
    }
}
```

```swift
// App/T2SReader/Preferences/PronunciationPage.swift
import SwiftUI
import T2SApp
import T2SCore

struct PronunciationPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editing: PronunciationEntry?
    @State private var adding = false

    var body: some View {
        let model = env.pronunciation
        List {
            Section {
                PageTitle(text: "Pronunciation", subtitle: "Say names and jargon your way. Applies to documents imported or reprocessed from now on.")
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                Pill(label: "Add word", glyph: "plus", style: .soft) { adding = true }
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                ForEach(model.entries) { entry in
                    Button { editing = entry } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.term).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                            Text("→ \(entry.replacement)\(entry.caseSensitive ? " · case-sensitive" : "")").typeRole(.meta).foregroundStyle(Tokens.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: 20, trailing: Spacing.margin))
                    .swipeActions(edge: .trailing) {
                        Button { Task { await model.delete(id: entry.id) } } label: { Label("Delete", systemImage: "trash") }.tint(Tokens.destructive)
                    }
                }
                Color.clear.frame(height: 120).listRowInsets(EdgeInsets())
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Tokens.ground)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Tokens.ground)
        .task { await model.refresh() }
        .sheet(isPresented: $adding) { PronunciationEditor(entry: nil) }
        .sheet(item: $editing) { PronunciationEditor(entry: $0) }
    }
}

private struct PronunciationEditor: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var entry: PronunciationEntry?
    @State private var term = ""
    @State private var replacement = ""
    @State private var caseSensitive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(entry == nil ? "Add word" : "Edit word").typeRole(.sectionHeader).foregroundStyle(Tokens.ink).padding(.top, Spacing.section)
            TextField("Word or name", text: $term).typeRole(.rowTitle).padding(.horizontal, 14).padding(.vertical, 12).background(Tokens.surface, in: Capsule())
            TextField("Say it as", text: $replacement).typeRole(.rowTitle).padding(.horizontal, 14).padding(.vertical, 12).background(Tokens.surface, in: Capsule())
            Toggle(isOn: $caseSensitive) { Text("Match case").typeRole(.rowTitle).foregroundStyle(Tokens.ink) }.tint(Tokens.ink)
            Pill(label: "Save", style: .accent) {
                Task { await env.pronunciation.save(term: term, replacement: replacement, caseSensitive: caseSensitive, id: entry?.id); dismiss() }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .background(Tokens.raised)
        .presentationDetents([.medium])
        .presentationCornerRadius(Spacing.sheetCorner)
        .onAppear {
            if let entry { term = entry.term; replacement = entry.replacement; caseSensitive = entry.caseSensitive }
        }
    }
}
```

```swift
// App/T2SReader/Preferences/StoragePage.swift
import SwiftUI
import T2SApp

/// Preferences → Storage (spec §2.4.5): prepare-on-charge budget, prepared amount and last run,
/// cache size and cap, per-document eviction.
struct StoragePage: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let storage = env.storage
        @Bindable var prefs = env.preferences
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                PageTitle(text: "Storage")
                section("Prepare on charge") {
                    Text("Render ahead while charging, so listening later costs no battery.").typeRole(.meta).foregroundStyle(Tokens.ink2)
                    HStack(spacing: 8) {
                        ForEach(ReaderPreferences.prepareBudgetOptions, id: \.seconds) { option in
                            Pill(label: option.label, style: prefs.prepareBudgetSeconds == option.seconds ? .selected : .soft) { prefs.prepareBudgetSeconds = option.seconds }
                        }
                    }
                    Text("Prepared: \(DurationFormatter.long(storage.preparedSeconds)) · Last run: \(storage.lastPrepareRun.map { DurationFormatter.age(of: $0) + " ago" } ?? "never")")
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                }
                section("Rendered audio") {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(storage.stats.bytes), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(storage.stats.capacityBytes), countStyle: .file)) · \(storage.stats.entries) clips")
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    HStack(spacing: 8) {
                        ForEach(StorageModel.capacityOptions, id: \.self) { bytes in
                            Pill(label: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file),
                                 style: storage.stats.capacityBytes == bytes ? .selected : .soft) { Task { await storage.setCapacity(bytes) } }
                        }
                    }
                }
                section("Per document") {
                    ForEach(storage.rows) { row in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.summary.document.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(1)
                                ProgressBar(fraction: row.renderedFraction)
                            }
                            Text("\(Int((row.renderedFraction * 100).rounded()))%").typeRole(.mono).foregroundStyle(Tokens.ink2)
                            Pill(label: "Evict", style: .destructiveSoft) { Task { await storage.evict(row.id) } }
                                .disabled(row.renderedFraction == 0)
                        }
                    }
                }
                if let error = storage.lastError { Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive) }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
        .task { await storage.refresh() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
            content()
        }
    }
}
```

```swift
// App/T2SReader/Preferences/PreferencesPage.swift
import SwiftUI
import T2SApp

/// Spec §2.4.5 Preferences: sections as a header plus rows of title, grey subtitle, right-aligned control.
struct PreferencesPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showAppearance = false

    var body: some View {
        @Bindable var prefs = env.preferences
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    PageTitle(text: "Preferences")
                    section("Voice") {
                        NavigationLink {
                            VoiceListPage(selection: prefs.defaultVoiceID) { option in prefs.defaultVoiceID = option.isDefault ? nil : option.id }
                        } label: {
                            row("Default voice", subtitle: env.voices.voices().first { $0.id == (prefs.defaultVoiceID ?? VoiceOption.systemDefault.id) }?.name ?? "System default")
                        }
                    }
                    section("Playback") {
                        row("Skip back", subtitle: "Seconds") {
                            Menu { ForEach(ReaderPreferences.skipBackOptions, id: \.self) { s in Button("\(s) s") { prefs.skipBackSeconds = s } } } label: { valuePill("\(prefs.skipBackSeconds) s") }
                        }
                        row("Skip forward", subtitle: "Seconds") {
                            Menu { ForEach(ReaderPreferences.skipForwardOptions, id: \.self) { s in Button("\(s) s") { prefs.skipForwardSeconds = s } } } label: { valuePill("\(prefs.skipForwardSeconds) s") }
                        }
                        row("Default speed", subtitle: "New documents start here") {
                            Menu { ForEach(SpeedPickerModel.rates.filter { $0 <= 3.0 }, id: \.self) { r in Button(SpeedPickerModel.label(for: r)) { prefs.defaultRate = r } } } label: { valuePill(SpeedPickerModel.label(for: prefs.defaultRate)) }
                        }
                        row("Autoplay next", subtitle: "Continue with the next queued item") {
                            Toggle("", isOn: $prefs.autoplayNext).labelsHidden().tint(Tokens.ink)
                        }
                    }
                    section("Reading") {
                        Button { showAppearance = true } label: { row("Appearance", subtitle: "Text size, line height, theme") }.buttonStyle(.plain)
                    }
                    section("Pronunciation") {
                        NavigationLink { PronunciationPage() } label: { row("Dictionary", subtitle: "\(env.pronunciation.entries.count) words") }
                    }
                    section("Storage") {
                        NavigationLink { StoragePage() } label: { row("Rendered audio and prepare on charge", subtitle: ByteCountFormatter.string(fromByteCount: Int64(env.storage.stats.bytes), countStyle: .file)) }
                    }
                    section("Cloud voices") {
                        row("Bring your own key", subtitle: "Coming soon").opacity(0.5)
                    }
                    section("iCloud sync") {
                        row("Sync positions and bookmarks", subtitle: "Coming later") { Toggle("", isOn: .constant(false)).labelsHidden().disabled(true) }
                    }
                    section("About") {
                        row("Fonts: Inter (SIL OFL) · Reader: Readium (BSD-3) · Extraction: Readability (Apache-2.0)", subtitle: "")
                    }
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, Spacing.margin)
            }
            .background(Tokens.ground)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showAppearance) { AppearanceSheet() }
        .task { await env.pronunciation.refresh(); await env.storage.refresh() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
            content()
        }
    }

    private func row(_ title: String, subtitle: String) -> some View {
        row(title, subtitle: subtitle) { Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Tokens.ink3) }
    }

    private func row<Control: View>(_ title: String, subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                if !subtitle.isEmpty { Text(subtitle).typeRole(.meta).foregroundStyle(Tokens.ink2) }
            }
            Spacer()
            control()
        }
        .contentShape(Rectangle())
    }

    private func valuePill(_ text: String) -> some View {
        Text(text).typeRole(.pill).foregroundStyle(Tokens.ink).padding(.horizontal, 14).padding(.vertical, 9).background(Tokens.surface, in: Capsule())
    }
}
```

`AppEnvironment` gains `let voices: any VoiceCatalog = SystemVoiceCatalog()`, `let pronunciation: PronunciationModel`, `let storage: StorageModel` (constructed in `init` from `store`, `library`, `audioStore`, `player`, `libraryModel`). `DetailsSheet` gains, above "Delete from library", `Pill(label: "Reprocess", glyph: "arrow.clockwise", style: .soft) { Task { _ = try? await env.library.reprocess(summary.id); if env.player.current?.id == summary.id, let s = try? await env.store.summary(id: summary.id) { await env.player.load(s, play: false) }; await env.libraryModel.refresh() } }` with a Meta caption "Re-reads the file with the current pronunciation dictionary. Rendered audio is discarded."

- [ ] **Step 3: Build, test, commit**

Run: `scripts/build-app.sh && swift test`
Expected: build succeeds; the root suite passes with the two new model suites.

```bash
git add Sources/T2SApp Tests/T2SAppTests App
git commit -m "App: Preferences page with voices, playback, reading, pronunciation dictionary, storage manager"
```

---

### Task 8: Per-document voice change with the discard warning (app target + `VoiceChangeModel`)

**Files:**
- Create: `Sources/T2SApp/Storage/VoiceChangeModel.swift`, `Tests/T2SAppTests/VoiceChangeModelTests.swift`
- Create: `App/T2SReader/Player/VoiceChangeSheet.swift`
- Modify: `App/T2SReader/Queue/QueueRow.swift` and `App/T2SReader/Player/PlayerSheet.swift` (context menu "Change voice")

**Interfaces:**
- Consumes: `Library.evictAudio`, `LibraryStore.update`, `DocumentSummary`, `PlayerModel`, `VoiceCatalog`, `VoiceListPage`.
- Produces: `@MainActor @Observable public final class VoiceChangeModel { init(library:player:libraryModel:); func discardedSeconds(for:) -> TimeInterval; func apply(voiceID: String?, to: DocumentSummary) async -> Bool }`; `VoiceChangeSheet(summary:)`.

Spec §5: changing voice invalidates that document's rendered audio (its render keys embed the voice); the UI warns with how much rendered audio will be discarded, with a `destructive` confirm.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/T2SAppTests/VoiceChangeModelTests.swift
import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct VoiceChangeModelTests {
    @Test func applyingAVoiceEvictsAudioAndPersistsTheOverride() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        let library = LibraryModel(library: f.library)
        let model = VoiceChangeModel(library: f.library, player: player, libraryModel: library)

        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.coordinator.waitForRenderIdle()
        await player.persistRenderedChapters()
        let before = try #require(try await f.store.summary(id: id))
        #expect(model.discardedSeconds(for: before) > 0)

        #expect(await model.apply(voiceID: "custom-voice", to: before))
        let after = try #require(try await f.store.summary(id: id))
        #expect(after.document.voiceID == "custom-voice" && after.renderedCount == 0)
        #expect(await f.audio.stats().entries == 0)
        #expect(player.current?.id == id && player.coordinator.document?.voiceID == "custom-voice")
        #expect(model.discardedSeconds(for: after) == 0)

        #expect(await model.apply(voiceID: nil, to: after))                  // back to the default
        #expect(try await f.store.document(id: id)?.voiceID == nil)
    }
}
```

- [ ] **Step 2: Implement**

```swift
// Sources/T2SApp/Storage/VoiceChangeModel.swift
import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

/// Per-document voice override (spec §2.2) with the spec §5 consequence: the document's rendered
/// audio is discarded because every render key embeds the voice.
@MainActor
@Observable
public final class VoiceChangeModel {
    public private(set) var lastError: String?
    private let library: Library
    private let player: PlayerModel
    private let libraryModel: LibraryModel

    public init(library: Library, player: PlayerModel, libraryModel: LibraryModel) {
        self.library = library
        self.player = player
        self.libraryModel = libraryModel
    }

    /// Rendered seconds that a voice change throws away (proportional to rendered utterances).
    public func discardedSeconds(for summary: DocumentSummary) -> TimeInterval {
        guard summary.utteranceCount > 0 else { return 0 }
        return summary.totalSeconds * Double(summary.renderedCount) / Double(summary.utteranceCount)
    }

    /// Evicts the audio, persists the override (nil = back to the default voice), reloads the
    /// document if it is the one playing. True on success.
    public func apply(voiceID: String?, to summary: DocumentSummary) async -> Bool {
        let wasCurrent = player.current?.id == summary.id
        do {
            try await library.evictAudio(for: summary.id)
            var document = summary.document
            document.voiceID = voiceID
            try await library.store.update(document)
            lastError = nil
        } catch {
            lastError = "\(error)"
            return false
        }
        if wasCurrent, let fresh = try? await library.store.summary(id: summary.id) {
            await player.load(fresh, play: false)
        }
        await libraryModel.refresh()
        return true
    }
}
```

```swift
// App/T2SReader/Player/VoiceChangeSheet.swift
import SwiftUI
import T2SApp
import T2SStore

/// Context-menu "Change voice": pick a voice; if rendered audio exists, the spec §5 warning with a
/// `destructive` confirm precedes the change.
struct VoiceChangeSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var summary: DocumentSummary
    @State private var pending: VoiceOption?

    var body: some View {
        NavigationStack {
            if let pending {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    Text("Change voice to \(pending.name)?").typeRole(.playerTitle).foregroundStyle(Tokens.ink).padding(.top, Spacing.section)
                    Text("About \(DurationFormatter.long(env.voiceChange.discardedSeconds(for: summary))) of rendered audio will be discarded and rendered again with the new voice.")
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    HStack(spacing: 8) {
                        Pill(label: "Change voice", glyph: "trash", style: .destructiveSoft) {
                            Task { _ = await env.voiceChange.apply(voiceID: pending.isDefault ? nil : pending.id, to: summary); dismiss() }
                        }
                        Pill(label: "Keep current", style: .soft) { self.pending = nil }
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.margin)
                .background(Tokens.raised)
            } else {
                VoiceListPage(selection: summary.document.voiceID) { option in
                    if env.voiceChange.discardedSeconds(for: summary) > 0 {
                        pending = option
                    } else {
                        Task { _ = await env.voiceChange.apply(voiceID: option.isDefault ? nil : option.id, to: summary); dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}
```

`AppEnvironment` gains `let voiceChange: VoiceChangeModel`. `QueueRow`'s context menu and `PlayerSheet`'s overflow gain `Button { showVoice = true } label: { Label("Change voice", systemImage: "person.wave.2") }` with `.sheet(isPresented: $showVoice) { VoiceChangeSheet(summary: …) }`.

- [ ] **Step 3: Test, build, commit**

Run: `swift test --filter VoiceChangeModelTests && scripts/build-app.sh`
Expected: 1 test passed; build succeeds.

```bash
git add Sources/T2SApp/Storage Tests/T2SAppTests/VoiceChangeModelTests.swift App
git commit -m "App: per-document voice change with the discard warning"
```

---

### Task 9: Docs, roadmap, and the manual pass

**Files:**
- Modify: `README.md` (Reader and Preferences in "Running the app"), `docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md` (Plan 4a/4b statuses; Plan 5 next), `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` §6.1 (a one-line note that v1 ships PDF as audio-first with page-level sync, as anticipated)

- [ ] **Step 1: Manual pass on the simulator** — import an article by link, read along (highlight follows, scroll suspends, Back to current, tap-to-seek), change speed (an unavailable rate is greyed if the RTF is high), start a sleep timer, change the default voice and a per-document voice (the warning appears once audio exists), add a pronunciation entry and reprocess a document from Details, evict a document's audio from Storage, check dark mode. Record findings in the report; anything broken is a fix round, not a note.
- [ ] **Step 2: Docs** — write the three edits above.
- [ ] **Step 3: Verify and commit**

Run: `swift test && scripts/build-app.sh && scripts/check-licenses.sh`

```bash
git add README.md docs
git commit -m "Docs: Reader, Preferences, roadmap after Plan 4b"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| §2.2 speed with pitch correction (UI), sleep timer incl. end of chapter, voice picker global and per document, pronunciation dictionary, bookmarks (Reader), storage manager | 6, 6, 7 + 8, 7, 5, 7 |
| §2.3 Reader as a separate page; leaving never stops playback | 5 |
| §2.4.1 Reader body type, user-adjustable size and line height | 4, 5 |
| §2.4.5 Reader page (chrome, decoration, auto-scroll, Back to current, tap-to-seek, bottom bar, catching up), speed picker, sleep timer, context menu items, Preferences page, voice-change warning | 1, 4, 5, 6, 7, 8 |
| §3.4 cache cap user-configurable | 7 |
| §3.4.1 prepare budget options; prepared amount and last run visible | 7 |
| §3.6 unavailable rates greyed with explanation; catching-up visible | 6, 5 |
| §3.7.2 Readium only at the boundary | 4 |
| §5 voice change invalidates audio with a warning | 8 |
| §6 fallback voice notice (system voice is the engine until Plan 5; Preferences says so) | 7 |
| §6.1 PDF audio-first with page-level sync | 4, 9 |

Hand-offs to Plan 5: Kokoro voices in `VoiceCatalog`; Now Playing / remote commands; the Share Extension (reusing `ArticleExtractor` + `ImportModel`); the multi-document Prepare runner and `BGProcessingTask` (setting `StorageModel.lastPrepareRunKey`); applying a changed prepare budget without a relaunch; the cloud-voices section. Known v1 limits recorded in the plan: auto-scroll works at block (paragraph) granularity; tap-to-seek matches by text and may miss on repeated identical sentences within one block; PDF has no word highlight.
