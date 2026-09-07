# Plan 10 — The native read-along (after ElevenReader) and an app-wide theme

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

_2026-09-07. Branch `plan-10-native-readalong` off `dev` @ 93811aa, in the main checkout (no worktree).
Executed with the subagent-driven workflow; the ledger with every ruling is
`.superpowers/sdd/2026-09-07-plan-10-native-readalong/progress.md` (local, git-ignored)._

**Goal:** The Reader page draws the book's text itself — one column of Inter on our ground with the
paragraph being read tinted and the spoken word tinted darker, taps that seek to a word, and
following that keeps the word mid-screen — for EPUBs, articles and PDFs alike; and the theme choice
applies to the whole app.

**Architecture:** A pure model in the `T2SApp` package (`ReaderText`) turns the `Timeline` the app
already synthesizes from into paragraphs, chapter titles and headings with exact UTF-16 offsets, and
answers where a highlight falls and which utterance a tap hits. A UIKit text view on TextKit 2
(`ReaderTextView`, App target) shows the whole document from one attributed string, draws the tints
as rounded rectangles under the glyphs, and hosts taps and following. `ReaderPage` swaps Readium's
navigators for it; the app stops linking `ReadiumNavigator` and the GCD web server.

**Tech Stack:** Swift 6, SwiftUI + UIKit (`UITextView` with `NSTextLayoutManager`), swift-testing,
xcodegen, the iPhone simulator (silent).

**Spec:** `docs/superpowers/specs/2026-09-07-native-readalong-design.md` (this plan argues from it);
the main spec `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` §2.4.1–2.4.5, §3.1, §3.7.2,
§6.1 for what it amends.

## Global Constraints

- **No audio on the owner's Mac, ever.** The simulator app is launched only as
  `SIMCTL_CHILD_T2S_SILENT=1 xcrun simctl launch <udid> com.t2s.reader`. Never change the Mac's
  volume. Never run anything that plays through the speakers.
- Swift 6 language mode everywhere (`swiftLanguageMode(.v6)` in every package target; the app builds
  with strict concurrency). iOS 18.0 deployment target. Xcode 26.
- Semantic colour tokens only (`Tokens.*`); no literal colours in views (spec §2.4.2). Type roles from
  spec §2.4.1; the bundled faces are `Inter-Regular`, `Inter-Medium`, `Inter-SemiBold`,
  `InterDisplay-ExtraBold`, `InterDisplay-Black` (PostScript names, `App/Resources/Fonts`).
- Readium types are never persisted (spec §3.7.2). `Packages/T2SReadium` is not modified by this plan.
- Every offset in `ReaderText` is UTF-16 (the unit `Utterance.source`, `HighlightRange.sourceRange`
  and `NSAttributedString` all count in).
- Every task ends with `swift test` green (root package, on macOS) and `scripts/build-app.sh` green
  (`** BUILD SUCCEEDED **`), and one commit whose message ends with
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Never run `rm -rf .build` anywhere: `.build/DerivedData-App` is the app's build. If SwiftPM's
  incremental build keeps a stale default argument after a `static let` change, remove only
  `.build/arm64-apple-macosx`.
- `scripts/test-readium.sh` is not run by this plan (nothing in the Readium package changes).

---

## File structure

| File | Responsibility |
|---|---|
| `Sources/T2SApp/Reader/ReaderText.swift` (new) | The text model: paragraphs, spans, kinds, the flattened string and its queries. Pure. |
| `Sources/T2SApp/Reader/ReaderModel.swift` | Gains `seek(toUtterance:sourceOffset:)` and `playhead(utteranceIndex:sourceOffset:in:)`; loses the tap-matching path in Task 4. |
| `Tests/T2SAppTests/ReaderTextTests.swift` (new) | Tests for the model. |
| `Tests/T2SAppTests/ReaderModelTests.swift` | New seek tests; old tap-matching tests removed in Task 4. |
| `App/T2SReader/Reader/ReaderTypesetter.swift` (new) | `ReaderText` + settings → `NSAttributedString`. Pure, nonisolated. |
| `App/T2SReader/Reader/ReaderTextView.swift` (new) | The UIKit text view, its highlight overlay, taps, following, hosted by SwiftUI. |
| `App/T2SReader/Reader/ReaderPage.swift` | Hosts `ReaderTextView`; builds `ReaderText`; no Readium. |
| `App/T2SReader/Design/Theme.swift` (new) | `ReaderTheme.colorScheme` and the `appTheme()` modifier. |
| `App/T2SReader/Root/RootPager.swift`, `App/T2SReader/T2SReaderApp.swift` | Apply the theme at the root. |
| `App/T2SReader/Preferences/AppearanceSheet.swift`, `App/T2SReader/Preferences/PreferencesPage.swift` | Theme caption. |
| `App/T2SReader/AppEnvironment.swift` | Loses `publications`. |
| `App/project.yml` | Drops the two Readium navigator products from the app template. |
| Deleted: `App/T2SReader/Reader/{EPUBReaderView,PDFReaderView,ReaderScripts,PublicationCache,ReaderError}.swift`, `Sources/T2SApp/Reader/SourceHit.swift` | Readium's navigators and the tap-matching they needed. |
| `Sources/T2SCore/Timeline/Highlighter.swift`, `Tests/T2SCoreTests/HighlighterTests.swift` | `sentence(at:in:)` and its two tests go (Task 4). |
| `docs/superpowers/specs/2026-09-01-t2s-reader-design.md`, `README.md`, `docs/HANDOFF.md`, `docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md` | Task 5. |

## Tasks

| # | Task | Owns | Verification |
|---|---|---|---|
| 1 | **`ReaderText` and the utterance seek.** The model of spec §3 with its queries; `ReaderModel.playhead(utteranceIndex:sourceOffset:in:)` extracted from the tap path and `seek(toUtterance:sourceOffset:)` on top of it (the old `playhead(for:in:)` delegates to it until Task 4). | `Sources/T2SApp/Reader/ReaderText.swift`, `Sources/T2SApp/Reader/ReaderModel.swift`, `Tests/T2SAppTests/ReaderTextTests.swift`, `Tests/T2SAppTests/ReaderModelTests.swift` | `swift test` |
| 2 | **`ReaderTextView` and the page.** The typesetter, the UIKit view with overlay tints, taps and following; `ReaderPage` hosts it for every source type; the Readium navigators, scripts, publication cache and the app's two navigator links are removed. | `App/T2SReader/Reader/*`, `App/T2SReader/AppEnvironment.swift`, `App/project.yml` | `swift test`; `scripts/build-app.sh`; silent simulator screenshots (light; text scale 1.6) |
| 3 | **Theme, app-wide.** `ReaderTheme.colorScheme`, the `appTheme()` modifier on the root pager and the Reader page, captions. | `App/T2SReader/Design/Theme.swift`, `App/T2SReader/Root/RootPager.swift`, `App/T2SReader/Reader/ReaderPage.swift`, `App/T2SReader/Preferences/{AppearanceSheet,PreferencesPage}.swift` | `scripts/build-app.sh`; a dark screenshot of the Queue page and the Reader with `reader.theme` = dark and the simulator in light mode |
| 4 | **Retire the tap-matching path.** `SourceHit`, `seek(to:)`, `utteranceIndex(for:in:)`, `locate`, `rawOffset`, `normalized`, `pageCount`, `playhead(for:in:)`, `activeSentence`, `Highlighter.sentence` and their tests. | `Sources/T2SApp/Reader/{ReaderModel,SourceHit}.swift`, `Sources/T2SCore/Timeline/Highlighter.swift`, `Tests/T2SAppTests/ReaderModelTests.swift`, `Tests/T2SCoreTests/HighlighterTests.swift` | `swift test`; `scripts/build-app.sh` |
| 5 | **Docs.** Main spec rev 11 (§2.4.2 `accentFaint` wording, §2.4.5 Reader page, §6.1, changelog), README layout lines, HANDOFF resume section with the phone checklist, roadmap. | `docs/`, `README.md` | review |

Strictly sequential: 2 needs 1; 3 and 4 edit files 2 rewrote; 5 describes the result. Every task ends
with a review; the whole branch gets a final review before `dev` fast-forwards.

## Decisions taken without the owner (each also in the ledger, with its cost if wrong)

- **One text view for the whole document, not a paragraph list.** One coordinate space for taps,
  tints and scrolling; TextKit 2 lays out lazily. Cost if a device proves it slow: chapter-at-a-time
  loading in the same view, no model change.
- **Tints hug each line** (rounded rectangles per line, 4 pt), like ElevenReader's blue theme, rather
  than one block behind the paragraph. Cost: a path-building function.
