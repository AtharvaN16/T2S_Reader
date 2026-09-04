# Plan 5: Audio Lifecycle, Share Extension, Prepare Runner, and Engines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the engine- and system-integration work left after Plans 4a/4b: a reliable long-form audio lifecycle with Lock Screen / Control Center controls; a Share Extension for links, text, EPUBs, and PDFs; automatic multi-document Prepare on charge; an opt-in, BYO-key HTTP voice; and Kokoro as the built-in engine once the device spikes have selected a viable runtime.

**Architecture:** `T2SApp` keeps pure state and policy testable on macOS. The app target owns Apple framework boundaries: MediaPlayer, AVAudioSession reset recovery, BackgroundTasks, Keychain, WebKit, and the Share Extension UI. A shared app-group `LibraryPaths` root is the single local-library location for both app and extension. `PrepareRunner` uses the already pure `RenderPolicy` for *all* eligible documents and a shared, priority-aware render lease so Prepare yields after an utterance to play-ahead. A `RoutedEngine` remains a `SynthesisEngine`: its voice IDs include the non-secret engine/configuration identity, so `RenderKey` still makes every voice/engine change structurally stale. Kokoro becomes the built-in route only after the Plan 0 findings make that route safe; `SystemSpeechEngine` remains the explicit failure fallback required by spec §6.

**Tech Stack:** Swift 6, SwiftUI, Observation, AVFoundation, MediaPlayer, BackgroundTasks, Foundation `NSExtensionItem`/`NSItemProvider`, UniformTypeIdentifiers, Security Keychain Services, URLSession, WebKit + vendored Readability.js, xcodegen 2.45.4, `kokoro-ios` + MisakiSwift (gated), existing T2SCore/T2SAudio/T2SLibrary/T2SApp targets. iOS 18 deployment; macOS 15 for root-package tests.

**Spec:** `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (rev 7). Sections §1.1, §2.1–§2.2, §2.4.5, §3.4, §3.4.1, §3.5, §3.6, §3.7.1–§3.7.5, §5, §6, §7.1–§7.5, §7.7, and §9 steps 7 and 9.

## Global Constraints

- **No backend, accounts, or developer-paid cloud service** (spec §1.1). Cloud voices are strictly user-supplied endpoint + key. Never log, put in `UserDefaults`, add to a URL, include in a render key, or show the key after saving it.
- **Render policy is authoritative** (spec §3.4.1). Nothing, including a Share Extension or Prepare, gates phase-1 import. Play-ahead is always higher priority than prime, Prepare, and manual work. Prepare is one document at a time, priority order continue-document then Queue, and stops on unplug, Low Power Mode, thermal `.serious`, cache cap, task expiry, or its playback-seconds budget.
- **Render correctness is structural** (spec §5). A `RenderKey` includes document, utterance, voice identity, engine identity, normalizer, and segmenter. The selected voice's stable ID must include the non-secret cloud configuration fingerprint; old cache entries are never accepted merely because an `audioRef` is non-nil.
- **Rate and underrun policy remain unchanged** (spec §3.6). The rolling RTF measures the actual selected engine; unavailable rates are disabled rather than silently lowered. An HTTP/Kokoro failure is surfaced and follows the existing per-utterance 200 ms silence policy; it must not halt a book.
- **Audio lifecycle** (spec §3.5): retain `.playback`, `.spokenAudio`, and `.longFormAudio`; publish actual elapsed time/rate on state or seek; keep lock screen artwork local; map remote controls only to the shared `PlayerModel` / `PlaybackCoordinator`; and recover a media-services reset at the last persisted `Position`, never an utterance index.
- **Share Extension trust boundary** (spec §2.1, §6): accept only `http`/`https` URLs, plain text, EPUB, and PDF; use `NSItemProvider` file representations only while their completion runs; copy bytes before return; run the same `ArticleExtractor` / `ImportModel` / `Library` validation as in-app import; present errors inline; and never expose arbitrary shared URLs to the reader.
- **Shared-container ownership** (spec §5, §3.7.3): app and extension use `group.com.t2s.reader` and `LibraryPaths(root:)`; the audio directory remains excluded from backup. The extension imports only phase 1 and never constructs an `AudioPlayer` or starts rendering.
- **Background processing is opportunistic** (spec §3.4.1, §7.7). A `BGProcessingTask` is a request, not a timer. Register once before launch finishes, declare `processing` and the identifier in generated Info.plist, set an expiration handler before work starts, and call `setTaskCompleted(success:)` exactly once.
- **Kokoro is gated** (spec §7.1–§7.5, §7.7). Do not add its package, weights, or shipping code until each required Plan 0 finding exists and is accepted. **Superseded for Task 5** by "Task 5 adjustments approved 2026-09-03" below: with §7.1 accepted and the A14 floor known, the engine, availability probe, route, catalog and fallback may land now; the constants (`KokoroRuntimeDecision.current`) and the word timings stay gated on the 17 Pro findings (§7.2–§7.5, §7.7).
- Preserve Plan 4a/4b constraints: Swift 6 strict concurrency; models testable with `swift test`; public types `Sendable`, actor-isolated, or `@MainActor`; token-only SwiftUI views; no generated Xcode project/Info.plist committed; `scripts/build-app.sh` after app edits; license audit after dependency changes; and one conventional commit per task.

## Verified toolchain facts (do not re-derive)

Verified against `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk` (Xcode 26.5), not inferred from online examples.

- `MPRemoteCommandCenter.shared()` exposes `playCommand`, `pauseCommand`, `togglePlayPauseCommand`, `changePlaybackRateCommand`, `skipForwardCommand`, `skipBackwardCommand`, `seekForwardCommand`, `seekBackwardCommand`, and `changePlaybackPositionCommand`. Every `MPRemoteCommand` accepts `addTarget(handler:)` and expects `MPRemoteCommandHandlerStatus`; skip events carry `interval`, rate events carry `playbackRate`, and position events carry `positionTime`. `MPSkipIntervalCommand.preferredIntervals` and `MPChangePlaybackRateCommand.supportedPlaybackRates` are writable.
- `MPNowPlayingInfoCenter.default().nowPlayingInfo` is a nullable dictionary and `playbackState` is available on iOS. The SDK documents `MPMediaItemPropertyTitle`, `MPMediaItemPropertyArtist`, `MPMediaItemPropertyArtwork`, and `MPMediaItemPropertyPlaybackDuration`, plus `MPNowPlayingInfoPropertyElapsedPlaybackTime`, `PlaybackRate`, `DefaultPlaybackRate`, queue index/count, and chapter number/count. The SDK explicitly says elapsed time is extrapolated from the supplied elapsed time and rate, so it must not be rewritten at the 10 Hz UI ticker. `MPMediaItemArtwork(bounds:requestHandler:)` is the iOS initializer.
- `AVAudioSession.mediaServicesWereResetNotification` is the Swift name in AVFAudio's local API notes. It is distinct from `AVAudioEngineConfigurationChange`: recovery must reapply the session category/activation and recreate the audio graph rather than merely call `play()`.
- `BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)` must run before application launch completes and only once per identifier. `BGProcessingTaskRequest(identifier:)` has `requiresExternalPower`, `requiresNetworkConnectivity`, and inherited `earliestBeginDate`; processing needs the `processing` background mode, runs only while idle, can run for minutes, and can be interrupted. `BGTask.expirationHandler` must cancel/clean up and `setTaskCompleted(success:)` must be called.
- A share extension receives `NSExtensionContext.inputItems`; every `NSExtensionItem` has optional `attributedContentText` and `[NSItemProvider] attachments`. `NSItemProvider` exposes `hasItemConformingToTypeIdentifier`, `loadItem`, `loadDataRepresentation`, `loadFileRepresentation`, and `loadInPlaceFileRepresentation`. The header says a file returned by `loadFileRepresentation` is deleted after the completion handler returns, so the implementation copies it inside that closure.
- `URLSessionConfiguration.background(withIdentifier:)` is available as `backgroundSessionConfigurationWithIdentifier:` in the SDK. A background session used from an app extension **must** set `sharedContainerIdentifier` or transfers fail with `NSURLErrorBackgroundSessionRequiresSharedContainer`; background configurations default `sessionSendsLaunchEvents` to true and the host receives `application(_:handleEventsForBackgroundURLSession:completionHandler:)`. This plan deliberately uses a normal foreground `URLSession` for a submitted share URL: importing/extracting must finish before the share sheet completes, and no background transfer is needed.
- Keychain Services provides `SecItemCopyMatching`, `SecItemAdd`, `SecItemUpdate`, and `SecItemDelete`; generic-password items support `kSecAttrService`, `kSecAttrAccount`, and `kSecValueData`. The SDK also notes that a keychain access group is required to share keychain items between separate applications. The app and its extension therefore do not need a new keychain-access-group entitlement: only the host app reads cloud keys, while the extension only imports local content.
- xcodegen 2.45.4 is installed. It supports the `app-extension` product type and target `entitlements`; generated `App/T2SReader.xcodeproj` and both generated Info.plists remain ignored. `scripts/build-app.sh` is the required project-generation/build command.
- Existing APIs to preserve: `PlayerModel` exposes `current`, `state`, `elapsed`, `total`, `chapterIndex`, `setRate`, `skip(by:)`, `seek(fraction:)`, `togglePlay`, `persistRenderedChapters`; `PlaybackCoordinator` exposes `play()`, `pause()`, `seek(toTime:)`, `device`, `queue`, `waitForRenderIdle`; `StorageModel.lastPrepareRunKey == "prepare.lastRun"`; `ReaderPreferences.prepareBudgetSeconds` persists at `AppPaths.prepareBudgetKey`; `Library.renderSnapshot(for:)`, `timelineForPlayback(_:)`, `LibraryPaths`, `ImportModel`, and `ArticleExtractor` already exist.

## File structure

```
Sources/T2SCore/Render/
  RenderArbiter.swift                         shared per-utterance priority lease
  RenderScheduler.swift                       acquire/release lease, cancellation boundary
  SynthesisEngine.swift                       routed voice identity contract
