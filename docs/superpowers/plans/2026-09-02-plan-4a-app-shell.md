# Plan 4a: App Shell, Import, and Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the first runnable iPhone app: the Queue · Collection · Preferences pager with the mini-player, the Add sheet that imports a link, a file, or pasted text, the player sheet with the tick scrubber, and audible playback through a system-voice fallback engine, all on the plumbing from Plans 1–3. The Reader page, speed picker, sleep timer, and Preferences content follow in Plan 4b.

**Architecture:** Everything with logic lives in a new root-package target `T2SApp` (pure Swift, `@Observable` `@MainActor` models, formatters, the import state machine, device-state mapping) so it is tested with `swift test` on macOS. The iOS app target `T2SReader` under `App/` (xcodegen project) holds SwiftUI views, the design tokens, the WKWebView article extractor, and the `AppEnvironment` that composes `LibraryStore`, `Library`, `FileAudioStore`, `PlaybackCoordinator`, and the readers. A `SystemSpeechEngine` in `T2SAudio` (AVSpeechSynthesizer, the spec §6 fallback) is the engine until Kokoro lands in Plan 5, so the app is usable end to end now. Readium types never reach the app's models: the Reader (Plan 4b) is the only view that touches them.

**Tech Stack:** Swift 6 (language mode 6), SwiftUI, Observation, AVFoundation (`AVSpeechSynthesizer`, `AVAudioSession`), WebKit (`WKWebView` + vendored Readability.js 0.6.0, Apache-2.0), UniformTypeIdentifiers, xcodegen 2.x (`/opt/homebrew/bin/xcodegen`), Readium swift-toolkit 3.11.0 (`ReadiumNavigator`, `ReadiumAdapterGCDWebServer` linked now, used in Plan 4b), Inter 4.1 static TTFs (SIL OFL 1.1). iOS 18 deployment; macOS 15 for `swift test`.

**Spec:** `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (rev 7). Sections §2.2, §2.3, §2.4 (all), §3 (coordinator ownership), §3.4.1 (visible state, nothing gated on rendering), §3.5 (audio session), §5, §6, §9 steps 6 and 8.

## Global Constraints

- **Semantic tokens only; no literal colors in views** (spec §2.4.2). Light / dark: `ground` #F8F8F7 / #101010, `surface` #EEEEEC / #1E1E1E, `raised` #FFFFFF / #1A1A1A, `ink` #111111 / #F2F2F2, `ink2` #8A8A8A / #8E8E8E, `ink3` #C9C9C7 / #3A3A3A, `accent` #FF7A1A / #FF8C3A, `accentSoft` = accent at 18% / 22%, `positive` #22A559 / #34C070, `destructive` #E5453B / #FF5A50. At most one `accent` element per screen. Selected chips are solid `ink` with `ground` text. `positive`/`destructive` only on state tags and confirming actions.
- **Type roles** (spec §2.4.1, Dynamic Type relative): Page title Inter Display 34 Black −0.03em; Player title Inter Display 26 ExtraBold ≤4 lines −0.025em; Section header Inter 17 Semibold −0.01em; Row title Inter 17 Medium ≤2 lines −0.01em; Pill label Inter 15 Medium −0.01em; Meta Inter 13 Regular 0; Timestamps and counts system monospaced 13 Regular. Fonts: `Inter-Regular`, `Inter-Medium`, `Inter-SemiBold`, `InterDisplay-ExtraBold`, `InterDisplay-Black` (PostScript names, bundled).
- **Spacing** (spec §2.4.3): 8pt grid; 24pt horizontal margins; 28pt between rows; 40pt between sections; 56pt from the safe-area top to a page title; **no cards in lists and no hairline dividers**; pills fully rounded; sheets with 28pt top corners; artwork 8pt radius small, 16pt large.
- **Navigation** (spec §2.4.4): no tab bar; a three-page horizontal pager Collection · Queue · Preferences opening on Queue; a tappable three-glyph indicator; the floating mini-player pill above it on every page, showing the playing item or the next queued item with "Play" when idle, hidden only when the Queue is empty; page titles are dropdowns where a page has views (`Queue ▾` → Queue / Finished).
- **Queue rows** (spec §2.4.5): 16pt source mark, source name, added-age, a `positive` check once fully rendered; row title; pill row `▶ Play ~12m` (becomes `❚❚ Pause` on the playing row), archive pill, overflow. Books show `Chapter 4 of 12`. Subtitle `14 items · ~6h 20m`. Total time is prefixed `~` until fully rendered (spec §3.3).
- **Add sheet** (spec §2.4.5 rev 7): three soft pills Paste a link / Open a file / Paste text; link page prefilled from the clipboard with one `accent` "Listen" pill, extraction preview with title, site, first lines, word count; file picker filtered to EPUB and PDF with multiple selection and a row per file; paste-text page with optional title; every import joins the end of the Queue and opens the Reader with playback started (in this plan, until the Reader exists, the player sheet opens and playback starts); errors inline in `destructive`, never a system alert.
- **Nothing is gated on rendering** (spec §3.4.1): a document is playable the moment it appears; there is no "processing…" state on import; the prime tier renders its first ~30 s.
- **Playback ownership** (spec §3): `PlaybackCoordinator` owns the playhead; the UI only calls `play/pause/seek/setRate/renderWholeDocument`, reads `state/playhead/highlight/timeIndex/measuredRTF/availableRates`, and calls `tick()` on a 10 Hz timer while playing. Positions persist through the store's `PlayheadStore` conformance; the UI never persists an utterance index (spec §3.2).
- **Audio session** (spec §3.5): category `.playback`, mode `.spokenAudio`; interruptions pause; the `audio` background mode is on. Now Playing / remote commands are Plan 5.
- **Readium never reaches the models.** `T2SApp` and every view except the Reader (Plan 4b) import no Readium module; `ReadiumDocumentReader` is injected into `Library` by `AppEnvironment`.
- **Every model in `T2SApp` is testable on macOS** with `swift test`; view files contain layout and bindings only. Every public type `Sendable`, an actor, or `@MainActor`; Swift 6; Swift Testing.
- Generated files are never committed: `App/T2SReader.xcodeproj/` and `App/T2SReader/Info.plist` come from `App/project.yml` (README rule). Fonts are committed (OFL) under `App/Resources/Fonts/` with their `LICENSE.txt`.
- Commit after every task with the message given in the task.

## Verified toolchain facts (do not re-derive)

- xcodegen is installed at `/opt/homebrew/bin/xcodegen`; the spike harness at `spikes/SpikeHarness/project.yml` is the house style. A package directory's scheme is named after the product (`-scheme T2SReadium`); an app project's scheme is the target name. Reliable simulator destination: `-destination "id=<udid>"` (local iPhone 16 Pro: `B4403B3A-10A8-43A3-9B61-FD2439ADFEA5`); for build-only, `-destination "generic/platform=iOS Simulator"` works.
- Readium 3.11.0 products the app links: `ReadiumShared`, `ReadiumStreamer`, `ReadiumNavigator`, `ReadiumAdapterGCDWebServer`. `GCDHTTPServer(assetRetriever:)`; `EPUBNavigatorViewController(publication:initialLocation:config:httpServer:)`; `DecorableNavigator.apply(decorations:in:)`, `Decoration(id:locator:style: .highlight(tint:isActive:))`; `EPUBPreferences { fontFamily, fontSize, lineHeight, theme, backgroundColor, textColor }`, `submitPreferences(_:)`; `Navigator.go(to:options:) async -> Bool`, `currentLocation`, `VisualNavigator.firstVisibleElementLocator() async`, delegate `navigator(_:locationDidChange:)`, `navigator(_:didTapAt:)`. (Plan 4b uses these; they are listed so this plan links the right products.)
- Inter 4.1 (`https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip`, 33.7 MB) ships static TTFs under `extras/ttf/`; the five we bundle have PostScript names equal to their file stems: `Inter-Regular`, `Inter-Medium`, `Inter-SemiBold`, `InterDisplay-ExtraBold`, `InterDisplay-Black`. `LICENSE.txt` at the archive root is SIL OFL 1.1.
- `AVSpeechSynthesizer.write(_:toBufferCallback:toMarkerCallback:)` delivers `AVAudioPCMBuffer`s at 22 050 Hz mono Float32 (the compact `en-US` voice), ending with a zero-length buffer; callbacks arrive on the main run loop (a blocked thread never receives them). On macOS 15 with the compact voice the marker callback delivers **no** word markers, so word timings are optional in the fallback engine: use markers when present, return `[]` otherwise (the highlighter already degrades to character-proportional timing).
- From Plans 1–3 (public API): `PlaybackCoordinator(engine:store:player:playheadStore:timeSource:configuration:)`, `load(_:timeline:)`, `play() async`, `pause()`, `seek(to:) async`, `seek(toTime:) async`, `setRate(_:)`, `renderWholeDocument()`, `resumeRendering() async`, `tick()`, `state: PlaybackState {idle, playing, paused, catchingUp, finished}`, `playhead`, `highlight: HighlightRange?`, `rate`, `availableRates`, `measuredRTF`, `lastRenderError`, `document`, `timeline`, `timeIndex: TimeIndex`, `device: DeviceState`, `queue: [UUID]`. `AudioPlayer(sampleRate:manualRendering:) throws`. `FakeEngine(secondsPerCharacter:)`, `InMemoryAudioStore(codec:capacityBytes:)`, `FileAudioStore(directory:codec:capacityBytes:)`, `AACCodec()`, `RawPCMCodec()`. `LibraryStore.onDisk(at:)`/`.inMemory()`, `summaries()`, `summary(id:)`, `queue()`, `collection()`, `setQueued(_:_:)`, `moveInQueue(_:to:)`, `setFinished(_:_:)`, `delete(id:)`, `timeline(for:)`, `pronunciations()`. `Library(paths:store:audioStore:readers:)`, `importFile(at:sourceType:) -> ImportResult`, `importArticle(_:originalHTML:) -> ImportResult`, `delete(_:)`, `timelineForPlayback(_:)`, `evictAudio(for:)`, `renderSnapshot(for:)`. `LibraryPaths(root:)`. `PDFDocumentReader()`, `ReadiumDocumentReader()` (T2SReadium, iOS only). `ArticleContent(title:byline:siteName:sourceURL:language:bodyXHTML:excerpt:)`, `XHTML.plainText(ofFragment:)` is internal to T2SLibrary — the word count comes from the extractor's own text.
- The coordinator's `replan()` plans only the loaded document (plus queue order for the prepare tier of that document). Multi-document Prepare needs a separate runner that loads each queued document's timeline; that is Plan 5 (with `BGProcessingTask`), not this plan.

## File structure

```
Package.swift                                   + T2SApp target and product, T2SAppTests
Sources/T2SApp/
  T2SApp.swift                                  module marker
  Formatting/DurationFormatter.swift            ~6h 20m · 12m · 0:42 · "2d" ages · "14 items"
  Environment/AppPaths.swift                    container root (Application Support/t2s), UserDefaults keys
  Environment/DeviceStateMapping.swift          battery/thermal/low-power/store stats → DeviceState (pure)
  Library/LibraryModel.swift                    @Observable: summaries, queue, finished, collection, actions
  Player/PlayerModel.swift                      @Observable bridge over PlaybackCoordinator
  Player/ScrubberModel.swift                    tick marks with the render frontier
  Import/ArticleExtracting.swift                protocol + ExtractedArticle
  Import/ImportModel.swift                      Add-sheet state machine