- **Headings come from the block's selector tag only.** Readium 3.11 labels every element `.body`;
  blocks whose selector ends in `#id` stay body. The chapter's own first block is recognised by text
  against its contents title, so the most visible heading is always right. Cost: some sub-headings
  render as body until import records roles (a later plan).
- **The document title and byline are drawn at the top** (ElevenReader does); a first spoken block that
  says the title becomes the title. Cost: two paragraph kinds.
- **PDF pages tint per utterance.** A page is not a paragraph. Cost: one flag.
- **No images, tables or footnotes.** They are not spoken; the owner asked for text like lyrics.
- **The tap-matching path is deleted, not kept behind the new view.** Nothing else uses it and it was
  the reason for `rawOffset` and the page-count recovery. Cost: none — the new path is exact.
- **`Packages/T2SReadium` untouched.** `LocatorMapping`'s highlight half becomes unused by the app;
  removing it means the simulator-only Readium test run, deferred.

## Deferred

- Import-time block roles (headings, quotes) once Readium or our own HTML pass provides them.
- Images inline (the EPUB's resources are reachable through the publication if ever wanted).
- Text selection, notes, sharing a quote.
- Removing `LocatorMapping.locator(for:in:)` and its tests from `T2SReadium`.

---

### Task 1: `ReaderText` and the utterance seek

**Files:**
- Create: `Sources/T2SApp/Reader/ReaderText.swift`
- Modify: `Sources/T2SApp/Reader/ReaderModel.swift` (the `seek(to:)` / `playhead(for:in:)` block, lines 46–72 today)
- Test: `Tests/T2SAppTests/ReaderTextTests.swift` (new), `Tests/T2SAppTests/ReaderModelTests.swift`

**Interfaces:**
- Consumes: `Timeline`, `Chapter`, `Utterance`, `Position`, `HighlightRange` from `T2SCore` (unchanged).
- Produces (Task 2 relies on these exact names):
  ```swift
  public struct ReaderText: Hashable, Sendable {
      public enum Kind: Hashable, Sendable { case documentTitle, byline, chapterTitle, heading(level: Int), body }
      public struct Span: Hashable, Sendable { public var utteranceIndex: Int; public var range: Range<Int> }
      public struct Paragraph: Hashable, Sendable, Identifiable {
          public var id: Int; public var kind: Kind; public var chapterIndex: Int?; public var text: String
          public var location: Int; public var spans: [Span]; public var tintsWholeParagraph: Bool
          public var range: Range<Int>
      }
      public let documentID: UUID
      public private(set) var paragraphs: [Paragraph]
      public private(set) var length: Int
      public init(documentID: UUID, timeline: Timeline, title: String, author: String?)
      public func paragraphIndex(forUtterance i: Int) -> Int?
      public func paragraph(at offset: Int) -> Paragraph?
      public func wordRange(for highlight: HighlightRange) -> Range<Int>?
      public func tintRange(forUtterance i: Int) -> Range<Int>?
      public func hit(at offset: Int) -> (utteranceIndex: Int, sourceOffset: Int)?
      public static func displayText(_ source: String) -> String
      public static func normalized(_ s: String) -> String
      static func kind(forSelector selector: String?) -> Kind
  }
  extension ReaderModel {
      public func seek(toUtterance index: Int, sourceOffset: Int) async -> Bool
      public static func playhead(utteranceIndex: Int, sourceOffset: Int, in timeline: Timeline) -> Playhead?
  }
  ```

- [ ] **Step 1: Write the failing tests for the model**

Create `Tests/T2SAppTests/ReaderTextTests.swift`:

```swift
import Foundation
import Testing
import T2SCore
@testable import T2SApp

@Suite struct ReaderTextTests {
    let id = UUID()

    func utterance(_ text: String, href: String = "OEBPS/ch1.xhtml", selector: String? = "#c1 > p:nth-child(2)",
                   offset: Int = 0, progression: Double = 0) -> Utterance {
        let n = text.utf16.count
        return Utterance(position: Position(resourceHref: href, progression: progression, charOffset: offset, cssSelector: selector),
                         source: text, spoken: text, spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)],
                         duration: .estimated(1))
    }

    func timeline(_ chapters: [(String, [Utterance])]) -> Timeline {
        Timeline(chapters: chapters.map { Chapter(title: $0.0, position: $0.1.first?.position ?? Position(resourceHref: "x", progression: 0), utterances: $0.1) })
    }

    // Two utterances of one block form one paragraph; a new selector starts another.
    @Test func consecutiveUtterancesOfABlockFormOneParagraph() {
        let t = timeline([("One", [
            utterance("First sentence.", selector: "#c1 > p:nth-child(2)"),
            utterance("Second sentence.", selector: "#c1 > p:nth-child(2)", offset: 16),
            utterance("Another block.", selector: "#c1 > p:nth-child(3)"),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: "Someone")
        let kinds = text.paragraphs.map(\.kind)
        #expect(kinds == [.documentTitle, .byline, .chapterTitle, .body, .body])
        let p = text.paragraphs[3]
        #expect(p.text == "First sentence. Second sentence.")
        #expect(p.spans == [ReaderText.Span(utteranceIndex: 0, range: 0..<15), ReaderText.Span(utteranceIndex: 1, range: 16..<32)])
        #expect(p.chapterIndex == 0 && p.tintsWholeParagraph)
        #expect(text.paragraphs[4].text == "Another block.")
    }

    @Test func locationsAndLengthFollowTheFlattenedString() {
        let t = timeline([("One", [utterance("Hello there.")])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: nil)
        // "Book\nOne\nHello there." — no byline without an author.
        #expect(text.paragraphs.map(\.kind) == [.documentTitle, .chapterTitle, .body])
        #expect(text.paragraphs.map(\.location) == [0, 5, 9])
        #expect(text.length == 21)
        #expect(text.paragraphs[2].range == 9..<21)
    }

    @Test func aFirstBlockThatSaysTheChapterTitleIsTheChapterTitle() {
        let t = timeline([("The Storm", [
            utterance("THE STORM.", selector: "#h"),
            utterance("It began at dusk.", selector: "#c1 > p:nth-child(2)"),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: nil)
        #expect(text.paragraphs.map(\.kind) == [.documentTitle, .chapterTitle, .body])
        #expect(text.paragraphs[1].text == "THE STORM." && text.paragraphs[1].spans.count == 1)
    }

    @Test func aChapterTitleEqualToTheDocumentTitleIsNotDrawn() {
        let t = timeline([("Book", [utterance("Only paragraph.")])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: nil)
        #expect(text.paragraphs.map(\.kind) == [.documentTitle, .body])
    }

    @Test func aFirstSpokenBlockThatSaysTheDocumentTitleBecomesTheTitle() {
        let t = timeline([("Intro", [
            utterance("War and Peace", selector: "#t"),
            utterance("Well, Prince.", selector: "#c1 > p:nth-child(2)"),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "War and Peace", author: "Tolstoy")
        #expect(text.paragraphs.map(\.kind) == [.documentTitle, .byline, .chapterTitle, .body])
        #expect(text.paragraphs[0].spans.count == 1)          // the spoken title
        #expect(text.paragraphs[2].text == "Intro" && text.paragraphs[2].spans.isEmpty)
    }

    @Test func headingsComeFromTheSelectorTag() {
        #expect(ReaderText.kind(forSelector: "#c1 > h2:nth-child(1)") == .heading(level: 2))
        #expect(ReaderText.kind(forSelector: "html > body > section > h1.title") == .heading(level: 1))
        #expect(ReaderText.kind(forSelector: "#c1 > p:nth-child(2)") == .body)
        #expect(ReaderText.kind(forSelector: "#heading-id") == .body)
        #expect(ReaderText.kind(forSelector: "#c1 > h7") == .body)
        #expect(ReaderText.kind(forSelector: nil) == .body)
    }

    @Test func aPDFPageIsOneParagraphTintedPerUtterance() {
        let href = "source.pdf"
        let t = timeline([("Doc", [
            utterance("Line one\nline two.", href: href, selector: nil, offset: 0, progression: 0),
            utterance("Still page one.", href: href, selector: nil, offset: 19, progression: 0),
            utterance("Page two.", href: href, selector: nil, offset: 35, progression: 0.5),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "Doc", author: nil)
        #expect(text.paragraphs.map(\.kind) == [.documentTitle, .body, .body])
        let page = text.paragraphs[1]
        #expect(page.text == "Line one line two. Still page one.")   // the newline shows as a space
        #expect(!page.tintsWholeParagraph)
        #expect(text.tintRange(forUtterance: 1) == (page.location + 19)..<(page.location + 34))
        #expect(text.tintRange(forUtterance: 0) == page.location..<(page.location + 18))
    }

    @Test func displayTextKeepsLengths() {
        #expect(ReaderText.displayText("a\r\nb\tc\u{00A0}d") == "a  b c d")
        #expect(ReaderText.displayText("a\r\nb").utf16.count == "a\r\nb".utf16.count)
    }

    @Test func normalizedIgnoresCaseWhitespaceAndTrailingPunctuation() {
        #expect(ReaderText.normalized("  The   Storm. ") == "the storm")
        #expect(ReaderText.normalized("CHAPTER I:") == "chapter i")
    }

    @Test func wordAndTintRangesLandInTheParagraph() {
        let t = timeline([("One", [
            utterance("First sentence.", selector: "#p1"),
            utterance("Second sentence.", selector: "#p1", offset: 16),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: nil)
        let p = text.paragraphs[2]
        let h = HighlightRange(utteranceIndex: 1, position: t[utterance: 1].position, sourceRange: 7..<16)   // "sentence."
        #expect(text.wordRange(for: h) == (p.location + 16 + 7)..<(p.location + 16 + 16))
        #expect(text.tintRange(forUtterance: 1) == p.range)
        #expect(text.paragraphIndex(forUtterance: 1) == 2)
        #expect(text.paragraphIndex(forUtterance: 2) == nil)
        let outOfRange = HighlightRange(utteranceIndex: 1, position: t[utterance: 1].position, sourceRange: 10..<40)
        #expect(text.wordRange(for: outOfRange) == nil)
    }

    @Test func hitsMapOffsetsBackToUtterances() {
        let t = timeline([("One", [
            utterance("First sentence.", selector: "#p1"),
            utterance("Second sentence.", selector: "#p1", offset: 16),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: nil)
        let p = text.paragraphs[2]
        func hit(_ offset: Int) -> [Int] { text.hit(at: offset).map { [$0.utteranceIndex, $0.sourceOffset] } ?? [] }
        #expect(hit(p.location + 3) == [0, 3])
        #expect(hit(p.location + 16 + 7) == [1, 7])
        #expect(hit(p.location + 15) == [1, 0])            // the gap between spans → the next utterance
        #expect(hit(p.location + 32) == [1, 15])           // the paragraph's end → its last character
        #expect(text.hit(at: 1) == nil)                                // inside the drawn title
        #expect(text.hit(at: text.length + 5) == nil)
        #expect(text.paragraph(at: p.location + 4)?.id == 2)
        #expect(text.paragraph(at: 0)?.kind == .documentTitle)
    }

    @Test func anEmptyTimelineStillHasTheTitle() {
        let text = ReaderText(documentID: id, timeline: Timeline(chapters: []), title: "Book", author: nil)
        #expect(text.paragraphs.map(\.kind) == [.documentTitle])
        #expect(text.length == 4)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter ReaderTextTests`
Expected: compile failure — `ReaderText` is not defined.

- [ ] **Step 3: Write `ReaderText`**

Create `Sources/T2SApp/Reader/ReaderText.swift`:

```swift
import Foundation
import T2SCore

/// The Reader page's text, drawn by us from the timeline (spec 2026-09-07 §3): paragraphs of the
/// utterances' own source text, chapter titles and headings, plus the answers the view needs —
/// where a highlight falls, what to tint, and which utterance a tap lands in. Every offset is
/// UTF-16 in the flattened string (`Paragraph.location` + an offset in `Paragraph.text`), the unit
/// `Utterance.source`, `HighlightRange.sourceRange` and `NSAttributedString` all count in.
public struct ReaderText: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case documentTitle
        case byline
        case chapterTitle
        case heading(level: Int)
        case body
    }

    /// One utterance inside a paragraph.
    public struct Span: Hashable, Sendable {
        public var utteranceIndex: Int
        /// UTF-16 range of the utterance's `source` inside the paragraph's `text`.
        public var range: Range<Int>

        public init(utteranceIndex: Int, range: Range<Int>) {
            self.utteranceIndex = utteranceIndex
            self.range = range
        }
    }

    public struct Paragraph: Hashable, Sendable, Identifiable {
        public var id: Int
        public var kind: Kind
        /// nil for the drawn title and byline.
        public var chapterIndex: Int?
        public var text: String
        /// Where `text` starts in the flattened string.
        public var location: Int
        /// The utterances this paragraph holds, in order; empty for text that is never spoken.
        public var spans: [Span]
        /// False on a PDF page: the tinted unit there is the utterance, not the page.
        public var tintsWholeParagraph: Bool

        public var range: Range<Int> { location ..< location + text.utf16.count }
    }

    public let documentID: UUID
    public private(set) var paragraphs: [Paragraph]
    /// UTF-16 length of the flattened string: paragraph texts joined by "\n".
    public private(set) var length: Int
    private var paragraphByUtterance: [Int]
    private var spanByUtterance: [Int]

    private struct BlockKey: Equatable {
        var href: String
        var selector: String?
        /// The page, for a PDF (no selector).
        var progression: Double?

        init(_ position: Position) {
            href = position.resourceHref
            selector = position.cssSelector
            progression = position.cssSelector == nil ? position.progression : nil
        }
    }

    private struct Item {
        var kind: Kind
        var chapter: Int?
        var text: String
        var spans: [Span]
        var tintsWhole: Bool
    }

    public init(documentID: UUID, timeline: Timeline, title: String, author: String?) {
        self.documentID = documentID
        var items: [Item] = []
        let documentTitle = Self.normalized(title)
        var utteranceIndex = 0
        for (c, chapter) in timeline.chapters.enumerated() {
            // Consecutive utterances that share a block, in order.
            var blocks: [[(index: Int, utterance: Utterance)]] = []
            var keys: [BlockKey] = []
            for utterance in chapter.utterances {
                let key = BlockKey(utterance.position)
                if keys.last == key {
                    blocks[blocks.count - 1].append((utteranceIndex, utterance))
                } else {
                    keys.append(key)
                    blocks.append([(utteranceIndex, utterance)])
                }
                utteranceIndex += 1
            }
            let chapterTitle = Self.normalized(chapter.title)
            for (b, block) in blocks.enumerated() {
                var text = ""
                var spans: [Span] = []
                for (index, utterance) in block {
                    if !text.isEmpty { text += " " }
                    let start = text.utf16.count
                    text += Self.displayText(utterance.source)
                    spans.append(Span(utteranceIndex: index, range: start ..< text.utf16.count))
                }
                let selector = block[0].utterance.position.cssSelector
                var kind = Self.kind(forSelector: selector)
                if b == 0 {
                    if Self.normalized(text) == chapterTitle {
                        kind = .chapterTitle
                    } else if chapterTitle != documentTitle {
                        items.append(Item(kind: .chapterTitle, chapter: c, text: chapter.title, spans: [], tintsWhole: true))
                    }
                }
                items.append(Item(kind: kind, chapter: c, text: text, spans: spans, tintsWhole: selector != nil))
            }
        }

        // The title at the top: the first spoken paragraph when it says the title, else drawn and
        // never spoken. The byline follows it.
        if let first = items.firstIndex(where: { !$0.spans.isEmpty }), Self.normalized(items[first].text) == documentTitle {
            var spokenTitle = items.remove(at: first)
            spokenTitle.kind = .documentTitle
            items.insert(spokenTitle, at: 0)
        } else {
            items.insert(Item(kind: .documentTitle, chapter: nil, text: title, spans: [], tintsWhole: true), at: 0)
        }
        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            items.insert(Item(kind: .byline, chapter: nil, text: author, spans: [], tintsWhole: true), at: 1)
        }

        var paragraphs: [Paragraph] = []
        var location = 0
        var paragraphByUtterance = Array(repeating: -1, count: timeline.utteranceCount)
        var spanByUtterance = Array(repeating: -1, count: timeline.utteranceCount)
        for item in items {
            let id = paragraphs.count
            paragraphs.append(Paragraph(id: id, kind: item.kind, chapterIndex: item.chapter, text: item.text,
                                        location: location, spans: item.spans, tintsWholeParagraph: item.tintsWhole))
            for (s, span) in item.spans.enumerated() {
                paragraphByUtterance[span.utteranceIndex] = id
                spanByUtterance[span.utteranceIndex] = s
            }
            location += item.text.utf16.count + 1
        }
        self.paragraphs = paragraphs
        self.length = max(0, location - 1)
        self.paragraphByUtterance = paragraphByUtterance
        self.spanByUtterance = spanByUtterance
    }

    // MARK: Queries

    public func paragraphIndex(forUtterance i: Int) -> Int? {
        guard paragraphByUtterance.indices.contains(i), paragraphByUtterance[i] >= 0 else { return nil }
        return paragraphByUtterance[i]
    }

    private func span(forUtterance i: Int) -> (paragraph: Paragraph, span: Span)? {
        guard let p = paragraphIndex(forUtterance: i) else { return nil }
        return (paragraphs[p], paragraphs[p].spans[spanByUtterance[i]])
    }

    /// The paragraph containing a flattened-string offset (the "\n" after a paragraph counts as its own).
    public func paragraph(at offset: Int) -> Paragraph? {
        guard offset >= 0, offset <= length, !paragraphs.isEmpty else { return nil }
        var low = 0
        var high = paragraphs.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if paragraphs[mid].location <= offset { low = mid } else { high = mid - 1 }
        }
        return paragraphs[low]
    }

    /// The highlight's `sourceRange` shifted into the document; nil when it falls outside its utterance.
    public func wordRange(for highlight: HighlightRange) -> Range<Int>? {
        guard let located = span(forUtterance: highlight.utteranceIndex),
              highlight.sourceRange.lowerBound >= 0,
              highlight.sourceRange.upperBound <= located.span.range.count
        else { return nil }
        let base = located.paragraph.location + located.span.range.lowerBound
        return (base + highlight.sourceRange.lowerBound) ..< (base + highlight.sourceRange.upperBound)
    }

    /// The whole paragraph, or the utterance's own range on a PDF page.
    public func tintRange(forUtterance i: Int) -> Range<Int>? {
        guard let located = span(forUtterance: i) else { return nil }
        let (paragraph, span) = located
        if paragraph.tintsWholeParagraph { return paragraph.range }
        return (paragraph.location + span.range.lowerBound) ..< (paragraph.location + span.range.upperBound)
    }

    /// The utterance under a flattened-string offset and the offset inside its `source`. An offset in
    /// the gap between two spans belongs to the next utterance (start); the paragraph's end belongs
    /// to the last utterance's last character; nil in text that is never spoken or past the end.
    public func hit(at offset: Int) -> (utteranceIndex: Int, sourceOffset: Int)? {
        guard let paragraph = paragraph(at: offset), let last = paragraph.spans.last else { return nil }
        let local = offset - paragraph.location
        if let inside = paragraph.spans.first(where: { $0.range.contains(local) }) {
            return (inside.utteranceIndex, local - inside.range.lowerBound)
        }
        if let next = paragraph.spans.first(where: { $0.range.lowerBound > local }) {
            return (next.utteranceIndex, 0)
        }
        return (last.utteranceIndex, max(0, last.range.count - 1))
    }

    // MARK: Rules

    /// A block's kind from its selector: the tag at the start of the last `>` segment, when it is h1…h6.
    /// An `#id` segment says nothing about the tag, so those blocks stay body (Readium 3.11 labels
    /// every text element `.body`; the selector is the only signal).
    static func kind(forSelector selector: String?) -> Kind {
        guard let selector else { return .body }
        let last = selector.split(separator: ">").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let tag = last.prefix { $0.isLetter || $0.isNumber }.lowercased()
        guard tag.count == 2, tag.hasPrefix("h"), let level = Int(String(tag.suffix(1))), (1...6).contains(level) else {
            return .body
        }
        return .heading(level: level)
    }

    /// The source with every whitespace scalar shown as a space; the UTF-16 length never changes, so
    /// offsets into `source` and into the paragraph are the same numbers (spec 2026-09-07 §3).
    public static func displayText(_ source: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in source.unicodeScalars {
            scalars.append(scalar.properties.isWhitespace ? " " : scalar)
        }
        return String(scalars)
    }

    /// Whitespace collapsed, case folded, trailing `.:;` and whitespace removed — how a block's text is
    /// compared with a chapter or document title.
    public static func normalized(_ s: String) -> String {
        let collapsed = s.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        var trimmed = Substring(collapsed)
        while let last = trimmed.last, last.isWhitespace || ".:;".contains(last) { trimmed = trimmed.dropLast() }
        return String(trimmed)
    }
}
```

- [ ] **Step 4: Run the model tests**

Run: `swift test --filter ReaderTextTests`
Expected: all 13 pass. If `displayTextKeepsLengths` fails on `\u{00A0}`, check `Unicode.Scalar.Properties.isWhitespace` covers NBSP (it does — White_Space property); if `aPDFPageIsOneParagraphTintedPerUtterance` fails on the expected ranges, recount: "Line one line two." is 18 units, the joining space is at 18, "Still page one." starts at 19 and ends at 34.

- [ ] **Step 5: Write the failing seek tests**

Append to `Tests/T2SAppTests/ReaderModelTests.swift`, inside the suite, after `withoutWordTimingsATapSeeksToTheUtteranceStart` (the suite already defines `utterance(_:href:offset:progression:)`, `epubTimeline` and `packedTimeline`):

```swift
    // MARK: Seeks by utterance (Plan 10: the native reader knows the utterance it drew)

    @Test func anOffsetInTheSecondSentenceSeeksToThatWordsStart() {
        let t = packedTimeline   // "First sentence. Second sentence here.", one timing per word, 0.5 s apart
        // "Second" is the third word (source offset 16): starts at 1.0 s; "here." is the fifth: 2.0 s.
        #expect(ReaderModel.playhead(utteranceIndex: 0, sourceOffset: 18, in: t) == Playhead(utteranceIndex: 0, offset: 1.0))
        #expect(ReaderModel.playhead(utteranceIndex: 0, sourceOffset: 34, in: t) == Playhead(utteranceIndex: 0, offset: 2.0))
        #expect(ReaderModel.playhead(utteranceIndex: 0, sourceOffset: 2, in: t) == Playhead(utteranceIndex: 0, offset: 0))
    }

    @Test func offsetsAreClampedAndTimingsOptional() {
        let t = epubTimeline   // no word timings → utterance start
        #expect(ReaderModel.playhead(utteranceIndex: 1, sourceOffset: 5, in: t) == Playhead(utteranceIndex: 1))
        #expect(ReaderModel.playhead(utteranceIndex: 1, sourceOffset: 999, in: t) == Playhead(utteranceIndex: 1))
        #expect(ReaderModel.playhead(utteranceIndex: 3, sourceOffset: 0, in: t) == nil)
        #expect(ReaderModel.playhead(utteranceIndex: -1, sourceOffset: 0, in: t) == nil)
    }

    @Test func seekingByUtteranceResumesFollowing() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        let reader = ReaderModel(player: player)
        reader.suspendFollowing()
        #expect(await reader.seek(toUtterance: 2, sourceOffset: 3))
        #expect(player.coordinator.playhead.utteranceIndex == 2)
        #expect(reader.isFollowing)
        #expect(await reader.seek(toUtterance: 99, sourceOffset: 0) == false)
        #expect(reader.activeHighlight?.utteranceIndex == 2)
    }