Sources/T2SAudio/
  AudioPlaying.swift, AudioPlayer.swift       resettable real graph / no-op fake implementation
  RoutedEngine.swift                          system / cloud / Kokoro route selection
  HTTPVoiceEngine.swift                       rate-limited, BYO-key OpenAI-compatible PCM adapter
  KokoroEngine.swift                          GATED: kokoro-ios + MisakiSwift implementation
Sources/T2SApp/
  Environment/AppPaths.swift                  app-group root and constants
  Playback/NowPlayingSnapshot.swift           pure metadata/remote-command mapping
  Playback/PrepareRunner.swift                multi-document policy execution and persistence
  Preferences/CloudVoiceSettings.swift        non-secret endpoint/model/voice defaults
  Preferences/CloudVoiceCatalog.swift         stable cloud voice IDs and visibility state
Tests/T2SCoreTests/Render/RenderArbiterTests.swift
Tests/T2SAudioTests/HTTPVoiceEngineTests.swift, RoutedEngineTests.swift, KokoroEngineTests.swift (gated)
Tests/T2SAppTests/NowPlayingSnapshotTests.swift, PrepareRunnerTests.swift, CloudVoiceSettingsTests.swift
App/
  project.yml                                 processing mode, app group, URL scheme, embedded Share Extension
  T2SReader/
    AppEnvironment.swift                      app-group graph, engine router, PrepareRunner
    System/AudioSessionController.swift       reset notification and recovery hand-off
    System/NowPlayingController.swift         MP info/artwork + remote commands
    System/PrepareTask.swift                  BGProcessingTask registration/scheduling
    System/KeychainSecretStore.swift          host-only cloud key store
    Import/ArticleExtractor.swift             moved to Shared so the extension uses the exact extractor
    Preferences/CloudVoicesPage.swift         endpoint/config/key UI and errors
    Preferences/PreferencesPage.swift         Cloud voices link replaces the placeholder
    Root/RootPager.swift, T2SReaderApp.swift  hand-off URL and task lifecycle
  Shared/
    ArticleExtractor.swift                    shared WebKit + Readability implementation
    SharedLibraryFactory.swift                app-group LibraryPaths/Library/ImportModel factory
  T2SReaderShare/
    ShareViewController.swift                 compact SwiftUI host and extension completion
    ShareImportService.swift                  NSExtensionItem → ImportModel
    ShareExtension.entitlements
  T2SReader.entitlements
docs/superpowers/
  plans/2026-09-03-plan-5-engine-share-nowplaying.md
  plans/2026-09-02-t2s-reader-roadmap.md
  specs/2026-09-01-t2s-reader-design.md       only resolved Plan-0 findings / implementation notes
docs/HANDOFF.md, README.md, docs/licenses.md
```

---

### Task 1: Audio lifecycle — Now Playing, remote controls, and media-services reset

**Files:**
- Create: `Sources/T2SApp/Playback/NowPlayingSnapshot.swift`, `Tests/T2SAppTests/NowPlayingSnapshotTests.swift`
- Create: `App/T2SReader/System/NowPlayingController.swift`
- Modify: `Sources/T2SAudio/AudioPlaying.swift`, `Sources/T2SAudio/AudioPlayer.swift`, `Tests/T2SAudioTests/Support/FakePlayer.swift`, `Sources/T2SAudio/PlaybackCoordinator.swift`, `Tests/T2SAudioTests/PlaybackCoordinatorTests.swift`
- Modify: `App/T2SReader/System/AudioSessionController.swift`, `App/T2SReader/AppEnvironment.swift`, `App/T2SReader/System/PlaybackTicker.swift`, `App/T2SReader/T2SReaderApp.swift`, `App/T2SReader/Root/RootPager.swift`, `App/project.yml`

**Interfaces:**
- Consumes: `PlayerModel`, `PlaybackCoordinator`, `ReaderPreferences.skipBackSeconds`/`skipForwardSeconds`, `LibraryPaths.coverURL`/`url(forRelativePath:)`, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, and `AVAudioSession.mediaServicesWereResetNotification`.
- Produces: `NowPlayingSnapshot` (pure title/author/duration/elapsed/rate/chapter/queue state), `NowPlayingController { start(); update(_:artwork:); clear() }`, `AudioPlaying.rebuildAfterMediaServicesReset()`, and `PlaybackCoordinator.recoverAfterMediaServicesReset() async`.

- [ ] **Step 1: Write the failing pure tests first**

```swift
// Tests/T2SAppTests/NowPlayingSnapshotTests.swift
import Foundation
import Testing
@testable import T2SApp

@Suite struct NowPlayingSnapshotTests {
    @Test func pausedSnapshotStopsClockAndUsesOneBasedChapter() {
        let value = NowPlayingSnapshot(title: "The Book", author: "Ada", duration: 600,
                                       elapsed: 42, rate: 2, isPlaying: false,
                                       chapterIndex: 1, chapterCount: 12, queueIndex: 0, queueCount: 3)
        #expect(value.playbackRate == 0)
        #expect(value.defaultPlaybackRate == 2)
        #expect(value.chapterNumber == 2 && value.queueIndex == 0 && value.queueCount == 3)
    }

    @Test func remoteRateOnlyAcceptsAdvertisedRatesAndSeekIsClamped() {
        #expect(NowPlayingSnapshot.acceptedRate(2, available: [0.5, 1, 1.5, 2]) == 2)
        #expect(NowPlayingSnapshot.acceptedRate(3, available: [0.5, 1, 1.5, 2]) == nil)
        #expect(NowPlayingSnapshot.clampedSeek(700, duration: 600) == 600)
        #expect(NowPlayingSnapshot.clampedSeek(-3, duration: 600) == 0)
    }
}
```

Run: `swift test --filter NowPlayingSnapshotTests`

Expected: compile failure: `NowPlayingSnapshot` is not found.

- [ ] **Step 2: Add the pure snapshot and reset-safe playback seam**

```swift
// Sources/T2SApp/Playback/NowPlayingSnapshot.swift
import Foundation

