# Plan 3: Persistence and Ingest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the pipeline a library: a SwiftData store that persists documents, per-chapter timeline blobs, resume positions, bookmarks, and the pronunciation dictionary; readers that turn an EPUB (Readium), a text PDF (PDFKit), or a web article (written to a minimal EPUB) into `ChapterInput`s with stable `Position`s; and a `Library` facade that imports, deletes, re-derives stale timelines, and evicts audio.

**Architecture:** Two new targets in the root package and one new iOS-only package. `T2SStore` (SwiftData) holds internal `@Model` rows behind a `@ModelActor` `LibraryStore` that speaks only `T2SCore` value types and implements `PlayheadStore`. `T2SLibrary` (Foundation, PDFKit, ImageIO) holds the `DocumentReader` protocol, the app-container layout (`LibraryPaths`), a stored-only ZIP writer and the article-to-EPUB writer, the PDFKit reader, and the `Library` actor that orchestrates import → `TimelineBuilder` → store. `Packages/T2SReadium` is a separate package because the Readium toolkit declares iOS only and fails manifest validation for macOS; it holds `ReadiumDocumentReader` (EPUB and article EPUB) and the `Position` ↔ `Locator` mapping, and is tested on the iOS simulator with `scripts/test-readium.sh`. The root package stays fully `swift test`-able on macOS.

**Tech Stack:** Swift 6 (language mode 6), SwiftPM, Swift Testing, SwiftData (`@Model`, `@ModelActor`), PDFKit + CoreGraphics + ImageIO (PDF text and cover), Foundation `XMLParser`, Readium swift-toolkit **3.11.0** (BSD-3-Clause; `ReadiumShared`, `ReadiumStreamer`) pinned exactly. macOS 15 for root-package tests, iOS 18 deployment; Xcode 26 / Swift 6.2 locally.

**Spec:** `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (rev 6). Sections §2.1, §2.3, §3.1, §3.2, §3.7.1–§3.7.5, §4, §5, §6, §7.6, §8, §9 step 3 (Readium part) and step 4 (`TimelineStore`).

## Global Constraints

- **Readium types are never persisted and never cross the `T2SReadium` boundary.** `Position` is the only persisted anchor; `Locator` is converted at the boundary (spec §3.7.2). `T2SCore`, `T2SStore`, `T2SLibrary` never import Readium.
- **Client-generated `UUID` primary keys** (spec §3.7.1). SwiftData `@Model` classes are `internal`; every public store API takes and returns `T2SCore` value types.
- **Utterances are stored as one `TimelineCodec` blob per chapter**, never as rows (spec §5). Per-chapter `utteranceCount`, `durationSeconds`, `renderedCount` are denormalized beside the blob so list screens never decode a blob.
- **Everything persisted carries `schemaVersion`, `segmenterVersion`, `normalizerVersion`** (spec §3.7.4). A mismatch against `Versions` marks the timeline stale; the fix is re-derivation from the retained source, never a migration (spec §3.7.3). Re-derivation removes the old utterances' audio keys from the `AudioStore` (orphan GC).
- **Rendered audio is cache.** `audioRef` on a persisted utterance is a hint; deleting a document, evicting its audio, or reprocessing it removes those keys from the store.
- **Source files are never mutated in place; the originally fetched article HTML is retained** next to the generated EPUB (spec §2.1, §3.7.3).
- **Error rows of spec §6:** a DRM-protected EPUB is rejected with `ImportError.drmProtected`; a malformed publication imports what parses and lists skipped resources; a source with no text is rejected with `ImportError.noText` before anything enters the library.
- **Everything imported joins the Queue** at the end; the Collection is every EPUB and PDF regardless of queue state (spec §2.3).
- **`Position` semantics per source type** (fixed here; Plan 4 depends on them):
  - EPUB / article: `resourceHref` = the reading-order resource href as Readium reports it (e.g. `OEBPS/ch1.xhtml`); `progression` = Readium's element progression within that resource; `charOffset` = UTF-16 offset of the block within the resource's text where blocks are joined by `"\n"`; `cssSelector` = Readium's selector for the block's element when it has one.
  - PDF: `resourceHref` = `"source.pdf"`; `progression` = `pageIndex / pageCount` (page start); `charOffset` = UTF-16 offset into the document text formed by joining the header-filtered page texts with `"\n"`; `cssSelector` = nil.
- **Segmentation and normalization happen at import** (Plan 1's `TimelineBuilder`), using the pronunciation dictionary held in the store at that moment. Dictionary edits reach existing documents through `Library.reprocess`, not a migration.
- **License ratchet** (spec §3.7.5): Readium pinned `exact: "3.11.0"` (BSD-3-Clause, verified). `scripts/check-licenses.sh` covers the root package and every package under `Packages/`.
- **Root package builds and tests on macOS with `swift test`.** Readium code lives only in `Packages/T2SReadium`, platform iOS only, tested with `scripts/test-readium.sh` (xcodebuild on the first available iPhone simulator).
- Every public type is `Sendable`, an actor, or `@MainActor`; no `nonisolated(unsafe)`. Swift Testing; run a root suite with `swift test --filter <SuiteName>`.
- Commit after every task with the message given in the task.

## Verified toolchain facts (do not re-derive)

- SwiftData `@Model` + `@ModelActor` compile and run under `swift test` on macOS 15 in Swift 6 mode (in-memory and on-disk `ModelConfiguration`).
- Readium swift-toolkit 3.11.0 declares `platforms: [.iOS(.v15)]`. Any package graph containing it fails on macOS with "the library 'ReadiumShared' requires macos 10.13, but depends on … SwiftSoup which requires macos 10.15" — even when the product dependency is conditioned on iOS. Hence the separate package.
- For a package directory, `xcodebuild -scheme <ProductName>` uses the auto-generated scheme (the scheme is named after the product, not `<Package>-Package`), and `-destination "id=<simulator udid>"` is the reliable destination form.
- Readium 3.11.0 API used here: `AssetRetriever(httpClient:)`, `retrieve(url: FileURL) async -> Result<Asset, AssetRetrieveURLError>`; `PublicationOpener(parser: DefaultPublicationParser(httpClient:assetRetriever:pdfFactory:))`, `open(asset:allowUserInteraction:) async -> Result<Publication, PublicationOpenError>` with cases `.formatNotSupported` and `.reading(ReadError)`; `Publication.isRestricted`, `.metadata.title: String?`, `.metadata.authors: [Contributor]` (`.name`), `.readingOrder: [Link]` (`href: String`, `title: String?`, `url() -> AnyURL`), `tableOfContents() async -> ReadResult<[Link]>`, `cover() async -> ReadResult<UIImage?>`, `content() -> Content?`, `Content.sequence()` (an `AsyncSequence` of `ContentElement`), `TextContentElement { locator, role, segments, text: String? }`, `Locator { href: AnyURL, mediaType, locations: Locations { progression, otherLocations["cssSelector"] as JSONValue.string }, text: Text { before, highlight, after } }`, `AnyURL.string`, `MediaType.xhtml`. A DRM'd EPUB is one whose `META-INF/encryption.xml` contains `enc:EncryptedData/sig:KeyInfo/adept:resource` (Adobe ADEPT) or an LCP license; Readium opens it as a restricted publication.

## File structure

```
Package.swift                                   + T2SStore, T2SLibrary targets and products
Sources/T2SCore/Model/PlayheadStore.swift       moved from T2SAudio (protocol only)
Sources/T2SCore/Model/Bookmark.swift            domain type
Sources/T2SStore/
  T2SStore.swift                                module marker
  Models.swift                                  internal @Model rows
  LibraryStore.swift                            @ModelActor: documents, queue, chapters, summaries
  LibraryStore+Playhead.swift                   PlayheadStore conformance
  LibraryStore+Bookmarks.swift
  LibraryStore+Pronunciation.swift
Sources/T2SLibrary/
  T2SLibrary.swift                              module marker
  DocumentReader.swift                          DocumentReader protocol, ReadDocument
  ImportError.swift
  LibraryPaths.swift                            app-container layout
  Archive/CRC32.swift
  Archive/StoredZipWriter.swift                 stored-only ZIP (EPUB container)
  Article/ArticleContent.swift
  Article/XHTML.swift                           escape, well-formedness, plain text
  Article/ArticleEPUBWriter.swift
  PDF/PDFDocumentReader.swift                   PDFKit text + outline → ChapterInput
  PDF/PDFCover.swift                            first page → JPEG via CoreGraphics + ImageIO
  Library.swift                                 import / delete / reprocess / evict facade
Tests/T2SStoreTests/…                           LibraryStore, playhead, bookmarks, dictionary
Tests/T2SLibraryTests/…                         paths, zip, article writer, PDF reader, Library
Packages/T2SReadium/
  Package.swift                                 iOS-only; depends on ../.. and swift-toolkit 3.11.0
  Sources/T2SReadium/T2SReadium.swift           module marker
  Sources/T2SReadium/ReadiumDocumentReader.swift
  Sources/T2SReadium/LocatorMapping.swift
  Tests/T2SReadiumTests/…                       simulator tests; fixtures built with StoredZipWriter