```

- [ ] **Step 6: Run to see them fail**

Run: `swift test --filter ReaderModelTests`
Expected: compile failure — no `playhead(utteranceIndex:sourceOffset:in:)`.

- [ ] **Step 7: Extract the utterance seek in `ReaderModel`**

In `Sources/T2SApp/Reader/ReaderModel.swift`, replace the body of `playhead(for:in:)` so it delegates, and add the two new members right after `seek(to:)`:

```swift
    /// Tap on a word the Reader drew itself (spec 2026-09-07 §5): seek to that word's timing inside
    /// its utterance and re-engage following. False when the index is out of range.
    public func seek(toUtterance index: Int, sourceOffset: Int) async -> Bool {
        guard let timeline = player.coordinator.timeline,
              let playhead = Self.playhead(utteranceIndex: index, sourceOffset: sourceOffset, in: timeline)
        else { return false }
        await player.coordinator.seek(to: playhead)
        isFollowing = true
        return true
    }

    /// Where an offset into an utterance's `source` lands: the start of the word whose timing covers
    /// it, or the utterance start when it carries no timings yet. Offsets are clamped into the source.
    public static func playhead(utteranceIndex: Int, sourceOffset: Int, in timeline: Timeline) -> Playhead? {
        guard utteranceIndex >= 0, utteranceIndex < timeline.utteranceCount else { return nil }
        let utterance = timeline[utterance: utteranceIndex]
        guard let timings = utterance.wordTimings, !timings.isEmpty else { return Playhead(utteranceIndex: utteranceIndex) }
        let sourceLength = utterance.source.utf16.count
        let clamped = min(max(0, sourceOffset), max(0, sourceLength - 1))
        let spoken = utterance.normalized.spokenRange(forSource: clamped ..< min(sourceLength, clamped + 1)).lowerBound
        let word = timings.first { $0.spokenRange.contains(spoken) }
            ?? timings.first { $0.spokenRange.lowerBound >= spoken }
        return Playhead(utteranceIndex: utteranceIndex, offset: word?.start ?? 0)
    }