public struct NowPlayingSnapshot: Hashable, Sendable {
    public var title: String; public var author: String; public var duration: TimeInterval
    public var elapsed: TimeInterval; public var rate: Double; public var isPlaying: Bool
    public var chapterIndex: Int?; public var chapterCount: Int; public var queueIndex: Int?; public var queueCount: Int
    public var playbackRate: Double { isPlaying ? rate : 0 }
    public var defaultPlaybackRate: Double { rate }
    public var chapterNumber: Int? { chapterIndex.map { $0 + 1 } }
    public init(title: String, author: String, duration: TimeInterval, elapsed: TimeInterval, rate: Double,
                isPlaying: Bool, chapterIndex: Int?, chapterCount: Int, queueIndex: Int?, queueCount: Int) {
        self.title = title; self.author = author; self.duration = max(0, duration)
        self.elapsed = Self.clampedSeek(elapsed, duration: duration); self.rate = rate; self.isPlaying = isPlaying
        self.chapterIndex = chapterIndex; self.chapterCount = chapterCount; self.queueIndex = queueIndex; self.queueCount = queueCount
    }
    public static func acceptedRate(_ value: Double, available: [Double]) -> Double? {
        available.first { abs($0 - value) < 0.001 }
    }
    public static func clampedSeek(_ value: TimeInterval, duration: TimeInterval) -> TimeInterval {
        min(max(0, value), max(0, duration))
    }
}
```

Add this requirement to `AudioPlaying` and implement it as a no-op on `FakePlayer`:

```swift
/// The only destructive hardware recovery operation. The coordinator immediately resets and
/// refills from its persisted Position, so implementations must not retain scheduled buffers.
func rebuildAfterMediaServicesReset()
```

In `AudioPlayer`, make `engine`, `player`, `timePitch`, and `format` resettable `private var`s. Extract the present attach/connect/start code into `makeGraph() throws`; `rebuildAfterMediaServicesReset()` must stop the old player, remove the configuration observer, build a fresh graph at the existing sample rate, reinstall one observer, and leave `isPlaying == false`. Do not try to retain an `AVAudioPlayerNode` across `mediaServicesWereReset`.

Add this coordinator operation (the `defer` preserves the original user intent):

```swift
public func recoverAfterMediaServicesReset() async {
    guard let timeline, timeline.utteranceCount > 0 else { return }
    let resume = PositionResolver.position(for: playhead, in: timeline)       // persisted anchor, never index
    let shouldPlay = state == .playing || state == .catchingUp
    player.rebuildAfterMediaServicesReset()
    player.reset()
    let target = PositionResolver.resolve(resume, in: timeline)
    await seek(to: target)
    if shouldPlay { await play() }
}
```

`load(_:)` must set `rendered[i]` only when the stored `audioRef` equals the *expected* current `RenderKey`; this fixes stale cache acceptance for this task and is required for Tasks 4–5.

- [ ] **Step 3: Build the MediaPlayer boundary exactly once**

`NowPlayingController` is `@MainActor final`, retains every command target token, and is initialized with `player`, `libraryModel`, `preferences`, and `paths`. Its `update` constructs `NowPlayingSnapshot` from the one shared player, then assigns this dictionary:

```swift
var info: [String: Any] = [
    MPMediaItemPropertyTitle: snapshot.title,
    MPMediaItemPropertyArtist: snapshot.author,
    MPMediaItemPropertyPlaybackDuration: snapshot.duration,
    MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
    MPNowPlayingInfoPropertyPlaybackRate: snapshot.playbackRate,
    MPNowPlayingInfoPropertyDefaultPlaybackRate: snapshot.defaultPlaybackRate,
    MPNowPlayingInfoPropertyChapterCount: snapshot.chapterCount,
    MPNowPlayingInfoPropertyPlaybackQueueCount: snapshot.queueCount,
]
if let chapter = snapshot.chapterNumber { info[MPNowPlayingInfoPropertyChapterNumber] = chapter }
if let index = snapshot.queueIndex { info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index }
if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
MPNowPlayingInfoCenter.default().nowPlayingInfo = info
```

Create `MPMediaItemArtwork(bounds: image.size) { _ in image }` from the document's local cover path. If no readable cover exists, use one cached `UIImage(systemName: "book.closed.fill")!`; never fetch artwork over the network. Set `playbackState` to `.playing` or `.paused`, clear info only when no document is loaded, and call `update` on load, play/pause, seek, document/chapter transition, rate change, and then at most once per elapsed second while playing.

Register the commands in `start()` as follows. Every handler returns `.commandFailed` when no document is loaded; asynchronous seeks/play commands create a `Task { @MainActor in … }` and return `.success` after enqueueing work.

```swift
center.skipBackwardCommand.preferredIntervals = [NSNumber(value: preferences.skipBackSeconds)]
center.skipForwardCommand.preferredIntervals = [NSNumber(value: preferences.skipForwardSeconds)]
center.changePlaybackRateCommand.supportedPlaybackRates = player.coordinator.availableRates.map(NSNumber.init(value:))

// play / pause / toggle: coordinator.play(), coordinator.pause(), player.togglePlay()
// MPSkipIntervalCommandEvent: player.skip(by: event.interval * direction)
// MPChangePlaybackRateCommandEvent: accept only NowPlayingSnapshot.acceptedRate(...), then player.setRate(_)
// MPChangePlaybackPositionCommandEvent: player.coordinator.seek(toTime: clamped position)
```

Handle continuous `seekForwardCommand` / `seekBackwardCommand` on `.endSeeking` by one configured skip interval; do not simulate an unbounded fast-forward. Disable previous/next-track, repeat, shuffle, ratings, and feedback: an audiobook queue is not a music playlist. Remove every target in `deinit`.

- [ ] **Step 4: Wire interruption and media-services recovery**

Keep existing interruption and route-change behaviour. Add an observer for `.mediaServicesWereResetNotification` on `AVAudioSession.sharedInstance()` in `AudioSessionController.activate`. Its closure must: reapply `.playback` / `.spokenAudio` / `.longFormAudio`, reactivate the session, then invoke a new async `recovering` closure. `T2SReaderApp` passes `Task { await environment.coordinator.recoverAfterMediaServicesReset() }`; do not rebuild from the notification observer itself.

`AppEnvironment` creates one `NowPlayingController`; `RootPager` starts it alongside `AudioSessionController`, calls its throttled `update` from `playbackTicking`, and clears it when a library delete removes the loaded document. Keep `UIBackgroundModes: [audio]` in this task—`processing` is added by Task 3, not early.

- [ ] **Step 5: Verify, then perform the physical-device pass**

Run:

```bash
swift test --filter "NowPlayingSnapshotTests|PlaybackCoordinatorTests|AudioPlayerTests"
scripts/build-app.sh
```

Expected: the selected root tests and simulator build pass.

On an iPhone (not the simulator): import a book with and without cover art; lock/unlock; exercise Lock Screen and Control Center play, pause, 15-back, 30-forward, rate, and scrub; connect/disconnect wired headphones and AirPods; receive/end a phone call; force the media-services-reset notification under the debugger if available. Verify recovery resumes at the same sentence/word, only resumes after an interruption that was actually playing, and never leaves stale Now Playing content after deletion. Record device/iOS and outcomes in the eventual Plan 5 manual report.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SCore Sources/T2SAudio Sources/T2SApp Tests App/T2SReader
git commit -m "App: Now Playing, remote controls, and audio-services recovery"
```

---

### Task 2: Share Extension — URL, text, EPUB, and PDF import through the shared library

**Files:**
- Create: `App/T2SReader/Shared/SharedLibraryFactory.swift`, `App/T2SReader/Shared/ShareHandoff.swift`
- Move: `App/T2SReader/Import/ArticleExtractor.swift` → `App/T2SReader/Shared/ArticleExtractor.swift`
- Create: `App/T2SReaderShare/ShareViewController.swift`, `App/T2SReaderShare/ShareImportService.swift`, `App/T2SReaderShare/ShareExtension.entitlements`, `App/T2SReader/T2SReader.entitlements`
- Create: `Tests/T2SAppTests/ShareHandoffTests.swift`
- Modify: `Sources/T2SApp/Environment/AppPaths.swift`, `Tests/T2SAppTests/AppPathsTests.swift`, `App/project.yml`, `App/T2SReader/AppEnvironment.swift`, `App/T2SReader/Root/RootPager.swift`, `App/T2SReader/T2SReaderApp.swift`

**Interfaces:**
- Consumes: `NSExtensionContext.inputItems`, `NSExtensionItem.attachments`, `NSItemProvider`, `UTType.url`/`.plainText`/`.epub`/`.pdf`, the shared `ArticleExtractor`, `ImportModel`, `Library`, `LibraryPaths`, and `NSExtensionContext.open(_:completionHandler:)`.
- Produces: `AppPaths.appGroupIdentifier`, `AppPaths.sharedContainerRoot()`, `SharedLibraryFactory.make() -> (paths, store, library, importModel)`, `ShareImportService.importItems(_:) async -> Result<[UUID], ShareImportError>`, and `t2s://import?id=<UUID>` hand-off handling in the host app.

- [ ] **Step 1: Write failing path/handoff tests**

```swift
// Tests/T2SAppTests/ShareHandoffTests.swift
import Foundation
import Testing
@testable import T2SApp

@Suite struct ShareHandoffTests {
    @Test func appGroupRootAndHandoffURLAreStable() throws {
        #expect(AppPaths.appGroupIdentifier == "group.com.t2s.reader")
        let root = try AppPaths.containerRoot(under: URL(filePath: "/tmp/t2s-group"))
        #expect(LibraryHandoff.url(for: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!).absoluteString
                == "t2s://import?id=00000000-0000-0000-0000-000000000001")
        #expect(LibraryHandoff.documentID(from: URL(string: "t2s://import?id=bad")!) == nil)
        #expect(root.lastPathComponent == "t2s")
    }
}
```