Sources/T2SAudio/SystemSpeechEngine.swift       AVSpeechSynthesizer fallback engine (spec §6)
Tests/T2SAppTests/…                             one suite per model
Tests/T2SAudioTests/SystemSpeechEngineTests.swift
App/
  project.yml                                   xcodegen; T2SReader app target
  T2SReader/
    T2SReaderApp.swift                          @main, environment injection
    AppEnvironment.swift                        composition root
    Design/Tokens.swift                         Color tokens (dynamic light/dark)
    Design/Typography.swift                     Font roles + tracking
    Design/Spacing.swift                        grid constants
    Design/Primitives.swift                     Pill, SoftPill, PageTitle, Meta, Artwork, ProgressBar
    Root/RootPager.swift                        three-page pager + indicator + mini-player overlay
    Root/PageIndicator.swift
    Root/MiniPlayer.swift
    Queue/QueuePage.swift, QueueRow.swift, EmptyQueue.swift, DetailsSheet.swift
    Collection/CollectionPage.swift, BookSheet.swift
    Player/PlayerSheet.swift, TickScrubber.swift, ChapterList.swift
    Import/AddSheet.swift, PasteLinkPage.swift, PasteTextPage.swift, FileImportRows.swift
    Import/ArticleExtractor.swift               WKWebView + Readability.js → ExtractedArticle
    Import/Readability.js                       vendored, Apache-2.0
    Preferences/PreferencesPage.swift           title + placeholder sections (content in Plan 4b)
    System/AudioSessionController.swift
    System/DeviceMonitor.swift
    System/PlaybackTicker.swift                 10 Hz tick while playing
  Resources/Fonts/*.ttf, LICENSE.txt
scripts/build-app.sh                            xcodegen generate + xcodebuild build (simulator)
scripts/fetch-fonts.sh                          re-downloads the five Inter TTFs
.github/workflows/ci.yml                        + app-ios job
README.md                                       App/ section
```

---

### Task 1: App project, fonts, `T2SApp` target, build script, CI

**Files:**
- Modify: `Package.swift` (add `T2SApp` target + product, `T2SAppTests`)
- Create: `Sources/T2SApp/T2SApp.swift`, `Tests/T2SAppTests/T2SAppSmokeTests.swift`
- Create: `App/project.yml`, `App/T2SReader/T2SReaderApp.swift`, `App/T2SReader/RootView.swift`
- Create: `App/Resources/Fonts/Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf`, `InterDisplay-ExtraBold.ttf`, `InterDisplay-Black.ttf`, `LICENSE.txt` (via the script)
- Create: `scripts/fetch-fonts.sh`, `scripts/build-app.sh`
- Modify: `.gitignore`, `.github/workflows/ci.yml`, `README.md`, `docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md`

**Interfaces:**
- Produces: root product `T2SApp` (depends on `T2SCore`, `T2SAudio`, `T2SStore`, `T2SLibrary`); app target `T2SReader` linking every T2S product, `T2SReadium`, and Readium's `ReadiumShared`, `ReadiumStreamer`, `ReadiumNavigator`, `ReadiumAdapterGCDWebServer`; `scripts/build-app.sh` exits 0 when the app builds for the simulator.

- [ ] **Step 1: Root package target and smoke test**

Add to `Package.swift` products: `.library(name: "T2SApp", targets: ["T2SApp"]),` and targets:

```swift
        .target(name: "T2SApp", dependencies: ["T2SCore", "T2SAudio", "T2SStore", "T2SLibrary"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "T2SAppTests",
            dependencies: ["T2SApp", "T2SCore", "T2SAudio", "T2SStore", "T2SLibrary"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
```

```swift
// Sources/T2SApp/T2SApp.swift
import T2SCore

/// The app's models and formatters, kept free of UIKit and Readium so they run under `swift test`.
public enum T2SApp {
    /// The T2SCore schema this build of T2SApp was compiled against.
    public static let coreSchemaVersion = Versions.schema
}
```

```swift
// Tests/T2SAppTests/T2SAppSmokeTests.swift
import Testing
import T2SCore
@testable import T2SApp

@Suite struct T2SAppSmokeTests {
    @Test func linksAgainstCore() {
        #expect(T2SApp.coreSchemaVersion == Versions.schema)
    }
}
```

Run: `swift test --filter T2SAppSmokeTests`
Expected: 1 test passed.

- [ ] **Step 2: Fonts**

```bash
# scripts/fetch-fonts.sh
#!/usr/bin/env bash
# Downloads Inter 4.1 and copies the five static faces the app bundles (spec §2.4.1) plus the OFL
# license into App/Resources/Fonts. The fonts are committed; run this only to refresh them.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -sSL -o "$tmp/inter.zip" https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip
mkdir -p App/Resources/Fonts
for face in Inter-Regular Inter-Medium Inter-SemiBold InterDisplay-ExtraBold InterDisplay-Black; do
  unzip -p "$tmp/inter.zip" "extras/ttf/$face.ttf" > "App/Resources/Fonts/$face.ttf"
done
unzip -p "$tmp/inter.zip" LICENSE.txt > App/Resources/Fonts/LICENSE.txt
ls -la App/Resources/Fonts
```

Run: `chmod +x scripts/fetch-fonts.sh && scripts/fetch-fonts.sh`
Expected: five `.ttf` files of roughly 410–425 KB each and `LICENSE.txt` beginning `Copyright (c) 2016 The Inter Project Authors`.

- [ ] **Step 3: The xcodegen project**

```yaml
# App/project.yml — the iOS app. Regenerate the .xcodeproj with `xcodegen generate` (never hand-edit it).
name: T2SReader
options:
  bundleIdPrefix: com.t2s
  deploymentTarget:
    iOS: "18.0"
  createIntermediateGroups: true
packages:
  T2S:
    path: ..
  T2SReadium:
    path: ../Packages/T2SReadium
  Readium:
    url: https://github.com/readium/swift-toolkit.git
    exactVersion: 3.11.0
targets:
  T2SReader:
    type: application
    platform: iOS
    sources:
      - path: T2SReader
      - path: Resources
        buildPhase: resources
    dependencies:
      - package: T2S
        product: T2SCore
      - package: T2S
        product: T2SAudio
      - package: T2S
        product: T2SStore
      - package: T2S
        product: T2SLibrary
      - package: T2S
        product: T2SApp
      - package: T2SReadium
        product: T2SReadium
      - package: Readium
        product: ReadiumShared
      - package: Readium
        product: ReadiumStreamer
      - package: Readium
        product: ReadiumNavigator
      - package: Readium
        product: ReadiumAdapterGCDWebServer
    info:
      path: T2SReader/Info.plist
      properties:
        CFBundleDisplayName: t2s
        UILaunchScreen: {}
        UIBackgroundModes: [audio]
        UIAppFonts:
          - Inter-Regular.ttf
          - Inter-Medium.ttf
          - Inter-SemiBold.ttf
          - InterDisplay-ExtraBold.ttf
          - InterDisplay-Black.ttf
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        LSSupportsOpeningDocumentsInPlace: false
        CFBundleDocumentTypes:
          - CFBundleTypeName: EPUB
            LSHandlerRank: Alternate
            LSItemContentTypes: [org.idpf.epub-container]
          - CFBundleTypeName: PDF
            LSHandlerRank: Alternate
            LSItemContentTypes: [com.adobe.pdf]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.t2s.reader
        SWIFT_VERSION: "6.0"
        SWIFT_STRICT_CONCURRENCY: complete
        TARGETED_DEVICE_FAMILY: "1,2"
        CODE_SIGN_STYLE: Automatic
        INFOPLIST_KEY_UIUserInterfaceStyle: Automatic
```

```swift
// App/T2SReader/T2SReaderApp.swift
import SwiftUI

@main
struct T2SReaderApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

```swift
// App/T2SReader/RootView.swift
import SwiftUI

/// Placeholder until Task 6 brings the pager. Proves the bundled fonts load: the title must render
/// in Inter Display Black, not the system font.
struct RootView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("t2s")
                .font(.custom("InterDisplay-Black", size: 34))
            Text("Fonts loaded: \(UIFont.fontNames(forFamilyName: "Inter Display").sorted().joined(separator: ", "))")
                .font(.custom("Inter-Regular", size: 13))
            Spacer()
        }
        .padding(24)
    }
}
```

- [ ] **Step 4: Build script, ignore rules, CI, README, roadmap**

```bash
# scripts/build-app.sh
#!/usr/bin/env bash
# Regenerates the Xcode project from App/project.yml and builds the app for the iOS simulator.
# Usage: scripts/build-app.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/../App"
xcodegen generate --quiet
set +e
xcodebuild build -scheme T2SReader -destination "generic/platform=iOS Simulator" \
  -derivedDataPath ../.build/DerivedData-App \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "$@" 2>&1 \
  | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" \
  | grep -Ev "/checkouts/.*: warning:|/SourcePackages/.*: warning:"
exit "${PIPESTATUS[0]}"
```

Append to `.gitignore` under the "Generated by xcodegen" comment:

```
App/T2SReader.xcodeproj/
App/T2SReader/Info.plist
```

CI: add a third job to `.github/workflows/ci.yml`:

```yaml
  app-ios:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: scripts/build-app.sh
```

README: in the layout block replace the `App/` line with

```
App/                   the iOS app: project.yml → T2SReader.xcodeproj (generated, ignored),
                       T2SReader/ (SwiftUI views, composition root), Resources/Fonts (Inter, OFL)
```

add `T2SApp (models, formatters)` to the `Package.swift` target list line, add `App/T2SReader.xcodeproj/` and `App/T2SReader/Info.plist` to the "Ignored and regenerated" sentence, and add to "Working on it":

```bash
scripts/build-app.sh           # regenerate App/T2SReader.xcodeproj and build for the simulator
open App/T2SReader.xcodeproj   # after scripts/build-app.sh has generated it
```

Roadmap: split row 4 into `4a | App shell, import, player: T2SApp models, design tokens, pager, Queue, Collection, mini-player, player sheet, Add sheet (link/file/text), system-voice fallback engine | 6, 8 | 2026-09-02-plan-4a-app-shell.md | written` and `4b | Reader page with decorations and auto-scroll, speed picker, sleep timer, Preferences, storage manager | 6, 8, 9 (part) | — | after 4a`; add `App/` to the layout block as above.

- [ ] **Step 5: Verify and commit**

Run: `chmod +x scripts/build-app.sh && scripts/build-app.sh`
Expected: `** BUILD SUCCEEDED **`, no `error:` lines, no warnings from files under `App/` or `Sources/`. The first run resolves and compiles Readium for the simulator (minutes). If xcodegen rejects `path: ..`, use `path: "../"`; if Xcode reports the two Readium references (from `Packages/T2SReadium` and from `project.yml`) as conflicting, they are the same URL at the same exact version — the fix is to make them identical, never to drop one.

Run: `swift test`
Expected: the existing suites plus `T2SAppSmokeTests` pass (Plan 3's final count + 1).

```bash
git add Package.swift Sources/T2SApp Tests/T2SAppTests App scripts .gitignore .github README.md docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md
git commit -m "Add the T2SReader app project, bundled Inter fonts, the T2SApp target, and the simulator build script"
```

---
### Task 2: `SystemSpeechEngine` — the system-voice fallback engine

**Files:**
- Create: `Sources/T2SAudio/SystemSpeechEngine.swift`
- Create: `Tests/T2SAudioTests/SystemSpeechEngineTests.swift`

**Interfaces:**
- Consumes: `SynthesisEngine`, `SynthesisRequest`, `SynthesisResult`, `SynthesisError.failed(String)`, `PCMAudio(sampleRate:samples:)`, `WordTiming` (T2SCore).
- Produces: `public final class SystemSpeechEngine: SynthesisEngine` with `engineID == "system-speech"`, `init(sampleRate: Double = PCMAudio.defaultSampleRate, fallbackLanguage: String = "en-US")`, `synthesize(_:) async throws -> SynthesisResult`; internal `static func resample(_:from:to:) throws -> PCMAudio`, `static func timings(from:text:sampleRate:totalSeconds:) -> [WordTiming]`, `struct Marker { range: Range<Int>; sampleOffset: Int }`.

The `AudioPlayer` schedules buffers in its own format (24 kHz mono by default) without inspecting `PCMAudio.sampleRate`, and `AACCodec` encodes at the PCM's rate, so the engine must hand back audio at the pipeline rate: the system voice speaks at 22 050 Hz and is resampled here.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SAudioTests/SystemSpeechEngineTests.swift
import AVFoundation
import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@Suite struct SystemSpeechEngineTests {
    @Test func timingsFollowMarkersAndCloseAtTheEnd() {
        let text = "Hello brave new world"
        let markers = [
            SystemSpeechEngine.Marker(range: 6..<11, sampleOffset: 11_025),     // "brave" at 0.5 s (22 050 Hz)
            SystemSpeechEngine.Marker(range: 0..<5, sampleOffset: 0),            // "Hello" at 0 s, out of order
            SystemSpeechEngine.Marker(range: 12..<15, sampleOffset: 22_050),     // "new" at 1.0 s
            SystemSpeechEngine.Marker(range: 16..<40, sampleOffset: 33_075),     // past the text: dropped
        ]
        let t = SystemSpeechEngine.timings(from: markers, text: text, sampleRate: 22_050, totalSeconds: 1.4)
        #expect(t.map(\.spokenRange) == [0..<5, 6..<11, 12..<15])
        #expect(t.map(\.start) == [0, 0.5, 1.0])
        #expect(t.map(\.end) == [0.5, 1.0, 1.4])
        #expect(SystemSpeechEngine.timings(from: [], text: text, sampleRate: 22_050, totalSeconds: 1).isEmpty)
    }

    @Test func resampleKeepsDurationAndLevel() throws {
        let from = 22_050.0, to = 24_000.0
        let sine = (0..<22_050).map { Float(sin(Double($0) * 2 * .pi * 440 / from)) * 0.5 }
        let out = try SystemSpeechEngine.resample(sine, from: from, to: to)
        #expect(out.sampleRate == to)
        #expect(abs(out.samples.count - 24_000) <= 64)
        let rms = (out.samples.reduce(0) { $0 + $1 * $1 } / Float(out.samples.count)).squareRoot()
        #expect(abs(rms - 0.3536) < 0.02)                                   // 0.5 / √2
        let same = try SystemSpeechEngine.resample(sine, from: from, to: from)
        #expect(same.samples == sine)
    }

    @Test func synthesizesAudibleAudioAtThePipelineRate() async throws {
        guard !AVSpeechSynthesisVoice.speechVoices().isEmpty else { return }   // no voices installed: nothing to test
        let engine = SystemSpeechEngine()
        let result = try await engine.synthesize(SynthesisRequest(spoken: "Hello world, this is a test.", voiceID: "default"))
        #expect(result.audio.sampleRate == PCMAudio.defaultSampleRate)
        #expect(result.audio.duration > 0.5 && result.audio.duration < 6)
        #expect(result.audio.samples.map(abs).max() ?? 0 > 0.01)             // not silence
        for (a, b) in zip(result.wordTimings, result.wordTimings.dropFirst()) {
            #expect(a.start <= b.start && a.end <= result.audio.duration)
        }
        #expect(engine.engineID == "system-speech")
    }

    @Test func emptyTextFails() async throws {
        guard !AVSpeechSynthesisVoice.speechVoices().isEmpty else { return }
        await #expect(throws: SynthesisError.self) {
            _ = try await SystemSpeechEngine().synthesize(SynthesisRequest(spoken: "   ", voiceID: "default"))
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SystemSpeechEngineTests`
Expected: compile error, `SystemSpeechEngine` not found.

- [ ] **Step 3: Implement**

```swift
// Sources/T2SAudio/SystemSpeechEngine.swift
import AVFoundation
import Foundation
import T2SCore

/// The spec §6 fallback engine (the system voice), and the only engine until Plan 5 lands Kokoro.
/// Offline synthesis through `AVSpeechSynthesizer.write`, resampled to the pipeline rate. Word
/// timings come from the synthesizer's markers when a voice provides them (the compact voices on
/// macOS do not); otherwise the result carries none and the highlighter degrades to
/// character-proportional timing (Plan 1).
public final class SystemSpeechEngine: SynthesisEngine {
    public let engineID = "system-speech"
    public let sampleRate: Double
    /// Used when the request's `voiceID` is not an `AVSpeechSynthesisVoice` identifier (e.g. "default").
    public let fallbackLanguage: String

    public init(sampleRate: Double = PCMAudio.defaultSampleRate, fallbackLanguage: String = "en-US") {
        self.sampleRate = sampleRate
        self.fallbackLanguage = fallbackLanguage
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        guard !request.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SynthesisError.failed("nothing to speak")
        }
        let captured = try await Self.speak(request.spoken, voiceID: request.voiceID, fallbackLanguage: fallbackLanguage)
        let audio = try Self.resample(captured.samples, from: captured.sampleRate, to: sampleRate)
        let timings = Self.timings(from: captured.markers, text: request.spoken,
                                   sampleRate: captured.sampleRate, totalSeconds: audio.duration)
        return SynthesisResult(audio: audio, wordTimings: timings)
    }

    // MARK: Markers → timings

    struct Marker: Hashable, Sendable {
        /// UTF-16 range into the spoken text.
        var range: Range<Int>
        /// Sample index into the synthesizer's own (unresampled) audio.
        var sampleOffset: Int
    }

    /// Each word runs from its marker to the next marker (or the end of the audio). Markers past
    /// the text are dropped; order follows the audio, not the marker delivery order.
    static func timings(from markers: [Marker], text: String, sampleRate: Double, totalSeconds: TimeInterval) -> [WordTiming] {
        let length = text.utf16.count
        let sorted = markers.filter { $0.range.upperBound <= length }.sorted { $0.sampleOffset < $1.sampleOffset }
        guard !sorted.isEmpty, sampleRate > 0 else { return [] }
        return sorted.indices.map { i in
            let start = min(totalSeconds, Double(sorted[i].sampleOffset) / sampleRate)
            let end = i + 1 < sorted.count ? min(totalSeconds, Double(sorted[i + 1].sampleOffset) / sampleRate) : totalSeconds
            return WordTiming(spokenRange: sorted[i].range, start: start, end: max(start, end))
        }
    }

    // MARK: Resampling

    static func resample(_ samples: [Float], from: Double, to: Double) throws -> PCMAudio {
        if abs(from - to) < 0.5 || samples.isEmpty { return PCMAudio(sampleRate: to, samples: samples) }
        guard let inFormat = AVAudioFormat(standardFormatWithSampleRate: from, channels: 1),
              let outFormat = AVAudioFormat(standardFormatWithSampleRate: to, channels: 1),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outFormat,
                                            frameCapacity: AVAudioFrameCount(Double(samples.count) * to / from) + 64)
        else { throw SynthesisError.failed("resampler unavailable for \(from) → \(to) Hz") }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            input.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        final class Feed { var served = false }
        let feed = Feed()
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if feed.served { outStatus.pointee = .endOfStream; return nil }
            feed.served = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error else {
            throw SynthesisError.failed(conversionError?.localizedDescription ?? "resample failed")
        }
        let out = Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
        return PCMAudio(sampleRate: to, samples: out)
    }

    // MARK: Speaking

    struct Captured: Sendable {
        var sampleRate: Double
        var samples: [Float]
        var markers: [Marker]
    }

    /// One `write` call. `AVSpeechSynthesizer` delivers its callbacks on the main run loop, so the
    /// session lives on the main actor and is retained by the callbacks until the final empty buffer.
    @MainActor
    private final class Session {
        let synthesizer = AVSpeechSynthesizer()
        var sampleRate: Double = 0
        var samples: [Float] = []
        var markers: [Marker] = []
        var continuation: CheckedContinuation<Captured, any Error>?

        func receive(_ buffer: AVAudioBuffer) {
            guard let continuation else { return }
            guard let pcm = buffer as? AVAudioPCMBuffer else {
                finish(.failure(SynthesisError.failed("unexpected buffer type \(type(of: buffer))")))
                return
            }
            if pcm.frameLength == 0 {
                if samples.isEmpty {
                    finish(.failure(SynthesisError.failed("the voice produced no audio")))
                } else {
                    finish(.success(Captured(sampleRate: sampleRate, samples: samples, markers: markers)))
                }
                return
            }
            guard pcm.format.commonFormat == .pcmFormatFloat32, let channel = pcm.floatChannelData?[0] else {
                finish(.failure(SynthesisError.failed("unsupported voice format \(pcm.format)")))
                return
            }
            if sampleRate == 0 { sampleRate = pcm.format.sampleRate }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
        }

        func receive(_ speechMarkers: [AVSpeechSynthesisMarker]) {
            let bytesPerSample = MemoryLayout<Float>.size
            for marker in speechMarkers where marker.mark == .word {
                let range = marker.textRange
                markers.append(Marker(range: range.location..<(range.location + range.length),
                                      sampleOffset: max(0, Int(marker.byteSampleOffset) / bytesPerSample)))
            }
        }

        private func finish(_ result: Result<Captured, any Error>) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }

    private static func speak(_ text: String, voiceID: String, fallbackLanguage: String) async throws -> Captured {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let session = Session()
                session.continuation = continuation
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID) ?? AVSpeechSynthesisVoice(language: fallbackLanguage)
                guard utterance.voice != nil else {
                    session.continuation = nil
                    continuation.resume(throwing: SynthesisError.failed("no system voice for \(fallbackLanguage)"))
                    return
                }
                session.synthesizer.write(utterance, toBufferCallback: { buffer in
                    MainActor.assumeIsolated { session.receive(buffer) }
                }, toMarkerCallback: { markers in
                    MainActor.assumeIsolated { session.receive(markers) }
                })
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SystemSpeechEngineTests`
Expected: 4 tests passed (the two voice-backed tests may take a few seconds). If the voice-backed tests hang, the callbacks are not reaching the main actor: confirm the test is not itself blocking the main thread (they are plain `async` tests, so they must not be marked `@MainActor`). If `marker.byteSampleOffset` proves to be a sample index rather than a byte offset on a real voice, that is a Plan 5 calibration item — record it in the report, do not guess.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SAudio/SystemSpeechEngine.swift Tests/T2SAudioTests/SystemSpeechEngineTests.swift
git commit -m "Add SystemSpeechEngine: AVSpeechSynthesizer fallback engine at the pipeline rate"
```

---

### Task 3: Formatters, container paths, device-state mapping (`T2SApp`)

**Files:**
- Create: `Sources/T2SApp/Formatting/DurationFormatter.swift`, `Sources/T2SApp/Environment/AppPaths.swift`, `Sources/T2SApp/Environment/DeviceStateMapping.swift`
- Create: `Tests/T2SAppTests/DurationFormatterTests.swift`, `Tests/T2SAppTests/AppPathsTests.swift`, `Tests/T2SAppTests/DeviceStateMappingTests.swift`

**Interfaces:**
- Consumes: `DeviceState` (T2SCore), `AudioStoreStats`.
- Produces: `public enum DurationFormatter { long(_:approximate:), remaining(_:approximate:), clock(_:), age(of:now:), items(_:) }`; `public enum AppPaths { containerRoot(under:), defaultContainerRoot(), audioCapacityKey, defaultAudioCapacityBytes, prepareBudgetKey }`; `public struct DeviceSignals { batteryState: BatteryState, thermal: ThermalLevel, lowPowerMode, storeBytes, storeCapacityBytes }`, `public enum BatteryState { unknown, unplugged, charging, full }`, `public enum ThermalLevel { nominal, fair, serious, critical }`, `public enum DeviceStateMapping { storeFullHeadroomBytes; deviceState(_:) -> DeviceState }`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SAppTests/DurationFormatterTests.swift
import Foundation
import Testing
@testable import T2SApp

@Suite struct DurationFormatterTests {
    @Test func longForm() {
        #expect(DurationFormatter.long(0) == "0m")
        #expect(DurationFormatter.long(59) == "1m")                          // rounds up below a minute
        #expect(DurationFormatter.long(42 * 60) == "42m")
        #expect(DurationFormatter.long(6 * 3600 + 20 * 60) == "6h 20m")
        #expect(DurationFormatter.long(2 * 3600) == "2h")
        #expect(DurationFormatter.long(6 * 3600 + 20 * 60, approximate: true) == "~6h 20m")
    }

    @Test func remainingForm() {
        #expect(DurationFormatter.remaining(12 * 60 + 5, approximate: true) == "~12m")
        #expect(DurationFormatter.remaining(3600 + 5 * 60, approximate: false) == "1h 5m")
        #expect(DurationFormatter.remaining(20, approximate: false) == "<1m")
        #expect(DurationFormatter.remaining(20, approximate: true) == "<1m")
    }

    @Test func clockForm() {
        #expect(DurationFormatter.clock(0) == "0:00")
        #expect(DurationFormatter.clock(42) == "0:42")
        #expect(DurationFormatter.clock(12 * 60 + 5) == "12:05")
        #expect(DurationFormatter.clock(3600 + 2 * 60 + 33) == "1:02:33")
        #expect(DurationFormatter.clock(-3) == "0:00")
    }

    @Test func ages() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func age(_ seconds: TimeInterval) -> String { DurationFormatter.age(of: now.addingTimeInterval(-seconds), now: now) }
        #expect(age(30) == "now")
        #expect(age(5 * 60) == "5m")
        #expect(age(3 * 3600) == "3h")
        #expect(age(2 * 86_400) == "2d")
        #expect(age(3 * 7 * 86_400) == "3w")
        #expect(age(120 * 86_400) == "4mo")
        #expect(age(400 * 86_400) == "1y")
        #expect(age(-60) == "now")                                           // clock skew
    }

    @Test func itemCounts() {
        #expect(DurationFormatter.items(0) == "0 items")
        #expect(DurationFormatter.items(1) == "1 item")
        #expect(DurationFormatter.items(14) == "14 items")
    }
}
```

```swift
// Tests/T2SAppTests/AppPathsTests.swift
import Foundation
import Testing
@testable import T2SApp

@Suite struct AppPathsTests {
    @Test func containerRootLivesUnderTheGivenBase() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-app-\(UUID().uuidString)")
        let root = try AppPaths.containerRoot(under: base)
        #expect(root.lastPathComponent == "t2s")
        #expect(root.deletingLastPathComponent().path == base.standardizedFileURL.path)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(try AppPaths.containerRoot(under: base) == root)             // idempotent
    }

    @Test func defaultsAreSensible() {
        #expect(AppPaths.defaultAudioCapacityBytes == 2 * 1024 * 1024 * 1024)
        #expect(AppPaths.audioCapacityKey == "audioCapacityBytes")
        #expect(AppPaths.prepareBudgetKey == "prepareBudgetSeconds")
    }
}
```

```swift
// Tests/T2SAppTests/DeviceStateMappingTests.swift
import Testing
import T2SCore
@testable import T2SApp

@Suite struct DeviceStateMappingTests {
    func signals(battery: BatteryState = .unplugged, thermal: ThermalLevel = .nominal, lowPower: Bool = false,
                 bytes: Int = 0, capacity: Int = 1_000_000_000) -> DeviceSignals {
        DeviceSignals(batteryState: battery, thermal: thermal, lowPowerMode: lowPower, storeBytes: bytes, storeCapacityBytes: capacity)
    }

    @Test func chargingAndFullCountAsCharging() {
        #expect(DeviceStateMapping.deviceState(signals(battery: .charging)).charging)
        #expect(DeviceStateMapping.deviceState(signals(battery: .full)).charging)
        #expect(!DeviceStateMapping.deviceState(signals(battery: .unplugged)).charging)
        #expect(!DeviceStateMapping.deviceState(signals(battery: .unknown)).charging)
    }

    @Test func thermalSeriousAndAbove() {
        #expect(!DeviceStateMapping.deviceState(signals(thermal: .fair)).thermalSerious)
        #expect(DeviceStateMapping.deviceState(signals(thermal: .serious)).thermalSerious)
        #expect(DeviceStateMapping.deviceState(signals(thermal: .critical)).thermalSerious)
    }

    @Test func lowPowerAndStoreHeadroom() {
        #expect(DeviceStateMapping.deviceState(signals(lowPower: true)).lowPowerMode)
        let headroom = DeviceStateMapping.storeFullHeadroomBytes
        #expect(!DeviceStateMapping.deviceState(signals(bytes: 1_000_000_000 - headroom - 1)).storeFull)
        #expect(DeviceStateMapping.deviceState(signals(bytes: 1_000_000_000 - headroom + 1)).storeFull)
        #expect(DeviceStateMapping.deviceState(signals(bytes: 5, capacity: 0)).storeFull)
        #expect(DeviceStateMapping.deviceState(signals()) == DeviceState.unplugged)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "DurationFormatterTests|AppPathsTests|DeviceStateMappingTests"`
Expected: compile errors, types not found.

- [ ] **Step 3: Implement**

```swift
// Sources/T2SApp/Formatting/DurationFormatter.swift
import Foundation

/// The app's time and count strings (spec §2.4.5). Every string is built here so screens agree.
public enum DurationFormatter {
    /// Totals: "6h 20m", "42m", "2h", "0m"; `~` prefix while the total is an estimate (spec §3.3).
    public static func long(_ seconds: TimeInterval, approximate: Bool = false) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.up))
        let h = minutes / 60, m = minutes % 60
        let body: String
        if h == 0 { body = "\(m)m" } else if m == 0 { body = "\(h)h" } else { body = "\(h)h \(m)m" }
        return approximate ? "~" + body : body
    }

    /// Remaining time on a Play pill: "~12m", "1h 5m", "<1m".
    public static func remaining(_ seconds: TimeInterval, approximate: Bool) -> String {
        if seconds < 60 { return "<1m" }
        return long(seconds, approximate: approximate)
    }

    /// Player clock: "0:42", "12:05", "1:02:33".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Added-age in the row meta line: "now", "5m", "3h", "2d", "3w", "4mo", "1y".
    public static func age(of date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        if s < 7 * 86_400 { return "\(Int(s / 86_400))d" }
        if s < 30 * 86_400 { return "\(Int(s / (7 * 86_400)))w" }
        if s < 365 * 86_400 { return "\(Int(s / (30 * 86_400)))mo" }
        return "\(Int(s / (365 * 86_400)))y"
    }

    public static func items(_ count: Int) -> String { count == 1 ? "1 item" : "\(count) items" }
}
```

```swift
// Sources/T2SApp/Environment/AppPaths.swift
import Foundation

/// Where the library lives on the device: `<Application Support>/t2s` (backed up; the audio cache
/// directory inside it is excluded from backup by `AppEnvironment`).
public enum AppPaths {
    public static let audioCapacityKey = "audioCapacityBytes"
    public static let prepareBudgetKey = "prepareBudgetSeconds"
    /// Spec §3.4: the cache cap is user-configurable; 2 GB is roughly 140 hours of 32 kbps AAC.
    public static let defaultAudioCapacityBytes = 2 * 1024 * 1024 * 1024

    /// `base/t2s`, created if needed.
    public static func containerRoot(under base: URL) throws -> URL {
        let root = base.standardizedFileURL.appendingPathComponent("t2s", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// The app's container: `<Application Support>/t2s`.
    public static func defaultContainerRoot() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return try containerRoot(under: support)
    }
}
```

```swift
// Sources/T2SApp/Environment/DeviceStateMapping.swift
import Foundation
import T2SCore

public enum BatteryState: Hashable, Sendable { case unknown, unplugged, charging, full }
public enum ThermalLevel: Hashable, Sendable { case nominal, fair, serious, critical }

/// Raw signals the app target reads from UIKit and ProcessInfo; kept UIKit-free so the mapping is testable.
public struct DeviceSignals: Hashable, Sendable {
    public var batteryState: BatteryState
    public var thermal: ThermalLevel
    public var lowPowerMode: Bool
    public var storeBytes: Int
    public var storeCapacityBytes: Int

    public init(batteryState: BatteryState, thermal: ThermalLevel, lowPowerMode: Bool, storeBytes: Int, storeCapacityBytes: Int) {
        self.batteryState = batteryState
        self.thermal = thermal
        self.lowPowerMode = lowPowerMode
        self.storeBytes = storeBytes
        self.storeCapacityBytes = storeCapacityBytes
    }
}

/// Spec §3.4.1 guards: Prepare stops on unplug, at thermal `.serious` or above, in Low Power Mode,
/// and at the cache cap. "At the cap" means less than one hour of AAC headroom left.
public enum DeviceStateMapping {
    /// 32 kbps × 3600 s ≈ 14 MB; twice that is the headroom Prepare needs to be worth starting.
    public static let storeFullHeadroomBytes = 32 * 1024 * 1024

    public static func deviceState(_ s: DeviceSignals) -> DeviceState {
        DeviceState(charging: s.batteryState == .charging || s.batteryState == .full,
                    thermalSerious: s.thermal == .serious || s.thermal == .critical,
                    lowPowerMode: s.lowPowerMode,
                    storeFull: s.storeCapacityBytes - s.storeBytes < storeFullHeadroomBytes)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "DurationFormatterTests|AppPathsTests|DeviceStateMappingTests"`
Expected: 10 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp Tests/T2SAppTests
git commit -m "T2SApp: duration formatter, container paths, device-state mapping"
```

---
### Task 4: `LibraryModel` and per-document progress (`T2SApp`)

**Files:**
- Create: `Sources/T2SApp/Library/DocumentProgress.swift`, `Sources/T2SApp/Library/LibraryModel.swift`
- Create: `Tests/T2SAppTests/Support/FakeReader.swift`, `Tests/T2SAppTests/Support/AppFixtures.swift`, `Tests/T2SAppTests/DocumentProgressTests.swift`, `Tests/T2SAppTests/LibraryModelTests.swift`

**Interfaces:**
- Consumes: `LibraryStore` (`summaries()`, `setQueued`, `moveInQueue`, `setFinished`), `Library` (`importFile`, `delete`, `timelineForPlayback`), `DocumentSummary`, `Timeline`, `TimeIndex`, `PositionResolver`, `DurationFormatter` (Task 3).
- Produces: `public struct DocumentProgress { elapsedSeconds, totalSeconds, chapterIndex, chapterCount, isApproximate; remainingSeconds; fraction; static func compute(summary:timeline:) }`; `@MainActor @Observable public final class LibraryModel { init(library:); summaries; progress: [UUID: DocumentProgress]; queueView: QueueView; queue; finished; collection; queueSubtitle; isQueueEmpty; lastError; refresh() async; archive(_:) async; enqueue(_:) async; move(_:to:) async; markFinished(_:_:) async; delete(_:) async; progress(for:) }`, `public enum QueueView { queue, finished }`.

- [ ] **Step 1: Test support**

```swift
// Tests/T2SAppTests/Support/FakeReader.swift
import Foundation
import T2SCore
import T2SLibrary

/// Canned chapters for EPUB imports (Readium is iOS-only). Two chapters, three sentences, ~3.3 s estimated.
struct FakeReader: DocumentReader {
    let supportedTypes: Set<SourceType> = [.epub, .article]
    var title = "Fake Book"
    var chapterCount = 2

    func read(fileURL: URL, sourceType: SourceType) async throws -> ReadDocument {
        let chapters = (1...chapterCount).map { n in
            let href = "OEBPS/ch\(n).xhtml"
            let text = n == 1 ? "First sentence. Second sentence." : "Sentence number \(n) here."
            return ChapterInput(title: "Chapter \(n)", position: Position(resourceHref: href, progression: 0, charOffset: 0),
                                blocks: [SourceBlock(text: text, position: Position(resourceHref: href, progression: 0, charOffset: 0))])
        }
        return ReadDocument(title: title, author: "Fake Author", coverImage: nil, chapters: chapters)
    }
}
```

```swift
// Tests/T2SAppTests/Support/AppFixtures.swift
import Foundation
import T2SCore
import T2SLibrary
import T2SStore

struct AppFixtures {
    let paths: LibraryPaths
    let store: LibraryStore
    let audio: InMemoryAudioStore
    let library: Library

    init(readers: [any DocumentReader] = [FakeReader()]) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-app-\(UUID().uuidString)")
        paths = LibraryPaths(root: root)
        store = try LibraryStore.inMemory()
        audio = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 50_000_000)
        library = Library(paths: paths, store: store, audioStore: audio, readers: readers)
    }

    /// Imports a placeholder EPUB through `FakeReader` and returns the new document's id.
    func importFake() async throws -> UUID {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).epub")
        try Data("PK".utf8).write(to: file)
        return try await library.importFile(at: file, sourceType: .epub).document.id
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
// Tests/T2SAppTests/DocumentProgressTests.swift
import Foundation
import Testing
import T2SCore
import T2SStore
@testable import T2SApp

@Suite struct DocumentProgressTests {
    func utterance(_ text: String, href: String, offset: Int, seconds: TimeInterval, rendered: Bool = false) -> Utterance {
        let n = text.utf16.count
        return Utterance(position: Position(resourceHref: href, progression: 0, charOffset: offset), source: text, spoken: text,
                         spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], audioRef: rendered ? "k" : nil,
                         duration: rendered ? .actual(seconds) : .estimated(seconds))
    }

    func timeline(rendered: Bool = false) -> Timeline {
        Timeline(chapters: [
            Chapter(title: "One", position: Position(resourceHref: "a", progression: 0, charOffset: 0), utterances: [
                utterance("Alpha.", href: "a", offset: 0, seconds: 10, rendered: rendered),
                utterance("Beta.", href: "a", offset: 7, seconds: 10, rendered: rendered),
            ]),
            Chapter(title: "Two", position: Position(resourceHref: "b", progression: 0, charOffset: 0), utterances: [
                utterance("Gamma.", href: "b", offset: 0, seconds: 20, rendered: rendered),
            ]),
        ])
    }

    func summary(resume: Position?) -> DocumentSummary {
        DocumentSummary(document: Document(title: "D", sourceType: .epub, resumePosition: resume), chapterCount: 2, utteranceCount: 3,
                        totalSeconds: 40, renderedCount: 0, isFinished: false, queueOrder: 0, lastPlayedAt: nil)
    }

    @Test func freshDocumentStartsAtZero() {
        let p = DocumentProgress.compute(summary: summary(resume: nil), timeline: timeline())
        #expect(p.elapsedSeconds == 0 && p.totalSeconds == 40 && p.remainingSeconds == 40)
        #expect(p.chapterIndex == 0 && p.chapterCount == 2 && p.fraction == 0)
        #expect(p.isApproximate)
    }

    @Test func resumeInsideTheSecondChapter() {
        let p = DocumentProgress.compute(summary: summary(resume: Position(resourceHref: "b", progression: 0, charOffset: 0)),
                                         timeline: timeline(rendered: true))
        #expect(p.elapsedSeconds == 20 && p.remainingSeconds == 20 && p.chapterIndex == 1)
        #expect(p.fraction == 0.5)
        #expect(!p.isApproximate)
    }

    @Test func emptyTimelineIsSafe() {
        let p = DocumentProgress.compute(summary: summary(resume: nil), timeline: Timeline(chapters: []))
        #expect(p.totalSeconds == 0 && p.fraction == 0 && p.chapterIndex == nil && p.chapterCount == 0)
    }
}
```

```swift
// Tests/T2SAppTests/LibraryModelTests.swift
import Foundation
import Testing
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct LibraryModelTests {
    @Test func refreshBuildsQueueAndProgress() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake(), b = try await f.importFake()
        let model = LibraryModel(library: f.library)
        await model.refresh()
        #expect(model.queue.map(\.id) == [a, b])
        #expect(model.finished.isEmpty)
        #expect(model.collection.map(\.id).sorted(by: { $0.uuidString < $1.uuidString }) == [a, b].sorted(by: { $0.uuidString < $1.uuidString }))
        #expect(!model.isQueueEmpty)
        let progress = try #require(model.progress(for: a))
        #expect(progress.chapterCount == 2 && progress.elapsedSeconds == 0 && progress.isApproximate)
        #expect(model.queueSubtitle.hasPrefix("2 items · ~"))
    }

    @Test func archiveEnqueueMoveFinishDelete() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake(), b = try await f.importFake(), c = try await f.importFake()
        let model = LibraryModel(library: f.library)
        await model.refresh()
        await model.archive(a)
        #expect(model.queue.map(\.id) == [b, c])
        await model.enqueue(a)
        #expect(model.queue.map(\.id) == [b, c, a])
        await model.move(a, to: 0)
        #expect(model.queue.map(\.id) == [a, b, c])
        await model.markFinished(b, true)
        #expect(model.queue.map(\.id) == [a, c])
        #expect(model.finished.map(\.id) == [b])
        model.queueView = .finished
        #expect(model.visibleRows.map(\.id) == [b])
        await model.markFinished(b, false)                                  // back to the end of the Queue
        #expect(model.queue.map(\.id) == [a, c, b])
        await model.delete(c)
        #expect(model.queue.map(\.id) == [a, b])
        #expect(try await f.store.document(id: c) == nil)
        #expect(model.lastError == nil)
    }

    @Test func emptyLibraryIsEmptyQueue() async throws {
        let f = try AppFixtures()
        let model = LibraryModel(library: f.library)
        await model.refresh()
        #expect(model.isQueueEmpty && model.queueSubtitle == "0 items")
    }

    @Test func progressFollowsSavedPositions() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake()
        let model = LibraryModel(library: f.library)
        try await f.store.savePosition(Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0), for: a)
        await model.refresh()
        let p = try #require(model.progress(for: a))
        #expect(p.chapterIndex == 1)
        #expect(p.elapsedSeconds > 0 && p.remainingSeconds < p.totalSeconds)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter "DocumentProgressTests|LibraryModelTests"`
Expected: compile errors, types not found.

- [ ] **Step 4: Implement**

```swift
// Sources/T2SApp/Library/DocumentProgress.swift
import Foundation
import T2SCore
import T2SStore

/// What a row needs to say where the listener is: remaining time, chapter n of m (spec §2.4.5).
/// Derived from the persisted `Position` through the timeline (spec §3.2), never stored.
public struct DocumentProgress: Hashable, Sendable {
    public var elapsedSeconds: TimeInterval
    public var totalSeconds: TimeInterval
    public var chapterIndex: Int?
    public var chapterCount: Int
    /// True until every utterance has an actual duration and audio (spec §3.3: totals are `~` until then).
    public var isApproximate: Bool

    public var remainingSeconds: TimeInterval { max(0, totalSeconds - elapsedSeconds) }
    public var fraction: Double { totalSeconds > 0 ? min(1, max(0, elapsedSeconds / totalSeconds)) : 0 }

    public static func compute(summary: DocumentSummary, timeline: Timeline) -> DocumentProgress {
        let index = TimeIndex(timeline)
        guard timeline.utteranceCount > 0 else {
            return DocumentProgress(elapsedSeconds: 0, totalSeconds: 0, chapterIndex: nil,
                                    chapterCount: timeline.chapters.count, isApproximate: !timeline.isFullyRendered)
        }
        let playhead = summary.document.resumePosition.map { PositionResolver.resolve($0, in: timeline) } ?? Playhead(utteranceIndex: 0)
        return DocumentProgress(elapsedSeconds: index.time(at: playhead), totalSeconds: index.totalDuration,
                                chapterIndex: timeline.chapterIndex(forUtterance: playhead.utteranceIndex),
                                chapterCount: timeline.chapters.count, isApproximate: !timeline.isFullyRendered)
    }
}
```

```swift
// Sources/T2SApp/Library/LibraryModel.swift
import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

public enum QueueView: Hashable, Sendable { case queue, finished }

/// The Queue and Collection pages' state (spec §2.3, §2.4.5). Reads summaries from the store and
/// per-document progress through `Library.timelineForPlayback`, which also re-derives a stale
/// timeline on the way (spec §3.7.3), so a version bump costs one refresh, not a migration.
@MainActor
@Observable
public final class LibraryModel {
    public private(set) var summaries: [DocumentSummary] = []
    public private(set) var progress: [UUID: DocumentProgress] = [:]
    public var queueView: QueueView = .queue
    public private(set) var lastError: String?

    private let library: Library

    public init(library: Library) { self.library = library }

    // MARK: Derived lists

    /// Queued, unfinished documents in user order.
    public var queue: [DocumentSummary] {
        summaries.filter { $0.queueOrder != nil && !$0.isFinished }.sorted { ($0.queueOrder ?? 0) < ($1.queueOrder ?? 0) }
    }

    /// Finished documents, most recently played first.
    public var finished: [DocumentSummary] {
        summaries.filter(\.isFinished).sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    /// Every EPUB and PDF, newest first, whatever its queue state (spec §2.3).
    public var collection: [DocumentSummary] {
        summaries.filter { $0.document.sourceType == .epub || $0.document.sourceType == .pdf }
    }

    public var visibleRows: [DocumentSummary] { queueView == .queue ? queue : finished }
    public var isQueueEmpty: Bool { queue.isEmpty }

    /// "14 items · ~6h 20m": remaining time across the Queue, `~` while any of it is an estimate.
    public var queueSubtitle: String {
        let rows = queue
        guard !rows.isEmpty else { return DurationFormatter.items(0) }
        var seconds: TimeInterval = 0
        var approximate = false
        for row in rows {
            if let p = progress[row.id] {
                seconds += p.remainingSeconds
                approximate = approximate || p.isApproximate
            } else {
                seconds += row.totalSeconds
                approximate = approximate || !row.isFullyRendered
            }
        }
        return "\(DurationFormatter.items(rows.count)) · \(DurationFormatter.long(seconds, approximate: approximate))"
    }

    public func progress(for id: UUID) -> DocumentProgress? { progress[id] }

    // MARK: Refresh

    public func refresh() async {
        do {
            let all = try await library.store.summaries()
            var next: [UUID: DocumentProgress] = [:]
            for s in all where s.queueOrder != nil || s.isFinished {
                if let timeline = try await library.timelineForPlayback(s.id) {
                    next[s.id] = DocumentProgress.compute(summary: s, timeline: timeline)
                }
            }
            summaries = all
            progress = next
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    // MARK: Actions (each ends with a refresh so the lists are always the store's truth)

    public func archive(_ id: UUID) async { await perform { try await self.library.store.setQueued(id, false) } }

    public func enqueue(_ id: UUID) async { await perform { try await self.library.store.setQueued(id, true) } }

    public func move(_ id: UUID, to index: Int) async { await perform { try await self.library.store.moveInQueue(id, to: index) } }

    /// Finished leaves the Queue; un-finishing puts the document back at the end (spec §2.4.5 context menu).
    public func markFinished(_ id: UUID, _ finished: Bool) async {
        await perform {
            try await self.library.store.setFinished(id, finished)
            try await self.library.store.setQueued(id, !finished)
        }
    }

    public func delete(_ id: UUID) async { await perform { try await self.library.delete(id) } }

    private func perform(_ action: @escaping @Sendable () async throws -> Void) async {
        do {
            try await action()
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
        await refresh()
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter "DocumentProgressTests|LibraryModelTests"`
Expected: 7 tests passed. If `perform`'s closure fails Sendable checking because it captures `self`, mark the parameter `@MainActor @Sendable () async throws -> Void` — the actions only touch actors.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SApp Tests/T2SAppTests
git commit -m "T2SApp: LibraryModel with queue, finished, collection views and per-document progress"
```

---

### Task 5: `PlayerModel` and `ScrubberModel` (`T2SApp`)

**Files:**
- Create: `Sources/T2SApp/Player/ScrubberModel.swift`, `Sources/T2SApp/Player/PlayerModel.swift`
- Create: `Tests/T2SAppTests/ScrubberModelTests.swift`, `Tests/T2SAppTests/PlayerModelTests.swift`

**Interfaces:**
- Consumes: `PlaybackCoordinator` (T2SAudio), `Library`, `LibraryStore.saveChapter`, `TimeIndex`, `Timeline`, `Playhead`, `DurationFormatter`, `DocumentSummary`.
- Produces: `public struct ScrubberModel { tickCount; renderedTicks: [Bool]; fraction; static func make(timeline:timeIndex:playhead:tickCount:) }`; `@MainActor @Observable public final class PlayerModel { init(coordinator:library:); current: DocumentSummary?; state; isPlaying; elapsed; total; isTotalApproximate; elapsedText; remainingText; totalText; chapters: [ChapterEntry]; chapterIndex; scrubber; isCatchingUp; renderError; load(_:play:) async; togglePlay() async; skip(by:) async; seek(fraction:) async; seek(toChapter:) async; setRate(_:); renderWholeDocument(); tick(); persistRenderedChapters() async }`, `public struct ChapterEntry { index, title, startSeconds, durationSeconds, fraction }`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SAppTests/ScrubberModelTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SApp

@Suite struct ScrubberModelTests {
    func timeline(rendered: Int) -> Timeline {
        var utterances: [Utterance] = []
        for i in 0..<4 {
            let text = "Utterance \(i)."
            let n = text.utf16.count
            utterances.append(Utterance(position: Position(resourceHref: "a", progression: 0, charOffset: i * 20), source: text, spoken: text,
                                        spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], audioRef: i < rendered ? "k\(i)" : nil,
                                        duration: i < rendered ? .actual(10) : .estimated(10)))
        }
        return Timeline(chapters: [Chapter(title: "1", position: utterances[0].position, utterances: utterances)])
    }

    @Test func ticksFollowTheRenderFrontier() {
        let t = timeline(rendered: 2)                                        // 40 s, first 20 s rendered
        let m = ScrubberModel.make(timeline: t, timeIndex: TimeIndex(t), playhead: Playhead(utteranceIndex: 1, offset: 5), tickCount: 8)
        #expect(m.tickCount == 8)
        #expect(m.renderedTicks == [true, true, true, true, false, false, false, false])
        #expect(abs(m.fraction - 15.0 / 40.0) < 1e-9)
    }

    @Test func partiallyRenderedTickIsNotRendered() {
        let t = timeline(rendered: 1)                                        // 10 s of 40 rendered; 8 ticks of 5 s
        let m = ScrubberModel.make(timeline: t, timeIndex: TimeIndex(t), playhead: Playhead(utteranceIndex: 0), tickCount: 8)
        #expect(m.renderedTicks == [true, true, false, false, false, false, false, false])
        let m3 = ScrubberModel.make(timeline: t, timeIndex: TimeIndex(t), playhead: Playhead(utteranceIndex: 0), tickCount: 3)
        #expect(m3.renderedTicks == [false, false, false])                  // a 13.3 s tick spans an unrendered utterance
    }

    @Test func emptyTimeline() {
        let t = Timeline(chapters: [])
        let m = ScrubberModel.make(timeline: t, timeIndex: TimeIndex(t), playhead: Playhead(utteranceIndex: 0), tickCount: 5)
        #expect(m.renderedTicks == Array(repeating: false, count: 5) && m.fraction == 0)
    }
}
```

```swift
// Tests/T2SAppTests/PlayerModelTests.swift
import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct PlayerModelTests {
    func makePlayer(_ f: AppFixtures) throws -> PlayerModel {
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        return PlayerModel(coordinator: coordinator, library: f.library)
    }

    @Test func loadExposesTimesChaptersAndScrubber() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let player = try makePlayer(f)
        await player.load(summary, play: false)
        #expect(player.current?.id == id)
        #expect(player.state == .paused)
        #expect(player.elapsed == 0 && player.total > 2)
        #expect(player.elapsedText == "0:00")
        #expect(player.totalText.hasPrefix("~"))                            // estimates until rendered
        #expect(player.chapters.map(\.title) == ["Chapter 1", "Chapter 2"])
        #expect(player.chapterIndex == 0)
        #expect(player.scrubber.tickCount == 48 && player.scrubber.fraction == 0)
        #expect(player.chapters[1].startSeconds > 0)
    }

    @Test func transportAndSeeks() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let player = try makePlayer(f)
        await player.load(summary, play: true)
        #expect(player.isPlaying)
        await player.togglePlay()
        #expect(player.state == .paused)
        await player.seek(toChapter: 1)
        #expect(player.chapterIndex == 1)
        #expect(player.elapsed == player.chapters[1].startSeconds)
        await player.seek(fraction: 0)
        #expect(player.elapsed == 0 && player.chapterIndex == 0)
        await player.skip(by: 1)
        #expect(abs(player.elapsed - 1) < 1e-6)
        await player.skip(by: -30)
        #expect(player.elapsed == 0)
        await player.skip(by: 10_000)
        #expect(player.state == .finished)
        player.setRate(1.5)
        #expect(player.coordinator.rate == 1.5)
    }

    @Test func persistsRenderedChapters() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let player = try makePlayer(f)
        await player.load(summary, play: false)
        await player.coordinator.waitForRenderIdle()                        // 60 s window covers the whole fake book
        #expect(player.coordinator.timeline?.isFullyRendered == true)
        #expect(!player.isTotalApproximate)
        await player.persistRenderedChapters()
        let stored = try #require(try await f.store.timeline(for: id)).timeline
        #expect(stored.isFullyRendered)
        #expect(try await f.store.summary(id: id)?.isFullyRendered == true)
        await player.persistRenderedChapters()                              // no change: no extra writes (unobservable here; must not throw)
        #expect(player.renderError == nil)
    }

    @Test func loadingAnotherDocumentPersistsTheFirst() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake(), b = try await f.importFake()
        let player = try makePlayer(f)
        await player.load(try #require(try await f.store.summary(id: a)), play: false)
        await player.coordinator.waitForRenderIdle()
        await player.load(try #require(try await f.store.summary(id: b)), play: false)
        #expect(try await f.store.summary(id: a)?.isFullyRendered == true)
        #expect(player.current?.id == b)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "ScrubberModelTests|PlayerModelTests"`
Expected: compile errors, types not found.

- [ ] **Step 3: Implement**

```swift
// Sources/T2SApp/Player/ScrubberModel.swift
import Foundation
import T2SCore

/// The tick scrubber (spec §2.4.5): uniform ticks, rendered ones in `ink`, unrendered in `ink3`, so
/// the render frontier (spec §3.3) is visible without a legend. A tick counts as rendered only when
/// every utterance overlapping its span has audio.
public struct ScrubberModel: Hashable, Sendable {
    public var tickCount: Int
    public var renderedTicks: [Bool]
    /// Playhead position 0…1 along the total (estimated) duration.
    public var fraction: Double

    public init(tickCount: Int, renderedTicks: [Bool], fraction: Double) {
        self.tickCount = tickCount
        self.renderedTicks = renderedTicks
        self.fraction = fraction
    }

    public static func make(timeline: Timeline, timeIndex: TimeIndex, playhead: Playhead, tickCount: Int = 48) -> ScrubberModel {
        let total = timeIndex.totalDuration
        guard tickCount > 0, total > 0, timeline.utteranceCount > 0 else {
            return ScrubberModel(tickCount: tickCount, renderedTicks: Array(repeating: false, count: max(0, tickCount)), fraction: 0)
        }
        var rendered: [Bool] = []
        rendered.reserveCapacity(tickCount)
        for i in 0..<tickCount {
            let start = total * Double(i) / Double(tickCount)
            let end = total * Double(i + 1) / Double(tickCount)
            let first = timeIndex.playhead(atTime: start).utteranceIndex
            // The utterance containing `end` (exclusive): step back from the boundary by a hair.
            let last = timeIndex.playhead(atTime: max(start, end - 1e-9)).utteranceIndex
            var ok = true
            for u in first...max(first, last) where timeline[utterance: u].audioRef == nil { ok = false; break }
            rendered.append(ok)
        }
        let fraction = min(1, max(0, timeIndex.time(at: playhead) / total))
        return ScrubberModel(tickCount: tickCount, renderedTicks: rendered, fraction: fraction)
    }
}
```

```swift
// Sources/T2SApp/Player/PlayerModel.swift
import Foundation
import Observation
import T2SAudio
import T2SCore
import T2SLibrary
import T2SStore

public struct ChapterEntry: Hashable, Sendable, Identifiable {
    public var index: Int
    public var title: String
    public var startSeconds: TimeInterval
    public var durationSeconds: TimeInterval
    /// How far the playhead is through this chapter, 0…1.
    public var fraction: Double
    public var id: Int { index }
}

/// The UI's one view of playback (spec §3): a thin, observable bridge over `PlaybackCoordinator`
/// plus the strings and derived shapes the player sheet and mini-player draw. It also owns the one
/// piece of persistence the coordinator does not: writing rendered chapters (actual durations, word
/// timings, audio refs) back to the store, on pause, on switching documents, and on demand.
@MainActor
@Observable
public final class PlayerModel {
    public let coordinator: PlaybackCoordinator
    public private(set) var current: DocumentSummary?
    public private(set) var renderError: String?

    private let library: Library
    /// Hash of each chapter as last written, to skip unchanged chapters on the next persist.
    private var persistedChapterHashes: [Int] = []

    public init(coordinator: PlaybackCoordinator, library: Library) {
        self.coordinator = coordinator
        self.library = library
    }

    // MARK: Derived state

    public var state: PlaybackState { coordinator.state }
    public var isPlaying: Bool { state == .playing || state == .catchingUp }
    public var isCatchingUp: Bool { state == .catchingUp }
    public var elapsed: TimeInterval { coordinator.timeIndex.time(at: coordinator.playhead) }
    public var total: TimeInterval { coordinator.timeIndex.totalDuration }
    public var isTotalApproximate: Bool { !(coordinator.timeline?.isFullyRendered ?? false) }
    public var elapsedText: String { DurationFormatter.clock(elapsed) }
    public var remainingText: String { DurationFormatter.remaining(total - elapsed, approximate: isTotalApproximate) }
    public var totalText: String { (isTotalApproximate ? "~" : "") + DurationFormatter.clock(total) }
    public var chapterIndex: Int? { coordinator.timeline?.chapterIndex(forUtterance: coordinator.playhead.utteranceIndex) }

    public var chapters: [ChapterEntry] {
        guard let timeline = coordinator.timeline else { return [] }
        let index = coordinator.timeIndex
        let now = elapsed
        return timeline.chapters.indices.map { c in
            let range = timeline.utteranceRange(ofChapter: c)
            let start = index.startTime(ofUtterance: range.lowerBound)
            let end = index.startTime(ofUtterance: range.upperBound)
            let duration = end - start
            let fraction = duration > 0 ? min(1, max(0, (now - start) / duration)) : 0
            return ChapterEntry(index: c, title: timeline.chapters[c].title, startSeconds: start, durationSeconds: duration, fraction: fraction)
        }
    }

    public var scrubber: ScrubberModel {
        guard let timeline = coordinator.timeline else { return ScrubberModel(tickCount: 48, renderedTicks: Array(repeating: false, count: 48), fraction: 0) }
        return ScrubberModel.make(timeline: timeline, timeIndex: coordinator.timeIndex, playhead: coordinator.playhead)
    }

    // MARK: Loading

    /// Loads a document (re-deriving a stale timeline on the way) and optionally starts playing.
    /// Whatever was loaded before is persisted first.
    public func load(_ summary: DocumentSummary, play: Bool) async {
        await persistRenderedChapters()
        do {
            guard let timeline = try await library.timelineForPlayback(summary.id) else {
                renderError = "Document is missing"
                return
            }
            coordinator.load(summary.document, timeline: timeline)
            current = summary
            persistedChapterHashes = timeline.chapters.map(\.hashValue)
            renderError = nil
            if play { await coordinator.play() }
        } catch {
            renderError = "\(error)"
        }
    }

    // MARK: Transport

    public func togglePlay() async {
        if isPlaying {
            coordinator.pause()
            await persistRenderedChapters()
        } else {
            await coordinator.play()
        }
    }

    public func skip(by seconds: TimeInterval) async { await coordinator.seek(toTime: elapsed + seconds) }

    public func seek(fraction: Double) async { await coordinator.seek(toTime: total * min(1, max(0, fraction))) }

    public func seek(toChapter c: Int) async {
        guard let timeline = coordinator.timeline, timeline.chapters.indices.contains(c) else { return }
        await coordinator.seek(to: Playhead(utteranceIndex: timeline.utteranceRange(ofChapter: c).lowerBound))
    }

    public func setRate(_ rate: Double) { coordinator.setRate(rate) }

    public func renderWholeDocument() { coordinator.renderWholeDocument() }

    /// Drive from a 10 Hz timer while playing (spec §3: the coordinator polls the player clock).
    public func tick() {
        coordinator.tick()
        if let error = coordinator.lastRenderError { renderError = error }
    }

    // MARK: Persistence of phase 2

    /// Writes chapters whose utterances changed since the last write (actual durations, word
    /// timings, audio refs from `.rendered` events). Cheap when nothing changed.
    public func persistRenderedChapters() async {
        guard let current, let timeline = coordinator.timeline else { return }
        for (c, chapter) in timeline.chapters.enumerated() {
            let hash = chapter.hashValue
            if c < persistedChapterHashes.count, persistedChapterHashes[c] == hash { continue }
            do {
                try await library.store.saveChapter(chapter, at: c, of: current.id)
                if c < persistedChapterHashes.count { persistedChapterHashes[c] = hash } else { persistedChapterHashes.append(hash) }
            } catch {
                renderError = "\(error)"
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "ScrubberModelTests|PlayerModelTests"`
Expected: 7 tests passed. `AudioPlayer(manualRendering: true)` runs without audio hardware; `waitForRenderIdle()` returns once the fake engine has rendered the whole three-sentence book. If `skip(by: 10_000)` does not end in `.finished`, check the coordinator's `seek(toTime:)` contract (Plan 2: a seek past the end marks the document finished) before touching the model.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp Tests/T2SAppTests
git commit -m "T2SApp: PlayerModel bridge over the coordinator, chapter entries, tick scrubber model"
```

---
### Task 6: Design system, composition root, and the root pager (app target)

**Files:**
- Create: `App/T2SReader/Design/Tokens.swift`, `Design/Typography.swift`, `Design/Spacing.swift`, `Design/Primitives.swift`
- Create: `App/T2SReader/AppEnvironment.swift`
- Create: `App/T2SReader/Root/RootPager.swift`, `Root/PageIndicator.swift`, `Root/MiniPlayer.swift`, `App/T2SReader/System/PlaybackTicker.swift`
- Create: `App/T2SReader/Queue/QueuePage.swift`, `App/T2SReader/Collection/CollectionPage.swift`, `App/T2SReader/Preferences/PreferencesPage.swift` (page titles only; Tasks 7–8 fill Queue and Collection)
- Modify: `App/T2SReader/T2SReaderApp.swift`; Delete: `App/T2SReader/RootView.swift`

**Interfaces:**
- Consumes: `LibraryModel`, `PlayerModel`, `AppPaths`, `DurationFormatter` (T2SApp); `LibraryStore.onDisk`, `FileAudioStore`, `AACCodec`, `AudioPlayer`, `SystemSpeechEngine`, `PlaybackCoordinator`, `SystemTimeSource`, `Library`, `LibraryPaths`, `PDFDocumentReader`, `ReadiumDocumentReader`.
- Produces: `enum Tokens` (all ten colors), `enum TypeRole` + `View.typeRole(_:)`, `enum Spacing`, primitives `Pill`, `PageTitle`, `Artwork`, `ProgressBar`, `PositiveCheck`; `@MainActor @Observable final class AppEnvironment { paths, store, audioStore, library, coordinator, libraryModel, player; static func live() throws }`; `RootPager`, `RootPage`, `PageIndicator`, `MiniPlayer`, `View.playbackTicking(_:)`.

No unit tests: every rule here is layout, verified by `scripts/build-app.sh` and by the reviewer against spec §2.4. Models are tested in Tasks 3–5.

- [ ] **Step 1: Tokens, typography, spacing**

```swift
// App/T2SReader/Design/Tokens.swift
import SwiftUI
import UIKit

/// Spec §2.4.2: semantic tokens only; views never name a literal color. Light / dark resolve
/// through a dynamic UIColor so the whole app follows the system or the user's theme.
enum Tokens {
    static let ground = dynamic(light: 0xF8F8F7, dark: 0x101010)
    static let surface = dynamic(light: 0xEEEEEC, dark: 0x1E1E1E)
    static let raised = dynamic(light: 0xFFFFFF, dark: 0x1A1A1A)
    static let ink = dynamic(light: 0x111111, dark: 0xF2F2F2)
    static let ink2 = dynamic(light: 0x8A8A8A, dark: 0x8E8E8E)
    static let ink3 = dynamic(light: 0xC9C9C7, dark: 0x3A3A3A)
    static let accent = dynamic(light: 0xFF7A1A, dark: 0xFF8C3A)
    static let accentSoft = dynamic(light: 0xFF7A1A, dark: 0xFF8C3A, lightAlpha: 0.18, darkAlpha: 0.22)
    static let positive = dynamic(light: 0x22A559, dark: 0x34C070)
    static let destructive = dynamic(light: 0xE5453B, dark: 0xFF5A50)

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return UIColor(rgb: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
```

```swift
// App/T2SReader/Design/Typography.swift
import SwiftUI

/// Spec §2.4.1 type roles: Inter with tight tracking on display and label text, normal tracking on
/// meta, monospaced digits for anything that counts. Sizes are Dynamic Type relative.
enum TypeRole {
    case pageTitle, playerTitle, sectionHeader, rowTitle, pill, meta, mono

    var font: Font {
        switch self {
        case .pageTitle: return .custom("InterDisplay-Black", size: 34, relativeTo: .largeTitle)
        case .playerTitle: return .custom("InterDisplay-ExtraBold", size: 26, relativeTo: .title)
        case .sectionHeader: return .custom("Inter-SemiBold", size: 17, relativeTo: .headline)
        case .rowTitle: return .custom("Inter-Medium", size: 17, relativeTo: .body)
        case .pill: return .custom("Inter-Medium", size: 15, relativeTo: .subheadline)
        case .meta: return .custom("Inter-Regular", size: 13, relativeTo: .footnote)
        case .mono: return .system(.footnote, design: .monospaced)
        }
    }

    /// Tracking in points at the role's base size (em × size).
    var tracking: CGFloat {
        switch self {
        case .pageTitle: return -0.03 * 34
        case .playerTitle: return -0.025 * 26
        case .sectionHeader, .rowTitle: return -0.01 * 17
        case .pill: return -0.01 * 15
        case .meta, .mono: return 0
        }
    }

    var lineLimit: Int? {
        switch self {
        case .playerTitle: return 4
        case .rowTitle: return 2
        default: return nil
        }
    }
}

extension View {
    func typeRole(_ role: TypeRole) -> some View {
        font(role.font).tracking(role.tracking).lineLimit(role.lineLimit)
    }
}
```

```swift
// App/T2SReader/Design/Spacing.swift
import CoreGraphics

/// Spec §2.4.3. Rhythm comes from white space and type weight, never from cards or dividers.
enum Spacing {
    static let grid: CGFloat = 8
    static let margin: CGFloat = 24
    static let row: CGFloat = 28
    static let section: CGFloat = 40
    static let titleTop: CGFloat = 56
    static let sheetCorner: CGFloat = 28
    static let artworkSmall: CGFloat = 8
    static let artworkLarge: CGFloat = 16
}
```

- [ ] **Step 2: Primitives**

```swift
// App/T2SReader/Design/Primitives.swift
import SwiftUI
import T2SLibrary

/// Fully rounded pill (spec §2.4.3). `.accent` is the one primary action per screen; `.selected`
/// is solid `ink` with `ground` text (chips); `.soft` and `.destructiveSoft` sit on `surface`.
struct Pill: View {
    enum Style { case soft, selected, accent, destructiveSoft }

    var label: String
    var glyph: String? = nil
    var style: Style = .soft
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let glyph { Image(systemName: glyph).font(.system(size: 13, weight: .semibold)) }
                Text(label).typeRole(.pill)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .soft: return Tokens.ink
        case .selected: return Tokens.ground
        case .accent: return .white
        case .destructiveSoft: return Tokens.destructive
        }
    }

    private var background: Color {
        switch style {
        case .soft: return Tokens.surface
        case .selected: return Tokens.ink
        case .accent: return Tokens.accent
        case .destructiveSoft: return Tokens.surface
        }
    }
}

/// Page title 56pt below the safe-area top, with an optional dropdown menu (spec §2.4.4).
struct PageTitle<Menu: View>: View {
    var text: String
    var subtitle: String? = nil
    @ViewBuilder var menu: () -> Menu

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(text).typeRole(.pageTitle).foregroundStyle(Tokens.ink)
                menu()
            }
            if let subtitle {
                Text(subtitle).typeRole(.meta).foregroundStyle(Tokens.ink2)
            }
        }
        .padding(.top, Spacing.titleTop)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PageTitle where Menu == EmptyView {
    init(text: String, subtitle: String? = nil) {
        self.init(text: text, subtitle: subtitle, menu: { EmptyView() })
    }
}

/// Cover artwork from a container-relative path; a `surface` block when there is none.
struct Artwork: View {
    var relativePath: String?
    var paths: LibraryPaths
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        Group {
            if let relativePath, let image = UIImage(contentsOfFile: paths.url(forRelativePath: relativePath).path) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Tokens.surface
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Thin progress line under covers and chapter rows.
struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.ink3)
                Capsule().fill(Tokens.ink).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 2)
    }
}

/// The `positive` check that means "ready": plays with no synthesis and no network (spec §3.4.1).
struct PositiveCheck: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(Tokens.positive)
            .accessibilityLabel("Ready to play offline")
    }
}
```

- [ ] **Step 3: Composition root**

```swift
// App/T2SReader/AppEnvironment.swift
import Foundation
import Observation
import T2SApp
import T2SAudio
import T2SCore
import T2SLibrary
import T2SReadium
import T2SStore

/// Builds the object graph once (spec §3): store → library → coordinator → models. Rendered audio
/// is cache, so its directory is excluded from backup (spec §3.7.3).
@MainActor
@Observable
final class AppEnvironment {
    let paths: LibraryPaths
    let store: LibraryStore
    let audioStore: FileAudioStore
    let library: Library
    let coordinator: PlaybackCoordinator
    let libraryModel: LibraryModel
    let player: PlayerModel

    init(paths: LibraryPaths, store: LibraryStore, audioStore: FileAudioStore, library: Library, coordinator: PlaybackCoordinator) {
        self.paths = paths
        self.store = store
        self.audioStore = audioStore
        self.library = library
        self.coordinator = coordinator
        libraryModel = LibraryModel(library: library)
        player = PlayerModel(coordinator: coordinator, library: library)
    }

    static func live() throws -> AppEnvironment {
        let paths = LibraryPaths(root: try AppPaths.defaultContainerRoot())
        try FileManager.default.createDirectory(at: paths.audioDirectory, withIntermediateDirectories: true)
        var audioDirectory = paths.audioDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try audioDirectory.setResourceValues(values)

        let store = try LibraryStore.onDisk(at: paths.databaseURL)
        let capacity = UserDefaults.standard.object(forKey: AppPaths.audioCapacityKey) as? Int ?? AppPaths.defaultAudioCapacityBytes
        let audioStore = FileAudioStore(directory: paths.audioDirectory, codec: AACCodec(), capacityBytes: capacity)
        let library = Library(paths: paths, store: store, audioStore: audioStore,
                              readers: [PDFDocumentReader(), ReadiumDocumentReader()])
        let coordinator = PlaybackCoordinator(engine: SystemSpeechEngine(), store: audioStore, player: try AudioPlayer(),
                                              playheadStore: store, timeSource: SystemTimeSource())
        return AppEnvironment(paths: paths, store: store, audioStore: audioStore, library: library, coordinator: coordinator)
    }
}
```

```swift
// App/T2SReader/T2SReaderApp.swift
import SwiftUI

@main
struct T2SReaderApp: App {
    @State private var environment: AppEnvironment? = {
        do { return try AppEnvironment.live() } catch { return nil }
    }()

    var body: some Scene {
        WindowGroup {
            if let environment {
                RootPager()
                    .environment(environment)
            } else {
                Text("The library could not be opened.")
                    .typeRole(.rowTitle)
                    .foregroundStyle(Tokens.destructive)
                    .padding(Spacing.margin)
            }
        }
    }
}
```

- [ ] **Step 4: Root pager, indicator, mini-player, ticker, page placeholders**

```swift
// App/T2SReader/Root/RootPager.swift
import SwiftUI

enum RootPage: Hashable, CaseIterable {
    case collection, queue, preferences

    var glyph: String {
        switch self {
        case .collection: return "books.vertical"
        case .queue: return "list.bullet"
        case .preferences: return "gearshape"
        }
    }

    var title: String {
        switch self {
        case .collection: return "Collection"
        case .queue: return "Queue"
        case .preferences: return "Preferences"
        }
    }
}

/// Spec §2.4.4: no tab bar; a three-page pager opening on Queue, a tappable three-glyph indicator,
/// and the floating mini-player above it on every page.
struct RootPager: View {
    @Environment(AppEnvironment.self) private var env
    @State private var page: RootPage = .queue
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                CollectionPage().tag(RootPage.collection)
                QueuePage().tag(RootPage.queue)
                PreferencesPage().tag(RootPage.preferences)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                if !env.libraryModel.isQueueEmpty || env.player.current != nil {
                    MiniPlayer { showPlayer = true }
                }
                PageIndicator(page: $page)
            }
            .padding(.bottom, Spacing.grid)
        }
        .background(Tokens.ground.ignoresSafeArea())
        .sheet(isPresented: $showPlayer) {
            PlayerSheet()
                .presentationCornerRadius(Spacing.sheetCorner)
                .presentationBackground(Tokens.raised)
        }
        .playbackTicking(env.player)
        .task { await env.libraryModel.refresh() }
    }
}
```

```swift
// App/T2SReader/Root/PageIndicator.swift
import SwiftUI

struct PageIndicator: View {
    @Binding var page: RootPage

    var body: some View {
        HStack(spacing: 28) {
            ForEach(RootPage.allCases, id: \.self) { p in
                Button {
                    withAnimation(.snappy) { page = p }
                } label: {
                    Image(systemName: p.glyph)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(p == page ? Tokens.ink : Tokens.ink3)
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.title)
                .accessibilityAddTraits(p == page ? .isSelected : [])
            }
        }
    }
}
```

```swift
// App/T2SReader/Root/MiniPlayer.swift
import SwiftUI
import T2SStore

/// Spec §2.4.4: artwork, title, play/pause, skip-forward. Shows the playing item, or the next
/// queued item with "Play" when idle. Tap expands to the player sheet.
struct MiniPlayer: View {
    @Environment(AppEnvironment.self) private var env
    var onExpand: () -> Void

    private var shown: DocumentSummary? { env.player.current ?? env.libraryModel.queue.first }

    var body: some View {
        if let shown {
            HStack(spacing: 12) {
                Artwork(relativePath: shown.document.coverImagePath, paths: env.paths, size: 36, radius: Spacing.artworkSmall)
                Text(shown.document.title)
                    .typeRole(.rowTitle)
                    .lineLimit(1)
                    .foregroundStyle(Tokens.ink)
                Spacer(minLength: 8)
                Button {
                    Task { await togglePlay(shown) }
                } label: {
                    Image(systemName: env.player.current?.id == shown.id && env.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(env.player.isPlaying ? "Pause" : "Play")
                Button {
                    Task { await env.player.skip(by: 30) }
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(env.player.current == nil)
                .accessibilityLabel("Skip forward 30 seconds")
            }
            .foregroundStyle(Tokens.ink)
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Tokens.raised, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .padding(.horizontal, Spacing.margin)
            .contentShape(Capsule())
            .onTapGesture(perform: onExpand)
        }
    }

    private func togglePlay(_ shown: DocumentSummary) async {
        if env.player.current?.id == shown.id {
            await env.player.togglePlay()
        } else {
            await env.player.load(shown, play: true)
        }
    }
}
```

```swift
// App/T2SReader/System/PlaybackTicker.swift
import SwiftUI
import T2SApp

/// Spec §3: the coordinator polls the player clock. One 10 Hz loop for the whole app, alive while
/// the root view is; it only calls `tick()` while something is playing.
private struct PlaybackTicking: ViewModifier {
    let player: PlayerModel

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                if player.isPlaying { player.tick() }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

extension View {
    func playbackTicking(_ player: PlayerModel) -> some View { modifier(PlaybackTicking(player: player)) }
}
```

```swift
// App/T2SReader/Queue/QueuePage.swift  (placeholder; Task 7 replaces it)
import SwiftUI

struct QueuePage: View {
    var body: some View {
        VStack { PageTitle(text: "Queue"); Spacer() }
            .padding(.horizontal, Spacing.margin)
            .background(Tokens.ground)
    }
}
```

```swift
// App/T2SReader/Collection/CollectionPage.swift  (placeholder; Task 8 replaces it)
import SwiftUI

struct CollectionPage: View {
    var body: some View {
        VStack { PageTitle(text: "Collection"); Spacer() }
            .padding(.horizontal, Spacing.margin)
            .background(Tokens.ground)
    }
}
```

```swift
// App/T2SReader/Preferences/PreferencesPage.swift  (content arrives in Plan 4b)
import SwiftUI

struct PreferencesPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            PageTitle(text: "Preferences")
            Text("Voice, playback, reading, pronunciation, and storage settings arrive with the Reader.")
                .typeRole(.meta)
                .foregroundStyle(Tokens.ink2)
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .background(Tokens.ground)
    }
}
```

`PlayerSheet` does not exist until Task 9; for this task add a one-line placeholder file `App/T2SReader/Player/PlayerSheet.swift` containing `import SwiftUI` and `struct PlayerSheet: View { var body: some View { Text("Player").typeRole(.rowTitle).padding(Spacing.margin) } }`, which Task 9 replaces.

- [ ] **Step 5: Build and commit**

Run: `scripts/build-app.sh`
Expected: `** BUILD SUCCEEDED **`, no warnings from `App/`. Common Swift 6 pitfalls here: `AppEnvironment.live()` is called from a `@State` initializer on the main actor (fine, `@MainActor` class); `UIColor { traits in … }` closures are synchronous; `Task { await … }` inside button actions captures `@MainActor` models legally.

```bash
git add App
git commit -m "App: design tokens and type roles, primitives, composition root, root pager with mini-player"
```

---
### Task 7: Queue page (app target)

**Files:**
- Replace: `App/T2SReader/Queue/QueuePage.swift`
- Create: `App/T2SReader/Queue/QueueRow.swift`, `App/T2SReader/Queue/EmptyQueue.swift`, `App/T2SReader/Queue/DetailsSheet.swift`, `App/T2SReader/Import/AddSheet.swift` (placeholder; Task 11 replaces it)

**Interfaces:**
- Consumes: `LibraryModel` (`visibleRows`, `queueView`, `queueSubtitle`, `progress(for:)`, `archive`, `enqueue`, `move`, `markFinished`, `delete`), `PlayerModel` (`current`, `isPlaying`, `load(_:play:)`, `togglePlay`, `renderWholeDocument`), `DocumentSummary`, `DocumentProgress`, `DurationFormatter`, primitives from Task 6.
- Produces: `QueuePage`, `QueueRow`, `EmptyQueue`, `DetailsSheet`, placeholder `AddSheet`.

Spec §2.4.5, Queue page: title with dropdown (Queue / Finished), a `+` and a "Search" pill top-right, subtitle `14 items · ~6h 20m`; rows with meta line (16pt source mark, source name, added-age, `positive` check when fully rendered), title, pill row (`▶ Play ~12m` / `❚❚ Pause`, archive, overflow); swipe → Archive; books show `Chapter 4 of 12`; empty state: title, grey paragraph about the share sheet, an "Import" pill. Tap the title → Reader page (Plan 4b; in this plan the player sheet opens instead — note in the code). Tap Play → plays in place. Context menu: Archive (`destructive`), Mark as finished (`positive`), Details, Render whole document (Sleep timer and Change voice arrive in Plans 4b/5).

- [ ] **Step 1: Rows and empty state**

```swift
// App/T2SReader/Queue/QueueRow.swift
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// One Queue row (spec §2.4.5). No card, no divider: the 28pt row gap is the rhythm.
struct QueueRow: View {
    @Environment(AppEnvironment.self) private var env
    var summary: DocumentSummary
    var onOpen: () -> Void
    var onDetails: () -> Void

    private var progress: DocumentProgress? { env.libraryModel.progress(for: summary.id) }
    private var isCurrent: Bool { env.player.current?.id == summary.id }
    private var isPlayingHere: Bool { isCurrent && env.player.isPlaying }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: sourceMark).font(.system(size: 16, weight: .medium))
                Text(sourceName)
                Text("·")
                Text(DurationFormatter.age(of: summary.document.addedAt))
                if let progress, summary.document.sourceType != .article, progress.chapterCount > 1, let c = progress.chapterIndex {
                    Text("·")
                    Text("Chapter \(c + 1) of \(progress.chapterCount)")
                }
                if summary.isFullyRendered { PositiveCheck() }
            }
            .typeRole(.meta)
            .foregroundStyle(Tokens.ink2)

            Button(action: onOpen) {
                Text(summary.document.title)
                    .typeRole(.rowTitle)
                    .foregroundStyle(Tokens.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Pill(label: isPlayingHere ? "Pause" : "Play \(remainingText)",
                     glyph: isPlayingHere ? "pause.fill" : "play.fill",
                     style: .soft) {
                    Task {
                        if isCurrent { await env.player.togglePlay() } else { await env.player.load(summary, play: true) }
                    }
                }
                Pill(label: "Archive", glyph: "archivebox", style: .soft) {
                    Task { await env.libraryModel.archive(summary.id) }
                }
                Menu {
                    contextItems
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.ink)
                        .frame(width: 36, height: 36)
                        .background(Tokens.surface, in: Circle())
                }
                .accessibilityLabel("More")
            }
        }
        .contextMenu { contextItems }
    }

    @ViewBuilder private var contextItems: some View {
        Button(role: .destructive) { Task { await env.libraryModel.archive(summary.id) } } label: { Label("Archive", systemImage: "archivebox") }
        Button { Task { await env.libraryModel.markFinished(summary.id, !summary.isFinished) } } label: {
            Label(summary.isFinished ? "Mark as unfinished" : "Mark as finished", systemImage: "checkmark.circle")
        }
        Button { Task { await env.libraryModel.move(summary.id, to: 0) } } label: { Label("Move to top", systemImage: "arrow.up.to.line") }
        Button(action: onDetails) { Label("Details", systemImage: "info.circle") }
        Button {
            Task {
                if !isCurrent { await env.player.load(summary, play: false) }
                env.player.renderWholeDocument()
            }
        } label: { Label("Render whole document", systemImage: "waveform") }
    }

    private var remainingText: String {
        if let progress { return DurationFormatter.remaining(progress.remainingSeconds, approximate: progress.isApproximate) }
        return DurationFormatter.remaining(summary.totalSeconds, approximate: !summary.isFullyRendered)
    }

    private var sourceMark: String {
        switch summary.document.sourceType {
        case .epub: return "book.closed"
        case .pdf: return "doc.text"
        case .article: return "globe"
        }
    }

    private var sourceName: String {
        switch summary.document.sourceType {
        case .epub: return "EPUB"
        case .pdf: return "PDF"
        case .article: return summary.document.sourceURL?.host() ?? "Article"
        }
    }
}
```

```swift
// App/T2SReader/Queue/EmptyQueue.swift
import SwiftUI

/// Spec §2.4.5 empty state: a grey paragraph explaining the share sheet and an "Import" pill.
struct EmptyQueue: View {
    var onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nothing queued yet. Share an article or a book from any app to t2s, or import one here. Everything you add plays right away — no waiting for it to process.")
                .typeRole(.meta)
                .foregroundStyle(Tokens.ink2)
            Pill(label: "Import", glyph: "plus", style: .soft, action: onImport)
        }
        .padding(.top, Spacing.grid)
    }
}
```

- [ ] **Step 2: The page, the details sheet, and the Add sheet placeholder**

```swift
// App/T2SReader/Queue/QueuePage.swift
import SwiftUI
import T2SApp
import T2SStore

struct QueuePage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showAdd = false
    @State private var showPlayer = false
    @State private var details: DocumentSummary?
    @State private var searchText = ""
    @State private var isSearching = false

    private var rows: [DocumentSummary] {
        let all = env.libraryModel.visibleRows
        guard isSearching, !searchText.isEmpty else { return all }
        return all.filter { $0.document.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        @Bindable var model = env.libraryModel
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                if isSearching {
                    TextField("Search", text: $searchText)
                        .typeRole(.rowTitle)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Tokens.surface, in: Capsule())
                        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                }
                if rows.isEmpty {
                    if model.queueView == .queue && !isSearching {
                        EmptyQueue { showAdd = true }
                            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                    } else {
                        Text(isSearching ? "No matches." : "Nothing finished yet.")
                            .typeRole(.meta).foregroundStyle(Tokens.ink2)
                            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                    }
                }
                ForEach(rows) { summary in
                    QueueRow(summary: summary, onOpen: {
                        // Plan 4b routes this to the Reader page; until then the player sheet stands in.
                        Task { await env.player.load(summary, play: true); showPlayer = true }
                    }, onDetails: { details = summary })
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { Task { await env.libraryModel.archive(summary.id) } } label: { Label("Archive", systemImage: "archivebox") }
                            .tint(Tokens.destructive)
                    }
                }
                Color.clear.frame(height: 120)                            // room for the mini-player and indicator
                    .listRowInsets(EdgeInsets())
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Tokens.ground)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Tokens.ground)
        .refreshable { await env.libraryModel.refresh() }
        .sheet(isPresented: $showAdd) { AddSheet() }
        .sheet(isPresented: $showPlayer) {
            PlayerSheet().presentationCornerRadius(Spacing.sheetCorner).presentationBackground(Tokens.raised)
        }
        .sheet(item: $details) { DetailsSheet(summary: $0) }
    }

    private var header: some View {
        @Bindable var model = env.libraryModel
        return HStack(alignment: .top) {
            PageTitle(text: model.queueView == .queue ? "Queue" : "Finished", subtitle: model.queueView == .queue ? model.queueSubtitle : nil) {
                Menu {
                    Button("Queue") { model.queueView = .queue }
                    Button("Finished") { model.queueView = .finished }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Tokens.ink2)
                        .padding(4)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.ink).frame(width: 36, height: 36)
                        .background(Tokens.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add")
                Pill(label: isSearching ? "Done" : "Search", style: isSearching ? .selected : .soft) {
                    withAnimation(.snappy) { isSearching.toggle(); if !isSearching { searchText = "" } }
                }
            }
            .padding(.top, Spacing.titleTop + 4)
        }
    }
}
```

```swift
// App/T2SReader/Queue/DetailsSheet.swift
import SwiftUI
import T2SApp
import T2SStore

/// Context-menu "Details": what the library knows about a document, and the only place to delete it
/// (delete removes from Queue and Collection both, spec §2.3).
struct DetailsSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var summary: DocumentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.document.title).typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                if let author = summary.document.author { Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2) }
            }
            VStack(alignment: .leading, spacing: 12) {
                row("Source", summary.document.sourceType.rawValue.uppercased())
                if let url = summary.document.sourceURL { row("Link", url.absoluteString) }
                row("Added", summary.document.addedAt.formatted(date: .abbreviated, time: .shortened))
                row("Chapters", "\(summary.chapterCount)")
                row("Length", DurationFormatter.long(summary.totalSeconds, approximate: !summary.isFullyRendered))
                row("Rendered", summary.utteranceCount > 0 ? "\(summary.renderedCount * 100 / summary.utteranceCount)%" : "—")
            }
            Spacer()
            Pill(label: "Delete from library", glyph: "trash", style: .destructiveSoft) {
                Task { await env.libraryModel.delete(summary.id); dismiss() }
            }
        }
        .padding(Spacing.margin)
        .padding(.top, Spacing.grid)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).typeRole(.meta).foregroundStyle(Tokens.ink2).frame(width: 84, alignment: .leading)
            Text(value).typeRole(.rowTitle).foregroundStyle(Tokens.ink).textSelection(.enabled)
        }
    }
}
```

```swift
// App/T2SReader/Import/AddSheet.swift  (placeholder; Task 11 replaces it)
import SwiftUI

struct AddSheet: View {
    var body: some View {
        Text("Import arrives in Task 11.").typeRole(.meta).foregroundStyle(Tokens.ink2).padding(Spacing.margin)
            .presentationDetents([.medium])
    }
}
```

- [ ] **Step 3: Build and commit**

Run: `scripts/build-app.sh`
Expected: `** BUILD SUCCEEDED **`. If `@Bindable var model = env.libraryModel` inside `body` fails because `LibraryModel.queueView` is not settable through the environment, expose a `Binding` via `Binding(get: { env.libraryModel.queueView }, set: { env.libraryModel.queueView = $0 })` instead; the menu only needs a setter.

```bash
git add App/T2SReader/Queue App/T2SReader/Import/AddSheet.swift
git commit -m "App: Queue page with rows, empty state, search, details sheet"
```

---

### Task 8: Collection page and book sheet (app target + `ChapterEntry.entries`)

**Files:**
- Modify: `Sources/T2SApp/Player/PlayerModel.swift` (move chapter-entry construction into a static `ChapterEntry.entries(timeline:timeIndex:elapsed:)` and call it from `chapters`)
- Create: `Tests/T2SAppTests/ChapterEntryTests.swift`
- Replace: `App/T2SReader/Collection/CollectionPage.swift`
- Create: `App/T2SReader/Collection/BookSheet.swift`

**Interfaces:**
- Consumes: `LibraryModel.collection`, `progress(for:)`, `enqueue`, `archive`; `PlayerModel.load(_:play:)`, `seek(toChapter:)`; `Library.timelineForPlayback`; `DocumentProgress`; `Artwork`, `ProgressBar`, `Pill`, `PageTitle`.
- Produces: `public static func ChapterEntry.entries(timeline: Timeline, timeIndex: TimeIndex, elapsed: TimeInterval) -> [ChapterEntry]`; `CollectionPage`, `BookSheet`.

Spec §2.4.5, Collection page: title, `N books` subtitle, `+` (Add sheet), 3-up cover grid with 16pt radius and a thin progress bar under each cover. Tap → book sheet: large floating cover, title in Player style, author, stat row (Chapters · Length `~5h 10m` · Rendered `42%`), `accent` "Play" pill, `+ Add to Queue` / `✓ In Queue` pill, then the chapter list with per-chapter play and progress.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/T2SAppTests/ChapterEntryTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SApp

@Suite struct ChapterEntryTests {
    @Test func entriesCarryStartsDurationsAndProgress() {
        func u(_ text: String, _ seconds: TimeInterval, href: String) -> Utterance {
            let n = text.utf16.count
            return Utterance(position: Position(resourceHref: href, progression: 0, charOffset: 0), source: text, spoken: text,
                             spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], duration: .estimated(seconds))
        }
        let timeline = Timeline(chapters: [
            Chapter(title: "One", position: Position(resourceHref: "a", progression: 0), utterances: [u("A.", 10, href: "a"), u("B.", 10, href: "a")]),
            Chapter(title: "Two", position: Position(resourceHref: "b", progression: 0), utterances: [u("C.", 20, href: "b")]),
            Chapter(title: "Empty", position: Position(resourceHref: "c", progression: 0), utterances: []),
        ])
        let entries = ChapterEntry.entries(timeline: timeline, timeIndex: TimeIndex(timeline), elapsed: 25)
        #expect(entries.map(\.title) == ["One", "Two", "Empty"])
        #expect(entries.map(\.startSeconds) == [0, 20, 40])
        #expect(entries.map(\.durationSeconds) == [20, 20, 0])
        #expect(entries.map(\.fraction) == [1, 0.25, 0])
        #expect(ChapterEntry.entries(timeline: Timeline(chapters: []), timeIndex: TimeIndex(Timeline(chapters: [])), elapsed: 0).isEmpty)
    }
}
```

- [ ] **Step 2: Refactor `PlayerModel.chapters` onto the static**

In `Sources/T2SApp/Player/PlayerModel.swift` add to `ChapterEntry`:

```swift
    /// One entry per chapter with its start on the (estimated) time axis and how far `elapsed` is through it.
    public static func entries(timeline: Timeline, timeIndex: TimeIndex, elapsed: TimeInterval) -> [ChapterEntry] {
        timeline.chapters.indices.map { c in
            let range = timeline.utteranceRange(ofChapter: c)
            let start = timeIndex.startTime(ofUtterance: range.lowerBound)
            let end = timeIndex.startTime(ofUtterance: range.upperBound)
            let duration = end - start
            let fraction = duration > 0 ? min(1, max(0, (elapsed - start) / duration)) : 0
            return ChapterEntry(index: c, title: timeline.chapters[c].title, startSeconds: start, durationSeconds: duration, fraction: fraction)
        }
    }
```

and replace the body of `PlayerModel.chapters` with:

```swift
        guard let timeline = coordinator.timeline else { return [] }
        return ChapterEntry.entries(timeline: timeline, timeIndex: coordinator.timeIndex, elapsed: elapsed)
```

Run: `swift test --filter "ChapterEntryTests|PlayerModelTests"`
Expected: 5 tests passed.

- [ ] **Step 3: Collection page and book sheet**

```swift
// App/T2SReader/Collection/CollectionPage.swift
import SwiftUI
import T2SApp
import T2SStore

struct CollectionPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showAdd = false
    @State private var selected: DocumentSummary?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        let books = env.libraryModel.collection
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                HStack(alignment: .top) {
                    PageTitle(text: "Collection", subtitle: books.count == 1 ? "1 book" : "\(books.count) books")
                    Spacer(minLength: 12)
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tokens.ink).frame(width: 36, height: 36)
                            .background(Tokens.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add")
                    .padding(.top, Spacing.titleTop + 4)
                }
                if books.isEmpty {
                    Text("Books and PDFs you import appear here, whether or not they are queued.")
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                }
                LazyVGrid(columns: columns, spacing: Spacing.row) {
                    ForEach(books) { book in
                        Button { selected = book } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                GeometryReader { geo in
                                    Artwork(relativePath: book.document.coverImagePath, paths: env.paths,
                                            size: geo.size.width, radius: Spacing.artworkLarge)
                                }
                                .aspectRatio(1, contentMode: .fit)
                                ProgressBar(fraction: env.libraryModel.progress(for: book.id)?.fraction ?? 0)
                                Text(book.document.title).typeRole(.meta).foregroundStyle(Tokens.ink).lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
        .sheet(isPresented: $showAdd) { AddSheet() }
        .sheet(item: $selected) { BookSheet(summary: $0) }
    }
}
```

```swift
// App/T2SReader/Collection/BookSheet.swift
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// Spec §2.4.5 book sheet. Chapters come from the timeline (re-derived if stale) and their
/// progress from the persisted position through `DocumentProgress`.
struct BookSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var summary: DocumentSummary

    @State private var chapters: [ChapterEntry] = []
    @State private var showPlayer = false

    private var live: DocumentSummary { env.libraryModel.summaries.first { $0.id == summary.id } ?? summary }
    private var isQueued: Bool { live.queueOrder != nil && !live.isFinished }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                HStack { Spacer(); Artwork(relativePath: live.document.coverImagePath, paths: env.paths, size: 180, radius: Spacing.artworkLarge)
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 12); Spacer() }
                    .padding(.top, Spacing.section)
                VStack(alignment: .leading, spacing: 8) {
                    Text(live.document.title).typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                    if let author = live.document.author { Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2) }
                }
                HStack(spacing: 6) {
                    Text("\(live.chapterCount) chapters")
                    Text("·")
                    Text(DurationFormatter.long(live.totalSeconds, approximate: !live.isFullyRendered))
                    Text("·")
                    Text("Rendered \(live.utteranceCount > 0 ? live.renderedCount * 100 / live.utteranceCount : 0)%")
                }
                .typeRole(.meta).foregroundStyle(Tokens.ink2)
                HStack(spacing: 8) {
                    Pill(label: "Play", glyph: "play.fill", style: .accent) {
                        Task { await env.player.load(live, play: true); showPlayer = true }
                    }
                    if isQueued {
                        Pill(label: "In Queue", glyph: "checkmark", style: .selected) { Task { await env.libraryModel.archive(live.id) } }
                    } else {
                        Pill(label: "Add to Queue", glyph: "plus", style: .soft) { Task { await env.libraryModel.enqueue(live.id) } }
                    }
                }
                VStack(alignment: .leading, spacing: 20) {
                    Text("Chapters").typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
                    ForEach(chapters) { chapter in
                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    await env.player.load(live, play: false)
                                    await env.player.seek(toChapter: chapter.index)
                                    await env.player.togglePlay()
                                    showPlayer = true
                                }
                            } label: {
                                Image(systemName: "play.fill").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Tokens.ink).frame(width: 32, height: 32)
                                    .background(Tokens.surface, in: Circle())
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(chapter.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(1)
                                ProgressBar(fraction: chapter.fraction)
                            }
                            Text(DurationFormatter.long(chapter.durationSeconds, approximate: !live.isFullyRendered))
                                .typeRole(.mono).foregroundStyle(Tokens.ink2)
                        }
                    }
                }
                Color.clear.frame(height: Spacing.section)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.raised)
        .presentationCornerRadius(Spacing.sheetCorner)
        .task(id: live.document.resumePosition) { await loadChapters() }
        .sheet(isPresented: $showPlayer) {
            PlayerSheet().presentationCornerRadius(Spacing.sheetCorner).presentationBackground(Tokens.raised)
        }
    }

    private func loadChapters() async {
        guard let timeline = try? await env.library.timelineForPlayback(live.id) else { chapters = []; return }
        let progress = DocumentProgress.compute(summary: live, timeline: timeline)
        chapters = ChapterEntry.entries(timeline: timeline, timeIndex: TimeIndex(timeline), elapsed: progress.elapsedSeconds)
    }
}
```

- [ ] **Step 4: Build, test, commit**

Run: `scripts/build-app.sh && swift test --filter "ChapterEntryTests|PlayerModelTests"`
Expected: build succeeds; 5 tests pass.

```bash
git add Sources/T2SApp/Player/PlayerModel.swift Tests/T2SAppTests/ChapterEntryTests.swift App/T2SReader/Collection
git commit -m "App: Collection grid and book sheet; ChapterEntry.entries shared with the player"
```

---
### Task 9: Player sheet, tick scrubber, chapter list (app target + `PlayerModel.addBookmark`)

**Files:**
- Modify: `Sources/T2SApp/Player/PlayerModel.swift` (add `addBookmark()`), `Tests/T2SAppTests/PlayerModelTests.swift` (one test)
- Replace: `App/T2SReader/Player/PlayerSheet.swift`
- Create: `App/T2SReader/Player/TickScrubber.swift`, `App/T2SReader/Player/ChapterList.swift`, `App/T2SReader/Player/ControlPill.swift`

**Interfaces:**
- Consumes: `PlayerModel` (everything from Task 5), `ScrubberModel`, `ChapterEntry`, `LibraryStore.add(_ bookmark:)`, `Bookmark`, `PositionResolver.position(for:in:)`, `RateLimits.allRates`, primitives.
- Produces: `PlayerModel.addBookmark() async -> Bool`; `PlayerSheet`, `TickScrubber`, `ChapterList`, `ControlPill`.

Spec §2.4.5, Player sheet: 56pt artwork; bookmark, sleep-timer, and overflow buttons; source and age line; Player title; author; a `Chapter 3 ▾` row opening the chapter list (title and duration per chapter); a `Read along →` row (Plan 4b; omitted here); tick scrubber with rendered ticks in `ink` and unrendered in `ink3`; times below in monospaced, total prefixed `~` until fully rendered; control pill: overflow | back 15 · play · forward 30 | speed as a bare number. The sleep timer and the speed picker are Plan 4b: the sleep-timer button is present but disabled, and the speed number opens a plain menu of the available rates until the picker arrives. During underrun the play glyph becomes a ring and a caption reads `catching up…` (spec §3.6).

- [ ] **Step 1: Bookmark support in the model, with its test**

Append to `PlayerModelTests`:

```swift
    @Test func addBookmarkStoresTheCurrentPosition() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let player = try makePlayer(f)
        #expect(await player.addBookmark() == false)                       // nothing loaded
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.seek(toChapter: 1)
        #expect(await player.addBookmark())
        let bookmarks = try await f.store.bookmarks(for: id)
        #expect(bookmarks.count == 1)
        #expect(bookmarks[0].position.resourceHref == "OEBPS/ch2.xhtml")
    }
```

Add to `PlayerModel`:

```swift
    /// A bookmark at the playhead, persisted as a `Position` (spec §3.2). False when nothing is loaded.
    public func addBookmark() async -> Bool {
        guard let current, let timeline = coordinator.timeline, timeline.utteranceCount > 0 else { return false }
        let position = PositionResolver.position(for: coordinator.playhead, in: timeline)
        do {
            try await library.store.add(Bookmark(documentID: current.id, position: position))
            return true
        } catch {
            renderError = "\(error)"
            return false
        }
    }
```

Run: `swift test --filter PlayerModelTests`
Expected: 5 tests passed.

- [ ] **Step 2: Scrubber, control pill, chapter list**

```swift
// App/T2SReader/Player/TickScrubber.swift
import SwiftUI
import T2SApp

/// Spec §2.4.5: uniform tick marks, rendered in `ink`, unrendered in `ink3`, so the render frontier
/// is visible without a legend. Drag anywhere to scrub; the seek fires on release.
struct TickScrubber: View {
    var model: ScrubberModel
    var onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fraction = dragFraction ?? model.fraction
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<model.tickCount, id: \.self) { i in
                        Capsule()
                            .fill(model.renderedTicks[i] ? Tokens.ink : Tokens.ink3)
                            .frame(width: 2, height: 14)
                        if i < model.tickCount - 1 { Spacer(minLength: 0) }
                    }
                }
                Capsule()
                    .fill(Tokens.ink)
                    .frame(width: 3, height: 22)
                    .offset(x: max(0, min(width - 3, width * fraction - 1.5)))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = min(1, max(0, $0.location.x / width)) }
                    .onEnded { value in
                        onSeek(min(1, max(0, value.location.x / width)))
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Scrubber")
        .accessibilityValue("\(Int((model.fraction * 100).rounded())) percent")
    }
}
```

```swift
// App/T2SReader/Player/ControlPill.swift
import SwiftUI
import T2SApp
import T2SCore

/// overflow | back 15 · play · forward 30 | speed (spec §2.4.5). The play glyph becomes a ring
/// while the coordinator is catching up (spec §3.6).
struct ControlPill: View {
    @Environment(AppEnvironment.self) private var env
    var onDetails: () -> Void

    var body: some View {
        let player = env.player
        HStack(spacing: 0) {
            Menu {
                Button { player.renderWholeDocument() } label: { Label("Render whole document", systemImage: "waveform") }
                Button(action: onDetails) { Label("Details", systemImage: "info.circle") }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            Spacer()
            control("gobackward.15", "Back 15 seconds") { Task { await player.skip(by: -15) } }
            Button {
                Task { await player.togglePlay() }
            } label: {
                Group {
                    if player.isCatchingUp {
                        ProgressView().progressViewStyle(.circular).tint(Tokens.ink)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 26, weight: .semibold))
                    }
                }
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            control("goforward.30", "Forward 30 seconds") { Task { await player.skip(by: 30) } }
            Spacer()
            Menu {
                ForEach([0.8, 1.0, 1.2, 1.5, 2.0, 3.0], id: \.self) { rate in
                    Button { player.setRate(rate) } label: {
                        Label(Self.rateText(rate), systemImage: player.coordinator.rate == rate ? "checkmark" : "")
                    }
                    .disabled(!player.coordinator.availableRates.contains(rate))
                }
            } label: {
                Text(Self.rateText(player.coordinator.rate)).typeRole(.mono).frame(width: 44, height: 44).contentShape(Rectangle())
            }
        }
        .foregroundStyle(Tokens.ink)
        .padding(.horizontal, 8)
        .frame(height: 64)
        .background(Tokens.surface, in: Capsule())
    }

    private func control(_ glyph: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    static func rateText(_ rate: Double) -> String {
        rate == rate.rounded() ? "\(Int(rate))x" : String(format: "%.1fx", rate)
    }
}
```

```swift
// App/T2SReader/Player/ChapterList.swift
import SwiftUI
import T2SApp

/// The `Chapter 3 ▾` row's sheet: title and duration per chapter, current chapter marked, tap to jump.
struct ChapterList: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let player = env.player
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Chapters").typeRole(.sectionHeader).foregroundStyle(Tokens.ink).padding(.top, Spacing.section)
                ForEach(player.chapters) { chapter in
                    Button {
                        Task { await player.seek(toChapter: chapter.index); dismiss() }
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(chapter.index == player.chapterIndex ? Tokens.ink : Tokens.ink3).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(chapter.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(1)
                                ProgressBar(fraction: chapter.fraction)
                            }
                            Text(DurationFormatter.long(chapter.durationSeconds, approximate: player.isTotalApproximate))
                                .typeRole(.mono).foregroundStyle(Tokens.ink2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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

- [ ] **Step 3: The sheet**

```swift
// App/T2SReader/Player/PlayerSheet.swift
import SwiftUI
import T2SApp
import T2SStore

struct PlayerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showChapters = false
    @State private var showDetails = false
    @State private var bookmarkSaved = false

    var body: some View {
        let player = env.player
        VStack(alignment: .leading, spacing: Spacing.section) {
            HStack(alignment: .top) {
                Artwork(relativePath: player.current?.document.coverImagePath, paths: env.paths, size: 56, radius: Spacing.artworkSmall)
                Spacer()
                HStack(spacing: 8) {
                    icon(bookmarkSaved ? "bookmark.fill" : "bookmark", "Bookmark") {
                        Task { bookmarkSaved = await player.addBookmark() }
                    }
                    icon("moon.zzz", "Sleep timer (arrives with the Reader)") {}
                        .disabled(true)
                        .opacity(0.4)
                    Menu {
                        Button { player.renderWholeDocument() } label: { Label("Render whole document", systemImage: "waveform") }
                        Button { showDetails = true } label: { Label("Details", systemImage: "info.circle") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.ink)
                            .frame(width: 36, height: 36).background(Tokens.surface, in: Circle())
                    }
                }
            }
            .padding(.top, Spacing.section)

            VStack(alignment: .leading, spacing: 8) {
                if let current = player.current {
                    HStack(spacing: 6) {
                        Text(sourceName(current))
                        Text("·")
                        Text(DurationFormatter.age(of: current.document.addedAt))
                    }
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    Text(current.document.title).typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                    if let author = current.document.author { Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2) }
                } else {
                    Text("Nothing playing").typeRole(.playerTitle).foregroundStyle(Tokens.ink2)
                }
            }

            if let index = player.chapterIndex, player.chapters.count > 1 {
                Button { showChapters = true } label: {
                    HStack(spacing: 6) {
                        Text("Chapter \(index + 1)").typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(Tokens.ink2)
                    }
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                TickScrubber(model: player.scrubber) { fraction in Task { await player.seek(fraction: fraction) } }
                HStack {
                    Text(player.elapsedText)
                    Spacer()
                    if player.isCatchingUp { Text("catching up…").typeRole(.meta) }
                    Spacer()
                    Text(player.totalText)
                }
                .typeRole(.mono).foregroundStyle(Tokens.ink2)
            }

            ControlPill { showDetails = true }

            if let error = player.renderError {
                Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive).lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .background(Tokens.raised)
        .sheet(isPresented: $showChapters) { ChapterList() }
        .sheet(isPresented: $showDetails) {
            if let current = player.current { DetailsSheet(summary: current) }
        }
        .onChange(of: player.coordinator.playhead) { _, _ in bookmarkSaved = false }
    }

    private func icon(_ glyph: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.ink)
                .frame(width: 36, height: 36).background(Tokens.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func sourceName(_ s: DocumentSummary) -> String {
        switch s.document.sourceType {
        case .epub: return "EPUB"
        case .pdf: return "PDF"
        case .article: return s.document.sourceURL?.host() ?? "Article"
        }
    }
}
```

- [ ] **Step 4: Build, test, commit**

Run: `scripts/build-app.sh && swift test --filter PlayerModelTests`
Expected: build succeeds; 5 tests pass. `.onChange(of:)` on `Playhead` needs `Playhead: Equatable` — it is `Hashable` (Plan 1).

```bash
git add Sources/T2SApp/Player/PlayerModel.swift Tests/T2SAppTests/PlayerModelTests.swift App/T2SReader/Player
git commit -m "App: player sheet with tick scrubber, control pill, chapter list, bookmarks"
```

---
### Task 10: `ImportModel` and the extraction contract (`T2SApp`)

**Files:**
- Create: `Sources/T2SApp/Import/ArticleExtracting.swift`, `Sources/T2SApp/Import/PlainTextArticle.swift`, `Sources/T2SApp/Import/ImportModel.swift`
- Create: `Tests/T2SAppTests/Support/FakeExtractor.swift`, `Tests/T2SAppTests/PlainTextArticleTests.swift`, `Tests/T2SAppTests/ImportModelTests.swift`

**Interfaces:**
- Consumes: `Library.importArticle(_:originalHTML:)`, `importFile(at:sourceType:)`, `ImportResult`, `ImportError`, `ArticleContent`, `LibraryStore.summary(id:)`, `DocumentSummary`.
- Produces: `public struct ExtractedArticle { content: ArticleContent; originalHTML: String; plainText: String; wordCount }`; `public enum ExtractionError { invalidURL, network(String), noArticle, timedOut }`; `public protocol ArticleExtracting: Sendable { func extract(from url: URL) async throws -> ExtractedArticle }`; `public enum PlainTextArticle { static func content(title:body:) -> ArticleContent; static func defaultTitle(for body:) -> String }`; `public struct FileRow: Identifiable { id: URL; name; state: FileState }`, `public enum FileState { pending, importing, done(DocumentSummary), failed(String) }`; `public enum ImportPhase { idle, fetching(URL), preview(ExtractedArticle), importing, done([DocumentSummary]), failed(String) }`; `@MainActor @Observable public final class ImportModel { init(library:extractor:); phase; fileRows; isThinPreview; static let thinArticleWordCount = 120; reset(); fetch(link:) async; confirmPreview() async; importText(title:body:) async; importFiles(_:) async }`.

The Add sheet (spec §2.4.5 rev 7) is a state machine: link → fetching → preview (always shown; thin extractions get a warning line) → importing → done; text and files skip the preview. Every import joins the Queue through `Library`, and `done` carries the summaries so the sheet's owner can open the first one. Errors are strings in `failed`, rendered inline by the sheet (never a system alert).

- [ ] **Step 1: Test support and failing tests**

```swift
// Tests/T2SAppTests/Support/FakeExtractor.swift
import Foundation
import T2SLibrary
@testable import T2SApp

struct FakeExtractor: ArticleExtracting {
    var article: ExtractedArticle? = ExtractedArticle(
        content: ArticleContent(title: "Fetched Title", byline: "Writer", siteName: "example.com",
                                sourceURL: URL(string: "https://example.com/post"), bodyXHTML: "<p>First paragraph.</p><p>Second one.</p>", excerpt: "First…"),
        originalHTML: "<html><body><p>First paragraph.</p></body></html>",
        plainText: "First paragraph. Second one.")
    var error: ExtractionError?

    func extract(from url: URL) async throws -> ExtractedArticle {
        if let error { throw error }
        guard var article else { throw ExtractionError.noArticle }
        article.content.sourceURL = url
        return article
    }
}
```

```swift
// Tests/T2SAppTests/PlainTextArticleTests.swift
import Testing
@testable import T2SApp

@Suite struct PlainTextArticleTests {
    @Test func paragraphsBecomeEscapedParagraphs() {
        let content = PlainTextArticle.content(title: "Notes", body: "Tom & Jerry <3\n\nSecond  paragraph.\nSame paragraph.\n\n\n")
        #expect(content.title == "Notes")
        #expect(content.bodyXHTML == "<p>Tom &amp; Jerry &lt;3</p><p>Second  paragraph.\nSame paragraph.</p>")
        #expect(content.sourceURL == nil && content.byline == nil)
    }

    @Test func defaultTitleIsTheFirstLineTrimmed() {
        #expect(PlainTextArticle.defaultTitle(for: "  A short note\nmore") == "A short note")
        #expect(PlainTextArticle.defaultTitle(for: String(repeating: "x", count: 120)) == String(repeating: "x", count: 80) + "…")
        #expect(PlainTextArticle.defaultTitle(for: " \n ") == "Pasted text")
        #expect(PlainTextArticle.content(title: "", body: "Hello there.").title == "Hello there.")
    }
}
```

```swift
// Tests/T2SAppTests/ImportModelTests.swift
import Foundation
import Testing
import T2SCore
import T2SLibrary
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct ImportModelTests {
    @Test func linkFlowFetchesPreviewsAndImports() async throws {
        let f = try AppFixtures()
        let model = ImportModel(library: f.library, extractor: FakeExtractor())
        let url = URL(string: "https://example.com/post")!
        await model.fetch(link: url)
        guard case .preview(let article) = model.phase else { Issue.record("expected preview, got \(model.phase)"); return }
        #expect(article.wordCount == 5)
        #expect(model.isThinPreview)                                         // 5 words < 120
        await model.confirmPreview()
        guard case .done(let docs) = model.phase else { Issue.record("expected done, got \(model.phase)"); return }
        #expect(docs.count == 1)
        #expect(docs[0].document.sourceType == .article && docs[0].document.sourceURL == url)
        #expect(docs[0].document.title == "Fake Book")                      // the reader's title wins (spec §2.1: one reflowable path)
        #expect(try await f.store.queue().map(\.id) == [docs[0].id])
        #expect(FileManager.default.fileExists(atPath: f.paths.originalHTMLURL(docs[0].id).path))
        model.reset()
        #expect(model.phase == .idle)
    }

    @Test func extractionFailureIsInline() async throws {
        let f = try AppFixtures()
        let model = ImportModel(library: f.library, extractor: FakeExtractor(error: .network("offline")))
        await model.fetch(link: URL(string: "https://example.com/x")!)
        #expect(model.phase == .failed("Couldn't load the page: offline"))
        await model.fetch(link: URL(string: "notaurl")!)
        #expect(model.phase == .failed("That doesn't look like a web address."))
    }

    @Test func importFailureAfterPreviewIsInline() async throws {
        let f = try AppFixtures(readers: [])                                  // no reader for articles
        let model = ImportModel(library: f.library, extractor: FakeExtractor())
        await model.fetch(link: URL(string: "https://example.com/post")!)
        await model.confirmPreview()
        #expect(model.phase == .failed("This kind of file isn't supported (article)."))
    }

    @Test func pastedTextImports() async throws {
        let f = try AppFixtures()
        let model = ImportModel(library: f.library, extractor: FakeExtractor())
        await model.importText(title: "", body: "A pasted note.\n\nWith two paragraphs.")
        guard case .done(let docs) = model.phase else { Issue.record("expected done, got \(model.phase)"); return }
        #expect(docs[0].document.sourceType == .article && docs[0].document.sourceURL == nil)
        await model.importText(title: "", body: "   ")
        #expect(model.phase == .failed("There's no text to read."))
    }

    @Test func filesImportOneByOneWithRows() async throws {
        let f = try AppFixtures()
        let model = ImportModel(library: f.library, extractor: FakeExtractor())
        let good = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).epub")
        try Data("PK".utf8).write(to: good)
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).txt")
        try Data("hi".utf8).write(to: bad)
        await model.importFiles([good, bad])
        #expect(model.fileRows.map(\.name) == [good.lastPathComponent, bad.lastPathComponent])
        guard case .done(let docs) = model.fileRows[0].state else { Issue.record("expected done"); return }
        #expect(docs.document.sourceType == .epub)
        #expect(model.fileRows[1].state == .failed("This kind of file isn't supported (txt)."))
        guard case .done(let imported) = model.phase else { Issue.record("expected done, got \(model.phase)"); return }
        #expect(imported.map(\.id) == [docs.id])
        await model.importFiles([bad])
        #expect(model.phase == .failed("Nothing could be imported."))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "PlainTextArticleTests|ImportModelTests"`
Expected: compile errors, types not found.

- [ ] **Step 3: Implement**

```swift
// Sources/T2SApp/Import/ArticleExtracting.swift
import Foundation
import T2SLibrary

/// What Readability gives us for a page: the article as a well-formed XHTML fragment (ready for
/// `ArticleEPUBWriter`), the original HTML to retain (spec §2.1), and the plain text for the preview.
public struct ExtractedArticle: Hashable, Sendable {
    public var content: ArticleContent
    public var originalHTML: String
    public var plainText: String

    public var wordCount: Int { plainText.split(whereSeparator: \.isWhitespace).count }

    public init(content: ArticleContent, originalHTML: String, plainText: String) {
        self.content = content
        self.originalHTML = originalHTML
        self.plainText = plainText
    }
}

public enum ExtractionError: Error, Equatable, Sendable {
    case invalidURL
    case network(String)
    /// The page loaded but Readability found no article in it.
    case noArticle
    case timedOut
}

/// The app target implements this with a hidden `WKWebView` + Readability.js; tests use a fake.
public protocol ArticleExtracting: Sendable {
    func extract(from url: URL) async throws -> ExtractedArticle
}
```

```swift
// Sources/T2SApp/Import/PlainTextArticle.swift
import Foundation
import T2SLibrary

/// "Paste text" (spec §2.4.5 rev 7): plain text becomes an article with no source URL. Blank lines
/// separate paragraphs; everything is escaped, so the body is always well-formed.
public enum PlainTextArticle {
    public static func content(title: String, body: String) -> ArticleContent {
        let paragraphs = body.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let xhtml = paragraphs.map { "<p>\(escape($0))</p>" }.joined()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ArticleContent(title: trimmedTitle.isEmpty ? defaultTitle(for: body) : trimmedTitle, bodyXHTML: xhtml)
    }

    /// The first non-blank line, cut to 80 characters; "Pasted text" when there is none.
    public static func defaultTitle(for body: String) -> String {
        guard let line = body.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else { return "Pasted text" }
        return line.count > 80 ? String(line.prefix(80)) + "…" : line
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
```

```swift
// Sources/T2SApp/Import/ImportModel.swift
import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

public struct FileRow: Identifiable, Hashable, Sendable {
    public var id: URL
    public var name: String
    public var state: FileState
}

public enum FileState: Hashable, Sendable {
    case pending, importing
    case done(DocumentSummary)
    case failed(String)
}

public enum ImportPhase: Hashable, Sendable {
    case idle
    case fetching(URL)
    case preview(ExtractedArticle)
    case importing
    case done([DocumentSummary])
    case failed(String)
}

/// The Add sheet's state (spec §2.4.5 rev 7). Every path ends in `.done` with the imported
/// documents, already queued by `Library`, or `.failed` with a sentence for the sheet to show inline.
@MainActor
@Observable
public final class ImportModel {
    /// Below this many words the preview says the extraction looks thin (spec §6).
    public static let thinArticleWordCount = 120

    public private(set) var phase: ImportPhase = .idle
    public private(set) var fileRows: [FileRow] = []

    private let library: Library
    private let extractor: any ArticleExtracting

    public init(library: Library, extractor: any ArticleExtracting) {
        self.library = library
        self.extractor = extractor
    }

    public var isThinPreview: Bool {
        if case .preview(let article) = phase { return article.wordCount < Self.thinArticleWordCount }
        return false
    }

    public func reset() {
        phase = .idle
        fileRows = []
    }

    // MARK: Paste a link

    public func fetch(link: URL) async {
        guard let scheme = link.scheme?.lowercased(), scheme == "http" || scheme == "https", link.host() != nil else {
            phase = .failed("That doesn't look like a web address.")
            return
        }
        phase = .fetching(link)
        do {
            phase = .preview(try await extractor.extract(from: link))
        } catch let error as ExtractionError {
            phase = .failed(Self.message(for: error))
        } catch {
            phase = .failed("Couldn't load the page: \(error.localizedDescription)")
        }
    }

    public func confirmPreview() async {
        guard case .preview(let article) = phase else { return }
        phase = .importing
        await finish { try await self.library.importArticle(article.content, originalHTML: article.originalHTML) }
    }

    // MARK: Paste text

    public func importText(title: String, body: String) async {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .failed("There's no text to read.")
            return
        }
        phase = .importing
        let content = PlainTextArticle.content(title: title, body: body)
        await finish { try await self.library.importArticle(content, originalHTML: "") }
    }

    // MARK: Open a file

    /// Imports each file in turn with a row per file; `phase` ends `.done` with every success, or
    /// `.failed` when none succeeded.
    public func importFiles(_ urls: [URL]) async {
        fileRows = urls.map { FileRow(id: $0, name: $0.lastPathComponent, state: .pending) }
        phase = .importing
        var imported: [DocumentSummary] = []
        for (i, url) in urls.enumerated() {
            fileRows[i].state = .importing
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                guard let type = Self.sourceType(for: url) else {
                    throw ImportError.unsupportedFormat(url.pathExtension.lowercased())
                }
                let result = try await library.importFile(at: url, sourceType: type)
                let summary = try await library.store.summary(id: result.document.id)
                guard let summary else { throw ImportError.unreadable("imported document vanished") }
                fileRows[i].state = .done(summary)
                imported.append(summary)
            } catch {
                fileRows[i].state = .failed(Self.message(for: error))
            }
        }
        phase = imported.isEmpty ? .failed("Nothing could be imported.") : .done(imported)
    }

    // MARK: Internals

    private func finish(_ body: @escaping @Sendable () async throws -> ImportResult) async {
        do {
            let result = try await body()
            guard let summary = try await library.store.summary(id: result.document.id) else {
                phase = .failed("The document was imported but could not be found.")
                return
            }
            phase = .done([summary])
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    static func sourceType(for url: URL) -> SourceType? {
        switch url.pathExtension.lowercased() {
        case "epub": return .epub
        case "pdf": return .pdf
        default: return nil
        }
    }

    /// One plain sentence per error (spec §6: never silent, never a system alert).
    static func message(for error: any Error) -> String {
        switch error {
        case ImportError.drmProtected: return "This file is copy-protected and can't be read."
        case ImportError.unsupportedFormat(let kind): return "This kind of file isn't supported (\(kind))."
        case ImportError.unreadable(let detail): return "This file couldn't be read. \(detail)"
        case ImportError.noText: return "There's no text to read."
        case ImportError.malformedBody: return "The article text couldn't be converted."
        case ExtractionError.invalidURL: return "That doesn't look like a web address."
        case ExtractionError.network(let detail): return "Couldn't load the page: \(detail)"
        case ExtractionError.noArticle: return "No article was found on that page."
        case ExtractionError.timedOut: return "The page took too long to load."
        default: return "Something went wrong: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "PlainTextArticleTests|ImportModelTests"`
Expected: 7 tests passed. `ImportPhase` and `FileState` are `Hashable` because `ExtractedArticle`, `DocumentSummary`, and `ArticleContent` are.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp/Import Tests/T2SAppTests
git commit -m "T2SApp: ImportModel state machine, extraction contract, plain-text articles"
```

---

### Task 11: Add sheet, link and text pages, file import, the WKWebView extractor (app target)

**Files:**
- Create: `scripts/fetch-readability.sh`; run it to create `App/Resources/Readability/Readability.js` and `App/Resources/Readability/LICENSE`
- Create: `App/T2SReader/Import/ArticleExtractor.swift`, `App/T2SReader/Import/PasteLinkPage.swift`, `App/T2SReader/Import/PasteTextPage.swift`, `App/T2SReader/Import/FileImportRows.swift`
- Replace: `App/T2SReader/Import/AddSheet.swift`
- Modify: `App/T2SReader/AppEnvironment.swift` (add `importModel`), `App/T2SReader/T2SReaderApp.swift` (`onOpenURL`), `App/T2SReader/Queue/QueuePage.swift` and `App/T2SReader/Collection/CollectionPage.swift` (pass `onImported` to `AddSheet` and open the player), `README.md` (vendored Readability note), `.github/workflows/ci.yml` (nothing new: the script output is committed)

**Interfaces:**
- Consumes: `ImportModel`, `ImportPhase`, `FileRow`, `ExtractedArticle`, `ArticleExtracting`, `ExtractionError`, `DocumentSummary`, primitives.
- Produces: `ArticleExtractor: ArticleExtracting` (hidden `WKWebView` + Readability.js 0.6.0); `AddSheet(onImported: (DocumentSummary) -> Void)`; `PasteLinkPage`, `PasteTextPage`, `FileImportRows`; `AppEnvironment.importModel`.

- [ ] **Step 1: Vendor Readability.js**

```bash
# scripts/fetch-readability.sh
#!/usr/bin/env bash
# Vendors Mozilla Readability 0.6.0 (Apache-2.0) into App/Resources/Readability. Committed; re-run to bump.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p App/Resources/Readability
curl -sSL -o App/Resources/Readability/Readability.js https://raw.githubusercontent.com/mozilla/readability/0.6.0/Readability.js
curl -sSL -o App/Resources/Readability/LICENSE https://raw.githubusercontent.com/mozilla/readability/0.6.0/LICENSE.md
head -3 App/Resources/Readability/Readability.js
grep -m1 -i "apache" App/Resources/Readability/LICENSE
```

Run: `chmod +x scripts/fetch-readability.sh && scripts/fetch-readability.sh`
Expected: the first lines of Readability.js include `Copyright (c) 2010 Arc90 Inc` and the license grep finds Apache. `App/Resources` is already a resources build phase (Task 1), so the file lands in the bundle as `Readability.js`.

- [ ] **Step 2: The extractor**

```swift
// App/T2SReader/Import/ArticleExtractor.swift
import Foundation
import T2SApp
import T2SLibrary
import WebKit

/// Loads the page in a hidden `WKWebView`, runs Readability.js, and serializes the article to an
/// XHTML fragment with `XMLSerializer` (images, media, and scripts removed: this is a listening app).
/// The Share Extension (Plan 5) reuses this class.
@MainActor
final class ArticleExtractor: NSObject, ArticleExtracting, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ExtractedArticle, any Error>?
    private var timeout: Task<Void, Never>?
    private var url: URL?

    static let timeoutSeconds: UInt64 = 20

    nonisolated func extract(from url: URL) async throws -> ExtractedArticle {
        try await MainActor.run { try self.begin(url) }
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in self.continuation = continuation }
        }
    }

    private func begin(_ url: URL) throws {
        guard continuation == nil, webView == nil else { throw ExtractionError.network("an extraction is already running") }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { throw ExtractionError.invalidURL }
        self.url = url
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.timeoutSeconds))
            self?.fail(ExtractionError.timedOut)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await runReadability() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        fail(ExtractionError.network(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        fail(ExtractionError.network(error.localizedDescription))
    }

    private func runReadability() async {
        guard let webView, let url else { return }
        guard let scriptURL = Bundle.main.url(forResource: "Readability", withExtension: "js"),
              let library = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            fail(ExtractionError.network("Readability.js is missing from the app bundle"))
            return
        }
        let runner = library + """

        (function () {
          var original = document.documentElement.outerHTML;
          var article = new Readability(document.cloneNode(true)).parse();
          if (!article || !article.content) { return null; }
          var container = document.createElementNS('http://www.w3.org/1999/xhtml', 'div');
          container.innerHTML = article.content;
          container.querySelectorAll('img, picture, figure, video, audio, iframe, svg, script, style, noscript, form, button').forEach(function (n) { n.remove(); });
          var xhtml = new XMLSerializer().serializeToString(container).replace(/&nbsp;/g, '\\u00a0');
          return { title: article.title || document.title || '', byline: article.byline || null, siteName: article.siteName || null,
                   excerpt: article.excerpt || null, lang: article.lang || document.documentElement.lang || null,
                   text: article.textContent || '', content: xhtml, html: original };
        })();
        """
        do {
            let result = try await webView.evaluateJavaScript(runner)
            guard let dict = result as? [String: Any], let content = dict["content"] as? String, !content.isEmpty else {
                fail(ExtractionError.noArticle)
                return
            }
            let title = (dict["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url.host() ?? "Article"
            let article = ExtractedArticle(
                content: ArticleContent(title: title, byline: dict["byline"] as? String, siteName: dict["siteName"] as? String,
                                        sourceURL: url, language: (dict["lang"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "en",
                                        bodyXHTML: content, excerpt: dict["excerpt"] as? String),
                originalHTML: dict["html"] as? String ?? "",
                plainText: dict["text"] as? String ?? "")
            succeed(article)
        } catch {
            fail(ExtractionError.network("Readability failed: \(error.localizedDescription)"))
        }
    }

    private func succeed(_ article: ExtractedArticle) {
        guard let continuation else { return }
        teardown()
        continuation.resume(returning: article)
    }

    private func fail(_ error: ExtractionError) {
        guard let continuation else { return }
        teardown()
        continuation.resume(throwing: error)
    }

    private func teardown() {
        timeout?.cancel()
        timeout = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation = nil
        url = nil
    }
}
```

The class is `@MainActor`; `ArticleExtracting` requires `Sendable`, which a main-actor class satisfies. `begin` runs before the continuation is stored, so a synchronous failure throws straight out of `extract`; `runReadability` and the delegate callbacks always find the continuation because `didFinish` cannot fire before `extract` has awaited the continuation (loading takes real time), but if it ever did, `succeed`/`fail` guard on `continuation == nil` and the 20 s timeout ends the wait.

- [ ] **Step 3: The sheet and its pages**

```swift
// App/T2SReader/Import/AddSheet.swift
import SwiftUI
import T2SApp
import T2SStore

/// Spec §2.4.5 rev 7: three soft pills, then the chosen path in place. `onImported` receives the
/// first imported document; the owner opens it with playback started.
struct AddSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var onImported: (DocumentSummary) -> Void

    enum Path { case link, text, files }
    @State private var path: Path?
    @State private var showFilePicker = false

    var body: some View {
        let model = env.importModel
        VStack(alignment: .leading, spacing: Spacing.section) {
            Text("Add").typeRole(.sectionHeader).foregroundStyle(Tokens.ink).padding(.top, Spacing.section)
            switch path {
            case nil:
                VStack(spacing: 12) {
                    option("Paste a link", "link") { path = .link }
                    option("Open a file", "doc") { path = .files; showFilePicker = true }
                    option("Paste text", "text.alignleft") { path = .text }
                }
            case .link:
                PasteLinkPage()
            case .text:
                PasteTextPage()
            case .files:
                FileImportRows()
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.epub, .pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await model.importFiles(urls) }
            case .failure: path = nil
            }
        }
        .onChange(of: model.phase) { _, phase in
            if case .done(let docs) = phase, let first = docs.first {
                dismiss()
                onImported(first)
            }
        }
        .onDisappear { model.reset() }
    }

    private func option(_ label: String, _ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: glyph).font(.system(size: 17, weight: .medium)).frame(width: 24)
                Text(label).typeRole(.rowTitle)
                Spacer()
            }
            .foregroundStyle(Tokens.ink)
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(Tokens.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
```

```swift
// App/T2SReader/Import/PasteLinkPage.swift
import SwiftUI
import T2SApp
import UIKit

/// URL field prefilled from the clipboard, one `accent` "Listen" pill, then the extraction preview
/// in place (title, site, first lines, word count) with "Listen" and "Cancel".
struct PasteLinkPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let model = env.importModel
        VStack(alignment: .leading, spacing: 20) {
            switch model.phase {
            case .preview(let article):
                VStack(alignment: .leading, spacing: 10) {
                    Text(article.content.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                    HStack(spacing: 6) {
                        if let site = article.content.siteName { Text(site); Text("·") }
                        Text("\(article.wordCount) words")
                    }
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    Text(String(article.plainText.prefix(280))).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(5)
                    if model.isThinPreview {
                        Text("This looks thin — the page may not have a readable article.").typeRole(.meta).foregroundStyle(Tokens.destructive)
                    }
                }
                HStack(spacing: 8) {
                    Pill(label: "Listen", glyph: "play.fill", style: .accent) { Task { await model.confirmPreview() } }
                    Pill(label: "Cancel", style: .soft) { model.reset() }
                }
            case .fetching:
                HStack(spacing: 10) { ProgressView().tint(Tokens.ink); Text("Fetching…").typeRole(.meta).foregroundStyle(Tokens.ink2) }
            case .importing:
                HStack(spacing: 10) { ProgressView().tint(Tokens.ink); Text("Importing…").typeRole(.meta).foregroundStyle(Tokens.ink2) }
            default:
                TextField("https://", text: $text)
                    .typeRole(.rowTitle)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Tokens.surface, in: Capsule())
                    .onSubmit { fetch() }
                Pill(label: "Listen", glyph: "play.fill", style: .accent) { fetch() }
                if case .failed(let message) = model.phase {
                    Text(message).typeRole(.meta).foregroundStyle(Tokens.destructive)
                }
            }
        }
        .onAppear {
            if text.isEmpty, UIPasteboard.general.hasURLs, let url = UIPasteboard.general.url { text = url.absoluteString }
            focused = text.isEmpty
        }
    }

    private func fetch() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        Task { await env.importModel.fetch(link: URL(string: candidate) ?? URL(string: "invalid://")!) }
    }
}
```

```swift
// App/T2SReader/Import/PasteTextPage.swift
import SwiftUI
import T2SApp

struct PasteTextPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var title = ""
    @State private var body_ = ""

    var body: some View {
        let model = env.importModel
        VStack(alignment: .leading, spacing: 16) {
            TextField("Title (optional)", text: $title)
                .typeRole(.rowTitle)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Tokens.surface, in: Capsule())
            TextEditor(text: $body_)
                .typeRole(.rowTitle)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 160)
                .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if case .importing = model.phase {
                HStack(spacing: 10) { ProgressView().tint(Tokens.ink); Text("Importing…").typeRole(.meta).foregroundStyle(Tokens.ink2) }
            } else {
                Pill(label: "Listen", glyph: "play.fill", style: .accent) { Task { await model.importText(title: title, body: body_) } }
            }
            if case .failed(let message) = model.phase {
                Text(message).typeRole(.meta).foregroundStyle(Tokens.destructive)
            }
        }
    }
}
```

```swift
// App/T2SReader/Import/FileImportRows.swift
import SwiftUI
import T2SApp

/// One row per chosen file with its state; the sheet closes itself when the batch ends with a success.
struct FileImportRows: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = env.importModel
        VStack(alignment: .leading, spacing: 16) {
            if model.fileRows.isEmpty {
                Text("Choose EPUB or PDF files.").typeRole(.meta).foregroundStyle(Tokens.ink2)
            }
            ForEach(model.fileRows) { row in
                HStack(spacing: 12) {
                    Image(systemName: "doc").foregroundStyle(Tokens.ink2)
                    Text(row.name).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(1)
                    Spacer()
                    switch row.state {
                    case .pending: Text("Waiting").typeRole(.meta).foregroundStyle(Tokens.ink2)
                    case .importing: ProgressView().tint(Tokens.ink)
                    case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.positive)
                    case .failed(let message): Text(message).typeRole(.meta).foregroundStyle(Tokens.destructive).lineLimit(2)
                    }
                }
            }
            if case .failed(let message) = model.phase, model.fileRows.isEmpty {
                Text(message).typeRole(.meta).foregroundStyle(Tokens.destructive)
            }
        }
    }
}
```

- [ ] **Step 4: Wire the environment, the pages, and "Open in"**

In `AppEnvironment` add `let importModel: ImportModel` and in `init` set `importModel = ImportModel(library: library, extractor: ArticleExtractor())`. In `QueuePage` and `CollectionPage` replace `AddSheet()` with

```swift
            AddSheet { imported in
                Task { await env.player.load(imported, play: true); showPlayer = true }
            }
```

(`CollectionPage` gains `@State private var showPlayer = false` and the same `.sheet(isPresented: $showPlayer) { PlayerSheet()… }` as the Queue page.) In `T2SReaderApp` add to the `RootPager()` view `.onOpenURL { url in Task { await environment.importModel.importFiles([url]) } }` — files handed over by "Open in" (Info.plist document types from Task 1) import straight into the Queue, and the Queue page's next refresh shows them. README: add a line under "Working on it": `scripts/fetch-readability.sh   # re-vendor Readability.js (committed under App/Resources/Readability)`.

- [ ] **Step 5: Build and commit**

Run: `scripts/build-app.sh`
Expected: `** BUILD SUCCEEDED **`. Then, on the simulator (`open App/T2SReader.xcodeproj`, run): Queue → `+` → Paste a link → a real article URL → the preview appears → Listen → the player sheet opens and the system voice starts within a few seconds. Record what you saw in the report; this is the one manual check in the plan.

```bash
git add scripts/fetch-readability.sh App README.md
git commit -m "App: Add sheet with link, file, and text import; WKWebView Readability extractor"
```

---
### Task 12: Audio session, device monitor, lifecycle persistence, docs (app target)

**Files:**
- Create: `App/T2SReader/System/AudioSessionController.swift`, `App/T2SReader/System/DeviceMonitor.swift`
- Modify: `App/T2SReader/Root/RootPager.swift` (queue → coordinator, scene-phase persistence), `App/T2SReader/T2SReaderApp.swift` (start the session and the monitor), `README.md`, `docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md`

**Interfaces:**
- Consumes: `PlaybackCoordinator.device`, `.queue`, `.pause()`; `PlayerModel.persistRenderedChapters()`; `DeviceSignals`, `DeviceStateMapping`, `BatteryState`, `ThermalLevel`; `FileAudioStore.stats()`.
- Produces: `AudioSessionController.activate(pausing:)`, `DeviceMonitor` (`@Observable`, `signals`, `start()`).

Spec §3.5: `AVAudioSession` category `.playback`, mode `.spokenAudio`. Spec §3.4.1: Prepare stops on unplug, at thermal `.serious`, in Low Power Mode, at the cache cap; charging is detected from the battery state. Interruptions pause playback; positions and rendered chapters are written when the app goes to the background.

- [ ] **Step 1: Audio session**

```swift
// App/T2SReader/System/AudioSessionController.swift
import AVFoundation
import Foundation

/// Spec §3.5. Activates the spoken-audio playback session and pauses on interruptions (a call,
/// another app taking the output) and when headphones are unplugged.
@MainActor
final class AudioSessionController {
    private var observers: [NSObjectProtocol] = []

    func activate(pausing pause: @escaping @MainActor () -> Void) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            // Playback still works through the default session; the loss is background continuation.
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue { MainActor.assumeIsolated { pause() } }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { MainActor.assumeIsolated { pause() } }
        })
    }
}
```

- [ ] **Step 2: Device monitor**

```swift
// App/T2SReader/System/DeviceMonitor.swift
import Foundation
import Observation
import T2SApp
import T2SCore
import UIKit

/// Reads the signals `DeviceStateMapping` needs (spec §3.4.1 guards) and republishes them whenever
/// iOS says they changed. The mapping itself is pure and tested in `T2SApp`.
@MainActor
@Observable
final class DeviceMonitor {
    private(set) var signals = DeviceSignals(batteryState: .unknown, thermal: .nominal, lowPowerMode: false, storeBytes: 0, storeCapacityBytes: 1)
    private let audioStore: FileAudioStore
    private var observers: [NSObjectProtocol] = []

    init(audioStore: FileAudioStore) { self.audioStore = audioStore }

    var deviceState: DeviceState { DeviceStateMapping.deviceState(signals) }

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let names: [Notification.Name] = [UIDevice.batteryStateDidChangeNotification, ProcessInfo.thermalStateDidChangeNotification,
                                          .NSProcessInfoPowerStateDidChange, UIApplication.didBecomeActiveNotification]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func refresh() {
        Task {
            let stats = await audioStore.stats()
            signals = DeviceSignals(batteryState: Self.battery(UIDevice.current.batteryState),
                                    thermal: Self.thermal(ProcessInfo.processInfo.thermalState),
                                    lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                    storeBytes: stats.bytes, storeCapacityBytes: stats.capacityBytes)
        }
    }

    private static func battery(_ state: UIDevice.BatteryState) -> BatteryState {
        switch state {
        case .charging: return .charging
        case .full: return .full
        case .unplugged: return .unplugged
        default: return .unknown
        }
    }

    private static func thermal(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .serious
        }
    }
}
```

- [ ] **Step 3: Wire it**

In `AppEnvironment` add `let audioSession = AudioSessionController()` and `let deviceMonitor: DeviceMonitor` (initialized with `audioStore`). In `T2SReaderApp`, when the environment exists, attach to `RootPager()`:

```swift
                    .onAppear {
                        environment.audioSession.activate(pausing: { environment.coordinator.pause() })
                        environment.deviceMonitor.start()
                    }
```

In `RootPager` add:

```swift
        .onChange(of: env.deviceMonitor.deviceState, initial: true) { _, state in env.coordinator.device = state }
        .onChange(of: env.libraryModel.queue.map(\.id), initial: true) { _, ids in env.coordinator.queue = ids }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await env.player.persistRenderedChapters() } }
        }
```

with `@Environment(\.scenePhase) private var scenePhase`. `DeviceState` is `Hashable` (Plan 2), so `onChange` compares it.

- [ ] **Step 4: Docs**

README "Working on it": already lists `scripts/build-app.sh`; add a short "Running the app" paragraph: open the generated project, pick the `T2SReader` scheme and an iPhone simulator, run; the system voice speaks until Plan 5 brings Kokoro; import with `+` on the Queue page. Roadmap: mark Plan 4a `executing` (or `done` when merged) and keep 4b's row.

- [ ] **Step 5: Build and commit**

Run: `scripts/build-app.sh && swift test && scripts/check-licenses.sh`
Expected: build succeeds; the whole root suite passes; guard exits 0.

```bash
git add App README.md docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md
git commit -m "App: audio session, device monitor feeding the render policy, background persistence"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| §2.2 in-app import (link, file, text); exact resume; offline by default | 10, 11; 5 (positions through the store); everything local |
| §2.3 Queue as primary list, Collection grid, archive vs delete | 7, 8, 4 |
| §2.4.1 type roles, Inter bundled, monospaced digits | 1, 6 |
| §2.4.2 semantic tokens, one accent per screen, chips solid ink | 6 (Tokens, Pill); reviewers check each page |
| §2.4.3 grid, margins, no cards or dividers, pill and sheet radii | 6, 7, 8, 9 |
| §2.4.4 pager, indicator, mini-player rules, title dropdowns | 6, 7 |
| §2.4.5 Queue page, Add sheet, Collection page, book sheet, Player sheet, context menu | 7, 11, 8, 9 |
| §3 coordinator ownership; UI reads state and ticks | 5, 9 |
| §3.3 `~` totals until rendered; tick scrubber shows the frontier | 3, 5, 9 |
| §3.4.1 device guards, queue order to the policy, "ready" check, no processing state | 3, 12, 7 |
| §3.5 audio session category and mode | 12 |
| §3.6 catching-up state visible | 9 |
| §5 container layout, cache excluded from backup, cap from preferences | 3, 6 |
| §6 model fallback engine; import errors inline; thin extraction surfaced | 2, 10, 11 |
| §9 steps 6 (part: playback surfaces) and 8 (Queue, Collection, Player; import) | all |

Hand-offs to Plan 4b: the Reader page (Readium navigator, decorations from `LocatorMapping`, auto-scroll, `Read along →` row, tap-title routing), the speed picker (replacing the control pill's menu), the sleep timer (enabling the player sheet's button), Preferences content (voice, playback, reading, pronunciation, storage with cap and evict, prepare budget), the voice-change warning. Hand-offs to Plan 5: Kokoro replacing `SystemSpeechEngine`, Now Playing and remote commands, the Share Extension (reusing `ArticleExtractor` and `ImportModel`), multi-document Prepare with `BGProcessingTask`, calibration of `SystemSpeechEngine` markers on a device voice.