```

and make the old entry point a thin wrapper (Task 4 deletes it):

```swift
    public static func playhead(for hit: SourceHit, in timeline: Timeline) -> Playhead? {
        guard let located = locate(hit, in: timeline) else { return nil }
        guard let sourceOffset = located.sourceOffset else { return Playhead(utteranceIndex: located.index) }
        let raw = Self.rawOffset(forCollapsed: sourceOffset, in: timeline[utterance: located.index].source)
        return playhead(utteranceIndex: located.index, sourceOffset: raw, in: timeline)
    }
```

- [ ] **Step 8: Run everything**

Run: `swift test`
Expected: green — 356 tests plus the 16 new ones. Zero warnings.

- [ ] **Step 9: Commit**

```bash
git add Sources/T2SApp/Reader/ReaderText.swift Sources/T2SApp/Reader/ReaderModel.swift Tests/T2SAppTests/ReaderTextTests.swift Tests/T2SAppTests/ReaderModelTests.swift
git commit -m "Plan 10 Task 1: ReaderText — paragraphs, titles and headings from the timeline with exact offsets; seeks by utterance

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `ReaderTextView` and the page

**Files:**
- Create: `App/T2SReader/Reader/ReaderTypesetter.swift`, `App/T2SReader/Reader/ReaderTextView.swift`
- Modify: `App/T2SReader/Reader/ReaderPage.swift`, `App/T2SReader/AppEnvironment.swift` (remove `publications`), `App/project.yml` (remove the `ReadiumNavigator` and `ReadiumAdapterGCDWebServer` products from the `T2SReaderApp` template's dependencies, lines 66–69)
- Delete: `App/T2SReader/Reader/EPUBReaderView.swift`, `App/T2SReader/Reader/PDFReaderView.swift`, `App/T2SReader/Reader/ReaderScripts.swift`, `App/T2SReader/Reader/PublicationCache.swift`, `App/T2SReader/Reader/ReaderError.swift`

**Interfaces:**
- Consumes: `ReaderText` (Task 1, exact names above), `ReaderModel.seek(toUtterance:sourceOffset:)`, `ReaderModel.activeHighlight` / `isFollowing` / `suspendFollowing()` (existing), `Tokens`, `Spacing`.
- Produces: `struct ReaderTextView: UIViewRepresentable` with `enum Tap { case word(utteranceIndex: Int, sourceOffset: Int), elsewhere }`, initialised as `ReaderTextView(text:textScale:lineHeight:highlight:isFollowing:onTap:onUserScroll:)`; `enum ReaderTypesetter { static func attributedString(for:scale:lineHeight:bylineColor:) -> NSAttributedString }`. Task 3 adds one modifier to `ReaderPage`; nothing else depends on the internals.

- [ ] **Step 1: The typesetter**

Create `App/T2SReader/Reader/ReaderTypesetter.swift`:

```swift
import T2SApp
import UIKit

/// `ReaderText` → one attributed string (spec 2026-09-07 §4): the type roles of spec §2.4.1 by
/// PostScript name, paragraph styles for spacing and line height, no colour except the byline —
/// `textView.textColor` is the dynamic `ink`, so a theme change recolours without a rebuild.
/// Nonisolated and pure so the page can build it off the main actor.
enum ReaderTypesetter {
    static let bodySize: CGFloat = 18

    private static func font(_ name: String, _ size: CGFloat, fallback: UIFont.Weight) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: fallback)
    }

    static func attributedString(for text: ReaderText, scale: Double, lineHeight: Double, bylineColor: UIColor) -> NSAttributedString {
        let body = bodySize * scale
        let result = NSMutableAttributedString()
        for (i, paragraph) in text.paragraphs.enumerated() {
            let font: UIFont
            var tracking: CGFloat = 0
            var before: CGFloat = 0
            var after: CGFloat = 0
            var color: UIColor?
            var multiple = 1.15
            switch paragraph.kind {
            case .documentTitle:
                font = Self.font("InterDisplay-Black", 34, fallback: .black)
                tracking = -0.03 * 34
                after = 8
            case .byline:
                font = Self.font("Inter-Regular", 13, fallback: .regular)
                color = bylineColor
                after = 24
            case .chapterTitle:
                font = Self.font("InterDisplay-ExtraBold", 26, fallback: .heavy)
                tracking = -0.025 * 26
                before = 40
                after = 16
            case .heading(let level):
                font = Self.font("Inter-SemiBold", body * (level <= 3 ? 1.15 : 1.0), fallback: .semibold)
                before = 24
                after = 8
            case .body:
                font = Self.font("Inter-Regular", body, fallback: .regular)
                after = 0.75 * body
                multiple = lineHeight
            }
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = multiple
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = after
            style.hyphenationFactor = 0
            style.alignment = .natural
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
            if tracking != 0 { attributes[.kern] = tracking }
            if let color { attributes[.foregroundColor] = color }
            result.append(NSAttributedString(string: paragraph.text, attributes: attributes))
            if i < text.paragraphs.count - 1 {
                // The separator carries its paragraph's style: TextKit reads it from the terminator too.
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        assert(result.length == text.length, "typeset length \(result.length) ≠ model length \(text.length)")
        return result
    }
}
```

- [ ] **Step 2: The text view**

Create `App/T2SReader/Reader/ReaderTextView.swift`:

```swift
import SwiftUI
import T2SApp
import T2SCore
import UIKit

/// The page's text (spec 2026-09-07 §4): one `UITextView` on TextKit 2 showing the whole document,
/// the paragraph and word tints drawn as rounded rectangles under the glyphs, taps mapped to
/// utterances, and following that keeps the spoken word in the middle third. Takes plain values —
/// SwiftUI re-runs `updateUIView` when any of them changes, which is what makes the Appearance
/// sheet work live. Never touch `layoutManager`: reading it downgrades the view to TextKit 1.
struct ReaderTextView: UIViewRepresentable {
    enum Tap: Equatable {
        case word(utteranceIndex: Int, sourceOffset: Int)
        case elsewhere
    }

    let text: ReaderText
    let textScale: Double
    let lineHeight: Double
    let highlight: HighlightRange?
    let isFollowing: Bool
    let onTap: (Tap) -> Void
    let onUserScroll: () -> Void

    /// Room for the floating top circles and the three-row bottom block (as the old page had).
    static let insets = UIEdgeInsets(top: 72, left: Spacing.margin, bottom: 240, right: Spacing.margin)
    static let cornerRadius: CGFloat = 4

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .clear
        view.textContainerInset = Self.insets
        view.textContainer.lineFragmentPadding = 0
        view.textColor = UIColor(Tokens.ink)
        view.contentInsetAdjustmentBehavior = .never
        view.verticalScrollIndicatorInsets = UIEdgeInsets(top: Self.insets.top, left: 0, bottom: Self.insets.bottom, right: 0)
        view.delegate = context.coordinator
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:))))
        view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak coordinator = context.coordinator] (_: UITextView, _) in
            coordinator?.redrawHighlight()
        }
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        coordinator.onUserScroll = onUserScroll
        coordinator.setText(text, scale: textScale, lineHeight: lineHeight)
        coordinator.setHighlight(highlight, following: isFollowing)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onUserScroll: onUserScroll)
    }

    /// Crosses from the build task to the main actor: the string is immutable once built and
    /// nothing else holds it.
    private struct Typeset: @unchecked Sendable {
        let string: NSAttributedString
    }

    private struct StyleKey: Equatable {
        var documentID: UUID
        var scale: Double
        var lineHeight: Double
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onTap: (Tap) -> Void
        var onUserScroll: () -> Void
        private weak var view: UITextView?
        private var text: ReaderText?
        private var styleKey: StyleKey?
        private var buildTask: Task<Void, Never>?
        private var highlight: HighlightRange?
        private var wasFollowing = true
        private var wordRange: Range<Int>?
        private var tintRange: Range<Int>?
        /// Centre the word without animation as soon as content exists (opening, or a rebuild).
        private var pendingCentre = true
        /// Sits under the text canvas (subview index 0); its bounds origin tracks the content offset so
        /// paths in content coordinates draw in place with no transforms.
        private let overlay = UIView()
        private let tintLayer = CAShapeLayer()
        private let wordLayer = CAShapeLayer()

        init(onTap: @escaping (Tap) -> Void, onUserScroll: @escaping () -> Void) {
            self.onTap = onTap
            self.onUserScroll = onUserScroll
        }

        func attach(_ view: UITextView) {
            self.view = view
            overlay.isUserInteractionEnabled = false
            overlay.backgroundColor = .clear
            overlay.layer.addSublayer(tintLayer)
            overlay.layer.addSublayer(wordLayer)
            view.insertSubview(overlay, at: 0)
            syncOverlay()
        }

        // MARK: Text

        func setText(_ text: ReaderText, scale: Double, lineHeight: Double) {
            let key = StyleKey(documentID: text.documentID, scale: scale, lineHeight: lineHeight)
            guard key != styleKey else { return }
            styleKey = key
            buildTask?.cancel()
            let bylineColor = UIColor(Tokens.ink2)
            buildTask = Task.detached(priority: .userInitiated) { [text] in
                let typeset = Typeset(string: ReaderTypesetter.attributedString(for: text, scale: scale, lineHeight: lineHeight, bylineColor: bylineColor))
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.styleKey == key, let view = self.view else { return }
                    self.text = text
                    view.attributedText = typeset.string
                    view.textColor = UIColor(Tokens.ink)
                    self.pendingCentre = true
                    self.recomputeRanges()
                    self.redrawHighlight()
                    self.centreIfNeeded(animated: false)
                    // TextKit 2 estimates the height of text it has not laid out; the first answer can be off.
                    DispatchQueue.main.async { [weak self] in
                        self?.redrawHighlight()
                        self?.centreIfNeeded(animated: false)
                    }
                }
            }
        }

        // MARK: Highlight

        func setHighlight(_ highlight: HighlightRange?, following: Bool) {
            let changed = highlight != self.highlight
            self.highlight = highlight
            if changed {
                recomputeRanges()
                redrawHighlight()
            }
            if following, changed || !wasFollowing {
                centreIfNeeded(animated: true)
            }
            wasFollowing = following
        }

        private func recomputeRanges() {
            guard let text, let highlight else {
                wordRange = nil
                tintRange = nil
                return
            }
            wordRange = text.wordRange(for: highlight)
            tintRange = text.tintRange(forUtterance: highlight.utteranceIndex)
        }

        func redrawHighlight() {
            guard let view else { return }
            let traits = view.traitCollection
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tintLayer.fillColor = UIColor(Tokens.accentFaint).resolvedColor(with: traits).cgColor
            wordLayer.fillColor = UIColor(Tokens.accentSoft).resolvedColor(with: traits).cgColor
            tintLayer.path = tintRange.map { path(for: rects(for: $0), padding: 0) }
            wordLayer.path = wordRange.map { path(for: rects(for: $0), padding: 1) }
            syncOverlay()
            CATransaction.commit()
        }

        private func path(for rects: [CGRect], padding: CGFloat) -> CGPath? {
            guard !rects.isEmpty else { return nil }
            let path = UIBezierPath()
            for rect in rects {
                path.append(UIBezierPath(roundedRect: rect.insetBy(dx: -padding, dy: 0), cornerRadius: ReaderTextView.cornerRadius))
            }
            return path.cgPath
        }

        /// Per-line rectangles of a flattened-string range, in content coordinates.
        private func rects(for range: Range<Int>) -> [CGRect] {
            guard let view, let layoutManager = view.textLayoutManager,
                  let contentManager = layoutManager.textContentManager,
                  let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.lowerBound),
                  let end = contentManager.location(contentManager.documentRange.location, offsetBy: range.upperBound),
                  let textRange = NSTextRange(location: start, end: end)
            else { return [] }
            layoutManager.ensureLayout(for: textRange)
            let inset = view.textContainerInset
            var rects: [CGRect] = []
            layoutManager.enumerateTextSegments(in: textRange, type: .highlight, options: [.rangeNotRequired]) { _, frame, _, _ in
                rects.append(frame.offsetBy(dx: inset.left, dy: inset.top))
                return true
            }
            return rects
        }

        private func syncOverlay() {
            guard let view else { return }
            overlay.frame = view.bounds
            overlay.bounds = CGRect(origin: view.contentOffset, size: view.bounds.size)
        }

        // MARK: Following

        private func centreIfNeeded(animated: Bool) {
            guard let view, let wordRange else { return }
            let rects = rects(for: wordRange)
            guard let first = rects.first else { return }
            let word = rects.dropFirst().reduce(first) { $0.union($1) }
            let insets = ReaderTextView.insets
            let visibleHeight = max(1, view.bounds.height - insets.top - insets.bottom)
            let visibleTop = view.contentOffset.y + insets.top
            let mid = word.midY
            if !pendingCentre, mid >= visibleTop + visibleHeight / 3, mid <= visibleTop + 2 * visibleHeight / 3 { return }
            pendingCentre = false
            let maxOffset = max(0, view.contentSize.height - view.bounds.height)
            let target = min(maxOffset, max(0, mid - insets.top - visibleHeight / 2))
            view.setContentOffset(CGPoint(x: 0, y: target), animated: animated)
        }

        // MARK: Taps

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view, let text, let layoutManager = view.textLayoutManager,
                  let contentManager = layoutManager.textContentManager
            else { onTap(.elsewhere); return }
            var point = gesture.location(in: view)
            point.x -= view.textContainerInset.left
            point.y -= view.textContainerInset.top
            guard let fragment = layoutManager.textLayoutFragment(for: point),
                  let element = fragment.textElement, let elementRange = element.elementRange
            else { onTap(.elsewhere); return }
            let local = CGPoint(x: point.x - fragment.layoutFragmentFrame.minX, y: point.y - fragment.layoutFragmentFrame.minY)
            guard let line = fragment.textLineFragments.first(where: { $0.typographicBounds.insetBy(dx: -8, dy: -8).contains(local) })
            else { onTap(.elsewhere); return }
            // Line-fragment indices are relative to the text element (the paragraph).
            let elementStart = contentManager.offset(from: contentManager.documentRange.location, to: elementRange.location)
            let index = line.characterIndex(for: CGPoint(x: local.x - line.typographicBounds.minX, y: local.y - line.typographicBounds.minY))
            let clamped = min(max(index, line.characterRange.location), line.characterRange.location + max(0, line.characterRange.length - 1))
            if let hit = text.hit(at: elementStart + clamped) {
                onTap(.word(utteranceIndex: hit.utteranceIndex, sourceOffset: hit.sourceOffset))
            } else {
                onTap(.elsewhere)
            }
        }

        // MARK: UIScrollViewDelegate

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            onUserScroll()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            syncOverlay()
        }
    }
}
```

Two things to verify against the SDK while writing, and record in the report: (a) `NSTextLineFragment.characterIndex(for:)` takes a point in the line fragment's coordinate space and returns an index relative to the text element, the same space as `characterRange` (Apple's header: "Returns the character index for point in the line fragment coordinate system"); if the simulator shows taps landing one line off, the local point must not subtract `typographicBounds.minY` — try both and keep the one that hits. (b) `UITextView(usingTextLayoutManager:)` exists on iOS 16+; the deployment target is 18.