Run: `swift test --filter ShareHandoffTests`

Expected: compile failure for `LibraryHandoff` and the app-group constant.

- [ ] **Step 2: Add the shared root and hand-off value**

Add to `AppPaths`:

```swift
public static let appGroupIdentifier = "group.com.t2s.reader"

public static func sharedContainerRoot(fileManager: FileManager = .default) throws -> URL {
    guard let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try containerRoot(under: group)
}
```

Put the URL-only `LibraryHandoff` in `Sources/T2SApp` (not the app target) so it is testable: `url(for:)` uses `URLComponents(scheme: "t2s", host: "import", queryItems: [.init(name: "id", value: id.uuidString)])`; `documentID(from:)` requires that exact scheme/host and exactly one valid UUID. This identifier is a pointer to an already-imported row in the app-group store, never a file path or secret.

`SharedLibraryFactory` builds `LibraryPaths(root: try AppPaths.sharedContainerRoot())`, `LibraryStore.onDisk(at:)`, `FileAudioStore(AACCodec())`, `Library`, `ReadiumDocumentReader`, `PDFDocumentReader`, and an `ImportModel(library:extractor: ArticleExtractor())`. It creates the root and marks its Audio child excluded from backup, exactly as the app factory does. Extract this common storage construction from `AppEnvironment.live()`; the app uses the shared version too, so the extension and host cannot diverge.

- [ ] **Step 3: Define the extension target and entitlements in `App/project.yml`**

Add both targets' generated entitlements and embed the extension in the application target. The app's properties gain the `t2s` URL scheme; it retains document types and audio mode.

```yaml
  T2SReader:
    dependencies:
      - target: T2SReaderShare
        embed: true
    entitlements:
      path: T2SReader/T2SReader.entitlements
      properties:
        com.apple.security.application-groups: [group.com.t2s.reader]
    info:
      properties:
        CFBundleURLTypes:
          - CFBundleURLName: com.t2s.reader.import
            CFBundleURLSchemes: [t2s]
  T2SReaderShare:
    type: app-extension
    platform: iOS
    sources:
      - path: T2SReaderShare
      - path: T2SReader/Shared
      - path: Resources/Readability
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
    entitlements:
      path: T2SReaderShare/ShareExtension.entitlements
      properties:
        com.apple.security.application-groups: [group.com.t2s.reader]
    info:
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.share-services
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ShareViewController
          NSExtensionAttributes:
            NSExtensionActivationSupportsWebURLWithMaxCount: 1
            NSExtensionActivationSupportsText: true
            NSExtensionActivationSupportsFileWithMaxCount: 8
        CFBundleDisplayName: Add to t2s
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.t2s.reader.share
        SWIFT_VERSION: "6.0"
        SWIFT_STRICT_CONCURRENCY: complete
        TARGETED_DEVICE_FAMILY: "1"
```

Keep `ArticleExtractor` source-identical when moving it to `Shared`; its `Bundle.main.url(forResource: "Readability", withExtension: "js")` now resolves in either target because both copy the same resource. Do not add a background `URLSession` here.

- [ ] **Step 4: Implement provider decoding and import**

`ShareViewController` hosts a small SwiftUI view: title `Add to t2s`, current item count/status, one accent `Add` pill, Cancel, and inline destructive error. It only calls `completeRequest` after `ShareImportService` returns.

`ShareImportService` is `@MainActor`. Flatten all `NSExtensionItem.attachments`, preserve their item order, and handle each provider in this priority order:

```swift
if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) { /* load URL; await model.fetch; await confirmPreview */ }
else if provider.hasItemConformingToTypeIdentifier(UTType.epub.identifier) { /* copy temporary file; await importFiles */ }
else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) { /* copy temporary file; await importFiles */ }
else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) { /* load String; await importText */ }
else { failures.append("This shared item isn't a link, EPUB, PDF, or text.") }
```

Bridge `loadItem`/`loadFileRepresentation` with checked continuations. For file representations, make a unique file under `paths.root/ShareInbox/<UUID>.<extension>` *inside the completion handler*, then call `ImportModel.importFiles([copy])`; `Library.importFile` makes its own permanent copy, after which remove the inbox copy in `defer`. Never pass the provider's temporary URL beyond the continuation. A shared URL uses `ImportModel.fetch(link:)` then `confirmPreview()` without showing a preview—the explicit user action was the Share-sheet Add button; the same extraction validation and error text still apply. Shared text is imported with the first nonblank line as its title through existing `PlainTextArticle`.

Collect every `.done` summary ID. On at least one success, call:

```swift
extensionContext.open(LibraryHandoff.url(for: firstID)) { _ in
    self.extensionContext.completeRequest(returningItems: nil)
}
```

The completion's Boolean is advisory: if the host refuses to open, still complete success because the item is durable in the common app-group library. The host's `RootPager.onOpenURL` must first parse `LibraryHandoff`; if valid, refresh the model, retrieve `store.summary(id:)`, and present that Reader. Otherwise retain the existing external-file route. On normal foreground activation, also refresh the library so an extension import is visible even if iOS did not open the app.

The two lifetime-sensitive helpers are implemented exactly this way (the remaining `ImportPhase` handling is ordinary conversion of `.done` and `.failed`):

```swift
// App/T2SReaderShare/ShareImportService.swift
@MainActor
private func copiedFile(from provider: NSItemProvider, type: UTType, into inbox: URL) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
            guard let url else { continuation.resume(throwing: error ?? ShareImportError.unavailable(type.identifier)); return }
            do {
                try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
                let name = provider.suggestedName?.isEmpty == false ? provider.suggestedName! : UUID().uuidString
                let destination = inbox.appendingPathComponent(name).appendingPathExtension(type.preferredFilenameExtension ?? "bin")
                try FileManager.default.copyItem(at: url, to: destination) // provider URL dies as this handler returns
                continuation.resume(returning: destination)
            } catch { continuation.resume(throwing: error) }
        }
    }
}

private func importedIDs(_ model: ImportModel, after operation: @escaping () async -> Void) async -> [UUID] {
    await operation()
    guard case .done(let summaries) = model.phase else { return [] }
    return summaries.map(\.id)
}
```

For the URL and text branches, the equivalent continuation accepts only `URL`/`NSURL` and `String`/`NSString`, respectively; any other coercion is `.unavailable`. The service rejects more than eight attachments before any import, retains each public `.failed(let message)` value as the inline error, and calls `model.reset()` only after it has retained its IDs/errors.

- [ ] **Step 5: Verify the build and a real share path**

Run:

```bash
swift test --filter "ShareHandoffTests|AppPathsTests|ImportModelTests"
scripts/build-app.sh
```

Expected: root tests pass and xcodegen builds both the host and embedded extension for the simulator.

On a signed device: share an `https` article from Safari, selected text, one EPUB, one PDF, multiple files, an unsupported image, and a malformed/DRM file. Verify each supported input appears once in Queue; no temporary extension file remains under `ShareInbox`; the share sheet returns promptly; launching hand-off opens the imported document if permitted; and a failure stays inline without a partially created library directory.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SApp Tests/T2SAppTests App/project.yml App/T2SReader
git commit -m "App: Share Extension imports into the shared library"
```

---

### Task 3: Prepare runner — multi-document budget, visible state, and `BGProcessingTask`

**Files:**
- Create: `Sources/T2SCore/Render/RenderArbiter.swift`, `Tests/T2SCoreTests/Render/RenderArbiterTests.swift`
- Create: `Sources/T2SApp/Playback/PrepareRunner.swift`, `Tests/T2SAppTests/PrepareRunnerTests.swift`
- Create: `App/T2SReader/System/PrepareTask.swift`
- Modify: `Sources/T2SCore/Render/RenderScheduler.swift`, `Sources/T2SAudio/PlaybackCoordinator.swift`, `Sources/T2SApp/Storage/StorageModel.swift`, `App/T2SReader/AppEnvironment.swift`, `App/T2SReader/T2SReaderApp.swift`, `App/T2SReader/Root/RootPager.swift`, `App/project.yml`
- Create/Modify: `App/T2SReader/Preferences/StoragePage.swift` (create from the Plan 4b Storage surface if that plan has not landed; otherwise modify it)

**Interfaces:**
- Consumes: `RenderPolicy`, `RenderScheduler`, `RenderSnapshot`, `Library.renderSnapshot(for:)`, `Library.timelineForPlayback(_:)`, `LibraryStore.saveChapter`, `AudioStore`, `DeviceState`, `AppPaths.prepareBudgetKey`, `StorageModel.lastPrepareRunKey`, and `BGProcessingTask`.
- Produces: `RenderArbiter` (play-ahead > prime > prepare > manual per utterance), `PrepareRunner { run(reason:device:) async -> PrepareRunResult; cancel() }`, `PrepareRunResult`, `StorageModel.recordPrepareRun(_:)`, and `PrepareTask.register/schedule`.

- [ ] **Step 1: Write failing arbiter and runner tests**

```swift
// Tests/T2SCoreTests/Render/RenderArbiterTests.swift
import Testing
@testable import T2SCore