scripts/test-readium.sh                         xcodebuild test on the first available iPhone simulator
scripts/check-licenses.sh                       now loops over root + Packages/*
.github/workflows/ci.yml                        + readium-ios job
README.md                                       layout update
```

---

### Task 1: Targets, package layout, protocol move, CI, license guard

**Files:**
- Modify: `Package.swift`
- Move: `Sources/T2SAudio/PlayheadStore.swift` → `Sources/T2SCore/Model/PlayheadStore.swift` (`git mv`)
- Create: `Sources/T2SStore/T2SStore.swift`, `Sources/T2SLibrary/T2SLibrary.swift`
- Create: `Tests/T2SStoreTests/T2SStoreSmokeTests.swift`, `Tests/T2SLibraryTests/T2SLibrarySmokeTests.swift`
- Create: `Packages/T2SReadium/Package.swift`, `Packages/T2SReadium/Sources/T2SReadium/T2SReadium.swift`, `Packages/T2SReadium/Tests/T2SReadiumTests/T2SReadiumSmokeTests.swift`
- Create: `scripts/test-readium.sh`
- Modify: `scripts/check-licenses.sh`, `.github/workflows/ci.yml`, `README.md`, `docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md`

**Interfaces:**
- Consumes: `T2SCore.Versions`, `T2SCore.Position`.
- Produces: products `T2SStore`, `T2SLibrary` (root), `T2SReadium` (sub-package); `public protocol PlayheadStore: Sendable { func save(_ position: Position, for documentID: UUID) async }` now in `T2SCore` (unchanged text); `scripts/test-readium.sh`.

- [ ] **Step 1: Move the protocol**

```bash
git mv Sources/T2SAudio/PlayheadStore.swift Sources/T2SCore/Model/PlayheadStore.swift
```

Then edit the moved file so it reads exactly:

```swift
// Sources/T2SCore/Model/PlayheadStore.swift
import Foundation

/// Where resume positions go (spec §5: local is the source of truth). `T2SStore.LibraryStore` conforms.
public protocol PlayheadStore: Sendable {
    func save(_ position: Position, for documentID: UUID) async
}
```

`T2SAudio` already imports `T2SCore`, so `PlaybackCoordinator` and `Tests/T2SAudioTests/Support/MemoryPlayheadStore.swift` need no change (the test file imports both modules).

- [ ] **Step 2: Write the smoke tests**

```swift
// Tests/T2SStoreTests/T2SStoreSmokeTests.swift
import Testing
import T2SCore
@testable import T2SStore

@Suite struct T2SStoreSmokeTests {
    @Test func linksAgainstCore() {
        #expect(T2SStore.coreSchemaVersion == Versions.schema)
    }
}
```

```swift
// Tests/T2SLibraryTests/T2SLibrarySmokeTests.swift
import Testing
import T2SCore
@testable import T2SLibrary

@Suite struct T2SLibrarySmokeTests {
    @Test func linksAgainstCore() {
        #expect(T2SLibrary.coreSchemaVersion == Versions.schema)
    }
}
```

- [ ] **Step 3: Package manifest and module markers**

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "T2S",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "T2SCore", targets: ["T2SCore"]),
        .library(name: "T2SAudio", targets: ["T2SAudio"]),
        .library(name: "T2SStore", targets: ["T2SStore"]),
        .library(name: "T2SLibrary", targets: ["T2SLibrary"]),
    ],
    targets: [
        .target(name: "T2SCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "T2SAudio", dependencies: ["T2SCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "T2SStore", dependencies: ["T2SCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "T2SLibrary", dependencies: ["T2SCore", "T2SStore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "T2SCoreTests",
            dependencies: ["T2SCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "T2SAudioTests",
            dependencies: ["T2SAudio", "T2SCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "T2SStoreTests",
            dependencies: ["T2SStore", "T2SCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "T2SLibraryTests",
            dependencies: ["T2SLibrary", "T2SStore", "T2SCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

```swift
// Sources/T2SStore/T2SStore.swift
import T2SCore

/// SwiftData persistence for documents, chapter blobs, positions, bookmarks, and the dictionary (spec §5).
public enum T2SStore {
    /// The T2SCore schema this build of T2SStore was compiled against.
    public static let coreSchemaVersion = Versions.schema
}
```

```swift
// Sources/T2SLibrary/T2SLibrary.swift
import T2SCore

/// Ingest and library orchestration: readers, the article-to-EPUB writer, the app-container layout,
/// and the `Library` facade over `T2SStore` (spec §4).
public enum T2SLibrary {
    /// The T2SCore schema this build of T2SLibrary was compiled against.
    public static let coreSchemaVersion = Versions.schema
}
```

- [ ] **Step 4: Run the root suite**

Run: `swift test`
Expected: builds; the two smoke suites pass alongside the existing 153 tests (155 total).

- [ ] **Step 5: The iOS-only Readium package**

```swift
// Packages/T2SReadium/Package.swift
// swift-tools-version: 6.0
import PackageDescription

// iOS only, on purpose: the Readium toolkit declares no macOS platform, and any package graph that
// contains it fails deployment-target validation on macOS. Keeping it here leaves the root package
// `swift test`-able on macOS. Test with `scripts/test-readium.sh` (xcodebuild on an iPhone simulator).
let package = Package(
    name: "T2SReadium",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "T2SReadium", targets: ["T2SReadium"]),
    ],
    dependencies: [
        .package(name: "T2S", path: "../.."),
        .package(url: "https://github.com/readium/swift-toolkit.git", exact: "3.11.0"),
    ],
    targets: [
        .target(
            name: "T2SReadium",
            dependencies: [
                .product(name: "T2SCore", package: "T2S"),
                .product(name: "T2SLibrary", package: "T2S"),
                .product(name: "ReadiumShared", package: "swift-toolkit"),
                .product(name: "ReadiumStreamer", package: "swift-toolkit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "T2SReadiumTests",
            dependencies: [
                "T2SReadium",
                .product(name: "T2SCore", package: "T2S"),
                .product(name: "T2SLibrary", package: "T2S"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

```swift
// Packages/T2SReadium/Sources/T2SReadium/T2SReadium.swift
import ReadiumShared
import T2SCore

/// Readium adapter: opens EPUBs into `ChapterInput`s and converts `Position` ↔ `Locator` at the
/// boundary (spec §3.7.2). Nothing from ReadiumShared leaves this module.
public enum T2SReadium {
    /// The T2SCore schema this build of T2SReadium was compiled against.
    public static let coreSchemaVersion = Versions.schema
}
```

```swift
// Packages/T2SReadium/Tests/T2SReadiumTests/T2SReadiumSmokeTests.swift
import ReadiumShared
import Testing
import T2SCore
@testable import T2SReadium

@Suite struct T2SReadiumSmokeTests {
    @Test func linksAgainstCoreAndReadium() {
        #expect(T2SReadium.coreSchemaVersion == Versions.schema)
        #expect(MediaType.xhtml.string == "application/xhtml+xml")
    }
}
```

```bash
# scripts/test-readium.sh
#!/usr/bin/env bash
# Runs the iOS-only Packages/T2SReadium tests on an iPhone simulator.
# Usage: scripts/test-readium.sh [extra xcodebuild args]
# Env:   SIMULATOR_ID=<udid> to pick a simulator; otherwise the first available iPhone is used.
set -euo pipefail
cd "$(dirname "$0")/../Packages/T2SReadium"

if [[ -z "${SIMULATOR_ID:-}" ]]; then
  SIMULATOR_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
devs = [d for r in sorted(runtimes) for d in runtimes[r] if d.get("isAvailable") and "iPhone" in d["name"]]
print(devs[-1]["udid"] if devs else "")')
  if [[ -z "$SIMULATOR_ID" ]]; then
    echo "no available iPhone simulator; install one in Xcode > Settings > Components" >&2
    exit 1
  fi
fi

echo "simulator: $SIMULATOR_ID"
set +e
xcodebuild test -scheme T2SReadium -destination "id=$SIMULATOR_ID" \
  -derivedDataPath .build/DerivedData "$@" 2>&1 \
  | grep -E "error:|warning:|Suite |Test run|Executed|TEST (SUCCEEDED|FAILED)|Testing failed" \
  | grep -Ev "/checkouts/.*: warning:"
exit "${PIPESTATUS[0]}"
```

**Implementation note (recorded after execution).** The original filter matched `warning: .*T2SReadium`, which never matches a real diagnostic because the module name sits in the path before `warning:`; the script now shows every warning except those from dependency checkouts.

Run: `chmod +x scripts/test-readium.sh && scripts/test-readium.sh`
Expected: `** TEST SUCCEEDED **` with the smoke test passing. The first run resolves and builds Readium and its dependencies for the simulator (several minutes); later runs are incremental. If `xcodebuild` reports no matching destination, run `xcrun simctl list devices available` and pass `SIMULATOR_ID=<udid>`.

- [ ] **Step 6: License guard over every package, CI job, README, roadmap**

```bash
# scripts/check-licenses.sh
#!/usr/bin/env bash
# scripts/check-licenses.sh — fails if any checked-out SPM dependency is copyleft.
# Scope: SPM checkouts of the root package and every package under Packages/; a binaryTarget or
# vendored source must be audited by hand (docs/licenses.md).
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob
status=0

check_package() {
  local pkg=$1
  echo "== $pkg"
  (cd "$pkg" && swift package resolve >/dev/null)
  for dir in "$pkg"/.build/checkouts/*/; do
    local name; name=$(basename "$dir")
    # Glob into an array: with nullglob an unmatched pattern yields an empty array.
    local files=( "$dir"LICENSE* "$dir"COPYING* )
    if [[ ${#files[@]} -eq 0 ]]; then
      echo "NO LICENSE FILE: $name"; status=1; continue
    fi
    if grep -qiE 'GNU (AFFERO |LESSER )?GENERAL PUBLIC LICENSE' "${files[0]}"; then
      echo "COPYLEFT: $name (${files[0]})"; status=1
    else
      echo "ok: $name"
    fi
  done
}

check_package .
for pkg in Packages/*/; do
  check_package "${pkg%/}"
done
exit $status
```

Run: `scripts/check-licenses.sh`
Expected: `== .` with no checkouts, then `== Packages/T2SReadium` listing `ok:` for `swift-toolkit`, `Fuzi`, `ZIPFoundation`, `Zip`, `SwiftSoup`, `swift-docc-plugin`, `swift-docc-symbolkit`, `CryptoSwift`, `GCDWebServer`, `SQLite.swift`, `DifferenceKit` (the exact set is whatever 3.11.0 resolves); exit 0. Any `COPYLEFT:` line stops this plan: report it.

```yaml
# .github/workflows/ci.yml
name: ci
on: [push, pull_request]
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: swift --version
      - run: swift test
      - run: scripts/check-licenses.sh
  readium-ios:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - run: xcodebuild -version
      - run: scripts/test-readium.sh
```

README: replace the layout block and the "Working on it" block with:

````markdown
## Repository layout

```
Package.swift          Swift package "T2S". Targets: T2SCore (text pipeline), T2SAudio
                       (playback), T2SStore (SwiftData), T2SLibrary (ingest + library facade).
Sources/<Target>/      library code, one directory per target
Tests/<Target>Tests/   Swift Testing suites; run with `swift test` on macOS
Packages/T2SReadium/   iOS-only package wrapping the Readium toolkit (EPUB reading, Locator
                       mapping). Readium does not build for macOS, so it is tested on the iOS
                       simulator with scripts/test-readium.sh.
App/                   (Plan 4) the iOS app and its extensions, generated by xcodegen
scripts/               CI helpers (check-licenses.sh, test-readium.sh)
spikes/                throwaway experiments — never imported by shipping code
  SpikeHarness/        iOS harness for spec §7; project.yml → generated .xcodeproj (ignored)
  findings/            one markdown file per spike result, from findings/TEMPLATE.md
docs/superpowers/
  specs/               design specs (the source of truth for what gets built)
  plans/               implementation plans, one file per plan, plus the roadmap
.github/workflows/     CI: swift test + license guard; Readium package on the simulator
```

Ignored and regenerated, so they may appear in an editor but never in git:
`.build/` (SwiftPM and xcodebuild output, in every package), `.swiftpm/`,
`.superpowers/` (planning-tool scratch),
`spikes/SpikeHarness/SpikeHarness.xcodeproj/` (from `project.yml`), and the
model files under `spikes/SpikeHarness/Resources/` (see `spikes/README.md`).

## Rules that keep this tidy

- One `.gitignore`, at the root.
- Generated files are never committed: project files come from `project.yml`,
  build output from SwiftPM and xcodebuild.
- New code goes in a target under `Sources/` with its tests under `Tests/`;
  code that needs an iOS-only dependency goes in a package under `Packages/`;
  `spikes/` is for experiments only.
- Every plan lives in `docs/superpowers/plans/`; every spec in
  `docs/superpowers/specs/`. Spike results go in `spikes/findings/`.

## Working on it

```bash
swift test                     # the root package, on macOS
scripts/test-readium.sh        # Packages/T2SReadium on an iPhone simulator
scripts/check-licenses.sh      # fails on any copyleft dependency, in every package
cd spikes/SpikeHarness && xcodegen generate && open SpikeHarness.xcodeproj
```
````

Roadmap (`docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md`): set Plan 3's file to `2026-09-02-plan-3-persistence-ingest.md` and status `written`; in the layout block replace the `Package.swift` line with `Package.swift                 SPM package "T2S": T2SCore, T2SAudio, T2SStore, T2SLibrary` and add a line `Packages/T2SReadium/          iOS-only package wrapping Readium (EPUB reading, Locator mapping)`.

- [ ] **Step 7: Verify and commit**

Run: `swift test && scripts/check-licenses.sh`
Expected: 155 tests pass; guard exits 0.

```bash
git add Package.swift Sources Tests Packages scripts .github README.md docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md
git commit -m "Add T2SStore and T2SLibrary targets, the iOS-only T2SReadium package, and its simulator test script"
```

---
### Task 2: `T2SStore` rows and `LibraryStore` — documents, queue, chapters, summaries

**Files:**
- Create: `Sources/T2SStore/Models.swift`
- Create: `Sources/T2SStore/LibraryStore.swift`
- Create: `Tests/T2SStoreTests/Support/Fixtures.swift`
- Create: `Tests/T2SStoreTests/LibraryStoreTests.swift`

**Interfaces:**
- Consumes: `Document`, `Timeline`, `Chapter`, `Position`, `SourceType`, `Versions`, `TimelineCodec.encode(_:segmenterVersion:normalizerVersion:)`, `TimelineCodec.decode(_:) -> EncodedChapter` from `T2SCore`.
- Produces: `public actor LibraryStore` (`@ModelActor`) with `static func inMemory() throws`, `static func onDisk(at: URL) throws`, `insert(_:timeline:)`, `document(id:)`, `documents()`, `queue()`, `collection()`, `summaries()`, `summary(id:)`, `update(_:)`, `delete(id:)`, `setQueued(_:_:)`, `moveInQueue(_:to:)`, `setFinished(_:_:)`, `timeline(for:) -> StoredTimeline?`, `chapter(_:of:)`, `saveChapter(_:at:of:)`, `replaceTimeline(_:for:)`; `public struct StoredTimeline { timeline, isStale }`; `public struct DocumentSummary`; `public enum LibraryStoreError { documentNotFound, duplicateDocument, chapterOutOfRange }`. Internal: `row(_:)`, `existing(_:)`, `chapterRowCount()`.

- [ ] **Step 1: Test fixtures (a copy of T2SCoreTests' helpers; SwiftPM test targets cannot share files)**

```swift
// Tests/T2SStoreTests/Support/Fixtures.swift
import Foundation
import T2SCore

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

- [ ] **Step 2: Write the failing tests**

```swift
// Tests/T2SStoreTests/LibraryStoreTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SStore

@Suite struct LibraryStoreTests {
    /// Exactly representable as a Double, so it survives the SQLite round trip unchanged.
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    func makeDocument(_ title: String = "Doc", type: SourceType = .epub) -> Document {
        Document(title: title, author: "A. Author", sourceType: type,
                 sourceURL: URL(string: "https://example.com/a"), addedAt: fixedDate)
    }

    @Test func insertAndFetchRoundTrip() async throws {
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        let timeline = makeTimeline([[makeUtterance("One."), makeUtterance("Two.", charOffset: 5)],
                                     [makeUtterance("Three.", href: "ch2.xhtml")]])
        try await store.insert(doc, timeline: timeline)
        #expect(try await store.document(id: doc.id) == doc)
        #expect(try await store.timeline(for: doc.id) == StoredTimeline(timeline: timeline, isStale: false))
        #expect(try await store.chapter(1, of: doc.id) == timeline.chapters[1])
        #expect(try await store.chapter(2, of: doc.id) == nil)
        #expect(try await store.timeline(for: UUID()) == nil)
    }

    @Test func duplicateInsertThrows() async throws {
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        await #expect(throws: LibraryStoreError.duplicateDocument(doc.id)) {
            try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        }
    }

    @Test func staleWhenVersionsDiffer() async throws {
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        var timeline = makeTimeline([[makeUtterance("One.")]])
        timeline.segmenterVersion = Versions.segmenter + 1
        try await store.insert(doc, timeline: timeline)
        let stored = try #require(try await store.timeline(for: doc.id))
        #expect(stored.isStale)
        #expect(stored.timeline.segmenterVersion == Versions.segmenter + 1)
    }

    @Test func deleteCascadesChapters() async throws {
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")],
                                                            [makeUtterance("Two.", href: "ch2.xhtml")]]))
        #expect(try await store.chapterRowCount() == 2)
        try await store.delete(id: doc.id)
        #expect(try await store.document(id: doc.id) == nil)
        #expect(try await store.chapterRowCount() == 0)
        await #expect(throws: LibraryStoreError.documentNotFound(doc.id)) { try await store.delete(id: doc.id) }
    }

    @Test func queueOrderingAndMoves() async throws {
        let store = try LibraryStore.inMemory()
        let a = makeDocument("a"), b = makeDocument("b"), c = makeDocument("c")
        for d in [a, b, c] {
            try await store.insert(d, timeline: makeTimeline([[makeUtterance("x")]]))
            try await store.setQueued(d.id, true)
        }
        #expect(try await store.queue().map(\.id) == [a.id, b.id, c.id])
        try await store.setQueued(a.id, true)                              // idempotent
        #expect(try await store.queue().map(\.id) == [a.id, b.id, c.id])
        try await store.moveInQueue(c.id, to: 0)
        #expect(try await store.queue().map(\.id) == [c.id, a.id, b.id])
        try await store.setQueued(a.id, false)                             // archive
        #expect(try await store.queue().map(\.id) == [c.id, b.id])
        try await store.setQueued(a.id, true)                              // back at the end
        #expect(try await store.queue().map(\.id) == [c.id, b.id, a.id])
        try await store.moveInQueue(c.id, to: 99)                          // clamped
        #expect(try await store.queue().map(\.id) == [b.id, a.id, c.id])
        #expect(try await store.summary(id: b.id)?.queueOrder == 0)
    }

    @Test func collectionHoldsBooksOnly() async throws {
        let store = try LibraryStore.inMemory()
        let epub = makeDocument("e", type: .epub), pdf = makeDocument("p", type: .pdf)
        let article = makeDocument("w", type: .article)
        for d in [epub, pdf, article] { try await store.insert(d, timeline: makeTimeline([[makeUtterance("x")]])) }
        #expect(Set(try await store.collection().map(\.id)) == [epub.id, pdf.id])
        #expect(try await store.documents().count == 3)
    }

    @Test func saveChapterRefreshesSummary() async throws {
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        var timeline = makeTimeline([[makeUtterance("One.", seconds: 1), makeUtterance("Two.", seconds: 1)]])
        try await store.insert(doc, timeline: timeline)
        var s = try #require(try await store.summary(id: doc.id))
        #expect(s.utteranceCount == 2 && s.renderedCount == 0 && s.chapterCount == 1)
        #expect(s.totalSeconds == 2)
        #expect(!s.isFullyRendered)

        timeline[utterance: 0].duration = .actual(1.5)
        timeline[utterance: 0].audioRef = "abc"
        timeline[utterance: 0].wordTimings = [WordTiming(spokenRange: 0..<4, start: 0, end: 1.5)]
        try await store.saveChapter(timeline.chapters[0], at: 0, of: doc.id)
        s = try #require(try await store.summary(id: doc.id))
        #expect(s.renderedCount == 1 && s.totalSeconds == 2.5)
        #expect(try await store.chapter(0, of: doc.id) == timeline.chapters[0])
        await #expect(throws: LibraryStoreError.chapterOutOfRange(5)) {
            try await store.saveChapter(timeline.chapters[0], at: 5, of: doc.id)
        }
    }

    @Test func replaceTimelineKeepsResumePosition() async throws {
        let store = try LibraryStore.inMemory()
        var doc = makeDocument()
        doc.resumePosition = Position(resourceHref: "ch1.xhtml", progression: 0, charOffset: 3)
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        let fresh = makeTimeline([[makeUtterance("One."), makeUtterance("Two.", charOffset: 5)]])
        try await store.replaceTimeline(fresh, for: doc.id)
        #expect(try await store.timeline(for: doc.id) == StoredTimeline(timeline: fresh, isStale: false))
        #expect(try await store.document(id: doc.id)?.resumePosition == doc.resumePosition)
        #expect(try await store.chapterRowCount() == 1)
    }

    @Test func updateChangesMetadataOnly() async throws {
        let store = try LibraryStore.inMemory()
        var doc = makeDocument()
        doc.resumePosition = Position(resourceHref: "ch1.xhtml", progression: 0.5)
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        var edited = doc
        edited.title = "Renamed"
        edited.voiceID = "af_heart"
        edited.coverImagePath = "Documents/x/cover.jpg"
        edited.resumePosition = nil                                        // ignored by update
        try await store.update(edited)
        let got = try #require(try await store.document(id: doc.id))
        #expect(got.title == "Renamed" && got.voiceID == "af_heart" && got.coverImagePath == "Documents/x/cover.jpg")
        #expect(got.resumePosition == doc.resumePosition)
    }

    @Test func onDiskStoreReopens() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-store-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("Library.store")
        let doc = makeDocument()
        do {
            let store = try LibraryStore.onDisk(at: url)
            try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        }
        let reopened = try LibraryStore.onDisk(at: url)
        #expect(try await reopened.document(id: doc.id) == doc)
        #expect(try await reopened.timeline(for: doc.id)?.timeline.utteranceCount == 1)
    }

    @Test func summariesNewestFirst() async throws {
        let store = try LibraryStore.inMemory()
        let old = Document(title: "old", sourceType: .epub, addedAt: fixedDate)
        let new = Document(title: "new", sourceType: .epub, addedAt: fixedDate.addingTimeInterval(60))
        try await store.insert(old, timeline: makeTimeline([[makeUtterance("x")]]))
        try await store.insert(new, timeline: makeTimeline([[makeUtterance("x")]]))
        #expect(try await store.summaries().map(\.document.title) == ["new", "old"])
        try await store.setFinished(old.id, true)
        #expect(try await store.summary(id: old.id)?.isFinished == true)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter LibraryStoreTests`
Expected: compile error, `LibraryStore` not found.

- [ ] **Step 4: Rows**

```swift
// Sources/T2SStore/Models.swift
import Foundation
import SwiftData

/// SwiftData rows. Internal on purpose (spec §3.7.1): the store hands out `T2SCore` value types,
/// so the persistence schema never shapes the domain model.
@Model
final class StoredDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String?
    /// `SourceType.rawValue`.
    var sourceType: String
    var sourceURL: String?
    var coverImagePath: String?
    var addedAt: Date
    var updatedAt: Date
    var lastPlayedAt: Date?
    var voiceID: String?
    /// JSON-encoded `Position`; nil until the first save.
    var resumePosition: Data?
    /// nil = not in the Queue; otherwise the row's rank, ascending and unique among queued rows.
    var queueOrder: Int?
    var isFinished: Bool
    var schemaVersion: Int
    var segmenterVersion: Int
    var normalizerVersion: Int
    @Relationship(deleteRule: .cascade, inverse: \StoredChapter.document)
    var chapters: [StoredChapter]

    init(id: UUID, title: String, author: String?, sourceType: String, sourceURL: String?,
         coverImagePath: String?, addedAt: Date, voiceID: String?,
         schemaVersion: Int, segmenterVersion: Int, normalizerVersion: Int) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.coverImagePath = coverImagePath
        self.addedAt = addedAt
        self.updatedAt = addedAt
        self.lastPlayedAt = nil
        self.voiceID = voiceID
        self.resumePosition = nil
        self.queueOrder = nil
        self.isFinished = false
        self.schemaVersion = schemaVersion
        self.segmenterVersion = segmenterVersion
        self.normalizerVersion = normalizerVersion
        self.chapters = []
    }
}

@Model
final class StoredChapter {
    var index: Int
    var title: String
    /// JSON-encoded `Position` of the chapter start.
    var position: Data
    /// `TimelineCodec` blob of the chapter's utterances (spec §5).
    var blob: Data
    var utteranceCount: Int
    /// Sum of the chapter's current durations at 1x, kept in step with `blob` so list screens
    /// never decode a blob to show a remaining time.
    var durationSeconds: Double
    /// Utterances whose `audioRef` is set.
    var renderedCount: Int
    var document: StoredDocument?

    init(index: Int, title: String, position: Data, blob: Data, utteranceCount: Int,
         durationSeconds: Double, renderedCount: Int) {
        self.index = index
        self.title = title
        self.position = position
        self.blob = blob
        self.utteranceCount = utteranceCount
        self.durationSeconds = durationSeconds
        self.renderedCount = renderedCount
        self.document = nil
    }
}
```

- [ ] **Step 5: The store**

```swift
// Sources/T2SStore/LibraryStore.swift
import Foundation
import SwiftData
import T2SCore

public struct StoredTimeline: Hashable, Sendable {
    public var timeline: Timeline
    /// True when any persisted stage version differs from the running `Versions`. The caller
    /// re-derives from the retained source (spec §3.7.3) instead of migrating.
    public var isStale: Bool

    public init(timeline: Timeline, isStale: Bool) {
        self.timeline = timeline
        self.isStale = isStale
    }
}

/// What list screens need per document, served without decoding a chapter blob (spec §5).
public struct DocumentSummary: Hashable, Sendable, Identifiable {
    public var document: Document
    public var chapterCount: Int
    public var utteranceCount: Int
    /// Sum of current durations at 1x; estimated until rendered (spec §3.3).
    public var totalSeconds: TimeInterval
    public var renderedCount: Int
    public var isFinished: Bool
    public var queueOrder: Int?
    public var lastPlayedAt: Date?

    public var id: UUID { document.id }
    /// The Queue row's `positive` check (spec §3.4.1): plays with no synthesis and no network.
    public var isFullyRendered: Bool { utteranceCount > 0 && renderedCount == utteranceCount }

    public init(document: Document, chapterCount: Int, utteranceCount: Int, totalSeconds: TimeInterval,
                renderedCount: Int, isFinished: Bool, queueOrder: Int?, lastPlayedAt: Date?) {
        self.document = document
        self.chapterCount = chapterCount
        self.utteranceCount = utteranceCount
        self.totalSeconds = totalSeconds
        self.renderedCount = renderedCount
        self.isFinished = isFinished
        self.queueOrder = queueOrder
        self.lastPlayedAt = lastPlayedAt
    }
}

public enum LibraryStoreError: Error, Equatable, Sendable {
    case documentNotFound(UUID)
    case duplicateDocument(UUID)
    case chapterOutOfRange(Int)
}

/// Local is the source of truth (spec §5). One actor owns the model context; callers only ever
/// see value types.
@ModelActor
public actor LibraryStore {
    static let schema = Schema([StoredDocument.self, StoredChapter.self])

    /// A throwaway store for tests and previews.
    public static func inMemory() throws -> LibraryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return LibraryStore(modelContainer: try ModelContainer(for: schema, configurations: config))
    }

    /// The app's store at `url` (`LibraryPaths.databaseURL`). Creates the parent directory.
    public static func onDisk(at url: URL) throws -> LibraryStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = ModelConfiguration(url: url)
        return LibraryStore(modelContainer: try ModelContainer(for: schema, configurations: config))
    }

    // MARK: Documents

    public func insert(_ document: Document, timeline: Timeline) throws {
        guard try row(document.id) == nil else { throw LibraryStoreError.duplicateDocument(document.id) }
        let row = StoredDocument(id: document.id, title: document.title, author: document.author,
                                 sourceType: document.sourceType.rawValue,
                                 sourceURL: document.sourceURL?.absoluteString,
                                 coverImagePath: document.coverImagePath, addedAt: document.addedAt,
                                 voiceID: document.voiceID,
                                 schemaVersion: timeline.schemaVersion,
                                 segmenterVersion: timeline.segmenterVersion,
                                 normalizerVersion: timeline.normalizerVersion)
        row.resumePosition = try document.resumePosition.map { try JSONEncoder().encode($0) }
        modelContext.insert(row)
        try replaceChapters(of: row, with: timeline)
        try modelContext.save()
    }

    public func document(id: UUID) throws -> Document? { try row(id).map(Self.domain) }

    /// Every document, newest first.
    public func documents() throws -> [Document] {
        try modelContext.fetch(FetchDescriptor<StoredDocument>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))
            .map(Self.domain)
    }

    /// Queued documents in user order (spec §2.3).
    public func queue() throws -> [Document] { try queueRows().map(Self.domain) }

    /// Every EPUB and PDF, newest first, whether or not it is queued (spec §2.3).
    public func collection() throws -> [Document] {
        let epub = SourceType.epub.rawValue, pdf = SourceType.pdf.rawValue
        let descriptor = FetchDescriptor<StoredDocument>(
            predicate: #Predicate { $0.sourceType == epub || $0.sourceType == pdf },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        return try modelContext.fetch(descriptor).map(Self.domain)
    }

    /// Every document's summary, newest first.
    public func summaries() throws -> [DocumentSummary] {
        try modelContext.fetch(FetchDescriptor<StoredDocument>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))
            .map(Self.summary)
    }

    public func summary(id: UUID) throws -> DocumentSummary? { try row(id).map(Self.summary) }

    /// Updates title, author, voice, cover, and source URL. The resume position and the queue
    /// state have their own calls and are ignored here.
    public func update(_ document: Document) throws {
        let row = try existing(document.id)
        row.title = document.title
        row.author = document.author
        row.voiceID = document.voiceID
        row.coverImagePath = document.coverImagePath
        row.sourceURL = document.sourceURL?.absoluteString
        row.updatedAt = Date()
        try modelContext.save()
    }

    public func delete(id: UUID) throws {
        let row = try existing(id)
        modelContext.delete(row)
        try modelContext.save()
    }

    // MARK: Queue

    /// Appends to the end of the Queue, or removes (archive). No-op when already in that state.
    public func setQueued(_ id: UUID, _ queued: Bool) throws {
        let row = try existing(id)
        if queued {
            guard row.queueOrder == nil else { return }
            row.queueOrder = (try queueRows().last?.queueOrder ?? -1) + 1
        } else {
            row.queueOrder = nil
        }
        row.updatedAt = Date()
        try modelContext.save()
    }

    /// Moves a queued document to `index` (clamped) and renumbers the Queue 0…n-1.
    public func moveInQueue(_ id: UUID, to index: Int) throws {
        var rows = try queueRows()
        guard let from = rows.firstIndex(where: { $0.id == id }) else { throw LibraryStoreError.documentNotFound(id) }
        let moving = rows.remove(at: from)
        rows.insert(moving, at: max(0, min(index, rows.count)))
        for (i, r) in rows.enumerated() { r.queueOrder = i }
        moving.updatedAt = Date()
        try modelContext.save()
    }

    public func setFinished(_ id: UUID, _ finished: Bool) throws {
        let row = try existing(id)
        row.isFinished = finished
        row.updatedAt = Date()
        try modelContext.save()
    }

    // MARK: Timelines

    /// Decodes every chapter blob. `isStale` when the persisted versions differ from `Versions`.
    public func timeline(for id: UUID) throws -> StoredTimeline? {
        guard let row = try row(id) else { return nil }
        let chapters = try row.chapters.sorted { $0.index < $1.index }.map { try TimelineCodec.decode($0.blob).chapter }
        let timeline = Timeline(chapters: chapters, schemaVersion: row.schemaVersion,
                                segmenterVersion: row.segmenterVersion, normalizerVersion: row.normalizerVersion)
        let stale = row.schemaVersion != Versions.schema
            || row.segmenterVersion != Versions.segmenter
            || row.normalizerVersion != Versions.normalizer
        return StoredTimeline(timeline: timeline, isStale: stale)
    }

    public func chapter(_ index: Int, of id: UUID) throws -> Chapter? {
        guard let row = try row(id), let c = row.chapters.first(where: { $0.index == index }) else { return nil }
        return try TimelineCodec.decode(c.blob).chapter
    }

    /// Persists phase-2 results (actual durations, word timings, `audioRef`) for one chapter and
    /// refreshes the denormalized counts. The chapter keeps the document's persisted versions.
    public func saveChapter(_ chapter: Chapter, at index: Int, of id: UUID) throws {
        let row = try existing(id)
        guard let c = row.chapters.first(where: { $0.index == index }) else {
            throw LibraryStoreError.chapterOutOfRange(index)
        }
        try Self.fill(c, with: chapter, segmenterVersion: row.segmenterVersion, normalizerVersion: row.normalizerVersion)
        row.updatedAt = Date()
        try modelContext.save()
    }

    /// Replaces every chapter and the versions: re-derivation after a version bump (spec §3.7.3).
    /// The resume position is untouched because `Position` survives re-segmentation (spec §3.2).
    public func replaceTimeline(_ timeline: Timeline, for id: UUID) throws {
        let row = try existing(id)
        try replaceChapters(of: row, with: timeline)
        row.updatedAt = Date()
        try modelContext.save()
    }

    // MARK: Internals

    func row(_ id: UUID) throws -> StoredDocument? {
        var descriptor = FetchDescriptor<StoredDocument>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func existing(_ id: UUID) throws -> StoredDocument {
        guard let row = try row(id) else { throw LibraryStoreError.documentNotFound(id) }
        return row
    }

    /// Test hook.
    func chapterRowCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<StoredChapter>())
    }

    private func queueRows() throws -> [StoredDocument] {
        try modelContext.fetch(FetchDescriptor<StoredDocument>(
            predicate: #Predicate { $0.queueOrder != nil },
            sortBy: [SortDescriptor(\.queueOrder)]))
    }

    private func replaceChapters(of row: StoredDocument, with timeline: Timeline) throws {
        for c in row.chapters { modelContext.delete(c) }
        row.chapters = []
        row.schemaVersion = timeline.schemaVersion
        row.segmenterVersion = timeline.segmenterVersion
        row.normalizerVersion = timeline.normalizerVersion
        for (i, chapter) in timeline.chapters.enumerated() {
            let c = StoredChapter(index: i, title: chapter.title, position: Data(), blob: Data(),
                                  utteranceCount: 0, durationSeconds: 0, renderedCount: 0)
            try Self.fill(c, with: chapter, segmenterVersion: timeline.segmenterVersion,
                          normalizerVersion: timeline.normalizerVersion)
            modelContext.insert(c)
            row.chapters.append(c)
        }
    }

    private static func fill(_ c: StoredChapter, with chapter: Chapter,
                             segmenterVersion: Int, normalizerVersion: Int) throws {
        c.title = chapter.title
        c.position = try JSONEncoder().encode(chapter.position)
        c.blob = try TimelineCodec.encode(chapter, segmenterVersion: segmenterVersion, normalizerVersion: normalizerVersion)
        c.utteranceCount = chapter.utterances.count
        c.durationSeconds = chapter.utterances.reduce(0) { $0 + $1.duration.seconds }
        c.renderedCount = chapter.utterances.filter { $0.audioRef != nil }.count
    }

    static func domain(_ r: StoredDocument) -> Document {
        Document(id: r.id, title: r.title, author: r.author,
                 sourceType: SourceType(rawValue: r.sourceType) ?? .epub,
                 sourceURL: r.sourceURL.flatMap(URL.init(string:)),
                 coverImagePath: r.coverImagePath, addedAt: r.addedAt, voiceID: r.voiceID,
                 resumePosition: r.resumePosition.flatMap { try? JSONDecoder().decode(Position.self, from: $0) })
    }

    static func summary(_ r: StoredDocument) -> DocumentSummary {
        DocumentSummary(document: domain(r), chapterCount: r.chapters.count,
                        utteranceCount: r.chapters.reduce(0) { $0 + $1.utteranceCount },
                        totalSeconds: r.chapters.reduce(0) { $0 + $1.durationSeconds },
                        renderedCount: r.chapters.reduce(0) { $0 + $1.renderedCount },
                        isFinished: r.isFinished, queueOrder: r.queueOrder, lastPlayedAt: r.lastPlayedAt)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter LibraryStoreTests`
Expected: 11 tests passed. If `SortDescriptor(\.queueOrder)` fails to type-check on the optional key path, use `SortDescriptor(\StoredDocument.queueOrder, order: .forward)`; if SwiftData rejects `#Predicate { $0.queueOrder != nil }`, fetch all rows and filter/sort in memory (the Queue is at most a few hundred rows). If a delete of a document with a to-many relationship crashes on the inverse, delete the chapter rows explicitly before the document row inside `delete(id:)`.

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SStore Tests/T2SStoreTests
git commit -m "Add LibraryStore: SwiftData documents, queue order, per-chapter timeline blobs, summaries"
```

---

### Task 3: `PlayheadStore` conformance, bookmarks, pronunciation dictionary

**Files:**
- Create: `Sources/T2SCore/Model/Bookmark.swift`
- Modify: `Sources/T2SStore/Models.swift` (two more rows), `Sources/T2SStore/LibraryStore.swift` (schema list; `delete(id:)` also deletes the document's bookmarks)
- Create: `Sources/T2SStore/LibraryStore+Playhead.swift`, `Sources/T2SStore/LibraryStore+Bookmarks.swift`, `Sources/T2SStore/LibraryStore+Pronunciation.swift`
- Create: `Tests/T2SStoreTests/PlayheadStoreTests.swift`, `Tests/T2SStoreTests/BookmarkTests.swift`, `Tests/T2SStoreTests/PronunciationTests.swift`

**Interfaces:**
- Consumes: `PlayheadStore` (T2SCore, moved in Task 1), `PronunciationEntry` (T2SCore), `LibraryStore.existing(_:)`.
- Produces: `public struct Bookmark: Codable, Hashable, Sendable, Identifiable { id, documentID, position, note, createdAt }` in T2SCore; `extension LibraryStore: PlayheadStore` plus `savePosition(_:for:) throws`; `bookmarks(for:)`, `add(_ bookmark:)`, `deleteBookmark(id:)`; `pronunciations()`, `upsert(_ entry:)`, `deletePronunciation(id:)`.

- [ ] **Step 1: The domain type**

```swift
// Sources/T2SCore/Model/Bookmark.swift
import Foundation

/// A user-placed anchor into a document (spec §2.2). Persisted as a `Position`, never as a
/// runtime index (spec §3.2).
public struct Bookmark: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var documentID: UUID
    public var position: Position
    public var note: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), documentID: UUID, position: Position, note: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.documentID = documentID
        self.position = position
        self.note = note
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
// Tests/T2SStoreTests/PlayheadStoreTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SStore

@Suite struct PlayheadStoreTests {
    @Test func saveThroughTheProtocolPersistsPositionAndLastPlayed() async throws {
        let store = try LibraryStore.inMemory()
        let doc = Document(title: "D", sourceType: .epub, addedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        let playhead: any PlayheadStore = store
        let p = Position(resourceHref: "ch1.xhtml", progression: 0.25, charOffset: 12, cssSelector: "p:nth-child(3)")
        await playhead.save(p, for: doc.id)
        #expect(try await store.document(id: doc.id)?.resumePosition == p)
        let s = try #require(try await store.summary(id: doc.id))
        #expect(s.lastPlayedAt != nil)
        #expect(abs((s.lastPlayedAt ?? .distantPast).timeIntervalSinceNow) < 5)
    }

    @Test func unknownDocumentIsIgnoredByTheProtocolAndThrownByTheDirectCall() async throws {
        let store = try LibraryStore.inMemory()
        let id = UUID()
        await (store as any PlayheadStore).save(Position(resourceHref: "x", progression: 0), for: id)
        await #expect(throws: LibraryStoreError.documentNotFound(id)) {
            try await store.savePosition(Position(resourceHref: "x", progression: 0), for: id)
        }
    }
}
```

```swift
// Tests/T2SStoreTests/BookmarkTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SStore

@Suite struct BookmarkTests {
    @Test func addListDeleteInCreationOrder() async throws {
        let store = try LibraryStore.inMemory()
        let doc = Document(title: "D", sourceType: .epub)
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let b1 = Bookmark(documentID: doc.id, position: Position(resourceHref: "ch1.xhtml", progression: 0.1), note: "first", createdAt: t0)
        let b2 = Bookmark(documentID: doc.id, position: Position(resourceHref: "ch1.xhtml", progression: 0.9), createdAt: t0.addingTimeInterval(1))
        try await store.add(b2)
        try await store.add(b1)
        #expect(try await store.bookmarks(for: doc.id) == [b1, b2])
        var edited = b1
        edited.note = "renamed"
        try await store.add(edited)                                        // upsert by id
        #expect(try await store.bookmarks(for: doc.id) == [edited, b2])
        try await store.deleteBookmark(id: b2.id)
        #expect(try await store.bookmarks(for: doc.id) == [edited])
        #expect(try await store.bookmarks(for: UUID()).isEmpty)
    }

    @Test func deletingTheDocumentDeletesItsBookmarks() async throws {
        let store = try LibraryStore.inMemory()
        let doc = Document(title: "D", sourceType: .epub)
        let other = Document(title: "O", sourceType: .pdf)
        for d in [doc, other] { try await store.insert(d, timeline: makeTimeline([[makeUtterance("One.")]])) }
        try await store.add(Bookmark(documentID: doc.id, position: Position(resourceHref: "ch1.xhtml", progression: 0)))
        let kept = Bookmark(documentID: other.id, position: Position(resourceHref: "source.pdf", progression: 0))
        try await store.add(kept)
        try await store.delete(id: doc.id)
        #expect(try await store.bookmarks(for: doc.id).isEmpty)
        #expect(try await store.bookmarks(for: other.id) == [kept])
    }
}
```

```swift
// Tests/T2SStoreTests/PronunciationTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SStore

@Suite struct PronunciationTests {
    @Test func upsertListDelete() async throws {
        let store = try LibraryStore.inMemory()
        let kokoro = PronunciationEntry(term: "Kokoro", replacement: "koh-koh-roh")
        let nginx = PronunciationEntry(term: "nginx", replacement: "engine x", caseSensitive: true)
        try await store.upsert(nginx)
        try await store.upsert(kokoro)
        #expect(try await store.pronunciations() == [kokoro, nginx])        // sorted by term, case-insensitively
        var edited = kokoro
        edited.replacement = "ko-ko-ro"
        try await store.upsert(edited)
        #expect(try await store.pronunciations() == [edited, nginx])
        try await store.deletePronunciation(id: nginx.id)
        #expect(try await store.pronunciations() == [edited])
        try await store.deletePronunciation(id: UUID())                     // unknown: no-op
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter "PlayheadStoreTests|BookmarkTests|PronunciationTests"`
Expected: compile errors (`Bookmark`, `add`, `pronunciations`, conformance missing).

- [ ] **Step 4: Rows and schema**

Append to `Sources/T2SStore/Models.swift`:

```swift
@Model
final class StoredBookmark {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    /// JSON-encoded `Position`.
    var position: Data
    var note: String?
    var createdAt: Date

    init(id: UUID, documentID: UUID, position: Data, note: String?, createdAt: Date) {
        self.id = id
        self.documentID = documentID
        self.position = position
        self.note = note
        self.createdAt = createdAt
    }
}

@Model
final class StoredPronunciation {
    @Attribute(.unique) var id: UUID
    var term: String
    var replacement: String
    var caseSensitive: Bool
    var updatedAt: Date

    init(id: UUID, term: String, replacement: String, caseSensitive: Bool, updatedAt: Date) {
        self.id = id
        self.term = term
        self.replacement = replacement
        self.caseSensitive = caseSensitive
        self.updatedAt = updatedAt
    }
}
```

In `LibraryStore.swift` change the schema line to

```swift
    static let schema = Schema([StoredDocument.self, StoredChapter.self, StoredBookmark.self, StoredPronunciation.self])
```

and make `delete(id:)` remove bookmarks first:

```swift
    public func delete(id: UUID) throws {
        let row = try existing(id)
        try deleteBookmarks(for: id)
        modelContext.delete(row)
        try modelContext.save()
    }
```

- [ ] **Step 5: The three extensions**

```swift
// Sources/T2SStore/LibraryStore+Playhead.swift
import Foundation
import T2SCore

extension LibraryStore: PlayheadStore {
    /// `PlayheadStore` is fire-and-forget by contract: the coordinator saves on pause, seek, every
    /// utterance boundary, and finish, and cannot act on a failure. A throwing variant exists for
    /// callers that can (`savePosition`).
    public func save(_ position: Position, for documentID: UUID) async {
        try? savePosition(position, for: documentID)
    }

    /// Records the resume position and the last-played time (spec §3.2, §5).
    public func savePosition(_ position: Position, for documentID: UUID) throws {
        let row = try existing(documentID)
        row.resumePosition = try JSONEncoder().encode(position)
        let now = Date()
        row.lastPlayedAt = now
        row.updatedAt = now
        try modelContext.save()
    }
}
```

```swift
// Sources/T2SStore/LibraryStore+Bookmarks.swift
import Foundation
import SwiftData
import T2SCore

extension LibraryStore {
    /// A document's bookmarks, oldest first.
    public func bookmarks(for documentID: UUID) throws -> [Bookmark] {
        let descriptor = FetchDescriptor<StoredBookmark>(
            predicate: #Predicate { $0.documentID == documentID },
            sortBy: [SortDescriptor(\.createdAt)])
        return try modelContext.fetch(descriptor).compactMap { row in
            guard let position = try? JSONDecoder().decode(Position.self, from: row.position) else { return nil }
            return Bookmark(id: row.id, documentID: row.documentID, position: position, note: row.note, createdAt: row.createdAt)
        }
    }

    /// Inserts, or replaces the bookmark with the same id.
    public func add(_ bookmark: Bookmark) throws {
        let data = try JSONEncoder().encode(bookmark.position)
        if let row = try bookmarkRow(bookmark.id) {
            row.documentID = bookmark.documentID
            row.position = data
            row.note = bookmark.note
            row.createdAt = bookmark.createdAt
        } else {
            modelContext.insert(StoredBookmark(id: bookmark.id, documentID: bookmark.documentID, position: data,
                                               note: bookmark.note, createdAt: bookmark.createdAt))
        }
        try modelContext.save()
    }

    public func deleteBookmark(id: UUID) throws {
        guard let row = try bookmarkRow(id) else { return }
        modelContext.delete(row)
        try modelContext.save()
    }

    func deleteBookmarks(for documentID: UUID) throws {
        let rows = try modelContext.fetch(FetchDescriptor<StoredBookmark>(predicate: #Predicate { $0.documentID == documentID }))
        for row in rows { modelContext.delete(row) }
    }

    private func bookmarkRow(_ id: UUID) throws -> StoredBookmark? {
        var descriptor = FetchDescriptor<StoredBookmark>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
```

```swift
// Sources/T2SStore/LibraryStore+Pronunciation.swift
import Foundation
import SwiftData
import T2SCore

extension LibraryStore {
    /// The user's dictionary, sorted by term without regard to case (spec §2.2, §4.1 rule 6).
    public func pronunciations() throws -> [PronunciationEntry] {
        try modelContext.fetch(FetchDescriptor<StoredPronunciation>())
            .map { PronunciationEntry(id: $0.id, term: $0.term, replacement: $0.replacement, caseSensitive: $0.caseSensitive) }
            .sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
    }

    /// Inserts, or replaces the entry with the same id.
    public func upsert(_ entry: PronunciationEntry) throws {
        if let row = try pronunciationRow(entry.id) {
            row.term = entry.term
            row.replacement = entry.replacement
            row.caseSensitive = entry.caseSensitive
            row.updatedAt = Date()
        } else {
            modelContext.insert(StoredPronunciation(id: entry.id, term: entry.term, replacement: entry.replacement,
                                                    caseSensitive: entry.caseSensitive, updatedAt: Date()))
        }
        try modelContext.save()
    }

    public func deletePronunciation(id: UUID) throws {
        guard let row = try pronunciationRow(id) else { return }
        modelContext.delete(row)
        try modelContext.save()
    }

    private func pronunciationRow(_ id: UUID) throws -> StoredPronunciation? {
        var descriptor = FetchDescriptor<StoredPronunciation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter "PlayheadStoreTests|BookmarkTests|PronunciationTests|LibraryStoreTests"`
Expected: 16 tests passed (the Task 2 suite still passes with the wider schema).

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SCore/Model/Bookmark.swift Sources/T2SStore Tests/T2SStoreTests
git commit -m "LibraryStore: PlayheadStore conformance, bookmarks, pronunciation dictionary"
```

---
### Task 4: `T2SLibrary` contracts and the app-container layout

**Files:**
- Create: `Sources/T2SLibrary/DocumentReader.swift`, `Sources/T2SLibrary/ImportError.swift`, `Sources/T2SLibrary/LibraryPaths.swift`
- Create: `Tests/T2SLibraryTests/LibraryPathsTests.swift`

**Interfaces:**
- Consumes: `ChapterInput`, `SourceType` from `T2SCore`.
- Produces: `public protocol DocumentReader: Sendable { var supportedTypes: Set<SourceType> { get }; func read(fileURL: URL, sourceType: SourceType) async throws -> ReadDocument }`; `public struct ReadDocument { title, author, coverImage: Data?, chapters: [ChapterInput], skippedResources: [String] }`; `public enum ImportError { drmProtected, unsupportedFormat(String), unreadable(String), noText, malformedBody(String) }`; `public struct LibraryPaths { root, databaseURL, audioDirectory, documentsDirectory, documentDirectory(_:), sourceURL(_:type:), originalHTMLURL(_:), coverURL(_:), relativePath(of:), url(forRelativePath:) }`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/T2SLibraryTests/LibraryPathsTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SLibrary

@Suite struct LibraryPathsTests {
    let paths = LibraryPaths(root: URL(fileURLWithPath: "/tmp/t2s-root/"))
    let id = UUID(uuidString: "0C1A9E2E-6D2B-4A8C-9F0D-1B2C3D4E5F60")!

    @Test func layoutIsFixed() {
        #expect(paths.databaseURL.path == "/tmp/t2s-root/Library.store")
        #expect(paths.audioDirectory.path == "/tmp/t2s-root/Audio")
        #expect(paths.documentDirectory(id).path == "/tmp/t2s-root/Documents/\(id.uuidString)")
        #expect(paths.sourceURL(id, type: .epub).lastPathComponent == "source.epub")
        #expect(paths.sourceURL(id, type: .article).lastPathComponent == "source.epub")
        #expect(paths.sourceURL(id, type: .pdf).lastPathComponent == "source.pdf")
        #expect(paths.originalHTMLURL(id).lastPathComponent == "original.html")
        #expect(paths.coverURL(id).lastPathComponent == "cover.jpg")
    }

    @Test func relativePathsRoundTrip() {
        let cover = paths.coverURL(id)
        let rel = paths.relativePath(of: cover)
        #expect(rel == "Documents/\(id.uuidString)/cover.jpg")
        #expect(paths.url(forRelativePath: rel!).path == cover.path)
        #expect(paths.relativePath(of: URL(fileURLWithPath: "/elsewhere/cover.jpg")) == nil)
        #expect(paths.relativePath(of: URL(fileURLWithPath: "/tmp/t2s-root")) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter LibraryPathsTests`
Expected: compile error, `LibraryPaths` not found.

- [ ] **Step 3: Implement**

```swift
// Sources/T2SLibrary/DocumentReader.swift
import Foundation
import T2SCore

/// What a reader extracts from one source file: metadata, a cover, and chapters of blocks ready
/// for `TimelineBuilder` (spec §4).
public struct ReadDocument: Hashable, Sendable {
    public var title: String
    public var author: String?
    /// Encoded image bytes (JPEG or PNG); nil when the source has no cover.
    public var coverImage: Data?
    public var chapters: [ChapterInput]
    /// Resources (hrefs or page labels) that yielded no text or failed to parse — imported
    /// documents say what was skipped rather than failing silently (spec §6).
    public var skippedResources: [String]

    public init(title: String, author: String? = nil, coverImage: Data? = nil,
                chapters: [ChapterInput], skippedResources: [String] = []) {
        self.title = title
        self.author = author
        self.coverImage = coverImage
        self.chapters = chapters
        self.skippedResources = skippedResources
    }
}

/// Turns a source file into chapters of `SourceBlock`s with the `Position` semantics fixed in the
/// plan's Global Constraints. Implementations: `PDFDocumentReader` (here) and
/// `ReadiumDocumentReader` (Packages/T2SReadium; EPUB and article EPUB).
public protocol DocumentReader: Sendable {
    var supportedTypes: Set<SourceType> { get }
    func read(fileURL: URL, sourceType: SourceType) async throws -> ReadDocument
}
```

```swift
// Sources/T2SLibrary/ImportError.swift
/// The import rows of spec §6.
public enum ImportError: Error, Equatable, Sendable {
    /// Rejected at import with a plain explanation; never silently (spec §6).
    case drmProtected
    case unsupportedFormat(String)
    case unreadable(String)
    /// The source parsed but produced no speakable text (a scanned PDF, an empty extraction).
    case noText
    /// The article body is not well-formed XHTML.
    case malformedBody(String)
}
```

```swift
// Sources/T2SLibrary/LibraryPaths.swift
import Foundation
import T2SCore

/// Where things live in the app container (spec §5). Rows store paths relative to `root`, so the
/// container can move (new device, restored backup) without rewriting them.
///
/// ```
/// <root>/Library.store                    SwiftData
/// <root>/Audio/<codec>/<renderKey>.audio  FileAudioStore (cache)
/// <root>/Documents/<uuid>/source.epub|pdf original.html cover.jpg
/// ```
public struct LibraryPaths: Hashable, Sendable {
    public var root: URL

    public init(root: URL) { self.root = root.standardizedFileURL }

    public var databaseURL: URL { root.appendingPathComponent("Library.store") }
    public var audioDirectory: URL { root.appendingPathComponent("Audio", isDirectory: true) }
    public var documentsDirectory: URL { root.appendingPathComponent("Documents", isDirectory: true) }

    public func documentDirectory(_ id: UUID) -> URL {
        documentsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// The imported source. Articles are stored as their generated EPUB (spec §2.1).
    public func sourceURL(_ id: UUID, type: SourceType) -> URL {
        documentDirectory(id).appendingPathComponent(type == .pdf ? "source.pdf" : "source.epub")
    }

    /// The originally fetched article HTML, retained for reprocessing (spec §2.1).
    public func originalHTMLURL(_ id: UUID) -> URL { documentDirectory(id).appendingPathComponent("original.html") }

    public func coverURL(_ id: UUID) -> URL { documentDirectory(id).appendingPathComponent("cover.jpg") }

    /// The `Document.coverImagePath` form of a URL under `root`; nil for anything else.
    public func relativePath(of url: URL) -> String? {
        let base = root.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base), path.count > base.count else { return nil }
        return String(path.dropFirst(base.count))
    }

    public func url(forRelativePath path: String) -> URL { root.appendingPathComponent(path) }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter LibraryPathsTests`
Expected: 2 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SLibrary Tests/T2SLibraryTests
git commit -m "Add DocumentReader contract, ImportError, and the app-container layout"
```

---

### Task 5: `PDFDocumentReader` over PDFKit

**Files:**
- Create: `Sources/T2SLibrary/PDF/PDFDocumentReader.swift`, `Sources/T2SLibrary/PDF/PDFCover.swift`
- Create: `Tests/T2SLibraryTests/Support/PDFFixture.swift`, `Tests/T2SLibraryTests/PDFDocumentReaderTests.swift`

**Interfaces:**
- Consumes: `DocumentReader`, `ReadDocument`, `ImportError` (Task 4); `RepeatedLineFilter.filter(pages:minPages:edge:)`, `SourceBlock`, `ChapterInput`, `Position` (T2SCore).
- Produces: `public struct PDFDocumentReader: DocumentReader` with `static let resourceHref = "source.pdf"`, `init()`; internal `static func read(_ document: PDFDocument, fallbackTitle: String) throws -> ReadDocument` and `static func outlineEntries(_:) -> [(title: String, page: Int)]`; internal `enum PDFCover { static func jpeg(of page: PDFPage, maxWidth: CGFloat = 600, quality: CGFloat = 0.8) -> Data? }`.

- [ ] **Step 1: The fixture builder**

```swift
// Tests/T2SLibraryTests/Support/PDFFixture.swift
import CoreGraphics
import CoreText
import Foundation
import PDFKit

enum PDFFixture {
    /// Writes a PDF whose pages carry the given lines, drawn top to bottom in 14 pt Helvetica.
    /// An empty line list makes a blank page.
    static func write(pages: [[String]], title: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fixture.pdf")
        var box = CGRect(x: 0, y: 0, width: 400, height: 600)
        var info: [CFString: Any] = [:]
        if let title { info[kCGPDFContextTitle] = title }
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let key = NSAttributedString.Key(kCTFontAttributeName as String)
        for lines in pages {
            ctx.beginPDFPage(nil)
            var y: CGFloat = 560
            for line in lines {
                let attributed = NSAttributedString(string: line, attributes: [key: font])
                ctx.textPosition = CGPoint(x: 40, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
                y -= 24
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// Attaches a top-level outline (title → 0-based page) to an open document, in memory.
    static func attachOutline(_ entries: [(String, Int)], to document: PDFDocument) {
        let root = PDFOutline()
        for (title, page) in entries {
            let entry = PDFOutline()
            entry.label = title
            if let p = document.page(at: page) {
                entry.destination = PDFDestination(page: p, at: CGPoint(x: 0, y: 600))
            }
            root.insertChild(entry, at: root.numberOfChildren)
        }
        document.outlineRoot = root
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
// Tests/T2SLibraryTests/PDFDocumentReaderTests.swift
import Foundation
import PDFKit
import Testing
import T2SCore
@testable import T2SLibrary

@Suite struct PDFDocumentReaderTests {
    let header = "The Example Book"
    func body(_ i: Int) -> String { "Body sentence number \(i) is here." }
    /// Running header on top, page number at the bottom, one body sentence between.
    func fourPages() -> [[String]] { (1...4).map { [header, body($0), "Page \($0)"] } }

    @Test func stripsRunningHeadersAndPageNumbers() async throws {
        let url = try PDFFixture.write(pages: fourPages(), title: "Example")
        let read = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        #expect(read.title == "Example")
        #expect(read.author == nil)
        #expect(read.chapters.count == 1)
        #expect(read.chapters[0].title == "Example")
        #expect(read.chapters[0].blocks.map(\.text) == (1...4).map(body))
        #expect(read.skippedResources.isEmpty)
    }

    @Test func positionsAreMonotonicAndResolve() async throws {
        let url = try PDFFixture.write(pages: fourPages())
        let read = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        #expect(read.title == "fixture")                                    // file name, no title attribute
        let blocks = read.chapters[0].blocks
        #expect(blocks.map(\.position.resourceHref) == Array(repeating: PDFDocumentReader.resourceHref, count: 4))
        #expect(blocks.map(\.position.progression) == [0, 0.25, 0.5, 0.75])
        var expected: [Int] = [], offset = 0
        for i in 1...4 { expected.append(offset); offset += body(i).utf16.count + 1 }
        #expect(blocks.map(\.position.charOffset) == expected)
        #expect(read.chapters[0].position == blocks[0].position)

        let timeline = TimelineBuilder.build(chapters: read.chapters, segmenter: Segmenter(normalizer: TextNormalizer()))
        #expect(timeline.utteranceCount == 4)
        for i in 0..<4 {
            #expect(PositionResolver.resolve(timeline[utterance: i].position, in: timeline) == Playhead(utteranceIndex: i))
        }
    }

    @Test func outlineBecomesChapters() throws {
        let url = try PDFFixture.write(pages: fourPages())
        let document = try #require(PDFDocument(url: url))
        PDFFixture.attachOutline([("Part Two", 3), ("Part One", 1), ("  ", 1)], to: document)
        let read = try PDFDocumentReader.read(document, fallbackTitle: "fixture")
        #expect(read.chapters.map(\.title) == ["Front matter", "Part One", "Part Two"])
        #expect(read.chapters.map { $0.blocks.count } == [1, 2, 1])
        #expect(read.chapters[1].position.progression == 0.25)
        #expect(read.chapters[1].position == read.chapters[1].blocks[0].position)
    }

    @Test func fewerThanTwoOutlineEntriesMeansOneChapter() throws {
        let url = try PDFFixture.write(pages: fourPages())
        let document = try #require(PDFDocument(url: url))
        PDFFixture.attachOutline([("Only", 0)], to: document)
        let read = try PDFDocumentReader.read(document, fallbackTitle: "fixture")
        #expect(read.chapters.map(\.title) == ["fixture"])
        #expect(read.chapters[0].blocks.count == 4)
    }

    @Test func blankPagesAreSkippedAndReported() async throws {
        let url = try PDFFixture.write(pages: [["Some text on page one."], [], ["More text on page three."]])
        let read = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        #expect(read.chapters.count == 1)
        #expect(read.chapters[0].blocks.map(\.text) == ["Some text on page one.", "More text on page three."])
        #expect(read.chapters[0].blocks.map(\.position.progression) == [0, 2.0 / 3.0])
        #expect(read.skippedResources == ["page 2"])
    }

    @Test func noTextIsRejected() async throws {
        let url = try PDFFixture.write(pages: [[], []])
        await #expect(throws: ImportError.noText) {
            _ = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        }
    }

    @Test func coverIsAJPEG() async throws {
        let url = try PDFFixture.write(pages: fourPages())
        let read = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        let cover = try #require(read.coverImage)
        #expect(cover.prefix(2) == Data([0xFF, 0xD8]))
        #expect(cover.count > 1_000)
    }

    @Test func unreadableFileIsRejected() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-pdf-\(UUID().uuidString).pdf")
        try Data("hello".utf8).write(to: url)
        await #expect(throws: ImportError.self) {
            _ = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        }
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter PDFDocumentReaderTests`
Expected: compile error, `PDFDocumentReader` not found.

- [ ] **Step 4: Implement**

```swift
// Sources/T2SLibrary/PDF/PDFCover.swift
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Renders a page to JPEG through CoreGraphics + ImageIO, so one implementation serves iOS and macOS.
enum PDFCover {
    static func jpeg(of page: PDFPage, maxWidth: CGFloat = 600, quality: CGFloat = 0.8) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = maxWidth / bounds.width
        let width = Int((bounds.width * scale).rounded()), height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: ctx)
        guard let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
```

```swift
// Sources/T2SLibrary/PDF/PDFDocumentReader.swift
import Foundation
import PDFKit
import T2SCore

/// Text PDFs through PDFKit (spec §2.1 rev 6): one `SourceBlock` per page after the running
/// header/footer filter (spec §4.1 rule 2); chapters from the outline when it has at least two
/// entries, else one chapter. Display stays in Readium's PDF navigator (Plan 4), which addresses
/// pages by `Position.progression`.
public struct PDFDocumentReader: DocumentReader {
    /// A PDF is one resource; the page travels in `progression` (Global Constraints).
    public static let resourceHref = "source.pdf"

    public let supportedTypes: Set<SourceType> = [.pdf]

    public init() {}

    public func read(fileURL: URL, sourceType: SourceType) async throws -> ReadDocument {
        guard let document = PDFDocument(url: fileURL) else {
            throw ImportError.unreadable("PDFKit could not open \(fileURL.lastPathComponent)")
        }
        if document.isLocked { throw ImportError.drmProtected }
        return try Self.read(document, fallbackTitle: fileURL.deletingPathExtension().lastPathComponent)
    }

    /// Entry point for an already-open document (tests attach an outline in memory).
    static func read(_ document: PDFDocument, fallbackTitle: String) throws -> ReadDocument {
        let pageCount = document.pageCount
        guard pageCount > 0 else { throw ImportError.noText }

        let rawLines: [[String]] = (0..<pageCount).map { i in
            (document.page(at: i)?.string ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let pages = RepeatedLineFilter.filter(pages: rawLines).map { $0.joined(separator: "\n") }
        guard pages.contains(where: { !$0.isEmpty }) else { throw ImportError.noText }

        var starts: [Int] = []
        var offset = 0
        for text in pages {
            starts.append(offset)
            offset += text.utf16.count + 1
        }
        func position(_ page: Int) -> Position {
            Position(resourceHref: resourceHref, progression: Double(page) / Double(pageCount), charOffset: starts[page])
        }
        func blocks(_ range: Range<Int>) -> [SourceBlock] {
            range.compactMap { page in
                pages[page].isEmpty ? nil : SourceBlock(text: pages[page], position: position(page))
            }
        }

        let attributes = document.documentAttributes ?? [:]
        let title = nonEmpty(attributes[PDFDocumentAttribute.titleAttribute] as? String) ?? fallbackTitle
        let author = nonEmpty(attributes[PDFDocumentAttribute.authorAttribute] as? String)

        var chapters: [ChapterInput] = []
        let entries = outlineEntries(document)
        if entries.count >= 2 {
            if entries[0].page > 0 {
                let front = blocks(0..<entries[0].page)
                if !front.isEmpty {
                    chapters.append(ChapterInput(title: "Front matter", position: front[0].position, blocks: front))
                }
            }
            for (i, entry) in entries.enumerated() {
                let end = i + 1 < entries.count ? entries[i + 1].page : pageCount
                let b = blocks(entry.page..<end)
                if !b.isEmpty { chapters.append(ChapterInput(title: entry.title, position: b[0].position, blocks: b)) }
            }
        } else {
            let b = blocks(0..<pageCount)
            chapters.append(ChapterInput(title: title, position: b[0].position, blocks: b))
        }

        let skipped = (0..<pageCount).filter { pages[$0].isEmpty }.map { "page \($0 + 1)" }
        let cover = document.page(at: 0).flatMap { PDFCover.jpeg(of: $0) }
        return ReadDocument(title: title, author: author, coverImage: cover, chapters: chapters, skippedResources: skipped)
    }

    /// Top-level outline entries that resolve to a page: sorted by page, one per page, blank
    /// labels replaced by "Section n".
    static func outlineEntries(_ document: PDFDocument) -> [(title: String, page: Int)] {
        guard let root = document.outlineRoot else { return [] }
        var found: [(title: String, page: Int, order: Int)] = []
        for i in 0..<root.numberOfChildren {
            guard let child = root.child(at: i), let page = child.destination?.page else { continue }
            let index = document.index(for: page)
            guard index >= 0, index < document.pageCount else { continue }
            found.append((child.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", index, i))
        }
        // Sort by page with outline order as the tie-break (Swift's sort is not stable), then keep
        // the first entry per page.
        found.sort { ($0.page, $0.order) < ($1.page, $1.order) }
        var seen = Set<Int>()
        var unique: [(title: String, page: Int)] = []
        for entry in found where seen.insert(entry.page).inserted {
            unique.append((entry.title.isEmpty ? "Section \(unique.count + 1)" : entry.title, entry.page))
        }
        return unique
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter PDFDocumentReaderTests`
Expected: 8 tests passed. If `page.string` returns the three lines joined by spaces instead of newlines, the fixture's line spacing is too small for PDFKit's line detection: raise the per-line step in `PDFFixture.write` from 24 to 40 and keep the reader unchanged. If the `outlineBecomesChapters` test finds `PDFDestination.page` nil, the in-memory outline is fine but `PDFDestination(page:at:)` needs a page that belongs to `document`; it does here, so check the outline was attached to the same `PDFDocument` instance passed to `read`.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SLibrary/PDF Tests/T2SLibraryTests
git commit -m "Add PDFDocumentReader: PDFKit text per page, header filter, outline chapters, JPEG cover"
```

---
### Task 6: `StoredZipWriter` — the EPUB container

**Files:**
- Create: `Sources/T2SLibrary/Archive/CRC32.swift`, `Sources/T2SLibrary/Archive/StoredZipWriter.swift`
- Create: `Tests/T2SLibraryTests/Support/Shell.swift`, `Tests/T2SLibraryTests/StoredZipWriterTests.swift`

**Interfaces:**
- Produces: `public struct ZipEntry: Hashable, Sendable { name: String; data: Data }`; `public enum StoredZipWriter { static func archive(_ entries: [ZipEntry]) -> Data }`; internal `enum CRC32 { static func checksum(_ data: Data) -> UInt32 }`; test helper `Shell.run(_:_:) -> (status, output)` (macOS only).

An EPUB is a ZIP whose first entry is an uncompressed `mimetype` with no extra field (OCF). Nothing else in the app needs compression, and Foundation has no ZIP API, so this is a ~60-line stored-only writer with a fixed timestamp (deterministic bytes) rather than a dependency.

- [ ] **Step 1: Test helper for macOS-only verification through `/usr/bin/unzip`**

```swift
// Tests/T2SLibraryTests/Support/Shell.swift
import Foundation

#if os(macOS)
enum Shell {
    struct Result {
        var status: Int32
        var output: String
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
#endif
```

- [ ] **Step 2: Write the failing tests**

```swift
// Tests/T2SLibraryTests/StoredZipWriterTests.swift
import Foundation
import Testing
@testable import T2SLibrary

@Suite struct StoredZipWriterTests {
    @Test func crc32MatchesTheCheckValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
    }

    @Test func layoutIsStoredAndInOrder() {
        let entries = [ZipEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
                       ZipEntry(name: "META-INF/container.xml", data: Data("<x/>".utf8))]
        let archive = StoredZipWriter.archive(entries)
        let nameBytes = entries.reduce(0) { $0 + $1.name.utf8.count }
        let payload = entries.reduce(0) { $0 + $1.data.count }
        #expect(archive.count == 30 * 2 + 46 * 2 + 22 + 2 * nameBytes + payload)
        #expect(archive.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))      // local file header
        #expect(archive[8..<10] == Data([0x00, 0x00]))                     // method 0 = stored
        #expect(archive[26..<28] == Data([0x08, 0x00]))                    // name length 8
        #expect(archive[28..<30] == Data([0x00, 0x00]))                    // no extra field
        #expect(archive[30..<38] == Data("mimetype".utf8))
        #expect(archive[38..<58] == Data("application/epub+zip".utf8))    // payload follows the name directly
        let eocd = Data(archive.suffix(22))
        #expect(eocd.prefix(4) == Data([0x50, 0x4B, 0x05, 0x06]))
        #expect(eocd[10..<12] == Data([0x02, 0x00]))                       // two entries
        #expect(StoredZipWriter.archive([]).count == 22)
    }

    @Test func unzipVerifiesTheArchive() throws {
        #if os(macOS)
        let entries = [ZipEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
                       ZipEntry(name: "OEBPS/a.txt", data: Data(repeating: 0x41, count: 5_000)),
                       ZipEntry(name: "OEBPS/b.txt", data: Data())]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).zip")
        try StoredZipWriter.archive(entries).write(to: url)
        let test = try Shell.run("/usr/bin/unzip", ["-t", url.path])
        #expect(test.status == 0, "\(test.output)")
        let list = try Shell.run("/usr/bin/unzip", ["-Z1", url.path])
        #expect(list.output.split(separator: "\n").map(String.init) == ["mimetype", "OEBPS/a.txt", "OEBPS/b.txt"])
        let verbose = try Shell.run("/usr/bin/unzip", ["-Zv", url.path])
        #expect(!verbose.output.lowercased().contains("defl"))
        #endif
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter StoredZipWriterTests`
Expected: compile error, `StoredZipWriter` not found.

- [ ] **Step 4: Implement**

```swift
// Sources/T2SLibrary/Archive/CRC32.swift
import Foundation

/// IEEE CRC-32 (the ZIP flavour), table-driven.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}
```

```swift
// Sources/T2SLibrary/Archive/StoredZipWriter.swift
import Foundation

public struct ZipEntry: Hashable, Sendable {
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

/// Writes a ZIP archive with every entry stored (method 0) in the order given, a fixed timestamp,
/// and no extra fields — exactly what the EPUB container (OCF) needs for `mimetype`, and enough for
/// everything else we write. Not a general ZIP library: no compression, no ZIP64, ASCII names.
public enum StoredZipWriter {
    private static let versionNeeded: UInt16 = 20
    private static let dosTime: UInt16 = 0          // 00:00:00
    private static let dosDate: UInt16 = 0x0021     // 1980-01-01

    public static func archive(_ entries: [ZipEntry]) -> Data {
        var out = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(out.count)

            // Local file header (30 bytes + name), then the stored bytes.
            out.append(le32(0x0403_4B50))
            out.append(le16(versionNeeded))
            out.append(le16(0))                       // general purpose flags
            out.append(le16(0))                       // method: stored
            out.append(le16(dosTime))
            out.append(le16(dosDate))
            out.append(le32(crc))
            out.append(le32(size))
            out.append(le32(size))
            out.append(le16(UInt16(name.count)))
            out.append(le16(0))                       // extra field length
            out.append(name)
            out.append(entry.data)

            // Central directory header (46 bytes + name).
            central.append(le32(0x0201_4B50))
            central.append(le16(versionNeeded))       // version made by
            central.append(le16(versionNeeded))       // version needed
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(dosTime))
            central.append(le16(dosDate))
            central.append(le32(crc))
            central.append(le32(size))
            central.append(le32(size))
            central.append(le16(UInt16(name.count)))
            central.append(le16(0))                   // extra
            central.append(le16(0))                   // comment
            central.append(le16(0))                   // disk number start
            central.append(le16(0))                   // internal attributes
            central.append(le32(0))                   // external attributes
            central.append(le32(offset))
            central.append(name)
        }

        let centralOffset = UInt32(out.count)
        out.append(central)
        // End of central directory (22 bytes).
        out.append(le32(0x0605_4B50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(entries.count)))
        out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(centralOffset))
        out.append(le16(0))
        return out
    }

    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter StoredZipWriterTests`
Expected: 3 tests passed.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SLibrary/Archive Tests/T2SLibraryTests
git commit -m "Add StoredZipWriter: stored-only ZIP with CRC-32 for EPUB containers"
```

---

### Task 7: `ArticleEPUBWriter`

**Files:**
- Create: `Sources/T2SLibrary/Article/ArticleContent.swift`, `Sources/T2SLibrary/Article/XHTML.swift`, `Sources/T2SLibrary/Article/ArticleEPUBWriter.swift`
- Create: `Tests/T2SLibraryTests/ArticleEPUBWriterTests.swift`

**Interfaces:**
- Consumes: `StoredZipWriter`, `ZipEntry` (Task 6); `ImportError` (Task 4).
- Produces: `public struct ArticleContent { title, byline, siteName, sourceURL, language, bodyXHTML, excerpt }`; `public enum ArticleEPUBWriter { static let chapterHref = "OEBPS/article.xhtml"; static func epub(for:identifier:modified:) throws -> Data; static func write(_:to:identifier:modified:) throws }`; internal `enum XHTML { escape(_:), validateFragment(_:) throws, plainText(ofFragment:) throws, plainText(ofDocument:) throws }`.

The Share Extension (Plan 5) runs Readability.js in a `WKWebView` and serializes `article.content` with `XMLSerializer`, which yields a well-formed XHTML fragment. The writer's contract is that fragment; it validates rather than repairs (spec §6: a bad extraction is shown to the user, not silently fixed), and it rejects a body with no text.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SLibraryTests/ArticleEPUBWriterTests.swift
import Foundation
import Testing
@testable import T2SLibrary

@Suite struct ArticleEPUBWriterTests {
    let article = ArticleContent(
        title: "Tom & Jerry <3",
        byline: "Jane Doe",
        siteName: "Example",
        sourceURL: URL(string: "https://example.com/tom?a=1&b=2"),
        bodyXHTML: "<p>First paragraph.</p><p>Second <em>one</em> &amp; more.</p>",
        excerpt: "Cats and mice.")

    @Test func xhtmlHelpers() throws {
        #expect(try XHTML.plainText(ofFragment: article.bodyXHTML) == "First paragraph.Second one & more.")
        #expect(throws: ImportError.self) { try XHTML.validateFragment("<p>unclosed") }
        #expect(throws: ImportError.self) { try XHTML.validateFragment("<p>&nbsp;</p>") }   // HTML entity, not XML
        try XHTML.validateFragment("<p>a\u{00A0}b<br/>c</p>")
        #expect(XHTML.escape("a & b < c > \"d\"") == "a &amp; b &lt; c &gt; &quot;d&quot;")
    }

    @Test func writesAValidContainer() throws {
        let epub = try ArticleEPUBWriter.epub(
            for: article,
            identifier: UUID(uuidString: "0C1A9E2E-6D2B-4A8C-9F0D-1B2C3D4E5F60")!,
            modified: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(epub.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(epub[30..<38] == Data("mimetype".utf8))                    // first, stored, no extra field
        #expect(epub[38..<58] == Data("application/epub+zip".utf8))
        #if os(macOS)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-epub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.epub")
        try epub.write(to: url)
        let unzip = try Shell.run("/usr/bin/unzip", ["-o", "-q", url.path, "-d", dir.path])
        #expect(unzip.status == 0, unzip.output)

        let container = try String(contentsOf: dir.appendingPathComponent("META-INF/container.xml"), encoding: .utf8)
        #expect(container.contains("full-path=\"OEBPS/content.opf\""))
        let opf = try String(contentsOf: dir.appendingPathComponent("OEBPS/content.opf"), encoding: .utf8)
        #expect(opf.contains("<dc:title>Tom &amp; Jerry &lt;3</dc:title>"))
        #expect(opf.contains("<dc:identifier id=\"pub-id\">urn:uuid:0c1a9e2e-6d2b-4a8c-9f0d-1b2c3d4e5f60</dc:identifier>"))
        #expect(opf.contains("<dc:creator>Jane Doe</dc:creator>"))
        #expect(opf.contains("<dc:publisher>Example</dc:publisher>"))
        #expect(opf.contains("<dc:source>https://example.com/tom?a=1&amp;b=2</dc:source>"))
        #expect(opf.contains("<dc:description>Cats and mice.</dc:description>"))
        #expect(opf.contains("<meta property=\"dcterms:modified\">2023-11-14T22:13:20Z</meta>"))
        #expect(opf.contains("properties=\"nav\""))
        #expect(opf.contains("<itemref idref=\"article\"/>"))
        let chapter = try String(contentsOf: dir.appendingPathComponent(ArticleEPUBWriter.chapterHref), encoding: .utf8)
        let text = try XHTML.plainText(ofDocument: chapter)
        #expect(text.contains("Tom & Jerry <3"))
        #expect(text.contains("First paragraph."))
        #expect(chapter.contains("<p class=\"byline\">Jane Doe</p>"))
        let nav = try String(contentsOf: dir.appendingPathComponent("OEBPS/nav.xhtml"), encoding: .utf8)
        #expect(nav.contains("epub:type=\"toc\""))
        #expect(nav.contains("<a href=\"article.xhtml\">Tom &amp; Jerry &lt;3</a>"))
        for name in ["OEBPS/nav.xhtml", "OEBPS/content.opf", "META-INF/container.xml"] {
            let xml = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            _ = try XHTML.plainText(ofDocument: xml)                     // well-formed
        }
        #endif
    }

    @Test func optionalMetadataIsOmittedNotEmptied() throws {
        let bare = ArticleContent(title: "Bare", bodyXHTML: "<p>Text.</p>")
        let epub = try ArticleEPUBWriter.epub(for: bare)
        let opf = try #require(String(data: epub, encoding: .isoLatin1))   // stored entries are readable in place
        #expect(!opf.contains("<dc:creator>"))
        #expect(!opf.contains("<dc:source>"))
        #expect(!opf.contains("<dc:publisher>"))
        #expect(!opf.contains("class=\"byline\""))
        #expect(opf.contains("<dc:language>en</dc:language>"))
    }

    @Test func malformedBodyIsRejectedBeforeWriting() {
        var bad = article
        bad.bodyXHTML = "<p>unclosed"
        #expect(throws: ImportError.self) { try ArticleEPUBWriter.epub(for: bad) }
    }

    @Test func emptyBodyIsRejected() {
        var empty = article
        empty.bodyXHTML = "<div> \n </div>"
        #expect(throws: ImportError.noText) { try ArticleEPUBWriter.epub(for: empty) }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ArticleEPUBWriterTests`
Expected: compile error, `ArticleContent` not found.

- [ ] **Step 3: Implement**

```swift
// Sources/T2SLibrary/Article/ArticleContent.swift
import Foundation

/// A web article after Readability extraction (spec §2.1), ready to be written as a minimal EPUB.
public struct ArticleContent: Hashable, Sendable {
    public var title: String
    public var byline: String?
    public var siteName: String?
    public var sourceURL: URL?
    /// BCP-47 tag for `xml:lang`. Readability rarely knows it; v1 is English-only (spec §7.1).
    public var language: String
    /// The article body as a **well-formed XHTML fragment**. The Share Extension serializes
    /// Readability's output with `XMLSerializer`, which produces exactly this; the writer validates
    /// and rejects anything else (`ImportError.malformedBody`).
    public var bodyXHTML: String
    public var excerpt: String?

    public init(title: String, byline: String? = nil, siteName: String? = nil, sourceURL: URL? = nil,
                language: String = "en", bodyXHTML: String, excerpt: String? = nil) {
        self.title = title
        self.byline = byline
        self.siteName = siteName
        self.sourceURL = sourceURL
        self.language = language
        self.bodyXHTML = bodyXHTML
        self.excerpt = excerpt
    }
}
```

```swift
// Sources/T2SLibrary/Article/XHTML.swift
import Foundation

/// The little XML the article writer needs: escaping, well-formedness through `XMLParser`, and
/// plain text for the "little text" check (spec §6).
enum XHTML {
    static let namespace = "http://www.w3.org/1999/xhtml"

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }

    /// Throws `ImportError.malformedBody` unless `fragment` parses as XML inside an XHTML wrapper.
    static func validateFragment(_ fragment: String) throws {
        _ = try plainText(ofFragment: fragment)
    }

    static func plainText(ofFragment fragment: String) throws -> String {
        try plainText(ofDocument: "<div xmlns=\"\(namespace)\">\(fragment)</div>")
    }

    /// Concatenated character data of a well-formed XML document; `ImportError.malformedBody` otherwise.
    static func plainText(ofDocument xml: String) throws -> String {
        let parser = XMLParser(data: Data(xml.utf8))
        let collector = TextCollector()
        parser.delegate = collector
        guard parser.parse() else {
            let reason = parser.parserError.map { "\($0.localizedDescription)" } ?? "unknown error"
            throw ImportError.malformedBody("line \(parser.lineNumber): \(reason)")
        }
        return collector.text
    }

    private final class TextCollector: NSObject, XMLParserDelegate {
        var text = ""
        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    }
}
```

```swift
// Sources/T2SLibrary/Article/ArticleEPUBWriter.swift
import Foundation

/// Writes a web article as a minimal EPUB 3 (one chapter, one nav) so it travels the same
/// reflowable path as a book (spec §2.1). The original HTML is retained by `Library`, not here.
public enum ArticleEPUBWriter {
    public static let chapterHref = "OEBPS/article.xhtml"
    static let opfHref = "OEBPS/content.opf"
    static let navHref = "OEBPS/nav.xhtml"

    /// The whole EPUB as bytes. Throws `ImportError.malformedBody` or `ImportError.noText`.
    public static func epub(for article: ArticleContent, identifier: UUID = UUID(), modified: Date = Date()) throws -> Data {
        let text = try XHTML.plainText(ofFragment: article.bodyXHTML)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.noText }
        return StoredZipWriter.archive([
            ZipEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
            ZipEntry(name: "META-INF/container.xml", data: Data(container.utf8)),
            ZipEntry(name: opfHref, data: Data(opf(for: article, identifier: identifier, modified: modified).utf8)),
            ZipEntry(name: navHref, data: Data(nav(for: article).utf8)),
            ZipEntry(name: chapterHref, data: Data(chapter(for: article).utf8)),
        ])
    }

    public static func write(_ article: ArticleContent, to url: URL, identifier: UUID = UUID(), modified: Date = Date()) throws {
        try epub(for: article, identifier: identifier, modified: modified).write(to: url, options: .atomic)
    }

    static let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>

        """

    static func opf(for a: ArticleContent, identifier: UUID, modified: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        var meta: [String] = [
            "<dc:identifier id=\"pub-id\">urn:uuid:\(identifier.uuidString.lowercased())</dc:identifier>",
            "<dc:title>\(XHTML.escape(a.title))</dc:title>",
            "<dc:language>\(XHTML.escape(a.language))</dc:language>",
        ]
        if let byline = a.byline { meta.append("<dc:creator>\(XHTML.escape(byline))</dc:creator>") }
        if let site = a.siteName { meta.append("<dc:publisher>\(XHTML.escape(site))</dc:publisher>") }
        if let url = a.sourceURL { meta.append("<dc:source>\(XHTML.escape(url.absoluteString))</dc:source>") }
        if let excerpt = a.excerpt { meta.append("<dc:description>\(XHTML.escape(excerpt))</dc:description>") }
        meta.append("<meta property=\"dcterms:modified\">\(formatter.string(from: modified))</meta>")
        let metadata = meta.map { "    " + $0 }.joined(separator: "\n")
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id" xml:lang="\(XHTML.escape(a.language))">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            \(metadata)
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="article" href="article.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="article"/>
              </spine>
            </package>

            """
    }

    static func nav(for a: ArticleContent) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
          <head><title>Contents</title></head>
          <body>
            <nav epub:type="toc">
              <h1>Contents</h1>
              <ol><li><a href="article.xhtml">\(XHTML.escape(a.title))</a></li></ol>
            </nav>
          </body>
        </html>

        """
    }

    static func chapter(for a: ArticleContent) -> String {
        let lang = XHTML.escape(a.language)
        let byline = a.byline.map { "      <p class=\"byline\">\(XHTML.escape($0))</p>\n" } ?? ""
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(lang)" lang="\(lang)">
              <head>
                <meta charset="utf-8"/>
                <title>\(XHTML.escape(a.title))</title>
              </head>
              <body>
                <section epub:type="bodymatter chapter">
                  <h1>\(XHTML.escape(a.title))</h1>
            \(byline)      <div class="article-body">
            \(a.bodyXHTML)
                  </div>
                </section>
              </body>
            </html>

            """
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ArticleEPUBWriterTests`
Expected: 5 tests passed. The multi-line literals strip their common leading indentation; if an `#expect(opf.contains(...))` fails on whitespace only, compare with the actual output and align the literal, never the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SLibrary/Article Tests/T2SLibraryTests
git commit -m "Add ArticleEPUBWriter: validated XHTML body into a minimal EPUB 3"
```

---
### Task 8: `Library` — import, delete, reprocess, evict

**Files:**
- Create: `Sources/T2SLibrary/Library.swift`
- Create: `Tests/T2SLibraryTests/Support/FakeDocumentReader.swift`, `Tests/T2SLibraryTests/LibraryTests.swift`

**Interfaces:**
- Consumes: `LibraryStore` (Tasks 2–3: `insert`, `document(id:)`, `timeline(for:)`, `replaceTimeline`, `saveChapter`, `setQueued`, `delete`, `pronunciations()`, `savePosition`), `LibraryPaths`, `DocumentReader`, `ImportError` (Task 4), `ArticleEPUBWriter` (Task 7), `PDFDocumentReader` (Task 5); `AudioStore.remove(_:)`, `RenderKey(rawValue:)`, `RenderSnapshot`, `TimelineBuilder`, `Segmenter`, `TextNormalizer(dictionary:)`, `PositionResolver` (T2SCore).
- Produces: `public actor Library { init(paths:store:audioStore:readers:); importFile(at:sourceType:) async throws -> ImportResult; importArticle(_:originalHTML:) async throws -> ImportResult; delete(_:) async throws; timelineForPlayback(_:) async throws -> Timeline?; reprocess(_:) async throws -> Timeline; evictAudio(for:) async throws; renderSnapshot(for:) async throws -> RenderSnapshot? }`; `public struct ImportResult { document, utteranceCount, skippedResources }`. Plan 4 builds `PolicyInput.documents` from `renderSnapshot(for:)` and loads playback with `timelineForPlayback`.

- [ ] **Step 1: A reader double (Readium is iOS-only, so macOS tests use canned chapters)**

```swift
// Tests/T2SLibraryTests/Support/FakeDocumentReader.swift
import Foundation
import T2SCore
@testable import T2SLibrary

/// Records every file a reader is asked to open.
actor ReadLog {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}

/// Stands in for `ReadiumDocumentReader` with canned chapters: two resources, three sentences.
struct FakeDocumentReader: DocumentReader {
    let supportedTypes: Set<SourceType> = [.epub, .article]
    var title = "Fake Book"
    var chapters: [ChapterInput] = [
        ChapterInput(title: "One", position: Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0, charOffset: 0), blocks: [
            SourceBlock(text: "First sentence. Second sentence.",
                        position: Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0, charOffset: 0)),
        ]),
        ChapterInput(title: "Two", position: Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0), blocks: [
            SourceBlock(text: "Third sentence.",
                        position: Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0)),
        ]),
    ]
    var skipped: [String] = []
    var failure: ImportError?
    let log = ReadLog()

    func read(fileURL: URL, sourceType: SourceType) async throws -> ReadDocument {
        await log.record(fileURL)
        if let failure { throw failure }
        return ReadDocument(title: title, author: "Fake Author", coverImage: Data([0xFF, 0xD8, 0xFF, 0xE0]),
                            chapters: chapters, skippedResources: skipped)
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
// Tests/T2SLibraryTests/LibraryTests.swift
import Foundation
import Testing
import T2SCore
import T2SStore
@testable import T2SLibrary

@Suite struct LibraryTests {
    struct Harness {
        let library: Library
        let paths: LibraryPaths
        let store: LibraryStore
        let audio: InMemoryAudioStore
    }

    func makeHarness(readers: [any DocumentReader]) throws -> Harness {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-lib-\(UUID().uuidString)")
        let paths = LibraryPaths(root: root)
        let store = try LibraryStore.inMemory()
        let audio = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let library = Library(paths: paths, store: store, audioStore: audio, readers: readers)
        return Harness(library: library, paths: paths, store: store, audio: audio)
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func scratchFile(_ ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).\(ext)")
        try Data("PK".utf8).write(to: url)
        return url
    }

    private func importFake(_ h: Harness) async throws -> ImportResult {
        try await h.library.importFile(at: try scratchFile("epub"), sourceType: .epub)
    }

    @Test func importsAPDF() async throws {
        let h = try makeHarness(readers: [PDFDocumentReader()])
        let pdf = try PDFFixture.write(pages: [["Hello from page one.", "And a second line."], ["Page two speaks."]],
                                       title: "Two Pages")
        let result = try await h.library.importFile(at: pdf, sourceType: .pdf)
        let doc = result.document
        #expect(doc.title == "Two Pages" && doc.sourceType == .pdf && doc.sourceURL == nil)
        #expect(result.utteranceCount == 3 && result.skippedResources.isEmpty)
        #expect(exists(h.paths.sourceURL(doc.id, type: .pdf)))
        #expect(exists(pdf))                                                // copied, never moved
        #expect(doc.coverImagePath == h.paths.relativePath(of: h.paths.coverURL(doc.id)))
        #expect(exists(h.paths.coverURL(doc.id)))
        #expect(try await h.store.queue().map(\.id) == [doc.id])
        #expect(try await h.store.timeline(for: doc.id)?.timeline.utteranceCount == 3)
        #expect(try await h.library.timelineForPlayback(doc.id)?.chapters.first?.title == "Two Pages")
    }

    @Test func importsAnEPUBThroughTheReader() async throws {
        let reader = FakeDocumentReader()
        let h = try makeHarness(readers: [PDFDocumentReader(), reader])
        let result = try await h.library.importFile(at: try scratchFile("epub"), sourceType: .epub)
        let doc = result.document
        #expect(await reader.log.urls == [h.paths.sourceURL(doc.id, type: .epub)])
        #expect(doc.title == "Fake Book" && doc.author == "Fake Author" && doc.sourceType == .epub)
        let timeline = try #require(try await h.store.timeline(for: doc.id)).timeline
        #expect(timeline.chapters.map(\.title) == ["One", "Two"])
        #expect(timeline.utteranceCount == 3)
        #expect(try await h.store.queue().map(\.id) == [doc.id])
        #expect(try await h.store.collection().map(\.id) == [doc.id])
    }

    @Test func importsAnArticleAsAnEPUBAndKeepsTheHTML() async throws {
        let reader = FakeDocumentReader(skipped: ["OEBPS/blank.xhtml"])
        let h = try makeHarness(readers: [reader])
        let article = ArticleContent(title: "An Article", byline: "Jane", sourceURL: URL(string: "https://example.com/a"),
                                     bodyXHTML: "<p>Body text.</p>")
        let result = try await h.library.importArticle(article, originalHTML: "<html><body><p>Body text.</p></body></html>")
        let doc = result.document
        #expect(doc.sourceType == .article && doc.sourceURL == article.sourceURL)
        #expect(result.skippedResources == ["OEBPS/blank.xhtml"])
        #expect(try String(contentsOf: h.paths.originalHTMLURL(doc.id), encoding: .utf8).contains("<p>Body text.</p>"))
        let epub = try Data(contentsOf: h.paths.sourceURL(doc.id, type: .article))
        #expect(epub.prefix(2) == Data("PK".utf8))
        #expect(await reader.log.urls == [h.paths.sourceURL(doc.id, type: .article)])
        #expect(try await h.store.queue().map(\.id) == [doc.id])
        #expect(try await h.store.collection().isEmpty)
    }

    @Test func malformedArticleLeavesNothingBehind() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        let article = ArticleContent(title: "Bad", bodyXHTML: "<p>unclosed")
        await #expect(throws: ImportError.self) { _ = try await h.library.importArticle(article, originalHTML: "<p>") }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: h.paths.documentsDirectory.path)) ?? []
        #expect(leftovers.isEmpty)
        #expect(try await h.store.documents().isEmpty)
    }

    @Test func unsupportedTypeLeavesNothingBehind() async throws {
        let h = try makeHarness(readers: [PDFDocumentReader()])
        await #expect(throws: ImportError.unsupportedFormat("epub")) {
            _ = try await h.library.importFile(at: try scratchFile("epub"), sourceType: .epub)
        }
        #expect(!exists(h.paths.documentsDirectory))
        #expect(try await h.store.documents().isEmpty)
    }

    @Test func readerFailureCleansUp() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader(failure: .drmProtected)])
        await #expect(throws: ImportError.drmProtected) {
            _ = try await h.library.importFile(at: try scratchFile("epub"), sourceType: .epub)
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: h.paths.documentsDirectory.path)) ?? []
        #expect(leftovers.isEmpty)
        #expect(try await h.store.documents().isEmpty)
    }

    @Test func noTextIsRejected() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader(chapters: [])])
        await #expect(throws: ImportError.noText) {
            _ = try await h.library.importFile(at: try scratchFile("epub"), sourceType: .epub)
        }
        #expect(try await h.store.documents().isEmpty)
    }

    @Test func deleteRemovesRowsFilesAndAudio() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        let doc = try await importFake(h).document
        let key = RenderKey(rawValue: "k1")
        try await h.audio.write(PCMAudio(samples: [0, 0, 0]), for: key)
        var timeline = try #require(try await h.store.timeline(for: doc.id)).timeline
        timeline[utterance: 0].audioRef = key.rawValue
        try await h.store.saveChapter(timeline.chapters[0], at: 0, of: doc.id)

        try await h.library.delete(doc.id)
        #expect(try await h.store.document(id: doc.id) == nil)
        #expect(!exists(h.paths.documentDirectory(doc.id)))
        #expect(await h.audio.contains(key) == false)
    }

    @Test func staleTimelineIsReprocessedForPlayback() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        let doc = try await importFake(h).document
        let resume = Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0)
        try await h.store.savePosition(resume, for: doc.id)
        // A timeline persisted by an older segmenter, with one rendered utterance under the old key.
        let oldKey = RenderKey(rawValue: "old")
        try await h.audio.write(PCMAudio(samples: [0]), for: oldKey)
        var stale = try #require(try await h.store.timeline(for: doc.id)).timeline
        stale.segmenterVersion = Versions.segmenter + 1
        stale[utterance: 0].audioRef = oldKey.rawValue
        try await h.store.replaceTimeline(stale, for: doc.id)
        #expect(try await h.store.timeline(for: doc.id)?.isStale == true)

        let fresh = try #require(try await h.library.timelineForPlayback(doc.id))
        #expect(fresh.segmenterVersion == Versions.segmenter && fresh.utteranceCount == 3)
        #expect(fresh.chapters.allSatisfy { $0.utterances.allSatisfy { $0.audioRef == nil } })
        #expect(try await h.store.timeline(for: doc.id)?.isStale == false)
        #expect(await h.audio.contains(oldKey) == false)                    // orphan removed
        #expect(try await h.store.document(id: doc.id)?.resumePosition == resume)
        #expect(PositionResolver.resolve(resume, in: fresh).utteranceIndex == 2)
    }

    @Test func evictAudioClearsRefsAndKeepsDurations() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        let doc = try await importFake(h).document
        let key = RenderKey(rawValue: "k2")
        try await h.audio.write(PCMAudio(samples: [0, 0]), for: key)
        var timeline = try #require(try await h.store.timeline(for: doc.id)).timeline
        timeline[utterance: 1].audioRef = key.rawValue
        timeline[utterance: 1].duration = .actual(0.75)
        try await h.store.saveChapter(timeline.chapters[0], at: 0, of: doc.id)

        try await h.library.evictAudio(for: doc.id)
        let after = try #require(try await h.store.timeline(for: doc.id)).timeline
        #expect(after[utterance: 1].audioRef == nil)
        #expect(after[utterance: 1].duration == .actual(0.75))
        #expect(await h.audio.contains(key) == false)
        #expect(try await h.store.summary(id: doc.id)?.renderedCount == 0)
    }

    @Test func renderSnapshotFollowsResumeAndAudioRefs() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        let doc = try await importFake(h).document
        try await h.store.savePosition(Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0), for: doc.id)
        var timeline = try #require(try await h.store.timeline(for: doc.id)).timeline
        timeline[utterance: 0].audioRef = "k3"
        try await h.store.saveChapter(timeline.chapters[0], at: 0, of: doc.id)
        let snapshot = try #require(try await h.library.renderSnapshot(for: doc.id))
        #expect(snapshot.documentID == doc.id)
        #expect(snapshot.rendered == [true, false, false])
        #expect(snapshot.resumeIndex == 2)
        #expect(snapshot.seconds.count == 3)
        #expect(try await h.library.renderSnapshot(for: UUID()) == nil)
    }

    @Test func dictionaryIsAppliedAtImportAndOnReprocess() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        try await h.store.upsert(PronunciationEntry(term: "Second", replacement: "2nd"))
        let doc = try await importFake(h).document
        let timeline = try #require(try await h.store.timeline(for: doc.id)).timeline
        #expect(timeline[utterance: 1].spoken == "2nd sentence.")
        #expect(timeline[utterance: 1].source == "Second sentence.")
        try await h.store.upsert(PronunciationEntry(term: "Third", replacement: "3rd"))
        let reprocessed = try await h.library.reprocess(doc.id)
        #expect(reprocessed[utterance: 2].spoken == "3rd sentence.")
        #expect(try await h.store.timeline(for: doc.id)?.timeline == reprocessed)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter LibraryTests`
Expected: compile error, `Library` not found.

- [ ] **Step 4: Implement**

```swift
// Sources/T2SLibrary/Library.swift
import Foundation
import T2SCore
import T2SStore

public struct ImportResult: Hashable, Sendable {
    public var document: Document
    public var utteranceCount: Int
    /// What the reader could not parse; the UI says so (spec §6).
    public var skippedResources: [String]

    public init(document: Document, utteranceCount: Int, skippedResources: [String]) {
        self.document = document
        self.utteranceCount = utteranceCount
        self.skippedResources = skippedResources
    }
}

/// The import / delete / re-derive facade over the store, the audio cache, and the readers
/// (spec §4). Import runs phase 1 only (spec §3.3); everything imported joins the Queue, and
/// nothing is gated on rendering (spec §3.4.1).
public actor Library {
    public let paths: LibraryPaths
    public let store: LibraryStore
    private let audioStore: any AudioStore
    private let readers: [any DocumentReader]

    public init(paths: LibraryPaths, store: LibraryStore, audioStore: any AudioStore, readers: [any DocumentReader]) {
        self.paths = paths
        self.store = store
        self.audioStore = audioStore
        self.readers = readers
    }

    // MARK: Import

    /// Copies `url` into the container (the original is never touched), reads it, segments it,
    /// stores it, and queues it. On any failure the document directory is removed.
    public func importFile(at url: URL, sourceType: SourceType) async throws -> ImportResult {
        let reader = try reader(for: sourceType)
        let id = UUID()
        let directory = paths.documentDirectory(id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: paths.sourceURL(id, type: sourceType))
            return try await ingest(id: id, sourceType: sourceType, sourceURL: nil, reader: reader)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// Writes the retained HTML and the generated EPUB (spec §2.1), then imports the EPUB as an article.
    public func importArticle(_ article: ArticleContent, originalHTML: String) async throws -> ImportResult {
        let reader = try reader(for: .article)
        let id = UUID()
        let directory = paths.documentDirectory(id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(originalHTML.utf8).write(to: paths.originalHTMLURL(id), options: .atomic)
            try ArticleEPUBWriter.write(article, to: paths.sourceURL(id, type: .article), identifier: id)
            return try await ingest(id: id, sourceType: .article, sourceURL: article.sourceURL, reader: reader)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    // MARK: Lifecycle

    /// Removes the document's cached audio, its rows, and its directory.
    public func delete(_ id: UUID) async throws {
        if let stored = try await store.timeline(for: id) { await removeAudio(of: stored.timeline) }
        try await store.delete(id: id)
        try? FileManager.default.removeItem(at: paths.documentDirectory(id))
    }

    /// The timeline to play. A stale timeline (version bump) is re-derived from the retained source
    /// first (spec §3.7.3), so playback never sees a version mismatch.
    public func timelineForPlayback(_ id: UUID) async throws -> Timeline? {
        guard let stored = try await store.timeline(for: id) else { return nil }
        return stored.isStale ? try await reprocess(id) : stored.timeline
    }

    /// Re-reads the retained source with the current segmenter, normalizer, and dictionary and
    /// replaces the chapters. The resume position survives (spec §3.2). The old utterances' audio
    /// keys are removed from the cache: they embed the old versions and would never be looked up again.
    @discardableResult
    public func reprocess(_ id: UUID) async throws -> Timeline {
        guard let document = try await store.document(id: id) else { throw LibraryStoreError.documentNotFound(id) }
        let reader = try reader(for: document.sourceType)
        let read = try await reader.read(fileURL: paths.sourceURL(id, type: document.sourceType),
                                         sourceType: document.sourceType)
        let timeline = try await build(read)
        if let old = try await store.timeline(for: id) { await removeAudio(of: old.timeline) }
        try await store.replaceTimeline(timeline, for: id)
        return timeline
    }

    /// Drops the document's rendered audio from the cache and clears every `audioRef`. Actual
    /// durations and word timings stay: they remain the best estimate until the next render.
    public func evictAudio(for id: UUID) async throws {
        guard let stored = try await store.timeline(for: id) else { return }
        await removeAudio(of: stored.timeline)
        var timeline = stored.timeline
        for c in timeline.chapters.indices where timeline.chapters[c].utterances.contains(where: { $0.audioRef != nil }) {
            for u in timeline.chapters[c].utterances.indices { timeline.chapters[c].utterances[u].audioRef = nil }
            try await store.saveChapter(timeline.chapters[c], at: c, of: id)
        }
    }

    /// What `RenderPolicy` needs for one document (spec §3.4.1). `rendered` follows `audioRef`;
    /// the coordinator reconciles against the store when it loads (Plan 2).
    public func renderSnapshot(for id: UUID) async throws -> RenderSnapshot? {
        guard let document = try await store.document(id: id),
              let timeline = try await timelineForPlayback(id) else { return nil }
        var rendered: [Bool] = []
        rendered.reserveCapacity(timeline.utteranceCount)
        for chapter in timeline.chapters { for u in chapter.utterances { rendered.append(u.audioRef != nil) } }
        let resume = document.resumePosition.map { PositionResolver.resolve($0, in: timeline).utteranceIndex } ?? 0
        return RenderSnapshot(documentID: id, timeline: timeline, rendered: rendered, resumeIndex: resume)
    }

    // MARK: Internals

    private func reader(for type: SourceType) throws -> any DocumentReader {
        guard let reader = readers.first(where: { $0.supportedTypes.contains(type) }) else {
            throw ImportError.unsupportedFormat(type.rawValue)
        }
        return reader
    }

    private func ingest(id: UUID, sourceType: SourceType, sourceURL: URL?, reader: any DocumentReader) async throws -> ImportResult {
        let read = try await reader.read(fileURL: paths.sourceURL(id, type: sourceType), sourceType: sourceType)
        let timeline = try await build(read)
        var coverPath: String?
        if let cover = read.coverImage {
            let url = paths.coverURL(id)
            try cover.write(to: url, options: .atomic)
            coverPath = paths.relativePath(of: url)
        }
        let document = Document(id: id, title: read.title, author: read.author, sourceType: sourceType,
                                sourceURL: sourceURL, coverImagePath: coverPath, addedAt: Date())
        try await store.insert(document, timeline: timeline)
        try await store.setQueued(id, true)
        return ImportResult(document: document, utteranceCount: timeline.utteranceCount, skippedResources: read.skippedResources)
    }

    /// Phase 1 (spec §3.3) with the dictionary as it stands now (Global Constraints).
    private func build(_ read: ReadDocument) async throws -> Timeline {
        let dictionary = try await store.pronunciations()
        let segmenter = Segmenter(normalizer: TextNormalizer(dictionary: dictionary))
        let timeline = TimelineBuilder.build(chapters: read.chapters, segmenter: segmenter)
        guard timeline.utteranceCount > 0 else { throw ImportError.noText }
        return timeline
    }

    private func removeAudio(of timeline: Timeline) async {
        for chapter in timeline.chapters {
            for utterance in chapter.utterances {
                if let ref = utterance.audioRef { try? await audioStore.remove(RenderKey(rawValue: ref)) }
            }
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter LibraryTests`
Expected: 12 tests passed. Then the whole root suite: `swift test` — every suite green.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SLibrary/Library.swift Tests/T2SLibraryTests
git commit -m "Add Library: import files and articles, delete, re-derive stale timelines, evict audio"
```

---
### Task 9: `ReadiumDocumentReader` (Packages/T2SReadium)

**Files:**
- Create: `Packages/T2SReadium/Sources/T2SReadium/ReadiumDocumentReader.swift`
- Create: `Packages/T2SReadium/Tests/T2SReadiumTests/Support/EPUBFixture.swift`, `Packages/T2SReadium/Tests/T2SReadiumTests/ReadiumDocumentReaderTests.swift`

**Interfaces:**
- Consumes: `DocumentReader`, `ReadDocument`, `ImportError`, `StoredZipWriter`, `ZipEntry`, `ArticleEPUBWriter`, `ArticleContent` (T2SLibrary); `SourceBlock`, `ChapterInput`, `Position`, `TimelineBuilder`, `Segmenter`, `TextNormalizer`, `PositionResolver` (T2SCore); Readium 3.11.0 as listed under "Verified toolchain facts".
- Produces: `public struct ReadiumDocumentReader: DocumentReader` with `supportedTypes == [.epub, .article]`, `init()`.

Run these tests with `scripts/test-readium.sh` (simulator). Every `Position` this reader emits follows the EPUB rule in Global Constraints; `charOffset` counts the trimmed block texts of one resource joined by `"\n"`.

- [ ] **Step 1: Fixtures built in the test, so nothing binary is committed**

```swift
// Packages/T2SReadium/Tests/T2SReadiumTests/Support/EPUBFixture.swift
import Foundation
import T2SLibrary

enum EPUBFixture {
    static func xhtml(title: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(title)</title></head><body>\(body)</body></html>
        """
    }

    static let front = xhtml(title: "Front", body: "<h1>Title Page</h1><p>By Someone.</p>")
    static let ch1 = xhtml(title: "One", body: "<h1>Chapter One</h1><p>First paragraph of one.</p><p>Second paragraph of one.</p>")
    static let ch2 = xhtml(title: "Two", body: "<h1>Chapter Two</h1><p>Only paragraph of two.</p>")
    static let blank = xhtml(title: "Blank", body: "")

    static func opf(spine: [String]) -> String {
        let items = spine.map { "<item id=\"\($0.replacingOccurrences(of: ".xhtml", with: ""))\" href=\"\($0)\" media-type=\"application/xhtml+xml\"/>" }
        let refs = spine.map { "<itemref idref=\"\($0.replacingOccurrences(of: ".xhtml", with: ""))\"/>" }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="pub-id">urn:uuid:5f1a2b3c-0000-4000-8000-000000000001</dc:identifier>
            <dc:title>Fixture Book</dc:title>
            <dc:creator>Ada Author</dc:creator>
            <dc:language>en</dc:language>
            <meta property="dcterms:modified">2026-09-02T00:00:00Z</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            \(items.joined(separator: "\n    "))
          </manifest>
          <spine>\(refs.joined())</spine>
        </package>
        """
    }

    static func nav(_ entries: [(title: String, href: String)]) -> String {
        let items = entries.map { "<li><a href=\"\($0.href)\">\($0.title)</a></li>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>
        <body><nav epub:type="toc"><ol>\(items)</ol></nav></body></html>
        """
    }

    static let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """

    static let adeptEncryption = """
        <?xml version="1.0"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#" xmlns:sig="http://www.w3.org/2000/09/xmldsig#" xmlns:adept="http://ns.adobe.com/adept">
          <enc:EncryptedData>
            <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
            <sig:KeyInfo><adept:resource>urn:uuid:5f1a2b3c-0000-4000-8000-000000000001</adept:resource></sig:KeyInfo>
            <enc:CipherData><enc:CipherReference URI="OEBPS/ch1.xhtml"/></enc:CipherData>
          </enc:EncryptedData>
        </encryption>
        """

    static func write(_ entries: [ZipEntry], name: String = "book.epub") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-epub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        let all = [ZipEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
                   ZipEntry(name: "META-INF/container.xml", data: Data(container.utf8))] + entries
        try StoredZipWriter.archive(all).write(to: url)
        return url
    }

    /// front.xhtml (not in the TOC), ch1, ch2, and a blank spine item; TOC → ch1, ch2.
    static func twoChapterBook() throws -> URL {
        try write([
            ZipEntry(name: "OEBPS/content.opf", data: Data(opf(spine: ["front.xhtml", "ch1.xhtml", "ch2.xhtml", "blank.xhtml"]).utf8)),
            ZipEntry(name: "OEBPS/nav.xhtml", data: Data(nav([("Chapter One", "ch1.xhtml"), ("Chapter Two", "ch2.xhtml")]).utf8)),
            ZipEntry(name: "OEBPS/front.xhtml", data: Data(front.utf8)),
            ZipEntry(name: "OEBPS/ch1.xhtml", data: Data(ch1.utf8)),
            ZipEntry(name: "OEBPS/ch2.xhtml", data: Data(ch2.utf8)),
            ZipEntry(name: "OEBPS/blank.xhtml", data: Data(blank.utf8)),
        ])
    }

    /// One chapter, no TOC entries.
    static func noTOCBook() throws -> URL {
        try write([
            ZipEntry(name: "OEBPS/content.opf", data: Data(opf(spine: ["ch1.xhtml", "ch2.xhtml"]).utf8)),
            ZipEntry(name: "OEBPS/nav.xhtml", data: Data(nav([]).utf8)),
            ZipEntry(name: "OEBPS/ch1.xhtml", data: Data(ch1.utf8)),
            ZipEntry(name: "OEBPS/ch2.xhtml", data: Data(ch2.utf8)),
        ])
    }

    static func drmBook() throws -> URL {
        try write([
            ZipEntry(name: "META-INF/encryption.xml", data: Data(adeptEncryption.utf8)),
            ZipEntry(name: "OEBPS/content.opf", data: Data(opf(spine: ["ch1.xhtml"]).utf8)),
            ZipEntry(name: "OEBPS/nav.xhtml", data: Data(nav([("Chapter One", "ch1.xhtml")]).utf8)),
            ZipEntry(name: "OEBPS/ch1.xhtml", data: Data(ch1.utf8)),
        ])
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
// Packages/T2SReadium/Tests/T2SReadiumTests/ReadiumDocumentReaderTests.swift
import Foundation
import Testing
import T2SCore
import T2SLibrary
@testable import T2SReadium

@Suite struct ReadiumDocumentReaderTests {
    let reader = ReadiumDocumentReader()

    @Test func splitsChaptersByTableOfContents() async throws {
        let read = try await reader.read(fileURL: try EPUBFixture.twoChapterBook(), sourceType: .epub)
        #expect(read.title == "Fixture Book")
        #expect(read.author == "Ada Author")
        #expect(read.coverImage == nil)
        #expect(read.chapters.map(\.title) == ["Front matter", "Chapter One", "Chapter Two"])
        #expect(read.chapters.map { $0.blocks.map(\.text) } == [
            ["Title Page", "By Someone."],
            ["Chapter One", "First paragraph of one.", "Second paragraph of one."],
            ["Chapter Two", "Only paragraph of two."],
        ])
        #expect(read.skippedResources.count == 1)
        #expect(read.skippedResources[0].hasSuffix("blank.xhtml"))
    }

    @Test func positionsFollowTheEPUBRule() async throws {
        let read = try await reader.read(fileURL: try EPUBFixture.twoChapterBook(), sourceType: .epub)
        let one = read.chapters[1].blocks
        #expect(one.allSatisfy { $0.position.resourceHref.hasSuffix("ch1.xhtml") })
        #expect(one.map(\.position.charOffset) == [0, "Chapter One".utf16.count + 1,
                                                    "Chapter One".utf16.count + 1 + "First paragraph of one.".utf16.count + 1])
        let progressions = one.map(\.position.progression)
        #expect(progressions == progressions.sorted() && progressions[0] < progressions[2])
        #expect(one[1].position.cssSelector?.contains("p") == true)
        #expect(read.chapters[1].position == one[0].position)
        #expect(read.chapters[0].blocks[0].position.resourceHref != one[0].position.resourceHref)

        let timeline = TimelineBuilder.build(chapters: read.chapters, segmenter: Segmenter(normalizer: TextNormalizer()))
        #expect(timeline.utteranceCount == 7)
        for i in 0..<timeline.utteranceCount {
            #expect(PositionResolver.resolve(timeline[utterance: i].position, in: timeline) == Playhead(utteranceIndex: i))
        }
    }

    @Test func noTableOfContentsMeansOneChapterPerResource() async throws {
        let read = try await reader.read(fileURL: try EPUBFixture.noTOCBook(), sourceType: .epub)
        #expect(read.chapters.count == 2)
        #expect(read.chapters.map { $0.blocks.count } == [3, 2])
        #expect(read.chapters.map(\.title) == ["Section 1", "Section 2"])
    }

    @Test func readsAnArticleEPUBFromTheWriter() async throws {
        let article = ArticleContent(title: "Tom & Jerry", byline: "Jane Doe", sourceURL: URL(string: "https://example.com/t"),
                                     bodyXHTML: "<p>First paragraph.</p><p>Second one.</p>")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-article-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("source.epub")
        try ArticleEPUBWriter.write(article, to: url)
        let read = try await reader.read(fileURL: url, sourceType: .article)
        #expect(read.title == "Tom & Jerry")
        #expect(read.author == "Jane Doe")
        #expect(read.chapters.count == 1)
        #expect(read.chapters[0].blocks.map(\.text) == ["Tom & Jerry", "Jane Doe", "First paragraph.", "Second one."])
        #expect(read.skippedResources.isEmpty)
    }

    @Test func drmIsRejectedPlainly() async throws {
        await #expect(throws: ImportError.drmProtected) {
            _ = try await reader.read(fileURL: try EPUBFixture.drmBook(), sourceType: .epub)
        }
    }

    @Test func garbageIsRejected() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).epub")
        try Data("not an epub".utf8).write(to: url)
        await #expect(throws: ImportError.self) { _ = try await reader.read(fileURL: url, sourceType: .epub) }
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `scripts/test-readium.sh`
Expected: compile error, `ReadiumDocumentReader` not found.

- [ ] **Step 4: Implement**

```swift
// Packages/T2SReadium/Sources/T2SReadium/ReadiumDocumentReader.swift
import Foundation
import ReadiumShared
import ReadiumStreamer
import T2SCore
import T2SLibrary
import UIKit

/// EPUBs (and article EPUBs) through the Readium streamer's content iterator. Readium types stay in
/// this file; the output is a `ReadDocument` whose `Position`s follow the EPUB rule in the plan's
/// Global Constraints (spec §3.7.2: convert at the boundary, never persist a `Locator`).
public struct ReadiumDocumentReader: DocumentReader {
    public let supportedTypes: Set<SourceType> = [.epub, .article]

    public init() {}

    public func read(fileURL: URL, sourceType: SourceType) async throws -> ReadDocument {
        let publication = try await open(fileURL)
        if publication.isRestricted { throw ImportError.drmProtected }          // spec §6: reject DRM plainly

        // Blocks grouped by resource, in reading order. `charOffset` counts trimmed block texts joined by "\n".
        guard let content = publication.content() else { throw ImportError.noText }
        var blocksByHref: [String: [SourceBlock]] = [:]
        var hrefOrder: [String] = []
        var offsets: [String: Int] = [:]
        for await element in content.sequence() {
            guard let textElement = element as? TextContentElement,
                  let text = textElement.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
            else { continue }
            let locator = textElement.locator
            let href = locator.href.string
            if blocksByHref[href] == nil { hrefOrder.append(href) }
            let offset = offsets[href, default: 0]
            var cssSelector: String?
            if case .string(let selector)? = locator.locations.otherLocations["cssSelector"] { cssSelector = selector }
            blocksByHref[href, default: []].append(SourceBlock(
                text: text,
                position: Position(resourceHref: href, progression: locator.locations.progression ?? 0,
                                   charOffset: offset, cssSelector: cssSelector)))
            offsets[href] = offset + text.utf16.count + 1
        }
        guard !hrefOrder.isEmpty else { throw ImportError.noText }

        let readingOrder = publication.readingOrder.map { $0.url().string }
        func resourceIndex(_ href: String) -> Int? {
            let key = Self.withoutFragment(href)
            return readingOrder.firstIndex(of: key) ?? hrefOrder.firstIndex(of: key)
        }

        // Table of contents → (title, resource index), first title per resource, ordered by resource.
        let toc = (try? await publication.tableOfContents().get()) ?? []
        var entries: [(title: String, resource: Int)] = []
        func walk(_ links: [Link]) {
            for link in links {
                if let r = resourceIndex(link.url().string), !entries.contains(where: { $0.resource == r }) {
                    let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    entries.append((title.isEmpty ? "Section \(entries.count + 1)" : title, r))
                }
                walk(link.children)
            }
        }
        walk(toc)
        entries.sort { $0.resource < $1.resource }

        var chapters: [ChapterInput] = []
        if entries.isEmpty {
            // No usable TOC: one chapter per resource with text, titled by the link or "Section n".
            for href in hrefOrder {
                let blocks = blocksByHref[href] ?? []
                let link = publication.readingOrder.first { $0.url().string == href }
                let title = link?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                chapters.append(ChapterInput(title: title.isEmpty ? "Section \(chapters.count + 1)" : title,
                                             position: blocks[0].position, blocks: blocks))
            }
        } else {
            // Each TOC entry owns its resource and every following resource up to the next entry;
            // resources before the first entry are front matter.
            var groups = Array(repeating: [SourceBlock](), count: entries.count + 1)
            for href in hrefOrder {
                let r = resourceIndex(href) ?? Int.max
                let owner = entries.lastIndex(where: { $0.resource <= r }).map { $0 + 1 } ?? 0
                groups[owner].append(contentsOf: blocksByHref[href] ?? [])
            }
            if !groups[0].isEmpty {
                chapters.append(ChapterInput(title: "Front matter", position: groups[0][0].position, blocks: groups[0]))
            }
            for (i, entry) in entries.enumerated() where !groups[i + 1].isEmpty {
                chapters.append(ChapterInput(title: entry.title, position: groups[i + 1][0].position, blocks: groups[i + 1]))
            }
        }

        let title = publication.metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let authors = publication.metadata.authors.map(\.name).filter { !$0.isEmpty }
        let cover = (try? await publication.cover().get())?.flatMap { $0.jpegData(compressionQuality: 0.8) }
        let skipped = readingOrder.filter { blocksByHref[$0] == nil }
        return ReadDocument(
            title: (title?.isEmpty == false ? title : nil) ?? fileURL.deletingPathExtension().lastPathComponent,
            author: authors.isEmpty ? nil : authors.joined(separator: ", "),
            coverImage: cover,
            chapters: chapters,
            skippedResources: skipped)
    }

    private func open(_ fileURL: URL) async throws -> Publication {
        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(parser: DefaultPublicationParser(
            httpClient: httpClient, assetRetriever: assetRetriever, pdfFactory: DefaultPDFDocumentFactory()))
        guard let url = FileURL(url: fileURL) else { throw ImportError.unreadable("not a file URL: \(fileURL)") }
        let asset: Asset
        switch await assetRetriever.retrieve(url: url) {
        case .success(let a): asset = a
        case .failure(let error): throw ImportError.unreadable("\(error)")
        }
        switch await opener.open(asset: asset, allowUserInteraction: false) {
        case .success(let publication): return publication
        case .failure(.formatNotSupported): throw ImportError.unsupportedFormat(fileURL.pathExtension)
        case .failure(.reading(let error)): throw ImportError.unreadable("\(error)")
        }
    }

    static func withoutFragment(_ href: String) -> String {
        href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `scripts/test-readium.sh`
Expected: 7 tests passed (6 here plus the smoke test). Known variations to handle without changing the tests' intent: if Readium reports resource hrefs with a different normalization between `locator.href.string` and `link.url().string` (percent-encoding), normalize both through `AnyURL(string:)?.normalized.string ?? href` in one helper and use it on both sides; if the DRM fixture opens as unrestricted, check that `META-INF/encryption.xml` is spelled exactly and that the `adept:resource` element sits under `sig:KeyInfo` — that is what `EPUBFormatSniffer` matches. If `publication.content()` returns nil for a valid EPUB, the streamer's `EPUBParser` did not attach the content service — that means the asset was not sniffed as EPUB; check the `mimetype` entry is first and stored.

- [ ] **Step 6: Commit**

```bash
git add Packages/T2SReadium
git commit -m "Add ReadiumDocumentReader: EPUB content iterator to ChapterInputs with stable Positions"
```

---

### Task 10: `LocatorMapping` — `Position` ↔ `Locator` at the boundary

**Files:**
- Create: `Packages/T2SReadium/Sources/T2SReadium/LocatorMapping.swift`
- Create: `Packages/T2SReadium/Tests/T2SReadiumTests/LocatorMappingTests.swift`

**Interfaces:**
- Consumes: `Position`, `HighlightRange`, `Timeline` (T2SCore); `Locator`, `Locator.Locations`, `Locator.Text`, `AnyURL`, `MediaType`, `JSONValue` (ReadiumShared).
- Produces: `public enum LocatorMapping { static let contextLength = 50; static func locator(for: Position, mediaType:, text:) -> Locator?; static func position(for: Locator) -> Position; static func locator(for: HighlightRange, in: Timeline, mediaType:) -> Locator? }`. Plan 4's reader page uses the last one for the active-word decoration and the second for "tap a sentence → seek".

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/T2SReadium/Tests/T2SReadiumTests/LocatorMappingTests.swift
import Foundation
import ReadiumShared
import Testing
import T2SCore
@testable import T2SReadium

@Suite struct LocatorMappingTests {
    @Test func positionRoundTripsThroughALocator() throws {
        let position = Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0.4, charOffset: 12,
                                cssSelector: "html > body > p:nth-child(2)")
        let locator = try #require(LocatorMapping.locator(for: position))
        #expect(locator.href.string == "OEBPS/ch1.xhtml")
        #expect(locator.mediaType == .xhtml)
        #expect(locator.locations.progression == 0.4)
        #expect(locator.locations.otherLocations["cssSelector"] == .string("html > body > p:nth-child(2)"))
        var back = LocatorMapping.position(for: locator)
        #expect(back.charOffset == nil)                                     // a Locator carries no char offset
        back.charOffset = 12
        #expect(back == position)
    }

    @Test func wordHighlightCarriesQuoteAndContext() {
        let source = "The quick brown fox jumps over the lazy dog."
        let n = source.utf16.count
        let utterance = Utterance(position: Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0, charOffset: 0,
                                                     cssSelector: "p:nth-child(1)"),
                                  source: source, spoken: source,
                                  spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], duration: .estimated(3))
        let timeline = Timeline(chapters: [Chapter(title: "1", position: utterance.position, utterances: [utterance])])
        let range = HighlightRange(utteranceIndex: 0, position: utterance.position, sourceRange: 10..<15)
        let locator = LocatorMapping.locator(for: range, in: timeline)
        #expect(locator?.text.highlight == "brown")
        #expect(locator?.text.before == "The quick ")
        #expect(locator?.text.after == " fox jumps over the lazy dog.")
        #expect(locator?.locations.otherLocations["cssSelector"] == .string("p:nth-child(1)"))
        #expect(LocatorMapping.locator(for: HighlightRange(utteranceIndex: 3, position: utterance.position, sourceRange: 0..<1), in: timeline) == nil)
    }

    @Test func contextIsCappedAtContextLength() {
        let source = String(repeating: "a", count: 200) + "WORD" + String(repeating: "b", count: 200)
        let n = source.utf16.count
        let utterance = Utterance(position: Position(resourceHref: "OEBPS/x.xhtml", progression: 0), source: source, spoken: source,
                                  spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], duration: .estimated(3))
        let timeline = Timeline(chapters: [Chapter(title: "1", position: utterance.position, utterances: [utterance])])
        let locator = LocatorMapping.locator(for: HighlightRange(utteranceIndex: 0, position: utterance.position, sourceRange: 200..<204), in: timeline)
        #expect(locator?.text.highlight == "WORD")
        #expect(locator?.text.before?.count == LocatorMapping.contextLength)
        #expect(locator?.text.after?.count == LocatorMapping.contextLength)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `scripts/test-readium.sh`
Expected: compile error, `LocatorMapping` not found.

- [ ] **Step 3: Implement**

```swift
// Packages/T2SReadium/Sources/T2SReadium/LocatorMapping.swift
import Foundation
import ReadiumShared
import T2SCore

/// The Readium boundary (spec §3.7.2): `Position` in, `Locator` out, and back. A word highlight is
/// a text quote with context plus the block's CSS selector, which the EPUB navigator's decorator
/// resolves to a DOM range.
public enum LocatorMapping {
    /// UTF-16 units of context on each side of a highlight quote.
    public static let contextLength = 50

    public static func locator(for position: Position, mediaType: MediaType = .xhtml, text: Locator.Text = Locator.Text()) -> Locator? {
        guard let href = AnyURL(string: position.resourceHref) else { return nil }
        var locations = Locator.Locations(progression: position.progression)
        if let selector = position.cssSelector { locations.otherLocations["cssSelector"] = .string(selector) }
        return Locator(href: href, mediaType: mediaType, locations: locations, text: text)
    }

    /// The persisted form of a navigator locator (a tapped sentence, the visible page). `charOffset`
    /// is unknown here; `PositionResolver` falls back to progression within the resource.
    public static func position(for locator: Locator) -> Position {
        var selector: String?
        if case .string(let s)? = locator.locations.otherLocations["cssSelector"] { selector = s }
        return Position(resourceHref: locator.href.string, progression: locator.locations.progression ?? 0,
                        charOffset: nil, cssSelector: selector)
    }

    /// The active word: the utterance's source slice as the quote, with up to `contextLength` UTF-16
    /// units of the same utterance before and after it.
    public static func locator(for range: HighlightRange, in timeline: Timeline, mediaType: MediaType = .xhtml) -> Locator? {
        guard range.utteranceIndex >= 0, range.utteranceIndex < timeline.utteranceCount else { return nil }
        let source = timeline[utterance: range.utteranceIndex].source as NSString
        let quote = NSRange(location: range.sourceRange.lowerBound, length: range.sourceRange.count)
        guard quote.location >= 0, quote.location + quote.length <= source.length else { return nil }
        let beforeStart = max(0, quote.location - contextLength)
        let afterEnd = min(source.length, quote.location + quote.length + contextLength)
        let afterStart = quote.location + quote.length
        let text = Locator.Text(
            after: afterStart < afterEnd ? source.substring(with: NSRange(location: afterStart, length: afterEnd - afterStart)) : nil,
            before: beforeStart < quote.location ? source.substring(with: NSRange(location: beforeStart, length: quote.location - beforeStart)) : nil,
            highlight: source.substring(with: quote))
        return locator(for: range.position, mediaType: mediaType, text: text)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `scripts/test-readium.sh`
Expected: 10 tests passed. Then the root suite and the guard: `swift test && scripts/check-licenses.sh`.

- [ ] **Step 5: Commit**

```bash
git add Packages/T2SReadium
git commit -m "Add LocatorMapping: Position to Locator and word-highlight quotes at the Readium boundary"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| §2.1 EPUB via Readium; article → minimal EPUB with original HTML retained; text PDF via PDFKit (rev 6) | 9, 7 + 8, 5 |
| §2.3 everything imported joins the Queue; Collection = EPUB + PDF | 8, 2 |
| §3.1 domain model persisted as value types; client UUIDs | 2 |
| §3.2 `Position` is the persisted anchor; survives re-segmentation | 2 (`replaceTimeline`), 8 (`reprocess`), 5 and 9 (round-trip tests) |
| §3.7.1 client-generated keys, schema does not shape the domain | 2 (internal rows) |
| §3.7.2 Readium never persisted; thin adapter | 9, 10 |
| §3.7.3 derived data re-derivable; sources never mutated; original HTML retained | 8 |
| §3.7.4 versions on every timeline; stale → re-derive | 2, 8 |
| §3.7.5 license ratchet over every package | 1 |
| §4 Importer → Readium → Segmenter → Timeline phase 1 → persisted | 8 |
| §5 SwiftData for documents, chapters, playheads, bookmarks, dictionary; blobs per chapter; container layout; audio is cache | 2, 3, 4, 8 |
| §6 DRM rejected plainly; malformed imports what parses and lists skipped; little text surfaced (`plainText`, `noText`); position fallback unchanged | 5, 7, 8, 9 |
| §7.6 Readium license verified, iOS-only reach recorded | 1 (guard + package), spec rev 6 |
| §8 Segmenter golden test over a real EPUB; `Position` round-trip stability | 9 |
| §9 step 3 (Readium part), step 4 (`TimelineStore`) | 9, 2 |

Not in this plan, by design: the Share Extension and Readability.js (Plan 5 produces `ArticleContent`), the Readium navigator and decorations (Plan 4 consumes `LocatorMapping`), sync tombstones and conflict policy (Plan 6, behind `SyncProvider`), and the pronunciation-dictionary UI (Plan 5).