- [ ] **Step 3: The page**

Rewrite the top of `App/T2SReader/Reader/ReaderPage.swift`. Imports become `SwiftUI`, `T2SApp`, `T2SCore`, `T2SStore` (drop `ReadiumShared`). State: replace `@State private var publication: Publication?` and `@State private var timeline: Timeline?` with `@State private var text: ReaderText?`. The `ZStack`'s first branch becomes:

```swift
            if let text {
                ReaderTextView(
                    text: text,
                    textScale: env.preferences.textScale,
                    lineHeight: env.preferences.lineHeight,
                    highlight: reader.activeHighlight,
                    isFollowing: reader.isFollowing,
                    onTap: handleTap,
                    onUserScroll: { reader.suspendFollowing() }
                )
                .ignoresSafeArea()
            } else if let error {
                Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive).padding(Spacing.margin)
            } else {
                ProgressView().tint(Tokens.ink)
            }
```

Replace `handleTap`, `handleReaderError`, `releasePublication` and `open()` with:

```swift
    private func handleTap(_ tap: ReaderTextView.Tap) {
        Task {
            if case .word(let index, let offset) = tap, await env.readerModel.seek(toUtterance: index, sourceOffset: offset) {
                return
            }
            withAnimation { chromeVisible.toggle() }
        }
    }

    /// Loads and starts the requested document when necessary, then draws its timeline's text
    /// (spec 2026-09-07 §5). The model is built off the main actor; a 24-hour book is about a
    /// million characters.
    private func open() async {
        if env.player.current?.id != summary.id {
            await env.player.load(summary, play: true)
        }
        guard let timeline = env.player.coordinator.timeline, timeline.utteranceCount > 0 else {
            error = "This document has no readable text."
            return
        }
        let document = summary.document
        text = await Task.detached(priority: .userInitiated) {
            ReaderText(documentID: document.id, timeline: timeline, title: document.title, author: document.author)
        }.value
    }
```