@Suite struct RenderArbiterTests {
    @Test func playAheadWaiterWinsBeforePrepareAtTheNextUtteranceBoundary() async {
        let arbiter = RenderArbiter()
        await arbiter.acquire(.prepare)
        let prepareAgain = Task { await arbiter.acquire(.prepare); return "prepare" }
        let playing = Task { await arbiter.acquire(.playAhead); return "play" }
        await arbiter.release()
        #expect(await playing.value == "play")
        await arbiter.release()
        #expect(await prepareAgain.value == "prepare")
        await arbiter.release()
    }
}
```

```swift
// Tests/T2SAppTests/PrepareRunnerTests.swift
import Foundation
import Testing
import T2SAudio
import T2SCore
@testable import T2SApp

@MainActor @Suite struct PrepareRunnerTests {
    @Test func continueThenQueueConsumesOneSharedPlaybackBudgetAndRecordsRun() async throws {
        let f = try AppFixtures(); let first = try await f.importFake(); let second = try await f.importFake()
        let suite = "prepare-\(UUID())"; let defaults = UserDefaults(suiteName: suite)!; defaults.removePersistentDomain(forName: suite)
        defaults.set(1.0, forKey: AppPaths.prepareBudgetKey)
        let runner = PrepareRunner(library: f.library, store: f.store, audioStore: f.audio,
                                   engine: FakeEngine(secondsPerCharacter: 0.05), defaults: defaults,
                                   arbiter: RenderArbiter())
        let result = await runner.run(lastPlayed: first, queue: [first, second],
                                      device: DeviceState(charging: true, thermalSerious: false, lowPowerMode: false, storeFull: false))
        #expect(result.renderedUtterances > 0 && result.documentIDs.first == first)
        #expect(defaults.object(forKey: StorageModel.lastPrepareRunKey) as? Date != nil)
    }

    @Test func unsafeDeviceDoesNoWorkAndDoesNotClaimARun() async throws {
        let f = try AppFixtures(); let id = try await f.importFake(); let defaults = UserDefaults(suiteName: "prepare-\(UUID())")!
        let runner = PrepareRunner(library: f.library, store: f.store, audioStore: f.audio,
                                   engine: FakeEngine(), defaults: defaults, arbiter: RenderArbiter())
        let result = await runner.run(lastPlayed: id, queue: [id], device: .unplugged)
        #expect(result.renderedUtterances == 0)
        #expect(defaults.object(forKey: StorageModel.lastPrepareRunKey) == nil)
    }
}
```

Run: `swift test --filter "RenderArbiterTests|PrepareRunnerTests"`

Expected: compile failures for both new types.

- [ ] **Step 2: Make the rendering boundary genuinely shared**

Implement `RenderArbiter` as an actor with four FIFO waiter queues. `acquire(_ tier:)` resumes the first waiter from the lowest raw-value nonempty tier; `release()` grants exactly one next waiter. Modify `RenderScheduler` to accept `arbiter` and acquire/release around **each cache miss/synthesis/store utterance**, not around its whole plan. It receives the job tier from `RenderRequest.job.tier`. Existing `PlaybackCoordinator` and the new runner receive the same `AppEnvironment.renderArbiter`; no second inference starts while a Prepare utterance is in flight, and play-ahead wins before the next Prepare utterance.

```swift
// Sources/T2SCore/Render/RenderArbiter.swift
public actor RenderArbiter {
    private var held = false
    private var waiters: [RenderTier: [CheckedContinuation<Void, Never>]] = [:]

    public init() {}

    public func acquire(_ tier: RenderTier) async {
        if !held { held = true; return }
        await withCheckedContinuation { continuation in
            waiters[tier, default: []].append(continuation)
        }
    }

    public func release() {
        for tier in [RenderTier.playAhead, .prime, .prepare, .manual] {
            guard var queue = waiters[tier], !queue.isEmpty else { continue }
            let next = queue.removeFirst()
            waiters[tier] = queue
            next.resume()                         // ownership transfers; held remains true
            return
        }
        held = false
    }
}
```

The scheduler's one critical section is deliberately narrow:

```swift
await arbiter.acquire(request.job.tier)
defer { Task { await arbiter.release() } }
// cache check, engine.synthesize, and atomic AudioStore.write for this one request
```

Use a local `await arbiter.release()` on every explicit error/cancellation return instead of an unstructured `defer` in final code if Swift 6's actor isolation rejects the task capture; do not accidentally let a cancelled task retain the lease.

Keep `RenderScheduler.cancel()` as a pending-work cancellation boundary. `PrepareRunner.cancel()` calls it and cancels its consumer task; an already writing utterance is allowed to finish, which is safe because every rendered result is atomically persisted.

- [ ] **Step 3: Implement `PrepareRunner` as policy execution, not a duplicate policy**

`PrepareRunner` is `@MainActor @Observable`, injected with `library`, `LibraryStore`, `AudioStore`, the app's selected `SynthesisEngine`, defaults, and the shared arbiter. `run`:

1. Guards `device.charging && !thermalSerious && !lowPowerMode && !storeFull`; otherwise returns `.skipped(.unsafeDevice)` and does not alter `lastPrepareRun`.
2. Reads `AppPaths.prepareBudgetKey` *at the start of every run*. Use `3 * 3600` for missing/nonpositive/NaN, and map `infinity` to `TimeInterval.greatestFiniteMagnitude`; do not reuse `CoordinatorConfiguration.prepareBudgetSeconds`, which is a launch-time value today.
3. De-duplicates `[lastPlayed] + queue`, fetches each `Library.renderSnapshot(for:)`, and feeds all available snapshots to a single `PolicyInput` with no `playing`, no prime/manual jobs, the actual device state, and the current budget. Filter the result to `.prepare`; this preserves the canonical continue-then-Queue ordering and shared playback-seconds budget.
4. Groups consecutive jobs by document. For each group, loads the current timeline once, creates a `RenderScheduler(engine:store:timeSource:arbiter:)`, builds `RenderRequest`s with the same expected `RenderKey` rule as `PlaybackCoordinator`, consumes `.rendered` events, updates the corresponding utterance's duration/timings/audio ref, and calls `store.saveChapter` only for changed chapters. It stops/replans remaining jobs if cancellation, expiry, unsafe device, or cache-full arrives.
5. Writes `Date()` to `StorageModel.lastPrepareRunKey` only if at least one utterance was durably saved; then returns document IDs, rendered count, prepared playback seconds, and a stop reason.

`StorageModel` gains `recordPrepareRun(_:)` and `refresh()` already reads the same key. After every foreground or background result, call `await storage.refresh()` and `await libraryModel.refresh()`, so Queue's existing positive check only turns on when fully rendered and Storage's prepared/last-run labels update without relaunch.

- [ ] **Step 4: Register and schedule BackgroundTasks correctly**

Add to the host target's generated plist properties:

```yaml
UIBackgroundModes: [audio, processing]
BGTaskSchedulerPermittedIdentifiers: [com.t2s.reader.prepare]
```

`PrepareTask` owns `static let identifier = "com.t2s.reader.prepare"`. `T2SReaderApp.init()` calls `PrepareTask.register()` before SwiftUI builds a scene. Registration casts only after checking `task is BGProcessingTask`, makes a cancellable `Task`, sets `task.expirationHandler` before starting work, and completes exactly once:

```swift
static func schedule() {
    let request = BGProcessingTaskRequest(identifier: identifier)
    request.requiresExternalPower = true
    request.requiresNetworkConnectivity = false
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do { try BGTaskScheduler.shared.submit(request) }
    catch { Logger.prepare.error("Prepare scheduling failed: \(error.localizedDescription, privacy: .public)") }
}
```

The launch handler uses a fresh app-group `AppEnvironment`/`PrepareRunner` rather than a SwiftUI view. On expiry it cancels the runner, saves already-completed chapters, schedules the next request, and reports `success: false`; on normal completion it schedules the next opportunity and reports success only for `.completed`/`.budgetExhausted`, not unsafe-device or storage-full. The app schedules on launch/active and whenever it enters background while on power; a foreground runner starts only when charging and idle (not playing) and `DeviceMonitor` changes should cancel it immediately on unsafe state. Do not use a `UIBackgroundTask` as a substitute for `BGProcessingTask`.

- [ ] **Step 5: Verify code paths, then the device-only path**

Run:

```bash
swift test --filter "RenderArbiterTests|PrepareRunnerTests|RenderPolicyTests|StorageModelTests"
scripts/build-app.sh
```

Expected: all selected tests and simulator build pass. The simulator cannot validate real background processing.

On device: choose each 1 h/3 h/8 h/Everything option, background while charging, and inspect Storage for prepared time and last run. In Xcode, schedule then simulate launch with:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.t2s.reader.prepare"]
```

