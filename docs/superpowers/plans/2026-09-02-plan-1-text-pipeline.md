# Plan 1: Text Pipeline (`T2SCore`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the headless text pipeline as a pure-Swift library: domain model, normalizer with span mapping, sentence segmenter, two-phase timeline, per-chapter codec, persisted-position resolution, and playhead-to-source highlight projection, all tested with `swift test` on macOS.

**Architecture:** One SPM target `T2SCore` with no dependencies beyond Foundation and NaturalLanguage. Text flows `SourceBlock → Segmenter → [Utterance]` where each utterance carries `source`, normalized `spoken`, and `[SpanMap]` between them. `Timeline` holds chapters of utterances; `TimelineCodec` packs a chapter into one blob; `PositionResolver` converts the persisted `Position` to the runtime `Playhead` and back; `Highlighter` projects a playhead to a source range. Nothing here touches Readium, audio, or SwiftData, which arrive in Plans 2 and 3 against these types.

**Tech Stack:** Swift 6 (language mode 6), Swift Package Manager, Swift Testing (`import Testing`), Foundation (`NSRegularExpression`, `Compression`), NaturalLanguage (`NLTokenizer`). macOS 15 for tests, iOS 18 deployment.

**Spec:** `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (rev 4). Sections §3.1, §3.2, §3.3, §3.7.3–§3.7.5, §4, §4.1, §5 (blob encoding), §6 (position fallback), §8, §9 steps 3–4.

## Global Constraints

- All persisted ranges are **integer UTF-16 offsets**; `String.Index` is never stored (spec §3.1).
- `Position` is the only persisted location type; `(utteranceIndex, offset)` is runtime-only (spec §3.2).
- Everything persisted carries a version: `schemaVersion`, `segmenterVersion`, `normalizerVersion` (spec §3.7.4). Bump a version whenever the output of that stage changes.
- Every normalizer rule consumes and produces `NormalizedText`; rules never touch strings directly (spec §4.1). Rule order is fixed: hyphenation, citations, abbreviations, numbers, URLs, whitespace, pronunciation dictionary.
- **Every spoken word range must project back to a non-empty source range** except pure insertions (spec §8). Tests assert this for every rule.
- Position resolution failure falls back to chapter start, never document start (spec §6).
- No GPL, LGPL, or AGPL dependency; `scripts/check-licenses.sh` runs in CI from Task 1 (spec §3.7.5).
- Test framework is Swift Testing. Run a suite with `swift test --filter <SuiteName>`.
- Commit after every task with the message given in the task.

---

### Task 1: Package scaffold, CI, and license guard

**Files:**
- Create: `Package.swift`
- Create: `Sources/T2SCore/Versions.swift`
- Create: `Tests/T2SCoreTests/VersionsTests.swift`
- Create: `scripts/check-licenses.sh`
- Create: `.github/workflows/ci.yml`
- Create: `.gitignore`

**Interfaces:**
- Produces: `public enum Versions { static let schema: Int; static let segmenter: Int; static let normalizer: Int }`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/T2SCoreTests/VersionsTests.swift
import Testing
@testable import T2SCore

@Suite struct VersionsTests {
    @Test func versionsStartAtOne() {
        #expect(Versions.schema == 1)
        #expect(Versions.segmenter == 1)
        #expect(Versions.normalizer == 1)
    }
}
```