Everything else on the page (top bar, bottom bar, tool row, sheets, `resolveVoiceName`) stays as it is. The `Back to current` pill already calls `reader.resumeFollowing()`, which flips `isFollowing` and makes the coordinator re-centre.

- [ ] **Step 4: Remove Readium from the page's world**

Delete the five files listed above. In `App/T2SReader/AppEnvironment.swift` delete the line `let publications = PublicationCache()`. In `App/project.yml`, under the `T2SReaderApp` template's `dependencies`, delete the two entries:

```yaml
      - package: Readium
        product: ReadiumNavigator
      - package: Readium
        product: ReadiumAdapterGCDWebServer
```

(`ReadiumShared` and `ReadiumStreamer` stay: `T2SReadium` needs them for import.) Then grep the App for any remaining `ReadiumNavigator`, `GCDHTTPServer`, `SourceHit`, `publications` reference — there must be none except `SourceHit` in the package (Task 4).

- [ ] **Step 5: Build and test**

Run: `swift test` — green (nothing in the packages changed except what Task 1 added).
Run: `scripts/build-app.sh` — `** BUILD SUCCEEDED **` with no new warnings. Fix Swift 6 isolation complaints here rather than with `@preconcurrency`: the coordinator is `@MainActor`, the typesetter is nonisolated and pure, the crossing is the `Typeset` box.