During a long Prepare, start playback and verify it receives the next render slot after at most the in-flight utterance; unplug, enable Low Power Mode, and raise thermal state where possible to ensure cancellation. Overnight reliability/runtime remains the Plan 0 §7.7 physical-device finding, not a simulator claim.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SCore Sources/T2SAudio Sources/T2SApp Tests App
git commit -m "App: multi-document Prepare runner and BGProcessingTask"
```

---

### Task 4: BYO-key HTTP voice behind `SynthesisEngine`

**Files:**
- Create: `Sources/T2SAudio/HTTPVoiceEngine.swift`, `Sources/T2SAudio/RoutedEngine.swift`, `Tests/T2SAudioTests/HTTPVoiceEngineTests.swift`, `Tests/T2SAudioTests/RoutedEngineTests.swift`
- Create: `Sources/T2SApp/Preferences/CloudVoiceSettings.swift`, `Sources/T2SApp/Preferences/CloudVoiceCatalog.swift`, `Tests/T2SAppTests/CloudVoiceSettingsTests.swift`
- Create: `App/T2SReader/System/KeychainSecretStore.swift`, `App/T2SReader/Preferences/CloudVoicesPage.swift`
- Modify: `Sources/T2SAudio/PlaybackCoordinator.swift`, `Sources/T2SApp/Preferences/VoiceCatalog.swift`, `Sources/T2SApp/Storage/VoiceChangeModel.swift`, `App/T2SReader/AppEnvironment.swift`, `App/T2SReader/Preferences/PreferencesPage.swift`, `App/project.yml`, `README.md`

**Interfaces:**
- Consumes: `SynthesisEngine`, `SynthesisRequest`, `RenderKey`, `URLSession`, Keychain Services, `VoiceCatalog`, `VoiceChangeModel`, and `PlayerModel.renderError`.
- Produces: `HTTPVoiceConfiguration`, `HTTPVoiceEngine`, `HTTPVoiceError`, `RequestRateLimiter`, `SecretStoring`, `CloudVoiceSettings`, `CloudVoiceCatalog`, and `RoutedEngine`.

- [ ] **Step 1: Write failing deterministic HTTP/config tests**

Use a URLProtocol-backed `URLSessionConfiguration.ephemeral` in the engine tests; no real service/key is permitted in tests.

```swift
@Suite struct HTTPVoiceEngineTests {
    @Test func postsBearerKeyAndDecodesPCMResponse() async throws {
        let session = TestURLSession.responding(status: 200, json: """
        {"audio":"AAAAAA==","sample_rate":24000,"word_timings":[]}
        """)
        let engine = HTTPVoiceEngine(configuration: .init(endpoint: URL(string: "https://voice.example/v1/audio/speech")!,
                                                          model: "user-model", requestRatePerMinute: 60),
                                     key: { "secret" }, session: session)
        let result = try await engine.synthesize(.init(spoken: "Hello", voiceID: "cloud:v1:voice"))
        #expect(result.audio.sampleRate == 24_000 && result.audio.samples.isEmpty)
        #expect(TestURLSession.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test func statusAndMissingKeySurfaceActionableErrors() async {
        let missing = HTTPVoiceEngine(configuration: .example, key: { nil }, session: .shared)
        await #expect(throws: HTTPVoiceError.self) { try await missing.synthesize(.init(spoken: "x", voiceID: "cloud:v1:v")) }
        let rejected = HTTPVoiceEngine(configuration: .example, key: { "x" }, session: TestURLSession.responding(status: 429, json: "{\"error\":\"slow down\"}"))
        await #expect(throws: HTTPVoiceError.self) { try await rejected.synthesize(.init(spoken: "x", voiceID: "cloud:v1:v")) }
    }
}
```

`CloudVoiceSettingsTests` must prove that endpoint/model/voice/rate persist in an isolated defaults suite, key text does not appear in defaults, and `voiceID` changes when any non-secret rendering-affecting setting changes.

Run: `swift test --filter "HTTPVoiceEngineTests|RoutedEngineTests|CloudVoiceSettingsTests"`

Expected: compile failures.

- [ ] **Step 2: Define the small, documented generic contract**

This is a **generic OpenAI-compatible PCM adapter**, not a claim that Alibaba, Replicate, and DeepInfra have identical APIs. The Cloud Voices page labels the required contract and lets advanced users point an endpoint/proxy at it:

```http
POST <endpoint>
Authorization: Bearer <key>
Content-Type: application/json

{"model":"<model>","input":"<spoken>","voice":"<provider voice>",
 "response_format":"pcm_f32le","sample_rate":24000,"timestamps":"word"}
```

The accepted response is JSON `{ audio: base64 little-endian Float32 mono PCM, sample_rate: 24000, word_timings: [{start,end,start_utf16,end_utf16}] }`. Word timings may be absent; validate monotonic times/ranges and return `[]` if absent so the existing highlighter degrades safely. Reject other sample rates, NaN samples, malformed base64, non-2xx responses, and >10 MiB replies. This exact contract keeps `T2SAudio` independently testable and avoids silently decoding arbitrary attacker-controlled media.

`HTTPVoiceConfiguration` has HTTPS endpoint, model, default provider voice, request-rate-per-minute (1…120), and a public non-secret `fingerprint` computed from canonical endpoint/model/voice/format/version. `HTTPVoiceError` has `.notConfigured`, `.missingKey`, `.invalidConfiguration`, `.rateLimited(retryAfter:)`, `.server(status:message:)`, `.malformedResponse`, and `.transport(String)` with user-safe descriptions.

The request/response core is intentionally small and has no provider-specific code paths:

```swift
// Sources/T2SAudio/HTTPVoiceEngine.swift
public final class HTTPVoiceEngine: SynthesisEngine, @unchecked Sendable {
    public let engineID = "http-voice-v1"
    private let configuration: HTTPVoiceConfiguration
    private let key: @Sendable () -> String?
    private let session: URLSession
    private let limiter: RequestRateLimiter

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        guard let key = key(), !key.isEmpty else { throw HTTPVoiceError.missingKey }
        try await limiter.wait()
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(WireRequest(model: configuration.model, input: request.spoken,
                                                                    voice: CloudVoiceID.parse(request.voiceID)?.voice ?? configuration.voice,
                                                                    responseFormat: "pcm_f32le", sampleRate: 24_000, timestamps: "word"))
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw HTTPVoiceError.transport("No HTTP response.") }
            if http.statusCode == 429 {
                let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                await limiter.deferUntil(seconds: seconds)
                throw HTTPVoiceError.rateLimited(retryAfter: seconds)
            }
            guard (200...299).contains(http.statusCode) else {
                throw HTTPVoiceError.server(status: http.statusCode, message: Self.safeServerMessage(data))
            }
            let wire = try JSONDecoder().decode(WireResponse.self, from: data)
            guard wire.sampleRate == 24_000, let bytes = Data(base64Encoded: wire.audio), bytes.count <= 10 * 1024 * 1024,
                  bytes.count.isMultiple(of: MemoryLayout<UInt32>.size) else { throw HTTPVoiceError.malformedResponse }
            let samples: [Float] = stride(from: 0, to: bytes.count, by: 4).map {
                Float(bitPattern: UInt32(littleEndian: bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: $0, as: UInt32.self) }))
            }
            return SynthesisResult(audio: PCMAudio(sampleRate: 24_000, samples: samples), wordTimings: try Self.timings(wire.wordTimings, text: request.spoken, duration: Double(samples.count) / 24_000))
        } catch let error as HTTPVoiceError { throw error }
        catch { throw HTTPVoiceError.transport(error.localizedDescription) }
    }
}
```

Use an indexed closure rather than reusing `$0` inside the nested `withUnsafeBytes` in the checked-in implementation (shown as `offset` below) so the decoder is unambiguous under Swift 6:

```swift
let samples = stride(from: 0, to: bytes.count, by: 4).map { offset in
    let bits: UInt32 = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    return Float(bitPattern: UInt32(littleEndian: bits))
}
```

- [ ] **Step 3: Implement rate limiting, routing, and structural cache identity**

`RequestRateLimiter` is an actor with injected clock/sleeper; it spaces starts by `60 / rpm`, honours `Retry-After` for a 429 response, and never sleeps the main actor. `HTTPVoiceEngine` is `Sendable`, owns the limiter, obtains the key only immediately before a request, uses `URLSession.data(for:)`, and clears local `Data` after decoding. It never logs request headers/body/key.

`KeychainSecretStore` uses a generic-password item with service `com.t2s.reader.cloud-voice`, account `default`, and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. `save(_:)` does update-or-add; blank deletes; `load()` returns a UTF-8 string; errors are surfaced to the settings page. Add an in-memory `SecretStoring` fake for UI/model tests. The extension never receives this dependency.

```swift
// App/T2SReader/System/KeychainSecretStore.swift
func save(_ value: String) throws {
    let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    if value.isEmpty { let status = SecItemDelete(query as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }; return }
    let data = Data(value.utf8)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
    if status == errSecItemNotFound {
        var add = query; add[kSecValueData] = data; add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw KeychainError.addFailed }
    } else if status != errSecSuccess { throw KeychainError(status) }
}