- [ ] **Step 2: Write the package manifest**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "T2S",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "T2SCore", targets: ["T2SCore"]),
    ],
    targets: [
        .target(name: "T2SCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "T2SCoreTests",
            dependencies: ["T2SCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

Create an empty `Tests/T2SCoreTests/Fixtures/.gitkeep` so the resource directory exists.

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter VersionsTests`
Expected: FAIL to compile with `error: cannot find 'Versions' in scope`.

- [ ] **Step 4: Write the implementation**

```swift
// Sources/T2SCore/Versions.swift
/// Bump a version whenever the output of that stage changes shape or content.
/// Persisted timelines record all three; a mismatch forces re-derivation (spec §3.7.4).
public enum Versions {
    public static let schema = 1
    public static let segmenter = 1
    public static let normalizer = 1
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter VersionsTests`
Expected: `✔ Test versionsStartAtOne() passed`.

- [ ] **Step 6: Add the license guard and CI**

```bash
#!/usr/bin/env bash
# scripts/check-licenses.sh — fails if any checked-out SPM dependency is copyleft.
set -euo pipefail
cd "$(dirname "$0")/.."
swift package resolve >/dev/null
shopt -s nullglob
status=0
for dir in .build/checkouts/*/; do
  name=$(basename "$dir")
  # Glob into an array: with nullglob an unmatched pattern yields an empty array.
  # (A bare `ls` with no arguments would list the cwd and mask a missing file.)
  files=( "$dir"LICENSE* "$dir"COPYING* )
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "NO LICENSE FILE: $name"; status=1; continue
  fi
  file=${files[0]}
  if grep -qiE 'GNU (AFFERO |LESSER )?GENERAL PUBLIC LICENSE' "$file"; then
    echo "COPYLEFT: $name ($file)"; status=1
  else
    echo "ok: $name"
  fi
done
exit $status
```

`chmod +x scripts/check-licenses.sh`.

```yaml
# .github/workflows/ci.yml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: sudo xcode-select -s /Applications/Xcode_16.2.app
      - run: swift test
      - run: scripts/check-licenses.sh
```

```
# .gitignore
.build/
.swiftpm/
*.xcodeproj/xcuserdata/
DerivedData/
```

Run: `scripts/check-licenses.sh`
Expected: exits 0 with no output lines (no dependencies yet).

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests scripts .github .gitignore
git commit -m "Scaffold T2SCore package with CI and license guard"
```

---

### Task 2: Domain model

**Files:**
- Create: `Sources/T2SCore/Model/Position.swift`
- Create: `Sources/T2SCore/Model/Playhead.swift`
- Create: `Sources/T2SCore/Model/Utterance.swift`
- Create: `Sources/T2SCore/Model/Timeline.swift`
- Create: `Sources/T2SCore/Model/Document.swift`
- Create: `Tests/T2SCoreTests/Support/Fixtures.swift`
- Create: `Tests/T2SCoreTests/TimelineTests.swift`

**Interfaces:**
- Produces:
  - `struct Position { resourceHref: String; progression: Double; charOffset: Int?; cssSelector: String? }`
  - `struct Playhead { utteranceIndex: Int; offset: TimeInterval }` (seconds into the utterance at 1x)
  - `struct SpanMap { sourceRange: Range<Int>; spokenRange: Range<Int>; var isLinear: Bool }`
  - `struct WordTiming { spokenRange: Range<Int>; start: TimeInterval; end: TimeInterval }`
  - `enum UtteranceDuration { case estimated(TimeInterval), actual(TimeInterval); var seconds; var isActual }`
  - `struct Utterance { position; source; spoken; spans; audioRef: String?; duration; wordTimings: [WordTiming]? }`
  - `struct Chapter { title; position; utterances: [Utterance] }`
  - `struct Timeline { schemaVersion; segmenterVersion; normalizerVersion; chapters; utteranceCount; utteranceRange(ofChapter:); chapterIndex(forUtterance:); subscript(utterance:); startTime(ofUtterance:); totalDuration; isFullyRendered }`
  - `struct Document { id: UUID; title; author; sourceType: SourceType; sourceURL; coverImagePath; addedAt; voiceID; resumePosition: Position? }`
  - Test helper `makeUtterance(_:seconds:href:charOffset:)` and `makeTimeline(_:)`.

`audioRef` is the render key string, not a URL: the app container path changes between launches, so an absolute URL would go stale. `AudioStore` (Plan 2) maps a key to a file.

- [ ] **Step 1: Write the test helper and failing tests**

```swift
// Tests/T2SCoreTests/Support/Fixtures.swift
import Foundation
@testable import T2SCore

func makeUtterance(_ text: String, seconds: TimeInterval = 1, href: String = "ch1.xhtml",
                   charOffset: Int = 0, progression: Double = 0) -> Utterance {
    let n = text.utf16.count
    return Utterance(
        position: Position(resourceHref: href, progression: progression, charOffset: charOffset),
        source: text, spoken: text,
        spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)],
        audioRef: nil, duration: .estimated(seconds), wordTimings: nil
    )
}

func makeTimeline(_ chapters: [[Utterance]]) -> Timeline {
    Timeline(chapters: chapters.enumerated().map { i, us in
        Chapter(title: "Chapter \(i + 1)",
                position: us.first?.position ?? Position(resourceHref: "ch\(i + 1).xhtml", progression: 0),
                utterances: us)
    })
}
```

```swift
// Tests/T2SCoreTests/TimelineTests.swift
import Testing
@testable import T2SCore

@Suite struct TimelineTests {
    let t = makeTimeline([
        [makeUtterance("a", seconds: 1), makeUtterance("b", seconds: 2)],
        [makeUtterance("c", seconds: 3, href: "ch2.xhtml"), makeUtterance("d", seconds: 4, href: "ch2.xhtml"), makeUtterance("e", seconds: 5, href: "ch2.xhtml")],
        [makeUtterance("f", seconds: 6, href: "ch3.xhtml")],
    ])

    @Test func countsAndRanges() {
        #expect(t.utteranceCount == 6)
        #expect(t.utteranceRange(ofChapter: 0) == 0..<2)
        #expect(t.utteranceRange(ofChapter: 1) == 2..<5)
        #expect(t.utteranceRange(ofChapter: 2) == 5..<6)
    }

    @Test func chapterLookup() {
        #expect(t.chapterIndex(forUtterance: 0) == 0)
        #expect(t.chapterIndex(forUtterance: 4) == 1)
        #expect(t.chapterIndex(forUtterance: 5) == 2)
        #expect(t.chapterIndex(forUtterance: 6) == nil)
    }

    @Test func subscriptGetAndSet() {
        var t = t
        #expect(t[utterance: 3].source == "d")
        t[utterance: 3].duration = .actual(4.5)
        #expect(t[utterance: 3].duration.isActual)
        #expect(t.chapters[1].utterances[1].duration.seconds == 4.5)
    }

    @Test func derivedTimes() {
        #expect(t.startTime(ofUtterance: 0) == 0)
        #expect(t.startTime(ofUtterance: 2) == 3)
        #expect(t.startTime(ofUtterance: 5) == 15)
        #expect(t.startTime(ofUtterance: 6) == 21)     // end of timeline
        #expect(t.totalDuration == 21)
        #expect(t.isFullyRendered == false)
    }

    @Test func versionsDefaultFromVersions() {
        #expect(t.schemaVersion == Versions.schema)
        #expect(t.segmenterVersion == Versions.segmenter)
        #expect(t.normalizerVersion == Versions.normalizer)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter TimelineTests`
Expected: FAIL to compile, `cannot find 'Timeline' in scope`.

- [ ] **Step 3: Write the model**

```swift
// Sources/T2SCore/Model/Position.swift
/// Persisted anchor into the source document. Never a Readium type (spec §3.7.2).
public struct Position: Codable, Hashable, Sendable {
    public var resourceHref: String
    /// 0…1 within the resource.
    public var progression: Double
    /// UTF-16 offset into the resource's extracted text, when known.
    public var charOffset: Int?
    public var cssSelector: String?

    public init(resourceHref: String, progression: Double, charOffset: Int? = nil, cssSelector: String? = nil) {
        self.resourceHref = resourceHref
        self.progression = progression
        self.charOffset = charOffset
        self.cssSelector = cssSelector
    }
}
```

```swift
// Sources/T2SCore/Model/Playhead.swift
import Foundation

/// Runtime-only position (spec §3.2). Never persisted.
public struct Playhead: Hashable, Sendable {
    public var utteranceIndex: Int
    /// Seconds into the utterance at 1x.
    public var offset: TimeInterval

    public init(utteranceIndex: Int, offset: TimeInterval = 0) {
        self.utteranceIndex = utteranceIndex
        self.offset = offset
    }
}
```

```swift
// Sources/T2SCore/Model/Utterance.swift
import Foundation

public struct SpanMap: Codable, Hashable, Sendable {
    public var sourceRange: Range<Int>
    public var spokenRange: Range<Int>

    public init(sourceRange: Range<Int>, spokenRange: Range<Int>) {
        self.sourceRange = sourceRange
        self.spokenRange = spokenRange
    }

    /// A linear span maps character-for-character and may be sliced. Anything else is atomic.
    /// Equal length is a heuristic: a same-length replacement is treated as linear, which is
    /// harmless because projection unions whole words anyway.
    public var isLinear: Bool { sourceRange.count == spokenRange.count }
}

public struct WordTiming: Codable, Hashable, Sendable {
    public var spokenRange: Range<Int>
    public var start: TimeInterval
    public var end: TimeInterval

    public init(spokenRange: Range<Int>, start: TimeInterval, end: TimeInterval) {
        self.spokenRange = spokenRange
        self.start = start
        self.end = end
    }
}

/// Always at 1x (spec §3.1).
public enum UtteranceDuration: Codable, Hashable, Sendable {
    case estimated(TimeInterval)
    case actual(TimeInterval)

    public var seconds: TimeInterval {
        switch self {
        case .estimated(let s), .actual(let s): return s
        }
    }

    public var isActual: Bool {
        if case .actual = self { return true }
        return false
    }
}

public struct Utterance: Codable, Hashable, Sendable {
    public var position: Position
    public var source: String
    public var spoken: String
    public var spans: [SpanMap]
    /// Render key of the cached audio file (spec §5), nil until rendered.
    public var audioRef: String?
    public var duration: UtteranceDuration
    public var wordTimings: [WordTiming]?

    public init(position: Position, source: String, spoken: String, spans: [SpanMap],
                audioRef: String? = nil, duration: UtteranceDuration, wordTimings: [WordTiming]? = nil) {
        self.position = position
        self.source = source
        self.spoken = spoken
        self.spans = spans
        self.audioRef = audioRef
        self.duration = duration
        self.wordTimings = wordTimings
    }
}
```

```swift
// Sources/T2SCore/Model/Timeline.swift
import Foundation

public struct Chapter: Codable, Hashable, Sendable {
    public var title: String
    public var position: Position
    public var utterances: [Utterance]

    public init(title: String, position: Position, utterances: [Utterance]) {
        self.title = title
        self.position = position
        self.utterances = utterances
    }
}

public struct Timeline: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var segmenterVersion: Int
    public var normalizerVersion: Int
    public var chapters: [Chapter]

    public init(chapters: [Chapter],
                schemaVersion: Int = Versions.schema,
                segmenterVersion: Int = Versions.segmenter,
                normalizerVersion: Int = Versions.normalizer) {
        self.chapters = chapters
        self.schemaVersion = schemaVersion
        self.segmenterVersion = segmenterVersion
        self.normalizerVersion = normalizerVersion
    }

    public var utteranceCount: Int { chapters.reduce(0) { $0 + $1.utterances.count } }

    /// Precondition: `c` is a valid chapter index.
    public func utteranceRange(ofChapter c: Int) -> Range<Int> {
        precondition(chapters.indices.contains(c), "chapter \(c) out of range (\(chapters.count))")
        let start = chapters[..<c].reduce(0) { $0 + $1.utterances.count }
        return start..<(start + chapters[c].utterances.count)
    }

    public func chapterIndex(forUtterance i: Int) -> Int? {
        guard i >= 0 else { return nil }
        var start = 0
        for (c, ch) in chapters.enumerated() {
            if i < start + ch.utterances.count { return c }
            start += ch.utterances.count
        }
        return nil
    }

    private func location(ofUtterance i: Int) -> (chapter: Int, local: Int) {
        guard let c = chapterIndex(forUtterance: i) else {
            preconditionFailure("utterance \(i) out of range (\(utteranceCount))")
        }
        return (c, i - utteranceRange(ofChapter: c).lowerBound)
    }

    public subscript(utterance i: Int) -> Utterance {
        get { let l = location(ofUtterance: i); return chapters[l.chapter].utterances[l.local] }
        set { let l = location(ofUtterance: i); chapters[l.chapter].utterances[l.local] = newValue }
    }

    /// Derived, display-only (spec §3.2): sum of preceding durations at 1x.
    /// `i == utteranceCount` is allowed and yields the total duration (the end of the timeline).
    public func startTime(ofUtterance i: Int) -> TimeInterval {
        precondition(i >= 0 && i <= utteranceCount, "utterance \(i) out of range (\(utteranceCount))")
        var t: TimeInterval = 0
        var n = 0
        for ch in chapters {
            for u in ch.utterances {
                if n == i { return t }
                t += u.duration.seconds
                n += 1
            }
        }
        return t
    }

    public var totalDuration: TimeInterval {
        chapters.reduce(0) { $0 + $1.utterances.reduce(0) { $0 + $1.duration.seconds } }
    }

    public var isFullyRendered: Bool {
        chapters.allSatisfy { $0.utterances.allSatisfy { $0.duration.isActual && $0.audioRef != nil } }
    }
}
```

```swift
// Sources/T2SCore/Model/Document.swift
import Foundation

public enum SourceType: String, Codable, Sendable {
    case epub, article, pdf
}

public struct Document: Codable, Hashable, Sendable, Identifiable {
    /// Client-generated; never a backend or CloudKit key (spec §3.7.1).
    public var id: UUID
    public var title: String
    public var author: String?
    public var sourceType: SourceType
    public var sourceURL: URL?
    /// Path relative to the app container.
    public var coverImagePath: String?
    public var addedAt: Date
    /// Per-document voice override.
    public var voiceID: String?
    public var resumePosition: Position?

    public init(id: UUID = UUID(), title: String, author: String? = nil, sourceType: SourceType,
                sourceURL: URL? = nil, coverImagePath: String? = nil, addedAt: Date = Date(),
                voiceID: String? = nil, resumePosition: Position? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.coverImagePath = coverImagePath
        self.addedAt = addedAt
        self.voiceID = voiceID
        self.resumePosition = resumePosition
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter TimelineTests`
Expected: 5 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Model Tests/T2SCoreTests
git commit -m "Add domain model: Position, Playhead, Utterance, Timeline, Document"
```

---

### Task 3: `NormalizedText` and span mapping

**Files:**
- Create: `Sources/T2SCore/Normalize/NormalizedText.swift`
- Create: `Tests/T2SCoreTests/NormalizedTextTests.swift`
- Create: `Tests/T2SCoreTests/Support/SpanAssertions.swift`

**Interfaces:**
- Produces:
  - `struct NormalizedText { let source: String; var spoken: String; var spans: [SpanMap]; init(source:); mutating func replace(spokenRange:with:); func sourceRange(forSpoken:) -> Range<Int>; func spokenRange(forSource:) -> Range<Int> }`
  - Test helper `expectEveryWordMapsToSource(_ t: NormalizedText)`.
- `replace(spokenRange:with:)` is the **only** primitive rules may use. It keeps `spans` sorted by `spokenRange.lowerBound`, splits linear spans precisely, treats non-linear spans as atomic, records deletions as empty-spoken spans, and records insertions as zero-width source points (spec §4.1 mapping conventions).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Support/SpanAssertions.swift
import Foundation
import Testing
@testable import T2SCore

/// Spec §8: every spoken word range projects back to a non-empty source range.
func expectEveryWordMapsToSource(_ t: NormalizedText, allowInsertions: Bool = false,
                                 sourceLocation: SourceLocation = #_sourceLocation) {
    let regex = try! NSRegularExpression(pattern: "\\S+")
    let ns = t.spoken as NSString
    for m in regex.matches(in: t.spoken, range: NSRange(location: 0, length: ns.length)) {
        let r = m.range.location..<(m.range.location + m.range.length)
        let src = t.sourceRange(forSpoken: r)
        if src.isEmpty && !allowInsertions {
            Issue.record("word \"\(ns.substring(with: m.range))\" at \(r) maps to empty source range", sourceLocation: sourceLocation)
        }
    }
}
```

```swift
// Tests/T2SCoreTests/NormalizedTextTests.swift
import Testing
@testable import T2SCore

@Suite struct NormalizedTextTests {
    @Test func identityMapsOneToOne() {
        let t = NormalizedText(source: "Dr. Smith")
        #expect(t.spoken == "Dr. Smith")
        #expect(t.spans == [SpanMap(sourceRange: 0..<9, spokenRange: 0..<9)])
        #expect(t.sourceRange(forSpoken: 4..<9) == 4..<9)
    }

    @Test func expansionMapsWholeSpanToWholeToken() {
        var t = NormalizedText(source: "Dr. Smith")
        t.replace(spokenRange: 0..<3, with: "Doctor")
        #expect(t.spoken == "Doctor Smith")
        #expect(t.sourceRange(forSpoken: 0..<6) == 0..<3)
        #expect(t.sourceRange(forSpoken: 2..<4) == 0..<3)      // partial of atomic → whole token
        #expect(t.sourceRange(forSpoken: 7..<12) == 4..<9)     // shifted linear tail
        #expect(t.spokenRange(forSource: 0..<3) == 0..<6)
        #expect(t.spokenRange(forSource: 4..<9) == 7..<12)
        expectEveryWordMapsToSource(t)
    }

    @Test func deletionLeavesEmptySpokenSpan() {
        var t = NormalizedText(source: "text [14] more")
        t.replace(spokenRange: 4..<9, with: "")
        #expect(t.spoken == "text more")
        #expect(t.sourceRange(forSpoken: 5..<9) == 10..<14)
        #expect(t.spans.contains(SpanMap(sourceRange: 4..<9, spokenRange: 4..<4)))
        #expect(t.spokenRange(forSource: 5..<9).isEmpty)       // "[14]" has no spoken text
        expectEveryWordMapsToSource(t)
    }

    @Test func insertionMapsToSourcePoint() {
        var t = NormalizedText(source: "world")
        t.replace(spokenRange: 0..<0, with: "Hello ")
        #expect(t.spoken == "Hello world")
        #expect(t.sourceRange(forSpoken: 0..<5) == 0..<0)
        #expect(t.sourceRange(forSpoken: 6..<11) == 0..<5)
    }

    @Test func replacementInsideLinearSpanSplitsIt() {
        var t = NormalizedText(source: "a 1 b")
        t.replace(spokenRange: 2..<3, with: "one")
        #expect(t.spoken == "a one b")
        #expect(t.spans == [
            SpanMap(sourceRange: 0..<2, spokenRange: 0..<2),
            SpanMap(sourceRange: 2..<3, spokenRange: 2..<5),
            SpanMap(sourceRange: 3..<5, spokenRange: 5..<7),
        ])
    }

    @Test func reverseOrderReplacementsKeepMapping() {
        var t = NormalizedText(source: "Mr. and Dr. X")
        t.replace(spokenRange: 8..<11, with: "Doctor")   // later match first
        t.replace(spokenRange: 0..<3, with: "Mister")
        #expect(t.spoken == "Mister and Doctor X")
        #expect(t.sourceRange(forSpoken: 0..<6) == 0..<3)
        #expect(t.sourceRange(forSpoken: 11..<17) == 8..<11)
        #expect(t.sourceRange(forSpoken: 18..<19) == 12..<13)
        expectEveryWordMapsToSource(t)
    }

    @Test func partialOverlapOfAtomicSpanKeepsWholeSource() {
        var t = NormalizedText(source: "Dr.")
        t.replace(spokenRange: 0..<3, with: "Doctor")
        t.replace(spokenRange: 3..<6, with: "TOR")          // touches half of the atomic span
        #expect(t.spoken == "DocTOR")
        #expect(t.sourceRange(forSpoken: 0..<3) == 0..<3)
        #expect(t.sourceRange(forSpoken: 3..<6) == 0..<3)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter NormalizedTextTests`
Expected: FAIL to compile, `cannot find 'NormalizedText' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Normalize/NormalizedText.swift
import Foundation

/// Spoken text plus the mapping back to the untouched source (spec §4.1).
/// Offsets are UTF-16 throughout, matching NSRange.
public struct NormalizedText: Hashable, Sendable {
    public let source: String
    public private(set) var spoken: String
    /// Sorted by spokenRange.lowerBound; spoken ranges never overlap.
    public private(set) var spans: [SpanMap]

    public init(source: String) {
        self.source = source
        self.spoken = source
        let n = source.utf16.count
        self.spans = [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)]
    }

    /// Rebuilds a persisted mapping without re-running rules. The caller guarantees the
    /// three parts came from one normalization pass (they are stored together on Utterance).
    public init(source: String, spoken: String, spans: [SpanMap]) {
        self.source = source
        self.spoken = spoken
        self.spans = spans
    }

    /// The one primitive rules use. Replaces `r` in `spoken` and rewrites spans so the
    /// new text maps to whatever source the replaced text mapped to.
    public mutating func replace(spokenRange r: Range<Int>, with replacement: String) {
        precondition(r.lowerBound >= 0 && r.upperBound <= spoken.utf16.count, "range out of bounds")
        let newLen = replacement.utf16.count
        var before: [SpanMap] = []
        var after: [SpanMap] = []
        var coveredLo = Int.max
        var coveredHi = Int.min

        for span in spans {
            let sr = span.spokenRange
            if sr.isEmpty {
                if sr.lowerBound <= r.lowerBound { before.append(span) } else { after.append(span) }
                continue
            }
            if sr.upperBound <= r.lowerBound { before.append(span); continue }
            if sr.lowerBound >= r.upperBound { after.append(span); continue }

            let ol = max(sr.lowerBound, r.lowerBound)
            let ou = min(sr.upperBound, r.upperBound)
            if span.isLinear {
                let base = span.sourceRange.lowerBound - sr.lowerBound
                coveredLo = min(coveredLo, base + ol)
                coveredHi = max(coveredHi, base + ou)
                if sr.lowerBound < ol {
                    before.append(SpanMap(sourceRange: (base + sr.lowerBound)..<(base + ol), spokenRange: sr.lowerBound..<ol))
                }
                if ou < sr.upperBound {
                    after.append(SpanMap(sourceRange: (base + ou)..<(base + sr.upperBound), spokenRange: ou..<sr.upperBound))
                }
            } else {
                coveredLo = min(coveredLo, span.sourceRange.lowerBound)
                coveredHi = max(coveredHi, span.sourceRange.upperBound)
                if sr.lowerBound < ol {
                    before.append(SpanMap(sourceRange: span.sourceRange, spokenRange: sr.lowerBound..<ol))
                }
                if ou < sr.upperBound {
                    after.append(SpanMap(sourceRange: span.sourceRange, spokenRange: ou..<sr.upperBound))
                }
            }
        }

        if coveredLo == Int.max {
            // Pure insertion: zero-width source point after the preceding span.
            let p = before.last?.sourceRange.upperBound ?? 0
            coveredLo = p
            coveredHi = p
        }

        let delta = newLen - r.count
        let inserted = SpanMap(sourceRange: coveredLo..<coveredHi, spokenRange: r.lowerBound..<(r.lowerBound + newLen))
        let shifted = after.map {
            SpanMap(sourceRange: $0.sourceRange,
                    spokenRange: ($0.spokenRange.lowerBound + delta)..<($0.spokenRange.upperBound + delta))
        }
        spans = before + [inserted] + shifted

        let lo = String.Index(utf16Offset: r.lowerBound, in: spoken)
        let hi = String.Index(utf16Offset: r.upperBound, in: spoken)
        spoken.replaceSubrange(lo..<hi, with: replacement)
    }

    /// Projection used at playback time: a spoken range → the source range to highlight.
    public func sourceRange(forSpoken r: Range<Int>) -> Range<Int> {
        var lo = Int.max
        var hi = Int.min
        for span in spans where !span.spokenRange.isEmpty {
            let ol = max(span.spokenRange.lowerBound, r.lowerBound)
            let ou = min(span.spokenRange.upperBound, r.upperBound)
            guard ol < ou else { continue }
            if span.isLinear {
                let s = span.sourceRange.lowerBound + (ol - span.spokenRange.lowerBound)
                lo = min(lo, s)
                hi = max(hi, s + (ou - ol))
            } else {
                lo = min(lo, span.sourceRange.lowerBound)
                hi = max(hi, span.sourceRange.upperBound)
            }
        }
        if lo == Int.max {
            let p = spans.last(where: { $0.spokenRange.lowerBound <= r.lowerBound })?.sourceRange.upperBound ?? 0
            return p..<p
        }
        return lo..<hi
    }

    /// Inverse projection used when resolving a persisted Position.
    public func spokenRange(forSource r: Range<Int>) -> Range<Int> {
        var lo = Int.max
        var hi = Int.min
        for span in spans {
            let ol = max(span.sourceRange.lowerBound, r.lowerBound)
            let ou = min(span.sourceRange.upperBound, r.upperBound)
            let overlaps = span.sourceRange.isEmpty
                ? (r.lowerBound <= span.sourceRange.lowerBound && span.sourceRange.lowerBound < r.upperBound)
                : ol < ou
            guard overlaps else { continue }
            if span.isLinear {
                let s = span.spokenRange.lowerBound + (ol - span.sourceRange.lowerBound)
                lo = min(lo, s)
                hi = max(hi, s + (ou - ol))
            } else {
                lo = min(lo, span.spokenRange.lowerBound)
                hi = max(hi, span.spokenRange.upperBound)
            }
        }
        if lo == Int.max {
            let p = spans.last(where: { $0.sourceRange.lowerBound <= r.lowerBound })?.spokenRange.upperBound ?? 0
            return p..<p
        }
        return lo..<hi
    }
}
```

Spans per sentence number in the tens, so the linear scans above are fine; do not add a binary search until a profile asks for it.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter NormalizedTextTests`
Expected: 7 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Normalize Tests/T2SCoreTests
git commit -m "Add NormalizedText with span mapping and projections"
```

---

### Task 4: Rule protocol, regex helper, hyphenation and whitespace rules

**Files:**
- Create: `Sources/T2SCore/Normalize/NormalizerRule.swift`
- Create: `Sources/T2SCore/Normalize/Pattern.swift`
- Create: `Sources/T2SCore/Normalize/Rules/RejoinHyphenationRule.swift`
- Create: `Sources/T2SCore/Normalize/Rules/CollapseWhitespaceRule.swift`
- Create: `Tests/T2SCoreTests/Rules/HyphenationAndWhitespaceTests.swift`

**Interfaces:**
- Produces:
  - `protocol NormalizerRule: Sendable { func apply(_ input: NormalizedText) -> NormalizedText }`
  - `struct Pattern: @unchecked Sendable { init(_ pattern: String, _ options: NSRegularExpression.Options = []) }`
  - `extension NormalizedText { mutating func replaceMatches(of: Pattern, with body: (NSTextCheckingResult, String) -> String?); mutating func replaceMatches(of: Pattern, template: String) }`
  - `extension NSTextCheckingResult { func group(_ i: Int, in s: String) -> String? }`
  - `struct RejoinHyphenationRule: NormalizerRule`, `struct CollapseWhitespaceRule: NormalizerRule`.
- Rules that need a regex declare `static let` `Pattern`s; `Pattern` wraps `NSRegularExpression`, which is immutable and thread-safe but not marked `Sendable`, hence `@unchecked`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Rules/HyphenationAndWhitespaceTests.swift
import Testing
@testable import T2SCore

@Suite struct HyphenationAndWhitespaceTests {
    @Test func rejoinsWordsHyphenatedAcrossLineBreaks() {
        let t = RejoinHyphenationRule().apply(NormalizedText(source: "the con-\ntinent was"))
        #expect(t.spoken == "the continent was")
        #expect(t.sourceRange(forSpoken: 4..<13) == 4..<15)   // "continent" ← "con-\ntinent"
        expectEveryWordMapsToSource(t)
    }

    @Test func keepsRealHyphens() {
        let t = RejoinHyphenationRule().apply(NormalizedText(source: "well-known"))
        #expect(t.spoken == "well-known")
    }

    @Test func rejoinsAcrossCRLF() {
        let t = RejoinHyphenationRule().apply(NormalizedText(source: "con-\r\ntinent"))
        #expect(t.spoken == "continent")
        expectEveryWordMapsToSource(t)
    }

    @Test func collapsesRunsAndTrims() {
        let t = CollapseWhitespaceRule().apply(NormalizedText(source: "  a  b\n\tc "))
        #expect(t.spoken == "a b c")
        #expect(t.sourceRange(forSpoken: 4..<5) == 8..<9)
        expectEveryWordMapsToSource(t)
    }

    @Test func singleSpacesAreUntouched() {
        let t = CollapseWhitespaceRule().apply(NormalizedText(source: "a b"))
        #expect(t.spans == [SpanMap(sourceRange: 0..<3, spokenRange: 0..<3)])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter HyphenationAndWhitespaceTests`
Expected: FAIL to compile, `cannot find 'RejoinHyphenationRule' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Normalize/NormalizerRule.swift
public protocol NormalizerRule: Sendable {
    func apply(_ input: NormalizedText) -> NormalizedText
}
```

```swift
// Sources/T2SCore/Normalize/Pattern.swift
import Foundation

/// NSRegularExpression is immutable and thread-safe; it just is not annotated Sendable.
struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }
}

extension NSTextCheckingResult {
    func group(_ i: Int, in s: String) -> String? {
        let r = range(at: i)
        guard r.location != NSNotFound else { return nil }
        return (s as NSString).substring(with: r)
    }
}

extension NormalizedText {
    /// Applies `body` to every match, right to left, so earlier offsets stay valid.
    /// `body` receives the match and the spoken text the matches were computed on;
    /// return nil to leave a match untouched.
    mutating func replaceMatches(of pattern: Pattern, with body: (NSTextCheckingResult, String) -> String?) {
        let original = spoken
        let matches = pattern.regex.matches(in: original, range: NSRange(location: 0, length: (original as NSString).length))
        for m in matches.reversed() {
            guard let replacement = body(m, original) else { continue }
            let r = m.range.location..<(m.range.location + m.range.length)
            replace(spokenRange: r, with: replacement)
        }
    }

    mutating func replaceMatches(of pattern: Pattern, template: String) {
        replaceMatches(of: pattern) { m, s in
            pattern.regex.replacementString(for: m, in: s, offset: 0, template: template)
        }
    }
}
```

```swift
// Sources/T2SCore/Normalize/Rules/RejoinHyphenationRule.swift
/// Rule 1 (spec §4.1): "con-\ntinent" → "continent". Real hyphens have no line break and are kept.
public struct RejoinHyphenationRule: NormalizerRule {
    static let pattern = Pattern("(\\p{L})-[ \\t]*\\r?\\n[ \\t]*(\\p{L})")

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.pattern, template: "$1$2")
        return t
    }
}
```

```swift
// Sources/T2SCore/Normalize/Rules/CollapseWhitespaceRule.swift
/// Runs after every content rule and before the pronunciation dictionary.
public struct CollapseWhitespaceRule: NormalizerRule {
    static let runs = Pattern("\\s+")
    static let edges = Pattern("^\\s+|\\s+$")

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.edges) { _, _ in "" }
        t.replaceMatches(of: Self.runs) { m, s in
            m.group(0, in: s) == " " ? nil : " "
        }
        return t
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter HyphenationAndWhitespaceTests`
Expected: 5 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Normalize Tests/T2SCoreTests/Rules
git commit -m "Add NormalizerRule, Pattern helper, hyphenation and whitespace rules"
```

---

### Task 5: Citation and footnote-marker rule

**Files:**
- Create: `Sources/T2SCore/Normalize/Rules/StripCitationsRule.swift`
- Create: `Tests/T2SCoreTests/Rules/StripCitationsTests.swift`

**Interfaces:**
- Produces: `struct StripCitationsRule: NormalizerRule`. Removes bracketed numeric citations (`[14]`, `[3, 7]`, `[2–5]`) with one preceding space, and Unicode superscript digits.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Rules/StripCitationsTests.swift
import Testing
@testable import T2SCore

@Suite struct StripCitationsTests {
    let rule = StripCitationsRule()

    @Test func dropsBracketedNumbers() {
        let t = rule.apply(NormalizedText(source: "as shown [14] earlier [3, 7] and [2–5]."))
        #expect(t.spoken == "as shown earlier and.")
        #expect(t.sourceRange(forSpoken: 9..<16) == 14..<21)   // "earlier"
        expectEveryWordMapsToSource(t)
    }

    @Test func dropsSuperscriptMarkers() {
        let t = rule.apply(NormalizedText(source: "theory¹² holds"))
        #expect(t.spoken == "theory holds")
        expectEveryWordMapsToSource(t)
    }

    @Test func keepsNonNumericBrackets() {
        let t = rule.apply(NormalizedText(source: "he said [sic] that"))
        #expect(t.spoken == "he said [sic] that")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter StripCitationsTests`
Expected: FAIL to compile, `cannot find 'StripCitationsRule' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Normalize/Rules/StripCitationsRule.swift
/// Rule 3 (spec §4.1): "[14]" must never become "bracket fourteen".
public struct StripCitationsRule: NormalizerRule {
    static let bracketed = Pattern(" ?\\[\\d+(?:\\s*[,\\u2013-]\\s*\\d+)*\\]")
    static let superscripts = Pattern("[\\u00B9\\u00B2\\u00B3\\u2070\\u2074-\\u2079]+")

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.bracketed) { _, _ in "" }
        t.replaceMatches(of: Self.superscripts) { _, _ in "" }
        return t
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter StripCitationsTests`
Expected: 3 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Normalize/Rules/StripCitationsRule.swift Tests/T2SCoreTests/Rules/StripCitationsTests.swift
git commit -m "Add citation and footnote-marker stripping rule"
```

---

### Task 6: Abbreviation expansion rule

**Files:**
- Create: `Sources/T2SCore/Normalize/Rules/ExpandAbbreviationsRule.swift`
- Create: `Tests/T2SCoreTests/Rules/ExpandAbbreviationsTests.swift`

**Interfaces:**
- Produces: `struct ExpandAbbreviationsRule: NormalizerRule` with a fixed, case-sensitive table.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Rules/ExpandAbbreviationsTests.swift
import Testing
@testable import T2SCore

@Suite struct ExpandAbbreviationsTests {
    let rule = ExpandAbbreviationsRule()

    @Test(arguments: [
        ("Dr. Smith", "Doctor Smith"),
        ("Mr. and Mrs. Jones", "Mister and Missus Jones"),
        ("Ms. Lee", "Miz Lee"),
        ("Prof. Chen, Jr.", "Professor Chen, Junior"),
        ("cats vs. dogs", "cats versus dogs"),
        ("apples, pears, etc.", "apples, pears, et cetera"),
        ("see Fig. 3", "see Figure 3"),
        ("No. 5", "Number 5"),
        ("Say No. Then leave.", "Say No. Then leave."),
        ("e.g. this, i.e. that", "for example this, that is that"),
        ("approx. 40", "approximately 40"),
    ])
    func expands(input: String, expected: String) {
        let t = rule.apply(NormalizedText(source: input))
        #expect(t.spoken == expected)
        expectEveryWordMapsToSource(t)
    }

    @Test func expansionMapsToAbbreviation() {
        let t = rule.apply(NormalizedText(source: "Dr. Smith"))
        #expect(t.sourceRange(forSpoken: 0..<6) == 0..<3)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ExpandAbbreviationsTests`
Expected: FAIL to compile, `cannot find 'ExpandAbbreviationsRule' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Normalize/Rules/ExpandAbbreviationsRule.swift
/// Rule 4a (spec §4.1). Case-sensitive on purpose: "no." mid-sentence is not "Number".
public struct ExpandAbbreviationsRule: NormalizerRule {
    static let table: [(Pattern, String)] = [
        (Pattern("\\be\\.g\\."), "for example"),
        (Pattern("\\bi\\.e\\."), "that is"),
        (Pattern("\\bNo\\.(?=\\s*\\d)"), "Number"),
        (Pattern("\\bDr\\."), "Doctor"),
        (Pattern("\\bMr\\."), "Mister"),
        (Pattern("\\bMrs\\."), "Missus"),
        (Pattern("\\bMs\\."), "Miz"),
        (Pattern("\\bProf\\."), "Professor"),
        (Pattern("\\bJr\\."), "Junior"),
        (Pattern("\\bSr\\."), "Senior"),
        (Pattern("\\bvs\\."), "versus"),
        (Pattern("\\betc\\."), "et cetera"),
        (Pattern("\\bFig\\."), "Figure"),
        (Pattern("\\bapprox\\."), "approximately"),
    ]

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        for (pattern, replacement) in Self.table {
            t.replaceMatches(of: pattern) { _, _ in replacement }
        }
        return t
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ExpandAbbreviationsTests`
Expected: 12 tests passed (11 parameterized plus 1).

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Normalize/Rules/ExpandAbbreviationsRule.swift Tests/T2SCoreTests/Rules/ExpandAbbreviationsTests.swift
git commit -m "Add abbreviation expansion rule"
```

---

### Task 7: Number words

**Files:**
- Create: `Sources/T2SCore/Normalize/NumberWords.swift`
- Create: `Tests/T2SCoreTests/NumberWordsTests.swift`

**Interfaces:**
- Produces: `enum NumberWords { static func cardinal(_ n: Int) -> String; static func ordinal(_ n: Int) -> String; static func year(_ y: Int) -> String; static func digits(_ s: String) -> String }`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/NumberWordsTests.swift
import Testing
@testable import T2SCore

@Suite struct NumberWordsTests {
    @Test(arguments: [
        (0, "zero"), (7, "seven"), (13, "thirteen"), (20, "twenty"), (21, "twenty-one"),
        (100, "one hundred"), (101, "one hundred one"), (999, "nine hundred ninety-nine"),
        (1000, "one thousand"), (1234, "one thousand two hundred thirty-four"),
        (1_000_000, "one million"), (2_500_017, "two million five hundred thousand seventeen"),
        (-5, "minus five"),
    ])
    func cardinal(n: Int, words: String) { #expect(NumberWords.cardinal(n) == words) }

    @Test(arguments: [
        (1, "first"), (2, "second"), (3, "third"), (4, "fourth"), (5, "fifth"), (8, "eighth"),
        (9, "ninth"), (12, "twelfth"), (20, "twentieth"), (21, "twenty-first"), (100, "one hundredth"),
        (1000, "one thousandth"),
    ])
    func ordinal(n: Int, words: String) { #expect(NumberWords.ordinal(n) == words) }

    @Test(arguments: [
        (1999, "nineteen ninety-nine"), (1900, "nineteen hundred"), (1905, "nineteen oh-five"),
        (2000, "two thousand"), (2005, "two thousand five"), (2010, "twenty ten"),
        (2024, "twenty twenty-four"), (1066, "ten sixty-six"), (3000, "three thousand"),
    ])
    func year(n: Int, words: String) { #expect(NumberWords.year(n) == words) }

    @Test func digitsSpokenIndividually() {
        #expect(NumberWords.digits("305") == "three zero five")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter NumberWordsTests`
Expected: FAIL to compile, `cannot find 'NumberWords' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Normalize/NumberWords.swift
enum NumberWords {
    private static let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                               "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
                               "seventeen", "eighteen", "nineteen"]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    private static let scales: [(Int, String)] = [
        (1_000_000_000_000, "trillion"), (1_000_000_000, "billion"), (1_000_000, "million"), (1_000, "thousand"),
    ]

    static func cardinal(_ n: Int) -> String {
        if n < 0 { return "minus " + cardinal(-n) }
        if n < 20 { return ones[n] }
        if n < 100 {
            let t = tens[n / 10]
            let o = n % 10
            return o == 0 ? t : "\(t)-\(ones[o])"
        }
        if n < 1000 {
            let h = "\(ones[n / 100]) hundred"
            let r = n % 100
            return r == 0 ? h : "\(h) \(cardinal(r))"
        }
        for (value, name) in scales where n >= value {
            let head = "\(cardinal(n / value)) \(name)"
            let r = n % value
            return r == 0 ? head : "\(head) \(cardinal(r))"
        }
        return String(n)
    }

    static func ordinal(_ n: Int) -> String {
        let c = cardinal(n)
        let irregular = ["one": "first", "two": "second", "three": "third", "five": "fifth",
                         "eight": "eighth", "nine": "ninth", "twelve": "twelfth"]
        let lastStart = c.lastIndex(where: { $0 == " " || $0 == "-" }).map { c.index(after: $0) } ?? c.startIndex
        let last = String(c[lastStart...])
        let replacement: String
        if let irr = irregular[last] {
            replacement = irr
        } else if last.hasSuffix("y") {
            replacement = String(last.dropLast()) + "ieth"
        } else {
            replacement = last + "th"
        }
        return String(c[..<lastStart]) + replacement
    }

    static func year(_ y: Int) -> String {
        guard (1000...2999).contains(y) else { return cardinal(y) }
        let hi = y / 100
        let lo = y % 100
        if y % 1000 == 0 { return cardinal(y) }
        if y >= 2000 && y < 2010 { return "two thousand \(cardinal(lo))" }
        if lo == 0 { return "\(cardinal(hi)) hundred" }
        if lo < 10 { return "\(cardinal(hi)) oh-\(cardinal(lo))" }
        return "\(cardinal(hi)) \(cardinal(lo))"
    }

    static func digits(_ s: String) -> String {
        s.compactMap { $0.wholeNumberValue }.map { ones[$0] }.joined(separator: " ")
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter NumberWordsTests`
Expected: 35 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Normalize/NumberWords.swift Tests/T2SCoreTests/NumberWordsTests.swift
git commit -m "Add NumberWords: cardinal, ordinal, year, digits"
```

---

### Task 8: Number expansion rule

**Files:**
- Create: `Sources/T2SCore/Normalize/Rules/ExpandNumbersRule.swift`
- Create: `Tests/T2SCoreTests/Rules/ExpandNumbersTests.swift`

**Interfaces:**
- Consumes: `NumberWords`.
- Produces: `struct ExpandNumbersRule: NormalizerRule`. Passes, in order: units, currency, percent, ordinal, decimal, year, cardinal.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Rules/ExpandNumbersTests.swift
import Testing
@testable import T2SCore

@Suite struct ExpandNumbersTests {
    let rule = ExpandNumbersRule()

    @Test(arguments: [
        ("I have 3 cats", "I have three cats"),
        ("about 1,200 people", "about one thousand two hundred people"),
        ("in 1999 and 2024", "in nineteen ninety-nine and twenty twenty-four"),
        ("the 21st century", "the twenty-first century"),
        ("costs $5", "costs five dollars"),
        ("costs $1", "costs one dollar"),
        ("costs $2.50", "costs two dollars and fifty cents"),
        ("costs $0.99", "costs ninety-nine cents"),
        ("costs £40 or €3", "costs forty pounds or three euros"),
        ("up 12% today", "up twelve percent today"),
        ("pi is 3.14", "pi is three point one four"),
        ("ran 5 km in 30 min", "ran five kilometers in thirty minutes"),
        ("1 km", "one kilometer"),
        ("2.5% of 40 kg", "two point five percent of forty kilograms"),
        ("version 2.0.1", "version 2.0.1"),
        ("born in 1999.", "born in nineteen ninety-nine."),
        ("count 3.", "count three."),
    ])
    func expands(input: String, expected: String) {
        let t = rule.apply(NormalizedText(source: input))
        #expect(t.spoken == expected)
        expectEveryWordMapsToSource(t)
    }

    @Test func currencyMapsToWholeToken() {
        let t = rule.apply(NormalizedText(source: "costs $2.50 now"))
        #expect(t.sourceRange(forSpoken: 6..<33) == 6..<11)   // "two dollars and fifty cents" ← "$2.50"
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ExpandNumbersTests`
Expected: FAIL to compile, `cannot find 'ExpandNumbersRule' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Normalize/Rules/ExpandNumbersRule.swift
import Foundation

/// Rule 4b (spec §4.1): ordinals, numerals, units, currency. Dotted version strings are left alone.
public struct ExpandNumbersRule: NormalizerRule {
    static let units = Pattern("\\b(\\d+(?:\\.\\d+)?)\\s?(km|kg|cm|mm|mph|GB|MB|ms|min)\\b")
    static let currency = Pattern("([$£€])(\\d{1,3}(?:,\\d{3})+|\\d+)(?:\\.(\\d{1,2}))?\\b")
    static let percent = Pattern("\\b(\\d+(?:\\.\\d+)?)%")
    static let ordinal = Pattern("\\b(\\d+)(?:st|nd|rd|th)\\b", .caseInsensitive)
    // Lookarounds: never inside a longer number or a dotted version string, but a
    // sentence-ending period after the number is fine.
    static let decimal = Pattern("(?<![\\d.])(\\d+)\\.(\\d+)(?!\\d)(?!\\.\\d)")
    static let year = Pattern("(?<![\\d.,])(1\\d{3}|2\\d{3})(?!\\d)(?![.,]\\d)")
    static let cardinal = Pattern("(?<![\\d.])(\\d{1,3}(?:,\\d{3})+|\\d+)(?!\\d)(?![.,]\\d)")

    static let unitNames: [String: (String, String)] = [
        "km": ("kilometer", "kilometers"), "kg": ("kilogram", "kilograms"), "cm": ("centimeter", "centimeters"),
        "mm": ("millimeter", "millimeters"), "mph": ("miles per hour", "miles per hour"),
        "GB": ("gigabyte", "gigabytes"), "MB": ("megabyte", "megabytes"), "ms": ("millisecond", "milliseconds"),
        "min": ("minute", "minutes"),
    ]
    static let currencyNames: [String: (String, String, String, String)] = [
        "$": ("dollar", "dollars", "cent", "cents"),
        "£": ("pound", "pounds", "penny", "pence"),
        "€": ("euro", "euros", "cent", "cents"),
    ]

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.units) { m, s in
            guard let num = m.group(1, in: s), let unit = m.group(2, in: s), let names = Self.unitNames[unit] else { return nil }
            return "\(num) \(num == "1" ? names.0 : names.1)"
        }
        t.replaceMatches(of: Self.currency) { m, s in
            guard let sym = m.group(1, in: s), let names = Self.currencyNames[sym],
                  let whole = Int(m.group(2, in: s)!.replacingOccurrences(of: ",", with: "")) else { return nil }
            let cents = m.group(3, in: s).flatMap { Int($0.count == 1 ? $0 + "0" : $0) } ?? 0
            let major = "\(NumberWords.cardinal(whole)) \(whole == 1 ? names.0 : names.1)"
            let minor = "\(NumberWords.cardinal(cents)) \(cents == 1 ? names.2 : names.3)"
            if cents == 0 { return major }
            if whole == 0 { return minor }
            return "\(major) and \(minor)"
        }
        t.replaceMatches(of: Self.percent) { m, s in
            guard let num = m.group(1, in: s) else { return nil }
            return "\(Self.spokenNumber(num)) percent"
        }
        t.replaceMatches(of: Self.ordinal) { m, s in
            m.group(1, in: s).flatMap(Int.init).map(NumberWords.ordinal)
        }
        t.replaceMatches(of: Self.decimal) { m, s in
            guard let whole = m.group(1, in: s).flatMap(Int.init), let frac = m.group(2, in: s) else { return nil }
            return "\(NumberWords.cardinal(whole)) point \(NumberWords.digits(frac))"
        }
        t.replaceMatches(of: Self.year) { m, s in
            m.group(1, in: s).flatMap(Int.init).map(NumberWords.year)
        }
        t.replaceMatches(of: Self.cardinal) { m, s in
            m.group(1, in: s).flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }.map(NumberWords.cardinal)
        }
        return t
    }

    private static func spokenNumber(_ s: String) -> String {
        if let dot = s.firstIndex(of: "."), let whole = Int(s[..<dot]) {
            return "\(NumberWords.cardinal(whole)) point \(NumberWords.digits(String(s[s.index(after: dot)...])))"
        }
        return Int(s).map(NumberWords.cardinal) ?? s
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ExpandNumbersTests`
Expected: 18 tests passed. If `version 2.0.1` fails, the lookarounds on `decimal` and `cardinal` are the culprit: they must refuse a digit on either side and a dot-digit after, while still allowing a bare sentence-ending period.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Normalize/Rules/ExpandNumbersRule.swift Tests/T2SCoreTests/Rules/ExpandNumbersTests.swift
git commit -m "Add number expansion rule: units, currency, percent, ordinals, decimals, years"
```

---

### Task 9: URL collapsing rule

**Files:**
- Create: `Sources/T2SCore/Normalize/Rules/CollapseURLsRule.swift`
- Create: `Tests/T2SCoreTests/Rules/CollapseURLsTests.swift`

**Interfaces:**
- Produces: `struct CollapseURLsRule: NormalizerRule`. A URL becomes its host without `www.`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Rules/CollapseURLsTests.swift
import Testing
@testable import T2SCore

@Suite struct CollapseURLsTests {
    let rule = CollapseURLsRule()

    @Test(arguments: [
        ("see https://www.nytimes.com/2024/05/01/tech.html today", "see nytimes.com today"),
        ("at http://example.org", "at example.org"),
        ("visit www.apple.com/iphone now", "visit apple.com now"),
        ("email me at a@b.com", "email me at a@b.com"),
        ("read https://x.com/y. Then go", "read x.com. Then go"),
        ("at http://example.org/.", "at example.org."),
    ])
    func collapses(input: String, expected: String) {
        let t = rule.apply(NormalizedText(source: input))
        #expect(t.spoken == expected)
        expectEveryWordMapsToSource(t)
    }

    @Test func hostMapsToWholeURL() {
        let t = rule.apply(NormalizedText(source: "see https://www.nytimes.com/x today"))
        #expect(t.sourceRange(forSpoken: 4..<15) == 4..<29)   // "https://www.nytimes.com/x" is 25 units
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CollapseURLsTests`
Expected: FAIL to compile, `cannot find 'CollapseURLsRule' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Normalize/Rules/CollapseURLsRule.swift
/// Rule 5 (spec §4.1): a URL is spoken as its bare host.
public struct CollapseURLsRule: NormalizerRule {
    // The optional path never ends in sentence punctuation, so "x.com/y." keeps its period.
    static let pattern = Pattern("\\b(?:https?://)?(?:www\\.)?([A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+)(?:/(?:\\S*[^\\s.,;:!?)\\]])?)?")

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.pattern) { m, s in
            guard let whole = m.group(0, in: s), let host = m.group(1, in: s) else { return nil }
            // Only touch things that look like URLs: a scheme, a www., or a path.
            let looksLikeURL = whole.hasPrefix("http") || whole.hasPrefix("www.") || whole.contains("/")
            return looksLikeURL ? host : nil
        }
        return t
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CollapseURLsTests`
Expected: 7 cases passed (the runner reports 2 test functions).

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Normalize/Rules/CollapseURLsRule.swift Tests/T2SCoreTests/Rules/CollapseURLsTests.swift
git commit -m "Add URL collapsing rule"
```

---

### Task 10: Pronunciation dictionary rule and the `TextNormalizer` pipeline

**Files:**
- Create: `Sources/T2SCore/Normalize/PronunciationEntry.swift`
- Create: `Sources/T2SCore/Normalize/Rules/PronunciationDictionaryRule.swift`
- Create: `Sources/T2SCore/Normalize/TextNormalizer.swift`
- Create: `Tests/T2SCoreTests/Rules/PronunciationDictionaryTests.swift`
- Create: `Tests/T2SCoreTests/TextNormalizerTests.swift`
- Create: `Tests/T2SCoreTests/Fixtures/corpus.txt`

**Interfaces:**
- Produces:
  - `struct PronunciationEntry: Codable, Hashable, Sendable, Identifiable { id: UUID; term: String; replacement: String; caseSensitive: Bool }`
  - `struct PronunciationDictionaryRule: NormalizerRule { init(entries: [PronunciationEntry]) }`
  - `struct TextNormalizer: Sendable { static let version: Int; init(dictionary: [PronunciationEntry] = []); var rules: [any NormalizerRule]; func normalize(_ source: String) -> NormalizedText }`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Rules/PronunciationDictionaryTests.swift
import Testing
@testable import T2SCore

@Suite struct PronunciationDictionaryTests {
    @Test func replacesWholeWordsOnly() {
        let rule = PronunciationDictionaryRule(entries: [
            PronunciationEntry(term: "Nguyen", replacement: "Nwin"),
        ])
        let t = rule.apply(NormalizedText(source: "Dr Nguyen and Nguyenson"))
        #expect(t.spoken == "Dr Nwin and Nguyenson")
        #expect(t.sourceRange(forSpoken: 3..<7) == 3..<9)
        expectEveryWordMapsToSource(t)
    }

    @Test func caseInsensitiveByDefault() {
        let rule = PronunciationDictionaryRule(entries: [PronunciationEntry(term: "SQL", replacement: "sequel")])
        #expect(rule.apply(NormalizedText(source: "sql and SQL")).spoken == "sequel and sequel")
    }

    @Test func caseSensitiveWhenAsked() {
        let rule = PronunciationDictionaryRule(entries: [PronunciationEntry(term: "US", replacement: "U S", caseSensitive: true)])
        #expect(rule.apply(NormalizedText(source: "the US and us")).spoken == "the U S and us")
    }
}
```

```swift
// Tests/T2SCoreTests/TextNormalizerTests.swift
import Foundation
import Testing
@testable import T2SCore

@Suite struct TextNormalizerTests {
    @Test func appliesRulesInSpecOrder() {
        let n = TextNormalizer(dictionary: [PronunciationEntry(term: "Doctor", replacement: "Dokter")])
        let t = n.normalize("Dr. Smith [1] paid $5 on\nhttps://x.com/a  in 1999.")
        #expect(t.spoken == "Dokter Smith paid five dollars on x.com in nineteen ninety-nine.")
        expectEveryWordMapsToSource(t)
    }

    @Test func versionMatchesVersions() {
        #expect(TextNormalizer.version == Versions.normalizer)
    }

    @Test func everyWordInCorpusMapsToSource() throws {
        let url = try #require(Bundle.module.url(forResource: "corpus", withExtension: "txt", subdirectory: "Fixtures"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.count >= 40)
        let n = TextNormalizer()
        for line in lines {
            let t = n.normalize(line)
            #expect(!t.spoken.isEmpty, "\(line)")
            expectEveryWordMapsToSource(t)
        }
    }
}
```

`Tests/T2SCoreTests/Fixtures/corpus.txt`: 50 lines of English prose from public-domain text, one sentence per line, including sentences with "Dr.", "Mr.", bracketed citations, dollar amounts, percentages, years, and a URL. Hyphenation across a line break cannot be expressed one-sentence-per-line; it is covered by Task 4's tests. Delete `Fixtures/.gitkeep`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "PronunciationDictionaryTests|TextNormalizerTests"`
Expected: FAIL to compile, `cannot find 'PronunciationDictionaryRule' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Normalize/PronunciationEntry.swift
import Foundation

public struct PronunciationEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var term: String
    public var replacement: String
    public var caseSensitive: Bool

    public init(id: UUID = UUID(), term: String, replacement: String, caseSensitive: Bool = false) {
        self.id = id
        self.term = term
        self.replacement = replacement
        self.caseSensitive = caseSensitive
    }
}
```

```swift
// Sources/T2SCore/Normalize/Rules/PronunciationDictionaryRule.swift
import Foundation

/// Rule 6 (spec §4.1): applied last, immediately before G2P. Whole-word matches only.
public struct PronunciationDictionaryRule: NormalizerRule {
    private let compiled: [(Pattern, String)]

    public init(entries: [PronunciationEntry]) {
        compiled = entries.map { e in
            let escaped = NSRegularExpression.escapedPattern(for: e.term)
            return (Pattern("\\b\(escaped)\\b", e.caseSensitive ? [] : [.caseInsensitive]), e.replacement)
        }
    }

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        for (pattern, replacement) in compiled {
            t.replaceMatches(of: pattern) { _, _ in replacement }
        }
        return t
    }
}
```

```swift
// Sources/T2SCore/Normalize/TextNormalizer.swift
/// Composes the rules in the order fixed by spec §4.1.
public struct TextNormalizer: Sendable {
    public static let version = Versions.normalizer
    public var rules: [any NormalizerRule]

    public init(dictionary: [PronunciationEntry] = []) {
        rules = [
            RejoinHyphenationRule(),
            StripCitationsRule(),
            ExpandAbbreviationsRule(),
            ExpandNumbersRule(),
            CollapseURLsRule(),
            CollapseWhitespaceRule(),
            PronunciationDictionaryRule(entries: dictionary),
        ]
    }

    public func normalize(_ source: String) -> NormalizedText {
        rules.reduce(NormalizedText(source: source)) { $1.apply($0) }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "PronunciationDictionaryTests|TextNormalizerTests"`
Expected: 6 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Normalize Tests/T2SCoreTests
git commit -m "Add pronunciation dictionary rule and TextNormalizer pipeline with corpus test"
```

---

### Task 11: Repeated-line filter for PDF headers, footers, and page numbers

**Files:**
- Create: `Sources/T2SCore/Segment/RepeatedLineFilter.swift`
- Create: `Tests/T2SCoreTests/RepeatedLineFilterTests.swift`

**Interfaces:**
- Produces: `enum RepeatedLineFilter { static func filter(pages: [[String]], minPages: Int = 3, edge: Int = 2) -> [[String]] }`. Operates on lines per page before segmentation; this is spec §4.1 rule 2, done at block level because it needs page structure the normalizer never sees.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/RepeatedLineFilterTests.swift
import Testing
@testable import T2SCore

@Suite struct RepeatedLineFilterTests {
    let words = ["alpha", "beta", "gamma", "delta", "epsilon"]
    func page(_ n: Int, body: [String]) -> [String] {
        ["THE GREAT BOOK — Chapter 2"] + body + ["Page \(n)"]
    }

    @Test func dropsHeadersFootersAndPageNumbers() {
        let pages = (1...5).map { n in page(n, body: ["The \(words[n - 1]) paragraph.", "It continues about \(words[n - 1])."]) }
        let out = RepeatedLineFilter.filter(pages: pages)
        #expect(out.count == 5)
        #expect(out[0] == ["The alpha paragraph.", "It continues about alpha."])
        #expect(out[4] == ["The epsilon paragraph.", "It continues about epsilon."])
    }

    @Test func keepsHeaderBelowThreshold() {
        let pages = (1...2).map { n in page(n, body: ["Body \(words[n - 1])"]) }
        let out = RepeatedLineFilter.filter(pages: pages)
        #expect(out[0].first == "THE GREAT BOOK — Chapter 2")
        #expect(out[0].last == "Body alpha")            // bare page numbers always go
    }

    @Test func keepsRepeatedLinesAwayFromEdges() {
        // A refrain repeated mid-page on every page is body text, not a header.
        let pages = (1...4).map { n in ["Header", "Opening \(words[n - 1]).", "Middle \(words[n - 1]).", "Once upon a time.", "More \(words[n - 1]).", "Closing \(words[n - 1]).", "Footer"] }
        let out = RepeatedLineFilter.filter(pages: pages)
        #expect(out.allSatisfy { $0.contains("Once upon a time.") })
        #expect(out[0].first == "Opening alpha.")
        #expect(out[0].last == "Closing alpha.")
    }

    @Test func bareNumbersAndPageOfGo() {
        let out = RepeatedLineFilter.filter(pages: [["  12  ", "text", "Page 3 of 9", "page 4"]])
        #expect(out == [["text"]])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RepeatedLineFilterTests`
Expected: FAIL to compile, `cannot find 'RepeatedLineFilter' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Segment/RepeatedLineFilter.swift
import Foundation

/// Spec §4.1 rule 2: lines recurring at the top or bottom of many pages are running
/// headers or footers; bare page numbers are always dropped.
public enum RepeatedLineFilter {
    static let pageNumber = Pattern("^\\s*(?:page\\s+)?\\d+(?:\\s+of\\s+\\d+)?\\s*$", .caseInsensitive)
    static let digits = Pattern("\\d+")

    public static func filter(pages: [[String]], minPages: Int = 3, edge: Int = 2) -> [[String]] {
        var pagesSeen: [String: Set<Int>] = [:]
        for (p, lines) in pages.enumerated() {
            let edgeLines = Array(lines.prefix(edge)) + Array(lines.suffix(edge))
            for line in edgeLines {
                pagesSeen[mask(line), default: []].insert(p)
            }
        }
        let recurring = Set(pagesSeen.filter { $0.value.count >= minPages }.keys)

        return pages.enumerated().map { p, lines in
            lines.enumerated().compactMap { i, line in
                if isPageNumber(line) { return nil }
                let atEdge = i < edge || i >= lines.count - edge
                if atEdge && recurring.contains(mask(line)) { return nil }
                return line
            }
        }
    }

    private static func mask(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let ns = trimmed as NSString
        return digits.regex.stringByReplacingMatches(in: trimmed, range: NSRange(location: 0, length: ns.length), withTemplate: "#")
    }

    private static func isPageNumber(_ line: String) -> Bool {
        let ns = line as NSString
        return pageNumber.regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RepeatedLineFilterTests`
Expected: 4 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Segment/RepeatedLineFilter.swift Tests/T2SCoreTests/RepeatedLineFilterTests.swift
git commit -m "Add repeated-line filter for PDF headers, footers, and page numbers"
```

---

### Task 12: Segmenter and duration estimator

**Files:**
- Create: `Sources/T2SCore/Segment/SourceBlock.swift`
- Create: `Sources/T2SCore/Segment/DurationEstimator.swift`
- Create: `Sources/T2SCore/Segment/Segmenter.swift`
- Create: `Tests/T2SCoreTests/SegmenterTests.swift`

**Interfaces:**
- Consumes: `TextNormalizer`, `Position`, `Utterance`.
- Produces:
  - `struct SourceBlock: Hashable, Sendable { text: String; position: Position }` — one paragraph-level block from an ingest adapter, `position.charOffset` = UTF-16 offset of the block within its resource.
  - `struct ChapterInput: Hashable, Sendable { title: String; position: Position; blocks: [SourceBlock] }`
  - `enum DurationEstimator { static let charsPerSecond: Double; static func estimate(spoken: String) -> TimeInterval }`
  - `struct Segmenter: Sendable { static let version: Int; var maxUtteranceLength: Int; var normalizer: TextNormalizer; init(normalizer:maxUtteranceLength:); func segment(_ block: SourceBlock) -> [Utterance] }`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/SegmenterTests.swift
import Testing
@testable import T2SCore

@Suite struct SegmenterTests {
    let seg = Segmenter(normalizer: TextNormalizer())
    func block(_ text: String, offset: Int = 100) -> SourceBlock {
        SourceBlock(text: text, position: Position(resourceHref: "ch1.xhtml", progression: 0.25, charOffset: offset))
    }

    @Test func splitsSentencesWithOffsets() {
        let us = seg.segment(block("Hello world. This is a test."))
        #expect(us.map(\.source) == ["Hello world.", "This is a test."])
        #expect(us.map(\.position.charOffset) == [100, 113])
        #expect(us.allSatisfy { $0.position.resourceHref == "ch1.xhtml" && $0.position.progression == 0.25 })
    }

    @Test func normalizesSpokenAndKeepsSource() {
        let u = seg.segment(block("Dr. Smith paid $5."))[0]
        #expect(u.source == "Dr. Smith paid $5.")
        #expect(u.spoken == "Doctor Smith paid five dollars.")
        #expect(u.spans.isEmpty == false)
        #expect(u.duration.isActual == false)
        #expect(u.duration.seconds > 0)
    }

    @Test func offsetsUseUTF16() {
        let us = seg.segment(block("Café 😀 ok. Next."))
        #expect(us[1].position.charOffset == 100 + "Café 😀 ok. ".utf16.count)
    }

    @Test func splitsOverlongSentencesAtClauses() {
        let long = Array(repeating: "clause one, clause two; clause three", count: 6).joined(separator: ", ") + "."
        let us = Segmenter(normalizer: TextNormalizer(), maxUtteranceLength: 80).segment(block(long))
        #expect(us.count >= 3)
        #expect(us.allSatisfy { $0.source.utf16.count <= 80 })
        #expect(us.map(\.source).joined(separator: " ") == long)   // nothing lost, nothing duplicated
        #expect(us[1].position.charOffset! > us[0].position.charOffset!)
    }

    @Test func dropsEmptyAndWhitespaceOnly() {
        #expect(seg.segment(block("   \n  ")).isEmpty)
    }

    @Test func estimatorIsProportionalWithFloor() {
        #expect(DurationEstimator.estimate(spoken: "") == 0.5)
        #expect(DurationEstimator.estimate(spoken: String(repeating: "a", count: 150)) == 10)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SegmenterTests`
Expected: FAIL to compile, `cannot find 'Segmenter' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Segment/SourceBlock.swift
public struct SourceBlock: Hashable, Sendable {
    public var text: String
    /// `charOffset` is the UTF-16 offset of this block within its resource's extracted text.
    public var position: Position

    public init(text: String, position: Position) {
        self.text = text
        self.position = position
    }
}

public struct ChapterInput: Hashable, Sendable {
    public var title: String
    public var position: Position
    public var blocks: [SourceBlock]

    public init(title: String, position: Position, blocks: [SourceBlock]) {
        self.title = title
        self.position = position
        self.blocks = blocks
    }
}
```

```swift
// Sources/T2SCore/Segment/DurationEstimator.swift
import Foundation

/// Phase-1 estimate (spec §3.3): ~180 words per minute ≈ 15 UTF-16 units per second.
public enum DurationEstimator {
    public static let charsPerSecond: Double = 15
    public static let floorSeconds: TimeInterval = 0.5

    public static func estimate(spoken: String) -> TimeInterval {
        max(floorSeconds, Double(spoken.utf16.count) / charsPerSecond)
    }
}
```

```swift
// Sources/T2SCore/Segment/Segmenter.swift
import Foundation
import NaturalLanguage

public struct Segmenter: Sendable {
    public static let version = Versions.segmenter
    /// Sentences longer than this (UTF-16 units of source) split at clause boundaries.
    public var maxUtteranceLength: Int
    public var normalizer: TextNormalizer

    public init(normalizer: TextNormalizer, maxUtteranceLength: Int = 300) {
        self.normalizer = normalizer
        self.maxUtteranceLength = maxUtteranceLength
    }

    public func segment(_ block: SourceBlock) -> [Utterance] {
        var result: [Utterance] = []
        for (text, offset) in sentences(in: block.text) {
            for (piece, pieceOffset) in split(text, at: offset) {
                let normalized = normalizer.normalize(piece)
                guard !normalized.spoken.isEmpty else { continue }
                var position = block.position
                position.charOffset = block.position.charOffset.map { $0 + pieceOffset }
                result.append(Utterance(
                    position: position,
                    source: piece,
                    spoken: normalized.spoken,
                    spans: normalized.spans,
                    duration: .estimated(DurationEstimator.estimate(spoken: normalized.spoken))
                ))
            }
        }
        return result
    }

    /// Trimmed sentences with their UTF-16 offset in `text`.
    private func sentences(in text: String) -> [(String, Int)] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [(String, Int)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let raw = text[range]
            let lead = raw.prefix(while: { $0.isWhitespace }).count
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let leadUTF16 = String(raw.prefix(lead)).utf16.count
                out.append((trimmed, range.lowerBound.utf16Offset(in: text) + leadUTF16))
            }
            return true
        }
        return out
    }

    /// Splits `sentence` into pieces ≤ maxUtteranceLength at the last clause boundary before the limit,
    /// falling back to the last space, then to a hard cut. Offsets are UTF-16 into the block.
    private func split(_ sentence: String, at offset: Int) -> [(String, Int)] {
        let ns = sentence as NSString
        guard ns.length > maxUtteranceLength else { return [(sentence, offset)] }
        var pieces: [(String, Int)] = []
        var start = 0
        let clause = CharacterSet(charactersIn: ";:,—–")
        while ns.length - start > maxUtteranceLength {
            let window = NSRange(location: start, length: maxUtteranceLength)
            var cut = ns.rangeOfCharacter(from: clause, options: .backwards, range: window).location
            if cut != NSNotFound && cut > start { cut += 1 }
            if cut == NSNotFound || cut <= start {
                cut = ns.rangeOfCharacter(from: .whitespaces, options: .backwards, range: window).location
            }
            if cut == NSNotFound || cut <= start { cut = start + maxUtteranceLength }
            let piece = ns.substring(with: NSRange(location: start, length: cut - start))
            let lead = piece.prefix(while: { $0.isWhitespace }).count
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { pieces.append((trimmed, offset + start + String(piece.prefix(lead)).utf16.count)) }
            start = cut
        }
        let tail = ns.substring(from: start)
        let lead = tail.prefix(while: { $0.isWhitespace }).count
        let trimmed = tail.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { pieces.append((trimmed, offset + start + String(tail.prefix(lead)).utf16.count)) }
        return pieces
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SegmenterTests`
Expected: 6 tests passed. `splitsOverlongSentencesAtClauses` relies on every cut landing right after a clause mark followed by a single space, which the input guarantees; the invariant being tested is that no source text is lost or duplicated.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Segment Tests/T2SCoreTests/SegmenterTests.swift
git commit -m "Add Segmenter with sentence splitting, clause splitting, and duration estimates"
```

---

### Task 13: Timeline builder (phase 1)

**Files:**
- Create: `Sources/T2SCore/Timeline/TimelineBuilder.swift`
- Create: `Tests/T2SCoreTests/TimelineBuilderTests.swift`

**Interfaces:**
- Consumes: `Segmenter`, `ChapterInput`, `Timeline`.
- Produces: `enum TimelineBuilder { static func build(chapters: [ChapterInput], segmenter: Segmenter) -> Timeline }`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/TimelineBuilderTests.swift
import Testing
@testable import T2SCore

@Suite struct TimelineBuilderTests {
    let chapters = [
        ChapterInput(title: "One", position: Position(resourceHref: "c1.xhtml", progression: 0), blocks: [
            SourceBlock(text: "First para. Two sentences.", position: Position(resourceHref: "c1.xhtml", progression: 0, charOffset: 0)),
            SourceBlock(text: "Second para.", position: Position(resourceHref: "c1.xhtml", progression: 0.5, charOffset: 27)),
        ]),
        ChapterInput(title: "Two", position: Position(resourceHref: "c2.xhtml", progression: 0), blocks: [
            SourceBlock(text: "Only one.", position: Position(resourceHref: "c2.xhtml", progression: 0, charOffset: 0)),
        ]),
    ]

    @Test func buildsChaptersInOrder() {
        let t = TimelineBuilder.build(chapters: chapters, segmenter: Segmenter(normalizer: TextNormalizer()))
        #expect(t.chapters.map(\.title) == ["One", "Two"])
        #expect(t.utteranceRange(ofChapter: 0) == 0..<3)
        #expect(t.utteranceRange(ofChapter: 1) == 3..<4)
        #expect(t[utterance: 2].position.charOffset == 27)
        #expect(t.totalDuration > 0)
        #expect(t.isFullyRendered == false)
    }

    @Test func stampsVersions() {
        let t = TimelineBuilder.build(chapters: chapters, segmenter: Segmenter(normalizer: TextNormalizer()))
        #expect(t.schemaVersion == Versions.schema)
        #expect(t.segmenterVersion == Segmenter.version)
        #expect(t.normalizerVersion == TextNormalizer.version)
    }

    @Test func keepsEmptyChapters() {
        let t = TimelineBuilder.build(chapters: [ChapterInput(title: "Blank", position: Position(resourceHref: "x", progression: 0), blocks: [])],
                                      segmenter: Segmenter(normalizer: TextNormalizer()))
        #expect(t.chapters.count == 1)
        #expect(t.utteranceCount == 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter TimelineBuilderTests`
Expected: FAIL to compile, `cannot find 'TimelineBuilder' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Timeline/TimelineBuilder.swift
/// Phase 1 of spec §3.3: every utterance with a Position and an estimated duration, no audio.
public enum TimelineBuilder {
    public static func build(chapters: [ChapterInput], segmenter: Segmenter) -> Timeline {
        Timeline(
            chapters: chapters.map { input in
                Chapter(title: input.title,
                        position: input.position,
                        utterances: input.blocks.flatMap(segmenter.segment))
            },
            schemaVersion: Versions.schema,
            segmenterVersion: Segmenter.version,
            normalizerVersion: TextNormalizer.version
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter TimelineBuilderTests`
Expected: 3 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Timeline/TimelineBuilder.swift Tests/T2SCoreTests/TimelineBuilderTests.swift
git commit -m "Add TimelineBuilder for phase-1 timelines"
```

---

### Task 14: Per-chapter blob codec

**Files:**
- Create: `Sources/T2SCore/Timeline/TimelineCodec.swift`
- Create: `Tests/T2SCoreTests/TimelineCodecTests.swift`

**Interfaces:**
- Produces: `enum TimelineCodec { static let formatVersion: UInt16; static func encode(_ chapter: Chapter) throws -> Data; static func decode(_ data: Data) throws -> Chapter; enum Error: Swift.Error { badMagic, unsupportedVersion(UInt16), corrupt } }`. Layout: 4-byte magic `T2SC`, little-endian `UInt16` format version, then LZFSE-compressed JSON of `Chapter` (spec §5: one compact blob per chapter).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/TimelineCodecTests.swift
import Foundation
import Testing
@testable import T2SCore

@Suite struct TimelineCodecTests {
    let chapter = Chapter(
        title: "One",
        position: Position(resourceHref: "c1.xhtml", progression: 0),
        utterances: (0..<200).map { i in
            var u = makeUtterance("Sentence number \(i) of the chapter.", seconds: 2, charOffset: i * 40)
            if i % 2 == 0 {
                u.audioRef = "key\(i)"
                u.duration = .actual(2.25)
                u.wordTimings = [WordTiming(spokenRange: 0..<8, start: 0, end: 0.5)]
            }
            return u
        }
    )

    @Test func roundTrips() throws {
        let data = try TimelineCodec.encode(chapter)
        #expect(try TimelineCodec.decode(data) == chapter)
    }

    @Test func isCompactAndTagged() throws {
        let data = try TimelineCodec.encode(chapter)
        #expect(data.prefix(4) == Data("T2SC".utf8))
        #expect(data.count < 200 * 100)                // well below one uncompressed JSON row per utterance
    }

    @Test func rejectsBadMagic() {
        #expect(throws: TimelineCodec.Error.badMagic) { try TimelineCodec.decode(Data("NOPE\u{0}\u{0}xx".utf8)) }
    }

    @Test func rejectsFutureVersion() throws {
        var data = try TimelineCodec.encode(chapter)
        data[4] = 0xFF; data[5] = 0xFF
        #expect(throws: TimelineCodec.Error.unsupportedVersion(0xFFFF)) { try TimelineCodec.decode(data) }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter TimelineCodecTests`
Expected: FAIL to compile, `cannot find 'TimelineCodec' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Timeline/TimelineCodec.swift
import Foundation

public enum TimelineCodec {
    public static let formatVersion: UInt16 = 1
    static let magic = Data("T2SC".utf8)

    public enum Error: Swift.Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt16)
        case corrupt
    }

    public static func encode(_ chapter: Chapter) throws -> Data {
        let json = try JSONEncoder().encode(chapter)
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        var out = magic
        var v = formatVersion.littleEndian
        withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
        out.append(compressed)
        return out
    }

    public static func decode(_ data: Data) throws -> Chapter {
        guard data.count >= 6, data.prefix(4) == magic else { throw Error.badMagic }
        let version = UInt16(data[4]) | (UInt16(data[5]) << 8)
        guard version == formatVersion else { throw Error.unsupportedVersion(version) }
        let payload = data.dropFirst(6)
        guard let json = try? (payload as NSData).decompressed(using: .lzfse) as Data else { throw Error.corrupt }
        do { return try JSONDecoder().decode(Chapter.self, from: json) }
        catch { throw Error.corrupt }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter TimelineCodecTests`
Expected: 4 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Timeline/TimelineCodec.swift Tests/T2SCoreTests/TimelineCodecTests.swift
git commit -m "Add TimelineCodec: versioned, LZFSE-compressed per-chapter blobs"
```

---

### Task 15: Position resolution

**Files:**
- Create: `Sources/T2SCore/Timeline/PositionResolver.swift`
- Create: `Tests/T2SCoreTests/PositionResolverTests.swift`

**Interfaces:**
- Consumes: `Timeline`, `Playhead`, `Position`, `NormalizedText.init(source:spoken:spans:)` and its two projections.
- Produces:
  - `extension Utterance { func time(atSourceOffset: Int) -> TimeInterval; func sourceOffset(atTime: TimeInterval) -> Int }` using word timings when present, proportional otherwise.
  - `enum PositionResolver { static func resolve(_ p: Position, in t: Timeline) -> Playhead; static func position(for ph: Playhead, in t: Timeline) -> Position }`.
- Resolution order: same `resourceHref` and `charOffset` inside an utterance's source range → exact; same href and `charOffset` before the first or between utterances → the last utterance starting at or before it; same href without `charOffset` → last utterance with `progression <= p.progression`; href unknown → start of the chapter whose `position.resourceHref` matches, else chapter 0 start (spec §6: chapter start, never further back than that).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/PositionResolverTests.swift
import Testing
@testable import T2SCore

@Suite struct PositionResolverTests {
    // Chapter 1: "Alpha beta." (0..<11) "Gamma delta epsilon." (12..<32)   Chapter 2: "Zeta." (0..<5)
    let t = makeTimeline([
        [makeUtterance("Alpha beta.", seconds: 2, charOffset: 0, progression: 0.0),
         makeUtterance("Gamma delta epsilon.", seconds: 4, charOffset: 12, progression: 0.4)],
        [makeUtterance("Zeta.", seconds: 1, href: "ch2.xhtml", charOffset: 0, progression: 0.0)],
    ])

    @Test func exactCharOffsetInsideUtterance() {
        let ph = PositionResolver.resolve(Position(resourceHref: "ch1.xhtml", progression: 0.4, charOffset: 22), in: t)
        #expect(ph.utteranceIndex == 1)
        #expect(abs(ph.offset - 2.0) < 0.01)          // 10 of 20 chars → half of 4 s
    }

    @Test func charOffsetInGapSnapsToPrecedingUtterance() {
        let ph = PositionResolver.resolve(Position(resourceHref: "ch1.xhtml", progression: 0.3, charOffset: 11), in: t)
        #expect(ph == Playhead(utteranceIndex: 0, offset: 2.0))
    }

    @Test func progressionOnlyFallsBackToNearest() {
        let ph = PositionResolver.resolve(Position(resourceHref: "ch1.xhtml", progression: 0.9), in: t)
        #expect(ph == Playhead(utteranceIndex: 1, offset: 0))
    }

    @Test func unknownHrefFallsBackToChapterStartNeverDocumentStart() {
        let ph = PositionResolver.resolve(Position(resourceHref: "ch2.xhtml", progression: 0.5, charOffset: 9_999), in: t)
        #expect(ph.utteranceIndex == 2)
        let ph2 = PositionResolver.resolve(Position(resourceHref: "missing.xhtml", progression: 0.5), in: t)
        #expect(ph2 == Playhead(utteranceIndex: 0, offset: 0))
    }

    @Test func roundTripsThroughPosition() {
        let ph = Playhead(utteranceIndex: 1, offset: 1.0)
        let p = PositionResolver.position(for: ph, in: t)
        #expect(p.resourceHref == "ch1.xhtml")
        #expect(p.charOffset == 17)                     // 1 of 4 s → 5 of 20 chars
        #expect(PositionResolver.resolve(p, in: t) == ph)
    }

    @Test func usesWordTimingsWhenPresent() {
        var t = t
        t[utterance: 1].wordTimings = [
            WordTiming(spokenRange: 0..<5, start: 0, end: 1),      // Gamma
            WordTiming(spokenRange: 6..<11, start: 1, end: 3),     // delta
            WordTiming(spokenRange: 12..<20, start: 3, end: 4),    // epsilon.
        ]
        let ph = PositionResolver.resolve(Position(resourceHref: "ch1.xhtml", progression: 0.4, charOffset: 18), in: t)
        #expect(ph.utteranceIndex == 1)
        #expect(ph.offset == 1.0)                       // "delta" starts at source 18 → 1.0 s
        #expect(PositionResolver.position(for: Playhead(utteranceIndex: 1, offset: 3.5), in: t).charOffset == 24)
    }

    @Test func survivesResegmentation() {
        let text = "One sentence here. Another sentence follows, with a clause; and another clause here. Third."
        let block = SourceBlock(text: text, position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 0))
        let coarse = TimelineBuilder.build(chapters: [ChapterInput(title: "C", position: block.position, blocks: [block])],
                                           segmenter: Segmenter(normalizer: TextNormalizer(), maxUtteranceLength: 300))
        let fine = TimelineBuilder.build(chapters: [ChapterInput(title: "C", position: block.position, blocks: [block])],
                                         segmenter: Segmenter(normalizer: TextNormalizer(), maxUtteranceLength: 30))
        #expect(fine.utteranceCount > coarse.utteranceCount)
        for i in 0..<coarse.utteranceCount {
            let u = coarse[utterance: i]
            let ph = Playhead(utteranceIndex: i, offset: u.duration.seconds / 2)
            let p = PositionResolver.position(for: ph, in: coarse)
            let re = PositionResolver.resolve(p, in: fine)
            let landed = fine[utterance: re.utteranceIndex]
            let landedChar = landed.position.charOffset! + landed.sourceOffset(atTime: re.offset)
            #expect(abs(landedChar - p.charOffset!) <= 1, "utterance \(i)")
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PositionResolverTests`
Expected: FAIL to compile, `cannot find 'PositionResolver' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Timeline/PositionResolver.swift
import Foundation

extension Utterance {
    var normalized: NormalizedText {
        NormalizedText(source: source, spoken: spoken, spans: spans)
    }

    /// Seconds at 1x at which the source character at `offset` is spoken.
    public func time(atSourceOffset offset: Int) -> TimeInterval {
        let clamped = max(0, min(offset, source.utf16.count))
        let spokenAt = normalized.spokenRange(forSource: clamped..<min(clamped + 1, source.utf16.count)).lowerBound
        if let timings = wordTimings, !timings.isEmpty {
            if let w = timings.last(where: { $0.spokenRange.lowerBound <= spokenAt }) { return w.start }
            return 0
        }
        let n = max(1, spoken.utf16.count)
        return duration.seconds * Double(spokenAt) / Double(n)
    }

    /// Source UTF-16 offset being spoken at `time` seconds at 1x.
    public func sourceOffset(atTime time: TimeInterval) -> Int {
        let spokenAt: Int
        if let timings = wordTimings, !timings.isEmpty {
            spokenAt = timings.last(where: { $0.start <= time })?.spokenRange.lowerBound ?? 0
        } else {
            let fraction = duration.seconds > 0 ? max(0, min(1, time / duration.seconds)) : 0
            spokenAt = Int((Double(spoken.utf16.count) * fraction).rounded(.down))
        }
        return normalized.sourceRange(forSpoken: spokenAt..<min(spokenAt + 1, spoken.utf16.count)).lowerBound
    }
}

public enum PositionResolver {
    /// Never fails. Falls back to chapter start, never to document start (spec §6).
    public static func resolve(_ p: Position, in t: Timeline) -> Playhead {
        var index = 0
        var candidates: [(Int, Utterance)] = []
        for ch in t.chapters {
            for u in ch.utterances {
                if u.position.resourceHref == p.resourceHref { candidates.append((index, u)) }
                index += 1
            }
        }

        if !candidates.isEmpty {
            if let c = p.charOffset {
                if let (i, u) = candidates.first(where: {
                    guard let start = $0.1.position.charOffset else { return false }
                    return start <= c && c < start + $0.1.source.utf16.count
                }) {
                    return Playhead(utteranceIndex: i, offset: u.time(atSourceOffset: c - u.position.charOffset!))
                }
                if let (i, u) = candidates.last(where: { ($0.1.position.charOffset ?? Int.max) <= c }) {
                    return Playhead(utteranceIndex: i, offset: u.duration.seconds)
                }
                return Playhead(utteranceIndex: candidates[0].0, offset: 0)
            }
            let (i, _) = candidates.last(where: { $0.1.position.progression <= p.progression }) ?? candidates[0]
            return Playhead(utteranceIndex: i, offset: 0)
        }

        if let c = t.chapters.firstIndex(where: { $0.position.resourceHref == p.resourceHref }),
           !t.chapters[c].utterances.isEmpty {
            return Playhead(utteranceIndex: t.utteranceRange(ofChapter: c).lowerBound, offset: 0)
        }
        return Playhead(utteranceIndex: 0, offset: 0)
    }

    public static func position(for ph: Playhead, in t: Timeline) -> Position {
        let u = t[utterance: ph.utteranceIndex]
        var p = u.position
        p.charOffset = u.position.charOffset.map { $0 + u.sourceOffset(atTime: ph.offset) }
        return p
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PositionResolverTests`
Expected: 7 tests passed. `roundTripsThroughPosition` expects `charOffset == 17`: 1 s of 4 s is 25% of 20 spoken chars = 5, plus the utterance start 12.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore Tests/T2SCoreTests
git commit -m "Add PositionResolver with charOffset, progression, and chapter-start fallbacks"
```

---

### Task 16: Highlight projection

**Files:**
- Create: `Sources/T2SCore/Timeline/Highlighter.swift`
- Create: `Tests/T2SCoreTests/HighlighterTests.swift`

**Interfaces:**
- Consumes: `Timeline`, `Playhead`, `Utterance.normalized`.
- Produces: `struct HighlightRange: Hashable, Sendable { utteranceIndex: Int; position: Position; sourceRange: Range<Int> }` where `sourceRange` is within that utterance's `source`; `enum Highlighter { static func highlight(at ph: Playhead, in t: Timeline) -> HighlightRange? }`. Uses word timings when present; otherwise picks the word by elapsed fraction. Skips spoken words whose source range is empty (insertions) by advancing to the next word.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/HighlighterTests.swift
import Testing
@testable import T2SCore

@Suite struct HighlighterTests {
    func timed() -> Timeline {
        var u = Segmenter(normalizer: TextNormalizer()).segment(
            SourceBlock(text: "Dr. Smith paid $5.", position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 40))
        )[0]
        // spoken: "Doctor Smith paid five dollars."
        u.wordTimings = [
            WordTiming(spokenRange: 0..<6, start: 0.0, end: 0.5),
            WordTiming(spokenRange: 7..<12, start: 0.5, end: 1.0),
            WordTiming(spokenRange: 13..<17, start: 1.0, end: 1.4),
            WordTiming(spokenRange: 18..<22, start: 1.4, end: 1.8),
            WordTiming(spokenRange: 23..<31, start: 1.8, end: 2.4),
        ]
        u.duration = .actual(2.4)
        return makeTimeline([[u]])
    }

    @Test func projectsExpandedWordToAbbreviation() {
        let h = Highlighter.highlight(at: Playhead(utteranceIndex: 0, offset: 0.25), in: timed())
        #expect(h?.sourceRange == 0..<3)               // "Dr."
        #expect(h?.position.charOffset == 40)
    }

    @Test func projectsCurrencyWordsToWholeToken() {
        let t = timed()
        #expect(Highlighter.highlight(at: Playhead(utteranceIndex: 0, offset: 1.5), in: t)?.sourceRange == 15..<17)   // "five" → "$5"
        #expect(Highlighter.highlight(at: Playhead(utteranceIndex: 0, offset: 2.0), in: t)?.sourceRange == 15..<18)   // "dollars." → "$5."
    }

    @Test func fallsBackToProportionalWithoutTimings() {
        var t = timed()
        t[utterance: 0].wordTimings = nil
        t[utterance: 0].duration = .estimated(2.0)
        let h = Highlighter.highlight(at: Playhead(utteranceIndex: 0, offset: 0.6), in: t)   // 30% → "Smith"
        #expect(h?.sourceRange == 4..<9)
    }

    @Test func nilPastEnd() {
        #expect(Highlighter.highlight(at: Playhead(utteranceIndex: 5, offset: 0), in: timed()) == nil)
    }

    @Test func skipsInsertedWords() {
        var t = timed()
        var n = NormalizedText(source: "world")
        n.replace(spokenRange: 0..<0, with: "Hello ")
        t[utterance: 0] = Utterance(position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 0),
                                    source: n.source, spoken: n.spoken, spans: n.spans,
                                    duration: .actual(1),
                                    wordTimings: [WordTiming(spokenRange: 0..<5, start: 0, end: 0.5),
                                                  WordTiming(spokenRange: 6..<11, start: 0.5, end: 1)])
        #expect(Highlighter.highlight(at: Playhead(utteranceIndex: 0, offset: 0.1), in: t)?.sourceRange == 0..<5)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter HighlighterTests`
Expected: FAIL to compile, `cannot find 'Highlighter' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Timeline/Highlighter.swift
import Foundation

public struct HighlightRange: Hashable, Sendable {
    public var utteranceIndex: Int
    /// The utterance's start position; combine with `sourceRange` to decorate the document.
    public var position: Position
    /// UTF-16 range within the utterance's `source`.
    public var sourceRange: Range<Int>
}

public enum Highlighter {
    static let word = Pattern("\\S+")

    public static func highlight(at ph: Playhead, in t: Timeline) -> HighlightRange? {
        guard ph.utteranceIndex >= 0, ph.utteranceIndex < t.utteranceCount else { return nil }
        let u = t[utterance: ph.utteranceIndex]
        let spokenWords: [Range<Int>]
        if let timings = u.wordTimings, !timings.isEmpty {
            let i = timings.lastIndex(where: { $0.start <= ph.offset }) ?? 0
            spokenWords = Array(timings[i...].map(\.spokenRange))
        } else {
            let ns = u.spoken as NSString
            let all = word.regex.matches(in: u.spoken, range: NSRange(location: 0, length: ns.length))
                .map { $0.range.location..<($0.range.location + $0.range.length) }
            guard !all.isEmpty else { return nil }
            let fraction = u.duration.seconds > 0 ? max(0, min(0.999, ph.offset / u.duration.seconds)) : 0
            let i = Int(Double(all.count) * fraction)
            spokenWords = Array(all[i...])
        }
        let n = u.normalized
        for w in spokenWords {
            let src = n.sourceRange(forSpoken: w)
            if !src.isEmpty {
                return HighlightRange(utteranceIndex: ph.utteranceIndex, position: u.position, sourceRange: src)
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter HighlighterTests`
Expected: 5 tests passed.

- [ ] **Step 5: Run the whole suite and the license guard**

Run: `swift test && scripts/check-licenses.sh`
Expected: all suites pass; guard exits 0.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SCore/Timeline/Highlighter.swift Tests/T2SCoreTests/HighlighterTests.swift
git commit -m "Add Highlighter: playhead to source-range projection"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| §3.1 domain model, UTF-16 ranges | 2 |
| §3.2 Position persisted, Playhead runtime | 2, 15 |
| §3.3 phase-1 timeline with estimates | 12, 13 |
| §3.7.4 versions on everything persisted | 1, 2, 13, 14 |
| §3.7.5 license check in CI | 1 |
| §4.1 NormalizedText, rules 1–6, mapping conventions | 3–10 |
| §4.1 rule 2 (PDF headers/footers) | 11 |
| §5 per-chapter blob | 14 |
| §6 fallback to chapter start | 15 |
| §8 TextNormalizer table tests and projection invariant | 3–10 |
| §8 Segmenter golden tests, Position round-trip | 12, 15 |
| §8 re-segmentation tolerance | 15 |
| §8 Highlight: exact source range for a playhead | 16 |

Not in this plan, by design: Readium ingest (`SourceBlock` producers) and SwiftData persistence are Plan 3; `SynthesisEngine`, `FakeEngine`, render keys, scheduler, and player are Plan 2.