- [ ] **Step 6: Look at it (silently)**

```bash
U=B4403B3A-10A8-43A3-9B61-FD2439ADFEA5            # iPhone 16 Pro; `xcrun simctl list devices available` if it moved
S=/private/tmp/claude-501/-Users-atharvanayak-Developer-t2s-reader/80ef6b96-655f-4f9d-8aea-9b02186a3b78/scratchpad
xcrun simctl boot $U; xcrun simctl bootstatus $U -b
xcrun simctl install $U .build/DerivedData-App/Build/Products/Debug-iphonesimulator/T2SReader.app
SIMCTL_CHILD_T2S_SILENT=1 xcrun simctl launch $U com.t2s.reader
C=$(xcrun simctl get_app_container $U com.t2s.reader data)
cp .build/DerivedData-App/SourcePackages/checkouts/swift-toolkit/Tests/Publications/Publications/childrens-literature.epub "$C/Documents/Inbox/"
xcrun simctl openurl $U "file://$C/Documents/Inbox/childrens-literature.epub"     # imports and opens the Reader, playing muted
sleep 8; xcrun simctl io $U screenshot "$S/plan10-task2-light.png"
```

The file URL route imports a fresh copy each time (fine in the simulator). Look at the screenshot: off-white page, "Children's Literature" in the Page title role at the top, a chapter title, body in Inter with a blank line between paragraphs and no indent, the paragraph under the playhead tinted faint orange with the spoken word darker, the chrome from Plan 9 intact, text fading under the top circles and the bottom block. Then the big text:

```bash
xcrun simctl terminate $U com.t2s.reader
xcrun simctl spawn $U defaults write com.t2s.reader reader.textScale -float 1.6
SIMCTL_CHILD_T2S_SILENT=1 xcrun simctl launch $U com.t2s.reader
cp .build/DerivedData-App/SourcePackages/checkouts/swift-toolkit/Tests/Publications/Publications/childrens-literature.epub "$C/Documents/Inbox/"
xcrun simctl openurl $U "file://$C/Documents/Inbox/childrens-literature.epub"
sleep 8; xcrun simctl io $U screenshot "$S/plan10-task2-scale16.png"
xcrun simctl spawn $U defaults delete com.t2s.reader reader.textScale
xcrun simctl terminate $U com.t2s.reader; xcrun simctl shutdown $U
```

Copy both screenshots into the ledger directory as `task-2-light.png` and `task-2-scale16.png`. If the word tint sits on the wrong line or the paragraph tint is empty, the rectangles are off by the container inset — check `rects(for:)` adds `textContainerInset` once and the overlay's `bounds.origin` equals `contentOffset`.

- [ ] **Step 7: Commit**

```bash
git add -A App/T2SReader/Reader App/T2SReader/AppEnvironment.swift App/project.yml
git commit -m "Plan 10 Task 2: the Reader draws its own text — ReaderTextView on TextKit 2 with paragraph and word tints, taps and following; Readium's navigators and the web server leave the app

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Theme, app-wide

**Files:**
- Create: `App/T2SReader/Design/Theme.swift`
- Modify: `App/T2SReader/Root/RootPager.swift` (the `.background(Tokens.ground.ignoresSafeArea())` line), `App/T2SReader/Reader/ReaderPage.swift` (the outer `ZStack`), `App/T2SReader/Preferences/AppearanceSheet.swift` (the "Theme" label), `App/T2SReader/Preferences/PreferencesPage.swift` (line 67, the row subtitle)

**Interfaces:**
- Consumes: `ReaderTheme` (`T2SApp`), `AppEnvironment.preferences`.
- Produces: `extension ReaderTheme { var colorScheme: ColorScheme? }`, `extension View { func appTheme() -> some View }`.

- [ ] **Step 1: The mapping and the modifier**

Create `App/T2SReader/Design/Theme.swift`:

```swift
import SwiftUI
import T2SApp

/// The theme choice applies to the whole app (spec 2026-09-07 §6). `system` means no preference.
extension ReaderTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Applied to the root pager and to the Reader page (a full-screen cover is its own presentation),
/// so every screen, sheet and the Reader's UIKit text view follow one choice.
private struct AppTheme: ViewModifier {
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.preferredColorScheme(env.preferences.theme.colorScheme)
    }
}

extension View {
    func appTheme() -> some View { modifier(AppTheme()) }
}
```

- [ ] **Step 2: Apply it**

In `RootPager.body`, after `.background(Tokens.ground.ignoresSafeArea())`, add `.appTheme()`. In `ReaderPage.body`, add `.appTheme()` to the outer `ZStack` after `.task(id: summary.id) { await open() }`. In `AppearanceSheet`, change `Text("Theme")` to `Text("Theme · applies to the whole app")`. In `PreferencesPage`, change the row subtitle to `"Text size, line height, theme for the whole app"`.

- [ ] **Step 3: Build and look**

Run: `scripts/build-app.sh` — `** BUILD SUCCEEDED **`.

Then, with the simulator in light mode:

```bash
U=B4403B3A-10A8-43A3-9B61-FD2439ADFEA5
S=/private/tmp/claude-501/-Users-atharvanayak-Developer-t2s-reader/80ef6b96-655f-4f9d-8aea-9b02186a3b78/scratchpad
xcrun simctl boot $U; xcrun simctl bootstatus $U -b; xcrun simctl ui $U appearance light
xcrun simctl install $U .build/DerivedData-App/Build/Products/Debug-iphonesimulator/T2SReader.app
xcrun simctl spawn $U defaults write com.t2s.reader reader.theme -string dark
SIMCTL_CHILD_T2S_SILENT=1 xcrun simctl launch $U com.t2s.reader
sleep 3; xcrun simctl io $U screenshot "$S/plan10-task3-queue-dark.png"
C=$(xcrun simctl get_app_container $U com.t2s.reader data)
cp .build/DerivedData-App/SourcePackages/checkouts/swift-toolkit/Tests/Publications/Publications/childrens-literature.epub "$C/Documents/Inbox/"
xcrun simctl openurl $U "file://$C/Documents/Inbox/childrens-literature.epub"
sleep 8; xcrun simctl io $U screenshot "$S/plan10-task3-reader-dark.png"
xcrun simctl spawn $U defaults delete com.t2s.reader reader.theme
xcrun simctl terminate $U com.t2s.reader; xcrun simctl shutdown $U
```

Both screenshots must be dark throughout: the Queue page (ground `#101010`, ink `#F2F2F2`) and the Reader with dark chrome, dark page and the text in light ink. If the Reader (a full-screen cover) came out light while the Queue is dark, the modifier on `ReaderPage` is missing; if a sheet from the Reader is light, add `.appTheme()` to that sheet's content too and note it in the report. Copy both into the ledger as `task-3-queue-dark.png`, `task-3-reader-dark.png`.