func load() throws -> String? {
    let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                                  kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw KeychainError(status) }
    return value
}
```

Add a `RoutedEngine` whose fixed `engineID` is `"routed-v1"`: `system:<identifier>` routes to `SystemSpeechEngine`; `cloud:<fingerprint>:<voice>` routes only when settings' current fingerprint matches and the Keychain has a key; unknown/mismatched values fail clearly. Because the complete routed ID is already `SynthesisRequest.voiceID`, the existing `RenderKey` produces distinct bytes for any cloud endpoint/model/voice change without exposing a secret. Modify coordinator loading to compare expected keys as in Task 1; do not trust an old `audioRef` after a route changes.

When Cloud settings change, show the existing voice-change destructive warning for the selected document before applying its new routed voice. The global default applies only when a document has no override; an existing cached `audioRef` whose expected key differs is re-rendered, never played. Surface cloud configuration/test errors in `CloudVoicesPage`, and render failures through existing `PlayerModel.renderError` / inline destructive text; do not hide a 401/429 behind silence alone.

- [ ] **Step 4: Replace the placeholder with the Cloud Voices page**

`PreferencesPage` replaces `row("Bring your own key", subtitle: "Coming soon")` with a `NavigationLink` to `CloudVoicesPage`. The page has endpoint, model, provider-voice, request-rate, and password-style API-key fields; Save / Remove key / Test voice actions; an explicit "Requests and charges go directly to your provider" caption; active route status; and inline error/result. The save path validates HTTPS and a nonempty model/voice before it can enable the route. Do not add a provider logo, account flow, analytics, or a network call without the user's Test/Play action.

`AppEnvironment` constructs one `CloudVoiceSettings`, host-only keychain store, `HTTPVoiceEngine`, and router; it injects the router into both `PlaybackCoordinator` and `PrepareRunner`. `CloudVoiceCatalog` appends only a configured cloud option to the system/Kokoro catalog and uses its routed stable ID. Update `docs/licenses.md` only if a new package is added (none is needed for this HTTP adapter).

- [ ] **Step 5: Verify**

Run:

```bash
swift test --filter "HTTPVoiceEngineTests|RoutedEngineTests|CloudVoiceSettingsTests|RenderKeyTests"
swift test
scripts/build-app.sh
```

Expected: all tests pass and no fixture/log contains `secret`, `Authorization`, or a user key. On device, test with a deliberately invalid key (clear actionable error), a local/dev compliant endpoint with a test key, 429/Retry-After, airplane mode, a voice/configuration change after audio exists, and key removal. Inspect device backup/Preferences output to confirm only non-secret settings persist.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SAudio Sources/T2SApp Tests App README.md docs/licenses.md
git commit -m "App: BYO-key HTTP cloud voice engine"
```

---

### Task 5: Kokoro built-in engine — **GATED on Plan 0 spike findings (§7.2–§7.5)**

**Do not begin this task** until `spikes/findings/` contains accepted results for §§7.1–§7.5 and §7.7, the spec contains their `RESOLVED` lines, and the license audit is green. There are currently no such findings beyond the template.

**Files:**
- Create: `Sources/T2SAudio/KokoroEngine.swift`, `Sources/T2SAudio/KokoroTokenTimingMapper.swift`, `Tests/T2SAudioTests/KokoroEngineTests.swift`, `Tests/T2SAudioTests/KokoroTokenTimingMapperTests.swift`
- Modify: `Package.swift`, `App/project.yml`, `App/T2SReader/AppEnvironment.swift`, `Sources/T2SAudio/RoutedEngine.swift`, `Sources/T2SApp/Preferences/VoiceCatalog.swift`, `scripts/check-licenses.sh`, `docs/licenses.md`, `.gitignore`
- Create/Modify: `App/T2SReader/Preferences/VoiceListPage.swift` (create from the Plan 4b voice-list surface if not yet merged; otherwise extend it for Kokoro voices)
- Create/update: model-download script and non-committed resource directory only as determined by findings; `spikes/findings/*`, design spec §7/§3.6/§11

**Interfaces:**
- Consumes (the Plan 0 harness pins, subject to re-verification at the selected version): `KokoroTTS(modelPath:g2p: .misaki)`, `generateAudio(voice:language:text:speed:) -> ([Float], [MToken]?)`, `KokoroTTS.Constants.samplingRate`, `MToken.text`, `whitespace`, `start_ts`, `end_ts`, and `NpyzReader` voice embeddings.
- Produces: `KokoroEngine: SynthesisEngine`, `KokoroVoiceCatalog`, validated `WordTiming` mapping, selected runtime resource policy, and a `RoutedEngine` default that prefers Kokoro but explicitly falls back to `SystemSpeechEngine` when model load is unavailable.

- [ ] **Step 1: Turn Plan 0 findings into implementation constants before tests**

Create `KokoroRuntimeDecision` from the findings: package versions/commit, model checksum, runtime (MLX or another accepted runtime), non-Pro measured RTF, derived `RateLimits` threshold, memory/cache limits, and whether background/idle execution is permitted. This value contains no guessed numbers. Add a test that rejects missing checksum/decision and a fixture-driven timing mapper test using the Plan 0 captured token data.

Run: `swift test --filter "KokoroEngineTests|KokoroTokenTimingMapperTests"`

Expected: failing tests until the selected runtime adapter and committed non-device fixtures exist. Do not manufacture a passing fixture or assume timestamps are words.

- [ ] **Step 2: Add only the approved packages and resource acquisition**

Add `kokoro-ios` and MisakiSwift at the exact Plan 0-approved versions to the root package/app package graph. Add the model/voice resource downloader with SHA-256 verification; model weights and voice `.npz` are gitignored, never fetched at runtime, and are bundled only after licensing/cache-size decisions are recorded. Run `swift package show-dependencies`, update `docs/licenses.md`, and require `scripts/check-licenses.sh` to remain green before compiling app code.

- [ ] **Step 3: Implement `KokoroEngine` and timing mapping**

`KokoroEngine` serializes model load and generation behind an actor/private serial executor because the MLX objects are not `Sendable`. It loads one checked model and selected voice embedding, calls `generateAudio`, verifies its native sample rate against the recorded decision, and returns `PCMAudio(sampleRate:samples:)`. `KokoroTokenTimingMapper` consumes only tokens with a nonempty lexical UTF-16 contribution and valid nondecreasing timestamps, maps them through the exact normalized spoken text, clamps ends to audio duration, and returns `[]` when alignment cannot be proven. It never invents word times from character positions when the runtime claims to provide them.

`engineID` includes `kokoro-<model-checksum-prefix>-<runtime>-<g2p-version>`; a selected Kokoro voice has `kokoro:<same identity>:<voice-name>`. The router chooses Kokoro at configuration time, not after a partially rendered utterance. If the model fails to load, route the whole document to `system:<voice>` before planning, so its render keys identify the actual fallback output.

- [ ] **Step 4: Apply every required finding explicitly**

| Plan 0 finding | What it changes in this task |
|---|---|
| §7.1 MisakiSwift coverage + license audit | Confirms English-only voice catalog and exact G2P dependency/license. A license failure or unacceptable coverage blocks shipping; do not substitute espeak-ng. |
| §7.2 sustained inference under `audio` | Pass enables normal background play-ahead. Fail changes `RoutedEngine`/runner policy to render only foreground/ready audio and adds the offline-prepared product fallback before release. |
| §7.3 runtime RTF, thermals, battery | Selects MLX/CoreML path, model limits, measured RTF, and the exact disabled-rate threshold; replaces illustrative §3.6 numbers. |
| §7.4 word timing accuracy | Pass enables `MToken.start_ts/end_ts` mapping. Constant/drifting error selects the documented correction/ONNX fallback; unavailable/incorrect timings block Kokoro read-along rather than shipping false highlights. |
| §7.5 non-Pro memory | Sets resource/cache/concurrency limits and any device exclusion. A jetsam-risk result blocks the runtime. |
| §7.7 `BGProcessingTask` | Pass enables Task 3's idle Kokoro Prepare route. Fail keeps foreground/on-charge/background-playback Prepare only; Task 3's UI remains accurate. |