- [ ] **Step 4: Commit**

```bash
git add App/T2SReader/Design/Theme.swift App/T2SReader/Root/RootPager.swift App/T2SReader/Reader/ReaderPage.swift App/T2SReader/Preferences/AppearanceSheet.swift App/T2SReader/Preferences/PreferencesPage.swift
git commit -m "Plan 10 Task 3: the theme applies to the whole app

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Retire the tap-matching path

**Files:**
- Delete: `Sources/T2SApp/Reader/SourceHit.swift`
- Modify: `Sources/T2SApp/Reader/ReaderModel.swift`, `Sources/T2SCore/Timeline/Highlighter.swift`, `Tests/T2SAppTests/ReaderModelTests.swift`, `Tests/T2SCoreTests/HighlighterTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ReaderModel` keeps `player`, `isFollowing`, `activeHighlight`, `isCatchingUp`, `chapterTitle`, `suspendFollowing()`, `resumeFollowing()`, `seek(toUtterance:sourceOffset:)`, `playhead(utteranceIndex:sourceOffset:in:)` and nothing else.

- [ ] **Step 1: Delete the tests of what goes**

In `Tests/T2SAppTests/ReaderModelTests.swift` remove `resolvesTheUtteranceUnderTheTap`, `whitespaceIsNormalizedOnBothSides`, `unknownTextOrResourceYieldsNil`, `aTapInTheSecondSentenceSeeksToThatWordsStart`, `aTapInTheFirstWordSeeksToTheStart`, `collapsedOffsetsMapOntoTheRawSource`, `withoutWordTimingsATapSeeksToTheUtteranceStart`, `pdfTapsResolveByPage`, and `seekingAndFollowing` (Task 1's `seekingByUtteranceResumesFollowing` covers it; keep its `chapterTitle` assertions by moving them into that test: `#expect(reader.chapterTitle == "Chapter 1")` before the seek and `== "Chapter 2"` after). Keep the fixtures the Task 1 tests use. In `Tests/T2SCoreTests/HighlighterTests.swift` remove `sentenceCoversWholeUtteranceSource` and `sentenceNilPastEnd` (and `twoUtterances()` if nothing else uses it).

- [ ] **Step 2: Run to see the build break where the code is now unreferenced**

Run: `swift test`
Expected: green (deleting tests breaks nothing) — this step exists so the next one is the only red.

- [ ] **Step 3: Delete the code**

- Delete `Sources/T2SApp/Reader/SourceHit.swift`.
- In `ReaderModel.swift` delete `activeSentence`, `seek(to:)`, `playhead(for:in:)`, `normalized(_:)`, `utteranceIndex(for:in:)`, `locate(_:in:)`, `rawOffset(forCollapsed:in:)`, `pageCount(from:)`. Update the type comment: "a tap on a word seeks there" now points at `seek(toUtterance:sourceOffset:)`.
- In `Highlighter.swift` delete `sentence(at:in:)`.
- `grep -rn "SourceHit\|activeSentence\|Highlighter.sentence\|rawOffset" Sources App Tests` must find nothing.

- [ ] **Step 4: Test and build**

Run: `swift test` — green, zero warnings. Run: `scripts/build-app.sh` — `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A Sources/T2SApp/Reader Sources/T2SCore/Timeline/Highlighter.swift Tests/T2SAppTests/ReaderModelTests.swift Tests/T2SCoreTests/HighlighterTests.swift
git commit -m "Plan 10 Task 4: retire the tap-matching path — the Reader knows the utterance it drew

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (§2.4.2 `accentFaint` row, §2.4.5 "Reader page" paragraph, §6.1, §11 changelog), `README.md` (the `Packages/T2SReadium/` and `App/` layout lines), `docs/HANDOFF.md` (a new "Resume here (2026-09-07) — Plan 10" section above the 2026-09-06 one; the Branches table's `dev` row), `docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md` (Plan 10 entry)

- [ ] **Step 1: The main spec, rev 11**

§2.4.2: the `accentFaint` row's "Used for" becomes `read-along paragraph tint behind the word (rev 11; was the sentence)`.

§2.4.5, replace the whole "**Reader page (rev 10, after ElevenReader).**" paragraph with:

> **Reader page (rev 11, after ElevenReader).** Separate full-screen page. Entered from a Queue row title, a chapter in the book sheet, or `Read along` in the player. No bar: floating 36pt `surface` circles over a `ground` fade — back top-left; bookmark and overflow (Chapters, Bookmarks, Appearance, Change voice, Sleep timer, Details, Render whole document) top-right. The body is our own text, drawn from the timeline, never the document's layout (design `2026-09-07-native-readalong-design.md`): one column on `ground`, 24pt margins; the document title in the Page title role and a byline in Meta/`ink2`; chapter titles in the Player title role (a chapter's own first block that says its title is the title); headings in Inter SemiBold when the block's selector names an h1–h6; body in Inter 18pt × text scale, line height × the reader's setting, no indent, a paragraph gap of 0.75 × the body size; images, tables and footnotes are not drawn. The paragraph under the playhead is tinted `accentFaint` and the spoken word `accentSoft` as 4pt-rounded rectangles per line; on a PDF the tinted unit is the utterance. Auto-scroll keeps the word in the middle third (only a word change scrolls); a drag suspends it and shows `Back to current`. Tap a word → seek to that word. Bottom block pinned over a `ground` fade: a 3pt progress bar whose segments show the render frontier (`ink` rendered, `ink3` not) with a knob, elapsed and total in monospaced beneath; then sleep timer · back 15 · play · forward 30 · speed; then appearance · a voice chip naming the routed voice (→ change voice) · contents. During underrun (§3.6) the play glyph becomes a ring and a caption reads `catching up…`. Text size and line height apply live; theme is app-wide (§2.4.2). The Player sheet keeps its tick scrubber.

§6.1, replace the body with:

> **PDF read-along shows the extracted text, not the page image** (rev 11). The Reader draws every document's timeline text itself, so PDFs get the same word-level tint as EPUBs; what they lose is the page's layout. Running headers and footers are filtered at import (§4.1 rule 2).

§11, add at the top:

> **rev 11 (2026-09-07)** — Plan 10: the native read-along.
>
> - **§2.4.5** the Reader draws its own text from the timeline (paragraphs, chapter titles, headings, paragraph and word tints, taps, following) — Readium's navigators leave the app; the design is `2026-09-07-native-readalong-design.md`. **§2.4.2** `accentFaint` tints the paragraph. **§6.1** PDFs read along at the word, as text.
> - Theme (System / Light / Dark) applies to the whole app, not the Reader alone.
> - Why: the owner's 2026-09-07 report — a black Readium page under light chrome (the Reader-only theme), and "it looks like pages from a PDF, not our UI; ElevenReader shows the text as part of its UI".

- [ ] **Step 2: README and roadmap**

README: the `Packages/T2SReadium/` line becomes "iOS-only package wrapping the Readium toolkit (EPUB import, positions, Locator mapping) …"; in the `App/` description, after "SwiftUI views, composition root", add "; `T2SReader/Reader/` draws the read-along text itself (`ReaderTextView`, TextKit 2)". Roadmap: add a Plan 10 entry after Plan 9 in the same style as its neighbours: "**Plan 10 — native read-along + app-wide theme** (2026-09-07): the Reader draws the timeline's text itself, after ElevenReader; Readium stays for import; theme applies everywhere."

- [ ] **Step 3: HANDOFF**

Add a section "## Resume here (2026-09-07) — Plan 10" above the 2026-09-06 one, in the same voice, covering: what the owner reported and what was reproduced (the Reader-only theme; the simulator recipe: `defaults write com.t2s.reader reader.theme -string dark`); what Plan 10 landed per task (the file names above); the no-audio rule (repeat it); the phone checklist for the owner — install with scheme **Phone**, open a book: the page is off-white in light mode with the title at the top and the paragraph and word tints; Appearance → Text size and Line height change the page while it is open; Theme → Dark darkens the whole app including the Queue; a tap on a word starts there; a drag stops following and `Back to current` returns; the contents sheet jumps chapters; a PDF reads along at the word — plus the two things the Mac could not verify (taps, drags). Update the `_Last updated_` line and the Branches table's `dev` row (test counts from the final `swift test`).

- [ ] **Step 4: Commit**

```bash
git add docs README.md
git commit -m "Plan 10 Task 5: docs — spec rev 11, HANDOFF resume section with the phone checklist, README and roadmap

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