- [ ] **Step 5: Verify on both specified physical devices**

Run `swift test`, `scripts/check-licenses.sh`, and `scripts/build-app.sh` first. Then run Plan 0's 50-sentence corpus, timing audit, memory/thermal/battery protocol, audio-background protocol, and three-night `BGProcessingTask` protocol on one Pro and one non-Pro device. Run a short real EPUB through import → Kokoro → AAC cache → read-along → lock screen → interruption/reset → Prepare. Record exact model/iOS/commit/checksum in the findings; a simulator/build success does not verify MLX or background inference.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/T2SAudio Sources/T2SApp Tests App scripts docs spikes .gitignore
git commit -m "Audio: add Kokoro engine after device spike decisions"
```

#### Task 5 adjustments approved 2026-09-03 (supersede the file list above where they differ)

Findings so far: §7.1 accepted (`spikes/findings/2026-09-03-g2p-coverage.md`); §7.3/§7.5 on the
iPhone 11 Pro show kokoro-ios/MLX cannot run below Apple GPU family 7 (A14)
(`2026-09-03-runtime-benchmark.md`). The 17 Pro numbers (§7.2–§7.5, §7.7) are still pending, so
this task ships the engine, probe, route, and fallback now and takes its constants later.

1. **Location.** Kokoro lives in a new `Packages/T2SKokoro` (platforms iOS 18 and macOS 15),
   mirroring `Packages/T2SReadium`: depends on the root `T2S` (`T2SCore`), `kokoro-ios` 1.0.11,
   `MLXUtilsLibrary` 0.0.6; wired into `App/project.yml` like T2SReadium. Reason: MLX needs its
   compiled Metal library, which `swift test` and the iOS simulator cannot provide; the root
   package stays `swift test`-clean for CI. Tests run with `scripts/test-kokoro.sh`
   (`xcodebuild test -destination 'platform=macOS'`) — MLX runs on Apple-silicon Macs, so
   `KokoroEngine` is exercised end to end with the real model on the Mac. Tests that need the
   model files are `.enabled(if:)` their presence, like the voice tests.
2. **Engine.** `KokoroEngine: SynthesisEngine` is an actor holding one loaded model and the
   selected voice embedding; `generateAudio` → `PCMAudio` at 24 kHz (verify
   `KokoroTTS.Constants.samplingRate`). `engineID = "kokoro-<checksum8>-mlx-misaki1.0.6"`; voice
   IDs `kokoro:<engineID>:<voice>`.
3. **Availability gate at configuration time.** `KokoroAvailability` requires
   `MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7)`, model + voices present with the
   recorded SHA-256, and a complete `KokoroRuntimeDecision`. Any failure routes the whole
   document to `system:<voice>` before planning (never mid-utterance).
4. **Route and catalog.** `RoutedEngine` gains the `kokoro:` prefix beside `system:` and the cloud
   IDs; `KokoroVoiceCatalog` lists the bundled English voices under "Kokoro (beta)" in
   Preferences → Voices. The default voice stays `system` until §7.2 passes on the 17 Pro.
5. **Timings.** `KokoroTokenTimingMapper` maps `MToken.start_ts/end_ts` but returns `[]` until its
   fixture test exists; the fixture is the 17 Pro CSV `timing` rows. Until then Kokoro documents
   use the estimated timeline.
6. **Constants.** `KokoroRuntimeDecision` rejects missing values (measured non-Pro RTF, derived
   rate threshold, memory limits); a `DEBUG`-only override enables the route for development on
   the 17 Pro before the numbers land.
7. **Resources.** `scripts/fetch-kokoro-model.sh` downloads the weights and `voices.npz` with the
   SHA-256 from `spikes/README.md` into a git-ignored resource directory; bundle-vs-download for
   shipping stays deferred.
8. **From §7.1.** `NumberWords` joins compound numbers with a space, with a test.

Order of work on branch `plan-5-task-5-kokoro`, tests first and one commit each: package skeleton
and fetch script → `KokoroEngine` synthesizing one sentence on the Mac → availability probe and
decision type → route, catalog, Preferences → normalizer fix → app wiring and a simulator run
proving the fallback → a build for the 17 Pro.

---

### Task 6: Documentation, roadmap, and final manual pass

**Files:**
- Modify: `README.md`, `docs/HANDOFF.md`, `docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md`, `docs/superpowers/specs/2026-09-01-t2s-reader-design.md`, `docs/licenses.md`

**Interfaces:**
- Consumes: accepted Plan 0 findings, implementation decisions from Tasks 1–5, test/build/physical-device report.
- Produces: an accurate Plan 5/Plan 6 hand-off, roadmap status, documented cloud-data contract, runtime/license provenance, and a reproducible manual validation checklist.

- [ ] **Step 1: Run the whole automated suite**

```bash
swift test
scripts/check-licenses.sh
scripts/build-app.sh
scripts/test-readium.sh
```

Expected: every applicable command exits 0. If Kokoro is still gated, record Task 5 as blocked by missing findings and do not claim the plan is fully implemented; all non-gated work can still be documented accurately.

- [ ] **Step 2: Complete the device manual matrix**

Record model/iOS and results for: Now Playing/Lock Screen/Control Center/AirPlay; wired and Bluetooth route changes; interruption and `mediaServicesWereReset`; all share payload types/errors; app-group hand-off; charging/unplug/Low-Power/thermal Prepare stops; `BGProcessingTask` debugger simulation plus overnight evidence; cloud missing key/401/429/network/config change; and, only after the gate opens, all Plan 0 Kokoro metrics. A failing scenario is a fix round, not a hand-off footnote.

- [ ] **Step 3: Update written project state**

Update README's app section with Share Extension setup, app-group signing prerequisite, Prepare's opportunistic nature, cloud contract/privacy/key removal, and model-resource setup only when Kokoro is unblocked. Update the roadmap: Plan 5 is `done` only when every non-gated task plus accepted Kokoro finding/task is complete; otherwise say `implemented except gated Kokoro pending Plan 0`. Update `HANDOFF.md` with current tests/device evidence, the selected engine/runtime/RTF if known, and Plan 6 next. Update spec §3.6/§7/§11 only with measured Plan 0 results, never planned figures. Keep licenses complete.

- [ ] **Step 4: Commit**

```bash
git add README.md docs
git commit -m "Docs: Plan 5 audio lifecycle, sharing, Prepare, and engines"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| §1.1 no backend/accounts; premium voices are BYO-key | 4, 6 |
| §2.1 article Share sheet → Readability → minimal EPUB; source formats | 2 |
| §2.2 Lock Screen/Control Center/AirPlay, Share Extension, cloud engine | 1, 2, 4 |
| §2.4.5 Queue prepared check, Storage prepared amount/last run, Cloud voices Preferences | 2, 3, 4 |
| §3.4 one-document rendering and cache behaviour | 1, 3, 4, 5 |
| §3.4.1 tier-3 order, budget, power/thermal guards, visible state, BG idle path | 3, 5 |
| §3.5 AVAudioEngine session, Now Playing, remote commands, long-form audio | 1 |
| §3.6 measured engine RTF, sustainable rates, no silent rate drop | 1, 4, 5 |
| §3.7.1 backend remains optional; §3.7.3 cache re-derivable; §3.7.5 license ratchet | 2, 4, 5, 6 |
| §5 render key identity and voice/engine cache invalidation | 1, 3, 4, 5 |
| §6 per-utterance failure fallback and model-load fallback | 2, 4, 5 |
| §7.1–§7.5 selected Kokoro runtime, G2P, timings, memory, thermals | 5, 6 |
| §7.7 BGProcessingTask feasibility and fallback | 3, 5, 6 |
| §9 step 7 Kokoro; step 8 Share Extension; step 9 Now Playing, cloud engine, Prepare | 1–5 |

Hand-off to Plan 6: CloudKit sync remains behind `SyncProvider`; the new app-group store must be the only local source. Live Activity/App Intents/Spotlight may consume `NowPlayingSnapshot`/`PlayerModel` but must not gain a second playback owner. CarPlay stays deferred even though MediaPlayer remote controls now work.
