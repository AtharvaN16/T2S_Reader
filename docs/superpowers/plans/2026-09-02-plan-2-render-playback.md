# Plan 2: Render and Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a phase-1 `Timeline` into audible, resumable playback: a synthesis-engine protocol with a deterministic fake, a render-key cache, the tiered render policy, a serial render scheduler, an `AVAudioEngine` player with pitch-corrected rate, and a `PlaybackCoordinator` that owns the playhead and publishes highlights.

**Architecture:** Everything engine-agnostic lives in `T2SCore` under `Sources/T2SCore/Render/` (protocols, `FakeEngine`, `RenderKey`, codec and store protocols with in-memory and file stores, `RenderPolicy`, `RenderScheduler`) plus `TimeIndex` under `Timeline/`. A new target `T2SAudio` depends on `T2SCore` and holds everything that touches AVFoundation: `AACCodec`, `AudioPlayer`, and `PlaybackCoordinator`. The coordinator is the only object that knows both the timeline and the player; the scheduler executes `RenderRequest`s it is handed and knows nothing about timelines. Tests drive the scheduler with `FakeEngine` + `InMemoryAudioStore` + `ManualTimeSource`, the player with `AVAudioEngine` manual rendering, and the coordinator with a `FakePlayer`.

**Tech Stack:** Swift 6 (language mode 6), SwiftPM, Swift Testing, Foundation, CryptoKit (`RenderKey`), AVFoundation (`T2SAudio` only), Observation (`@Observable` coordinator). macOS 15 for tests, iOS 18 deployment.

**Spec:** `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (rev 5). Sections §3.2, §3.3, §3.4, §3.4.1, §3.5, §3.6, §5, §6, §8, §9 step 5.

## Global Constraints

- The runtime playhead is `Playhead(utteranceIndex, offset)`; it is index-anchored so that replacing an estimated duration with an actual one never moves it (spec §3.2). Absolute seconds are derived, display-only values.
- The render-ahead window is denominated in **playback-seconds at the current rate**: window = `windowSeconds × rate` (spec §3.4, §3.6). Changing rate resizes it.
- The scheduler is **serial** and runs off the main actor; a seek **flushes** pending work; it **idles** when no job is eligible (spec §3.4).
- Render tiers and their order are fixed by spec §3.4.1: play-ahead, prime (first ~30 s of a newly imported document), prepare (only while charging; continue-document first, then queue order; budget in playback-minutes, default 3 h; stops on unplug, thermal `.serious`, Low Power Mode, or a full cache), manual (whole document, any power state). Play-ahead is never preempted.
- **One document renders at a time**; starting playback of a second document preempts the first, whose completed utterances are retained (spec §3.4).
- Rendered audio is cache, never truth. Its key is a hash over `documentID · utteranceIndex · voiceID · engineID · normalizerVersion · segmenterVersion` (spec §5), and the versions are read from the **`Timeline`** that produced the utterances, never from `Versions`.
- Production audio is AAC ~32 kbps mono 24 kHz; raw PCM is never persisted (spec §3.4). The raw codec exists for tests only.
- LRU eviction against a configurable cache cap (spec §3.4). Disk full: pause rendering, evict LRU, surface the storage manager (spec §6).
- Synthesis failure for one utterance: log, insert 200 ms of silence, continue (spec §6). Underrun: pause with a visible "catching up" state; never stutter (spec §3.6). Playhead past end: clamp, mark finished (spec §6).
- Measured RTF is a rolling average reported by the scheduler; rates whose sustained demand `RTF × rate` exceeds the safety factor 0.8 are unavailable (spec §3.6).
- Player graph: `AVAudioEngine → AVAudioPlayerNode → AVAudioUnitTimePitch → mainMixer`, buffers scheduled per utterance for gapless playback, rate 0.5x–4x with pitch correction, playhead from `playerTime` (spec §3.5).
- `Position` persistence goes through a `PlayheadStore` protocol; the coordinator saves on pause, seek, utterance boundary, and finish.
- Every public type is `Sendable` or `@MainActor`; no `nonisolated(unsafe)`. Swift Testing; run a suite with `swift test --filter <SuiteName>`.
- Commit after every task with the message given in the task.

---

### Task 1: `T2SAudio` target and package layout

**Files:**
- Modify: `Package.swift`
- Create: `Sources/T2SAudio/T2SAudio.swift`
- Create: `Tests/T2SAudioTests/T2SAudioSmokeTests.swift`

**Interfaces:**
- Produces: library product `T2SAudio` depending on `T2SCore`; test target `T2SAudioTests`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/T2SAudioTests/T2SAudioSmokeTests.swift
import Testing
import T2SCore
@testable import T2SAudio

@Suite struct T2SAudioSmokeTests {
    @Test func linksAgainstCore() {
        #expect(T2SAudio.coreSchemaVersion == Versions.schema)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter T2SAudioSmokeTests`
Expected: FAIL, `error: no such module 'T2SAudio'`.

- [ ] **Step 3: Update the manifest and add the module file**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "T2S",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "T2SCore", targets: ["T2SCore"]),
        .library(name: "T2SAudio", targets: ["T2SAudio"]),
    ],
    targets: [
        .target(name: "T2SCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "T2SAudio", dependencies: ["T2SCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
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
    ]
)
```

```swift
// Sources/T2SAudio/T2SAudio.swift
import T2SCore

/// AVFoundation-backed playback for T2SCore timelines.
public enum T2SAudio {
    /// The T2SCore schema this build of T2SAudio was compiled against.
    public static let coreSchemaVersion = Versions.schema
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter T2SAudioSmokeTests`
Expected: 1 test passed.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/T2SAudio Tests/T2SAudioTests
git commit -m "Add T2SAudio target"
```

---

### Task 2: `TimeIndex` and `Playhead` helpers

**Files:**
- Create: `Sources/T2SCore/Timeline/TimeIndex.swift`
- Modify: `Sources/T2SCore/Model/Playhead.swift`
- Create: `Tests/T2SCoreTests/TimeIndexTests.swift`

**Interfaces:**
- Produces:
  - `extension Playhead: Comparable` (by `utteranceIndex`, then `offset`).
  - `struct TimeIndex: Sendable { init(_ timeline: Timeline); utteranceCount; totalDuration; startTime(ofUtterance:); duration(ofUtterance:); time(at: Playhead) -> TimeInterval; playhead(atTime:) -> Playhead; advance(_:by:) -> Playhead; clamp(_:) -> Playhead }`, built once from a timeline (O(n)) and rebuilt by the owner when durations change; all lookups O(log n) or O(1).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/TimeIndexTests.swift
import Testing
@testable import T2SCore

@Suite struct TimeIndexTests {
    let t = makeTimeline([
        [makeUtterance("a", seconds: 1), makeUtterance("b", seconds: 2)],
        [makeUtterance("c", seconds: 3, href: "ch2.xhtml"), makeUtterance("d", seconds: 4, href: "ch2.xhtml")],
    ])

    @Test func matchesTimelineStartTimes() {
        let ix = TimeIndex(t)
        #expect(ix.utteranceCount == 4)
        #expect(ix.totalDuration == 10)
        for i in 0...4 { #expect(ix.startTime(ofUtterance: i) == t.startTime(ofUtterance: i)) }
        #expect(ix.duration(ofUtterance: 2) == 3)
    }

    @Test func timeAndPlayheadRoundTrip() {
        let ix = TimeIndex(t)
        #expect(ix.time(at: Playhead(utteranceIndex: 2, offset: 1.5)) == 4.5)
        #expect(ix.playhead(atTime: 4.5) == Playhead(utteranceIndex: 2, offset: 1.5))
        #expect(ix.playhead(atTime: 3.0) == Playhead(utteranceIndex: 2, offset: 0))     // boundary belongs to the next utterance
        #expect(ix.playhead(atTime: -1) == Playhead(utteranceIndex: 0, offset: 0))
        #expect(ix.playhead(atTime: 10) == Playhead(utteranceIndex: 3, offset: 4))      // clamped to the end
        #expect(ix.playhead(atTime: 99) == Playhead(utteranceIndex: 3, offset: 4))
    }

    @Test func advanceCrossesBoundaries() {
        let ix = TimeIndex(t)
        #expect(ix.advance(Playhead(utteranceIndex: 0, offset: 0.5), by: 1.0) == Playhead(utteranceIndex: 1, offset: 0.5))
        #expect(ix.advance(Playhead(utteranceIndex: 1, offset: 1.0), by: -2.0) == Playhead(utteranceIndex: 0, offset: 0))
        #expect(ix.advance(Playhead(utteranceIndex: 3, offset: 1.0), by: 100) == Playhead(utteranceIndex: 3, offset: 4))
        #expect(ix.clamp(Playhead(utteranceIndex: 9, offset: 0)) == Playhead(utteranceIndex: 3, offset: 4))
        #expect(ix.clamp(Playhead(utteranceIndex: 1, offset: 7)) == Playhead(utteranceIndex: 1, offset: 2))
    }

    @Test func emptyTimeline() {
        let ix = TimeIndex(makeTimeline([[]]))
        #expect(ix.utteranceCount == 0)
        #expect(ix.totalDuration == 0)
        #expect(ix.playhead(atTime: 5) == Playhead(utteranceIndex: 0, offset: 0))
    }

    @Test func playheadIsComparable() {
        #expect(Playhead(utteranceIndex: 1, offset: 9) < Playhead(utteranceIndex: 2, offset: 0))
        #expect(Playhead(utteranceIndex: 2, offset: 0.5) < Playhead(utteranceIndex: 2, offset: 1))
    }

    /// Spec §8: replacing an estimate with an actual never moves the playhead.
    @Test func actualDurationsNeverMoveThePlayhead() {
        var t = t
        let ph = Playhead(utteranceIndex: 2, offset: 1.5)
        let before = TimeIndex(t).time(at: ph)
        t[utterance: 0].duration = .actual(1.7)
        t[utterance: 1].duration = .actual(2.9)
        let after = TimeIndex(t).time(at: ph)
        #expect(ph == Playhead(utteranceIndex: 2, offset: 1.5))          // the playhead itself is untouched
        #expect(before == 4.5 && abs(after - 6.1) < 1e-9)                 // only the derived display time moved
        #expect(Highlighter.highlight(at: ph, in: t)?.utteranceIndex == 2)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter TimeIndexTests`
Expected: FAIL to compile, `cannot find 'TimeIndex' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Model/Playhead.swift  (append)
extension Playhead: Comparable {
    public static func < (a: Playhead, b: Playhead) -> Bool {
        a.utteranceIndex != b.utteranceIndex ? a.utteranceIndex < b.utteranceIndex : a.offset < b.offset
    }
}
```

```swift
// Sources/T2SCore/Timeline/TimeIndex.swift
import Foundation

/// Prefix sums over utterance durations at 1x. Build once per timeline revision; every lookup
/// is O(1) or O(log n), unlike `Timeline.startTime(ofUtterance:)` which is O(n) per call.
public struct TimeIndex: Hashable, Sendable {
    /// `starts[i]` is the start time of utterance `i`; `starts[count]` is the total duration.
    public let starts: [TimeInterval]

    public init(_ timeline: Timeline) {
        var s: [TimeInterval] = [0]
        s.reserveCapacity(timeline.utteranceCount + 1)
        var acc: TimeInterval = 0
        for ch in timeline.chapters {
            for u in ch.utterances {
                acc += u.duration.seconds
                s.append(acc)
            }
        }
        starts = s
    }

    public var utteranceCount: Int { starts.count - 1 }
    public var totalDuration: TimeInterval { starts[starts.count - 1] }

    public func startTime(ofUtterance i: Int) -> TimeInterval { starts[i] }
    public func duration(ofUtterance i: Int) -> TimeInterval { starts[i + 1] - starts[i] }

    public func time(at ph: Playhead) -> TimeInterval {
        let c = clamp(ph)
        return utteranceCount == 0 ? 0 : starts[c.utteranceIndex] + c.offset
    }

    /// The utterance whose span contains `t`; a boundary belongs to the utterance that starts there.
    public func playhead(atTime t: TimeInterval) -> Playhead {
        guard utteranceCount > 0 else { return Playhead(utteranceIndex: 0, offset: 0) }
        if t <= 0 { return Playhead(utteranceIndex: 0, offset: 0) }
        if t >= totalDuration { return Playhead(utteranceIndex: utteranceCount - 1, offset: duration(ofUtterance: utteranceCount - 1)) }
        var lo = 0, hi = utteranceCount - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= t { lo = mid } else { hi = mid - 1 }
        }
        return Playhead(utteranceIndex: lo, offset: t - starts[lo])
    }

    public func advance(_ ph: Playhead, by seconds: TimeInterval) -> Playhead {
        playhead(atTime: time(at: ph) + seconds)
    }

    /// Keeps the index inside the timeline and the offset inside its utterance. An index past the
    /// end snaps to the end of the timeline; a negative index snaps to its start.
    public func clamp(_ ph: Playhead) -> Playhead {
        guard utteranceCount > 0 else { return Playhead(utteranceIndex: 0, offset: 0) }
        if ph.utteranceIndex >= utteranceCount {
            return Playhead(utteranceIndex: utteranceCount - 1, offset: duration(ofUtterance: utteranceCount - 1))
        }
        if ph.utteranceIndex < 0 { return Playhead(utteranceIndex: 0, offset: 0) }
        let i = ph.utteranceIndex
        return Playhead(utteranceIndex: i, offset: max(0, min(ph.offset, duration(ofUtterance: i))))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter TimeIndexTests`
Expected: 6 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore Tests/T2SCoreTests/TimeIndexTests.swift
git commit -m "Add TimeIndex prefix sums and Playhead comparison"
```

---

### Task 3: `SynthesisEngine`, `PCMAudio`, and `FakeEngine`

**Files:**
- Create: `Sources/T2SCore/Render/PCMAudio.swift`
- Create: `Sources/T2SCore/Render/SynthesisEngine.swift`
- Create: `Sources/T2SCore/Render/TimeSource.swift`
- Create: `Sources/T2SCore/Render/FakeEngine.swift`
- Create: `Tests/T2SCoreTests/Render/FakeEngineTests.swift`

**Interfaces:**
- Produces:
  - `struct PCMAudio: Hashable, Sendable { static let defaultSampleRate = 24_000.0; sampleRate: Double; samples: [Float]; duration; static func silence(seconds:sampleRate:) }` (mono).
  - `struct SynthesisRequest: Hashable, Sendable { spoken: String; voiceID: String }`
  - `struct SynthesisResult: Hashable, Sendable { audio: PCMAudio; wordTimings: [WordTiming] }`
  - `enum SynthesisError: Error, Equatable { case failed(String) }`
  - `protocol SynthesisEngine: Sendable { var engineID: String { get }; func synthesize(_:) async throws -> SynthesisResult }`
  - `protocol TimeSource: Sendable { func now() -> TimeInterval }`, `struct SystemTimeSource`, `final class ManualTimeSource` with `advance(by:)` and `set(_:)`.
  - `actor FakeEngine: SynthesisEngine` producing silence of `spoken.utf16.count × secondsPerCharacter` seconds (rounded to whole samples, and the timings are computed from that exact duration) with proportional per-word timings; `fail(on:)` injects a failure for a given spoken text; `simulatedRTF` advances a `ManualTimeSource` by `RTF × audio seconds` per call so scheduler tests can measure RTF; `hold()` makes every subsequent `synthesize` wait until `release()` so tests can control interleaving; `requests` records every call.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Render/FakeEngineTests.swift
import Testing
@testable import T2SCore

@Suite struct FakeEngineTests {
    @Test func silenceOfKnownLengthWithWordTimings() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.1)
        let r = try await engine.synthesize(SynthesisRequest(spoken: "Hello big world", voiceID: "v"))
        #expect(r.audio.sampleRate == 24_000)
        #expect(r.audio.samples.count == 36_000)                         // 15 chars × 0.1 s × 24 kHz
        #expect(r.audio.samples.allSatisfy { $0 == 0 })
        #expect(r.wordTimings.map(\.spokenRange) == [0..<5, 6..<9, 10..<15])
        #expect(r.wordTimings.map(\.start) == [0.0, 0.6, 1.0])
        #expect(r.wordTimings.map(\.end) == [0.5, 0.9, 1.5])
        #expect(await engine.requests.count == 1)
    }

    @Test func failureInjection() async {
        let engine = FakeEngine()
        await engine.fail(on: "boom")
        await #expect(throws: SynthesisError.failed("boom")) {
            try await engine.synthesize(SynthesisRequest(spoken: "boom", voiceID: "v"))
        }
        _ = try? await engine.synthesize(SynthesisRequest(spoken: "fine", voiceID: "v"))
        #expect(await engine.requests.map(\.spoken) == ["boom", "fine"])
    }

    @Test func simulatedRTFAdvancesTheClock() async throws {
        let clock = ManualTimeSource()
        let engine = FakeEngine(secondsPerCharacter: 0.1, simulatedRTF: 0.5, timeSource: clock)
        _ = try await engine.synthesize(SynthesisRequest(spoken: "0123456789", voiceID: "v"))   // 1.0 s of audio
        #expect(clock.now() == 0.5)
    }

    @Test func silenceHelper() {
        let s = PCMAudio.silence(seconds: 0.2)
        #expect(s.samples.count == 4_800)
        #expect(s.duration == 0.2)
    }

    @Test func holdBlocksUntilReleased() async throws {
        let engine = FakeEngine()
        await engine.hold()
        let task = Task { try await engine.synthesize(SynthesisRequest(spoken: "x", voiceID: "v")) }
        await Task.yield()
        #expect(await engine.requests.isEmpty)                            // parked before recording
        await engine.release()
        _ = try await task.value
        #expect(await engine.requests.count == 1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter FakeEngineTests`
Expected: FAIL to compile, `cannot find 'FakeEngine' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Render/PCMAudio.swift
import Foundation

/// Mono PCM. The engine's native output; encoded before it is ever persisted (spec §3.4).
public struct PCMAudio: Hashable, Sendable {
    public static let defaultSampleRate: Double = 24_000
    public var sampleRate: Double
    public var samples: [Float]

    public init(sampleRate: Double = PCMAudio.defaultSampleRate, samples: [Float]) {
        self.sampleRate = sampleRate
        self.samples = samples
    }

    public var duration: TimeInterval { Double(samples.count) / sampleRate }

    public static func silence(seconds: TimeInterval, sampleRate: Double = PCMAudio.defaultSampleRate) -> PCMAudio {
        PCMAudio(sampleRate: sampleRate, samples: Array(repeating: 0, count: Int((seconds * sampleRate).rounded())))
    }
}
```

```swift
// Sources/T2SCore/Render/SynthesisEngine.swift
import Foundation

public struct SynthesisRequest: Hashable, Sendable {
    public var spoken: String
    public var voiceID: String
    public init(spoken: String, voiceID: String) {
        self.spoken = spoken
        self.voiceID = voiceID
    }
}

public struct SynthesisResult: Hashable, Sendable {
    public var audio: PCMAudio
    /// Offsets into `spoken`; times relative to the utterance start at 1x.
    public var wordTimings: [WordTiming]
    public init(audio: PCMAudio, wordTimings: [WordTiming]) {
        self.audio = audio
        self.wordTimings = wordTimings
    }
}

public enum SynthesisError: Error, Equatable, Sendable {
    case failed(String)
}

/// One implementation per backend (spec §3): Kokoro on-device, HTTP for BYO keys, Fake for tests.
public protocol SynthesisEngine: Sendable {
    /// Part of every render key (spec §5); change it when output would differ.
    var engineID: String { get }
    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult
}
```

```swift
// Sources/T2SCore/Render/TimeSource.swift
import Foundation

public protocol TimeSource: Sendable {
    func now() -> TimeInterval
}

public struct SystemTimeSource: TimeSource {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// A clock tests move by hand.
public final class ManualTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval

    public init(_ start: TimeInterval = 0) { current = start }

    public func now() -> TimeInterval { lock.withLock { current } }
    public func advance(by seconds: TimeInterval) { lock.withLock { current += seconds } }
    public func set(_ t: TimeInterval) { lock.withLock { current = t } }
}
```

```swift
// Sources/T2SCore/Render/FakeEngine.swift
import Foundation

/// Silence of a precisely known duration with synthetic word timings (spec §8).
public actor FakeEngine: SynthesisEngine {
    public nonisolated let engineID = "fake"
    public let secondsPerCharacter: TimeInterval
    /// When set, each call advances `timeSource` by `simulatedRTF × audio seconds`.
    public let simulatedRTF: Double?
    private let timeSource: ManualTimeSource?
    private var failures: Set<String> = []
    private var held = false
    private var parked: [CheckedContinuation<Void, Never>] = []
    public private(set) var requests: [SynthesisRequest] = []

    public init(secondsPerCharacter: TimeInterval = 0.05, simulatedRTF: Double? = nil, timeSource: ManualTimeSource? = nil) {
        self.secondsPerCharacter = secondsPerCharacter
        self.simulatedRTF = simulatedRTF
        self.timeSource = timeSource
    }

    public func fail(on spoken: String) { failures.insert(spoken) }

    /// Every later `synthesize` parks until `release()`.
    public func hold() { held = true }

    public func release() {
        held = false
        let waiting = parked
        parked.removeAll()
        waiting.forEach { $0.resume() }
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        while held { await withCheckedContinuation { parked.append($0) } }
        requests.append(request)
        if failures.contains(request.spoken) { throw SynthesisError.failed(request.spoken) }
        let rate = PCMAudio.defaultSampleRate
        let sampleCount = Int((Double(request.spoken.utf16.count) * secondsPerCharacter * rate).rounded())
        let seconds = Double(sampleCount) / rate                     // exact: what the audio really lasts
        if let rtf = simulatedRTF { timeSource?.advance(by: rtf * seconds) }
        let audio = PCMAudio(sampleRate: rate, samples: Array(repeating: 0, count: sampleCount))
        let n = max(1, request.spoken.utf16.count)
        let ns = request.spoken as NSString
        let words = Self.word.regex.matches(in: request.spoken, range: NSRange(location: 0, length: ns.length))
        let timings = words.map { m -> WordTiming in
            let r = m.range.location..<(m.range.location + m.range.length)
            return WordTiming(spokenRange: r,
                              start: seconds * Double(r.lowerBound) / Double(n),
                              end: seconds * Double(r.upperBound) / Double(n))
        }
        return SynthesisResult(audio: audio, wordTimings: timings)
    }

    private static let word = Pattern("\\S+")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter FakeEngineTests`
Expected: 5 tests passed. If `wordTimings.map(\.start)` fails on floating rounding, compare with a tolerance of 1e-9 rather than changing the model.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Render Tests/T2SCoreTests/Render
git commit -m "Add SynthesisEngine protocol, PCMAudio, TimeSource, and FakeEngine"
```

---

### Task 4: `RenderKey`

**Files:**
- Create: `Sources/T2SCore/Render/RenderKey.swift`
- Create: `Tests/T2SCoreTests/Render/RenderKeyTests.swift`

**Interfaces:**
- Produces: `struct RenderKey: Hashable, Sendable, Codable { rawValue: String (64 hex); init(documentID:utteranceIndex:voiceID:engineID:normalizerVersion:segmenterVersion:); init(rawValue:); fileName: String }`. `Utterance.audioRef` stores `rawValue`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Render/RenderKeyTests.swift
import Foundation
import Testing
@testable import T2SCore

@Suite struct RenderKeyTests {
    let doc = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    func key(index: Int = 3, voice: String = "af_heart", engine: String = "kokoro", norm: Int = 1, seg: Int = 1) -> RenderKey {
        RenderKey(documentID: doc, utteranceIndex: index, voiceID: voice, engineID: engine, normalizerVersion: norm, segmenterVersion: seg)
    }

    @Test func deterministic() {
        #expect(key() == key())
        #expect(key().rawValue.count == 64)
        #expect(key().rawValue.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(key().fileName == key().rawValue + ".audio")
    }

    @Test func everyInputChangesTheKey() {
        let base = key()
        #expect(key(index: 4) != base)
        #expect(key(voice: "am_adam") != base)
        #expect(key(engine: "http") != base)
        #expect(key(norm: 2) != base)
        #expect(key(seg: 2) != base)
        #expect(RenderKey(documentID: UUID(), utteranceIndex: 3, voiceID: "af_heart", engineID: "kokoro", normalizerVersion: 1, segmenterVersion: 1) != base)
    }

    @Test func roundTripsThroughRawValue() {
        #expect(RenderKey(rawValue: key().rawValue) == key())
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RenderKeyTests`
Expected: FAIL to compile, `cannot find 'RenderKey' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Render/RenderKey.swift
import CryptoKit
import Foundation

/// Filename of a rendered utterance (spec §5). Changing any input makes a new key, so a voice
/// or engine change invalidates the old audio structurally instead of serving it.
public struct RenderKey: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(documentID: UUID, utteranceIndex: Int, voiceID: String, engineID: String,
                normalizerVersion: Int, segmenterVersion: Int) {
        let material = [documentID.uuidString, String(utteranceIndex), voiceID, engineID,
                        String(normalizerVersion), String(segmenterVersion)].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(material.utf8))
        rawValue = digest.map { String(format: "%02x", $0) }.joined()
    }

    public var fileName: String { rawValue + ".audio" }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RenderKeyTests`
Expected: 3 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Render/RenderKey.swift Tests/T2SCoreTests/Render/RenderKeyTests.swift
git commit -m "Add RenderKey hash over the six cache inputs"
```

---

### Task 5: `AudioCodec` and `AudioStore` with LRU eviction

**Files:**
- Create: `Sources/T2SCore/Render/AudioCodec.swift`
- Create: `Sources/T2SCore/Render/AudioStore.swift`
- Create: `Sources/T2SCore/Render/InMemoryAudioStore.swift`
- Create: `Sources/T2SCore/Render/FileAudioStore.swift`
- Create: `Tests/T2SCoreTests/Render/AudioStoreTests.swift`

**Interfaces:**
- Produces:
  - `protocol AudioCodec: Sendable { identifier: String; encode(_:) throws -> Data; decode(_:) throws -> PCMAudio }`; `struct RawPCMCodec` (tests only: 8-byte little-endian sample rate then Float32 LE samples).
  - `struct AudioStoreStats: Hashable, Sendable { bytes; entries; capacityBytes }`, `enum AudioStoreError: Error, Equatable { case capacityExceeded(needed: Int, capacity: Int) }`.
  - `protocol AudioStore: Sendable { contains(_:) async -> Bool; write(_:for:) async throws; read(_:) async throws -> PCMAudio?; remove(_:) async throws; stats() async -> AudioStoreStats; setCapacity(bytes:) async }` with LRU semantics: a write that does not fit evicts least-recently-used entries until it does, or throws `capacityExceeded` when the entry alone exceeds the cap; reads refresh recency.
  - `actor InMemoryAudioStore(codec:capacityBytes:)`, `actor FileAudioStore(directory:codec:capacityBytes:)` (one file per key named `key.fileName`; recency by modification date; existing files are indexed at init).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Render/AudioStoreTests.swift
import Foundation
import Testing
@testable import T2SCore

@Suite struct AudioStoreTests {
    let doc = UUID()
    func key(_ i: Int) -> RenderKey { RenderKey(documentID: doc, utteranceIndex: i, voiceID: "v", engineID: "fake", normalizerVersion: 1, segmenterVersion: 1) }
    func pcm(_ seconds: TimeInterval) -> PCMAudio { PCMAudio.silence(seconds: seconds, sampleRate: 1000) }   // 4 KB per second
    func stores() -> [(String, any AudioStore)] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-store-\(UUID().uuidString)")
        return [("memory", InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000)),
                ("file", FileAudioStore(directory: dir, codec: RawPCMCodec(), capacityBytes: 10_000))]
    }

    @Test func rawCodecRoundTrips() throws {
        let c = RawPCMCodec()
        let a = PCMAudio(sampleRate: 24_000, samples: [0, 0.5, -0.25, 1])
        #expect(try c.decode(c.encode(a)) == a)
        #expect(c.identifier == "pcm-f32le")
    }

    @Test func writeReadRemove() async throws {
        for (name, s) in stores() {
            try await s.write(pcm(1), for: key(1))
            #expect(await s.contains(key(1)), "\(name)")
            #expect(try await s.read(key(1)) == pcm(1), "\(name)")
            #expect(try await s.read(key(2)) == nil, "\(name)")
            let st = await s.stats()
            #expect(st.entries == 1 && st.bytes == 4_008 && st.capacityBytes == 10_000, "\(name)")
            try await s.remove(key(1))
            #expect(!(await s.contains(key(1))), "\(name)")
        }
    }

    @Test func evictsLeastRecentlyUsed() async throws {
        for (name, s) in stores() {
            try await s.write(pcm(1), for: key(1))       // 4 KB
            try await s.write(pcm(1), for: key(2))       // 8 KB
            _ = try await s.read(key(1))                  // key 1 is now the most recent
            try await s.write(pcm(1), for: key(3))       // needs 12 KB → evict LRU = key 2
            #expect(await s.contains(key(1)), "\(name)")
            #expect(!(await s.contains(key(2))), "\(name)")
            #expect(await s.contains(key(3)), "\(name)")
            #expect(await s.stats().entries == 2, "\(name)")
        }
    }

    @Test func oversizedEntryThrows() async throws {
        for (name, s) in stores() {
            await #expect(throws: AudioStoreError.capacityExceeded(needed: 12_008, capacity: 10_000), "\(name)") {
                try await s.write(pcm(3), for: key(9))
            }
        }
    }

    @Test func overwritingWithOversizedDataKeepsTheOldEntry() async throws {
        for (name, s) in stores() {
            try await s.write(pcm(1), for: key(1))
            await #expect(throws: AudioStoreError.capacityExceeded(needed: 12_008, capacity: 10_000), "\(name)") {
                try await s.write(pcm(3), for: key(1))
            }
            #expect(try await s.read(key(1)) == pcm(1), "\(name)")
            #expect(await s.stats().entries == 1, "\(name)")
        }
    }

    @Test func loweringCapacityEvicts() async throws {
        for (name, s) in stores() {
            try await s.write(pcm(1), for: key(1))
            try await s.write(pcm(1), for: key(2))
            await s.setCapacity(bytes: 5_000)
            #expect(await s.stats().entries == 1, "\(name)")
            #expect(await s.contains(key(2)), "\(name)")
        }
    }

    @Test func fileStoreIndexesExistingFilesOnInit() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-store-\(UUID().uuidString)")
        let first = FileAudioStore(directory: dir, codec: RawPCMCodec(), capacityBytes: 10_000)
        try await first.write(pcm(1), for: key(1))
        let second = FileAudioStore(directory: dir, codec: RawPCMCodec(), capacityBytes: 10_000)
        #expect(await second.contains(key(1)))
        #expect(await second.stats().bytes == 4_008)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AudioStoreTests`
Expected: FAIL to compile, `cannot find 'RawPCMCodec' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Render/AudioCodec.swift
import Foundation

public protocol AudioCodec: Sendable {
    var identifier: String { get }
    func encode(_ pcm: PCMAudio) throws -> Data
    func decode(_ data: Data) throws -> PCMAudio
}

public enum AudioCodecError: Error, Equatable {
    case malformed
}

/// Tests only. Raw PCM is never persisted in production (spec §3.4).
public struct RawPCMCodec: AudioCodec {
    public let identifier = "pcm-f32le"
    public init() {}

    public func encode(_ pcm: PCMAudio) throws -> Data {
        var out = Data(capacity: 8 + pcm.samples.count * 4)
        var rate = pcm.sampleRate.bitPattern.littleEndian
        withUnsafeBytes(of: &rate) { out.append(contentsOf: $0) }
        for s in pcm.samples {
            var bits = s.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { out.append(contentsOf: $0) }
        }
        return out
    }

    public func decode(_ input: Data) throws -> PCMAudio {
        let data = Data(input)
        guard data.count >= 8, (data.count - 8) % 4 == 0 else { throw AudioCodecError.malformed }
        let rate = Double(bitPattern: UInt64(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }))
        var samples: [Float] = []
        samples.reserveCapacity((data.count - 8) / 4)
        var offset = 8
        while offset < data.count {
            let bits = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            samples.append(Float(bitPattern: UInt32(littleEndian: bits)))
            offset += 4
        }
        return PCMAudio(sampleRate: rate, samples: samples)
    }
}
```

```swift
// Sources/T2SCore/Render/AudioStore.swift
import Foundation

public struct AudioStoreStats: Hashable, Sendable {
    public var bytes: Int
    public var entries: Int
    public var capacityBytes: Int
    public init(bytes: Int, entries: Int, capacityBytes: Int) {
        self.bytes = bytes
        self.entries = entries
        self.capacityBytes = capacityBytes
    }
}

public enum AudioStoreError: Error, Equatable, Sendable {
    case capacityExceeded(needed: Int, capacity: Int)
}

/// Rendered audio is cache, never truth (spec §3.7.3). LRU against a user-configurable cap (spec §3.4).
public protocol AudioStore: Sendable {
    func contains(_ key: RenderKey) async -> Bool
    /// Evicts least-recently-used entries until the entry fits; throws when it never can.
    func write(_ pcm: PCMAudio, for key: RenderKey) async throws
    /// Refreshes the entry's recency.
    func read(_ key: RenderKey) async throws -> PCMAudio?
    func remove(_ key: RenderKey) async throws
    func stats() async -> AudioStoreStats
    /// Evicts immediately if the new cap is below current usage.
    func setCapacity(bytes: Int) async
}

/// Shared LRU bookkeeping for the two stores: keys ordered oldest → newest with their sizes.
struct LRUIndex: Sendable {
    private(set) var order: [RenderKey] = []
    private(set) var sizes: [RenderKey: Int] = [:]
    var bytes: Int { sizes.values.reduce(0, +) }

    mutating func touch(_ key: RenderKey) {
        if let i = order.firstIndex(of: key) { order.remove(at: i); order.append(key) }
    }

    mutating func insert(_ key: RenderKey, size: Int) {
        if sizes[key] != nil { order.removeAll { $0 == key } }
        sizes[key] = size
        order.append(key)
    }

    mutating func remove(_ key: RenderKey) {
        sizes[key] = nil
        order.removeAll { $0 == key }
    }

    /// Keys to evict (oldest first) so that `bytes + incoming <= capacity`.
    func victims(toFit incoming: Int, capacity: Int) -> [RenderKey] {
        var free = capacity - bytes
        var out: [RenderKey] = []
        for k in order where free < incoming {
            free += sizes[k] ?? 0
            out.append(k)
        }
        return out
    }
}
```

```swift
// Sources/T2SCore/Render/InMemoryAudioStore.swift
import Foundation

public actor InMemoryAudioStore: AudioStore {
    private let codec: any AudioCodec
    private var capacity: Int
    private var blobs: [RenderKey: Data] = [:]
    private var lru = LRUIndex()

    public init(codec: any AudioCodec, capacityBytes: Int) {
        self.codec = codec
        self.capacity = capacityBytes
    }

    public func contains(_ key: RenderKey) -> Bool { blobs[key] != nil }

    public func write(_ pcm: PCMAudio, for key: RenderKey) throws {
        let data = try codec.encode(pcm)
        // Guard before touching any state: a rejected overwrite must leave the old entry intact.
        guard data.count <= capacity else { throw AudioStoreError.capacityExceeded(needed: data.count, capacity: capacity) }
        if blobs[key] != nil { lru.remove(key); blobs[key] = nil }
        for victim in lru.victims(toFit: data.count, capacity: capacity) { blobs[victim] = nil; lru.remove(victim) }
        blobs[key] = data
        lru.insert(key, size: data.count)
    }

    public func read(_ key: RenderKey) throws -> PCMAudio? {
        guard let data = blobs[key] else { return nil }
        lru.touch(key)
        return try codec.decode(data)
    }

    public func remove(_ key: RenderKey) {
        blobs[key] = nil
        lru.remove(key)
    }

    public func stats() -> AudioStoreStats {
        AudioStoreStats(bytes: lru.bytes, entries: blobs.count, capacityBytes: capacity)
    }

    public func setCapacity(bytes: Int) {
        capacity = bytes
        for victim in lru.victims(toFit: 0, capacity: capacity) { blobs[victim] = nil; lru.remove(victim) }
    }
}
```

```swift
// Sources/T2SCore/Render/FileAudioStore.swift
import Foundation

/// One file per key under `directory`. Recency is the file's modification date, so the index
/// survives relaunches without a sidecar database.
public actor FileAudioStore: AudioStore {
    private let directory: URL
    private let codec: any AudioCodec
    private var capacity: Int
    private var lru = LRUIndex()

    public init(directory: URL, codec: any AudioCodec, capacityBytes: Int) {
        self.directory = directory
        self.codec = codec
        self.capacity = capacityBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys = [.fileSizeKey, .contentModificationDateKey] as [URLResourceKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        let entries = files.compactMap { url -> (RenderKey, Int, Date)? in
            guard url.pathExtension == "audio", let v = try? url.resourceValues(forKeys: Set(keys)),
                  let size = v.fileSize, let date = v.contentModificationDate else { return nil }
            return (RenderKey(rawValue: url.deletingPathExtension().lastPathComponent), size, date)
        }
        for (key, size, _) in entries.sorted(by: { $0.2 < $1.2 }) { lru.insert(key, size: size) }
    }

    private func url(_ key: RenderKey) -> URL { directory.appendingPathComponent(key.fileName) }

    public func contains(_ key: RenderKey) -> Bool { lru.sizes[key] != nil }

    public func write(_ pcm: PCMAudio, for key: RenderKey) throws {
        let data = try codec.encode(pcm)
        // Guard before touching any state: a rejected overwrite must leave the old entry intact.
        guard data.count <= capacity else { throw AudioStoreError.capacityExceeded(needed: data.count, capacity: capacity) }
        if lru.sizes[key] != nil { lru.remove(key) }              // the atomic write below replaces the file
        for victim in lru.victims(toFit: data.count, capacity: capacity) { evict(victim) }
        try data.write(to: url(key), options: .atomic)
        lru.insert(key, size: data.count)
    }

    public func read(_ key: RenderKey) throws -> PCMAudio? {
        guard lru.sizes[key] != nil else { return nil }
        let data = try Data(contentsOf: url(key))
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url(key).path)
        lru.touch(key)
        return try codec.decode(data)
    }

    public func remove(_ key: RenderKey) { evict(key) }

    public func stats() -> AudioStoreStats {
        AudioStoreStats(bytes: lru.bytes, entries: lru.sizes.count, capacityBytes: capacity)
    }

    public func setCapacity(bytes: Int) {
        capacity = bytes
        for victim in lru.victims(toFit: 0, capacity: capacity) { evict(victim) }
    }

    private func evict(_ key: RenderKey) {
        try? FileManager.default.removeItem(at: url(key))
        lru.remove(key)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AudioStoreTests`
Expected: 7 tests passed. Sizes: 1 s at 1 kHz is 1,000 samples × 4 bytes + 8-byte header = 4,008 bytes.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Render Tests/T2SCoreTests/Render/AudioStoreTests.swift
git commit -m "Add AudioCodec, AudioStore protocol, in-memory and file stores with LRU eviction"
```

---

### Task 6: `RateLimits`

**Files:**
- Create: `Sources/T2SCore/Render/RateLimits.swift`
- Create: `Tests/T2SCoreTests/Render/RateLimitsTests.swift`

**Interfaces:**
- Produces: `enum RateLimits { static let allRates: [Double]; static let safetyFactor = 0.8; static func isSustainable(rate:rtf:) -> Bool; static func maxSustainableRate(rtf: Double?) -> Double; static func availableRates(rtf: Double?) -> [Double] }`. Unknown RTF (nil, NaN, ≤ 0) means every rate is available.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Render/RateLimitsTests.swift
import Testing
@testable import T2SCore

@Suite struct RateLimitsTests {
    @Test(arguments: [
        (0.08, 4.0), (0.2, 4.0), (0.3, 2.5), (0.5, 1.5), (0.8, 1.0), (1.0, 0.75), (2.0, 0.5), (9.0, 0.5),
    ])
    func maxRate(rtf: Double, expected: Double) {
        #expect(RateLimits.maxSustainableRate(rtf: rtf) == expected)
    }

    @Test func unknownRTFAllowsEverything() {
        #expect(RateLimits.maxSustainableRate(rtf: nil) == 4.0)
        #expect(RateLimits.maxSustainableRate(rtf: .nan) == 4.0)
        #expect(RateLimits.maxSustainableRate(rtf: 0) == 4.0)
        #expect(RateLimits.availableRates(rtf: nil) == RateLimits.allRates)
    }

    @Test func availableRatesAreAPrefixOfAllRates() {
        #expect(RateLimits.availableRates(rtf: 0.3) == [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5])
        #expect(RateLimits.isSustainable(rate: 2.5, rtf: 0.3))
        #expect(!RateLimits.isSustainable(rate: 3.0, rtf: 0.3))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RateLimitsTests`
Expected: FAIL to compile, `cannot find 'RateLimits' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Render/RateLimits.swift
import Foundation

/// Spec §3.6: playback rate multiplies synthesis load. Demand is `RTF × rate`; anything above
/// the safety factor is not offered rather than offered and then stuttering.
public enum RateLimits {
    public static let allRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0]
    public static let safetyFactor = 0.8

    public static func isSustainable(rate: Double, rtf: Double) -> Bool {
        guard rtf.isFinite, rtf > 0 else { return true }
        return rtf * rate <= safetyFactor + 1e-9
    }

    /// The highest listed rate that is sustainable; the lowest listed rate when none is.
    public static func maxSustainableRate(rtf: Double?) -> Double {
        guard let rtf, rtf.isFinite, rtf > 0 else { return allRates.last! }
        return allRates.last(where: { isSustainable(rate: $0, rtf: rtf) }) ?? allRates.first!
    }

    public static func availableRates(rtf: Double?) -> [Double] {
        let cap = maxSustainableRate(rtf: rtf)
        return allRates.filter { $0 <= cap }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RateLimitsTests`
Expected: 10 cases passed (3 test functions).

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Render/RateLimits.swift Tests/T2SCoreTests/Render/RateLimitsTests.swift
git commit -m "Add RateLimits: sustainable playback rates from measured RTF"
```

---

### Task 7: `RenderPolicy`

**Files:**
- Create: `Sources/T2SCore/Render/RenderPolicy.swift`
- Create: `Tests/T2SCoreTests/Render/RenderPolicyTests.swift`

**Interfaces:**
- Produces:
  - `enum RenderTier: Int, Comparable, Sendable { playAhead, prime, prepare, manual }`
  - `struct RenderJob: Hashable, Sendable { documentID: UUID; utteranceIndex: Int; tier: RenderTier }`
  - `struct RenderSnapshot: Hashable, Sendable { documentID; seconds: [TimeInterval]; rendered: [Bool]; resumeIndex: Int; init(documentID:timeline:rendered:resumeIndex:) }` — `rendered[i]` is whether the store holds utterance `i`'s key; `seconds[i]` is the current (estimated or actual) duration.
  - `struct PlayingState: Hashable, Sendable { documentID; playhead: Playhead; rate: Double }`
  - `struct DeviceState: Hashable, Sendable { charging; thermalSerious; lowPowerMode; storeFull }`
  - `struct PolicyInput: Sendable { documents: [UUID: RenderSnapshot]; playing: PlayingState?; lastPlayed: UUID?; queue: [UUID]; primes: [UUID]; manual: [UUID]; device: DeviceState; windowSeconds = 60; primeSeconds = 30; prepareBudgetSeconds = 3 × 3600 }`
  - `enum RenderPolicy { static func plan(_ input: PolicyInput) -> [RenderJob] }` — pure; output ordered by tier, then by document order within the tier, then by utterance index; each `(document, index)` at most once, at its highest tier.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Render/RenderPolicyTests.swift
import Foundation
import Testing
@testable import T2SCore

@Suite struct RenderPolicyTests {
    let a = UUID(), b = UUID(), c = UUID()

    /// 100 utterances of 10 s each = 1,000 s per document.
    func snap(_ id: UUID, rendered: Set<Int> = [], resume: Int = 0) -> RenderSnapshot {
        RenderSnapshot(documentID: id, seconds: Array(repeating: 10, count: 100),
                       rendered: (0..<100).map { rendered.contains($0) }, resumeIndex: resume)
    }
    func input(playing: PlayingState? = nil, lastPlayed: UUID? = nil, queue: [UUID] = [], primes: [UUID] = [],
               manual: [UUID] = [], device: DeviceState = .init(charging: false, thermalSerious: false, lowPowerMode: false, storeFull: false),
               docs: [RenderSnapshot]) -> PolicyInput {
        var i = PolicyInput(documents: Dictionary(uniqueKeysWithValues: docs.map { ($0.documentID, $0) }),
                            playing: playing, lastPlayed: lastPlayed, queue: queue, primes: primes, manual: manual, device: device)
        i.windowSeconds = 60
        i.primeSeconds = 30
        i.prepareBudgetSeconds = 300
        return i
    }
    func indices(_ jobs: [RenderJob], _ id: UUID, _ tier: RenderTier) -> [Int] {
        jobs.filter { $0.documentID == id && $0.tier == tier }.map(\.utteranceIndex)
    }

    @Test func playAheadWindowScalesWithRate() {
        let one = RenderPolicy.plan(input(playing: .init(documentID: a, playhead: .init(utteranceIndex: 5, offset: 3), rate: 1), docs: [snap(a)]))
        #expect(indices(one, a, .playAhead) == [5, 6, 7, 8, 9, 10])          // 60 s at 1x → 6 utterances
        let three = RenderPolicy.plan(input(playing: .init(documentID: a, playhead: .init(utteranceIndex: 5, offset: 3), rate: 3), docs: [snap(a)]))
        #expect(indices(three, a, .playAhead) == Array(5..<23))                // 180 s at 3x → 18 utterances
    }

    @Test func renderedUtterancesCountTowardTheWindowButAreNotJobs() {
        let jobs = RenderPolicy.plan(input(playing: .init(documentID: a, playhead: .init(utteranceIndex: 0, offset: 0), rate: 1), docs: [snap(a, rendered: [0, 1, 2])]))
        #expect(indices(jobs, a, .playAhead) == [3, 4, 5])
    }

    @Test func primeRendersTheFirstThirtySeconds() {
        let jobs = RenderPolicy.plan(input(primes: [b], docs: [snap(b)]))
        #expect(indices(jobs, b, .prime) == [0, 1, 2])
    }

    @Test func prepareOnlyWhileCharging() {
        let off = RenderPolicy.plan(input(lastPlayed: a, queue: [a, b], docs: [snap(a), snap(b)]))
        #expect(off.isEmpty)
        for bad in [DeviceState(charging: true, thermalSerious: true, lowPowerMode: false, storeFull: false),
                    DeviceState(charging: true, thermalSerious: false, lowPowerMode: true, storeFull: false),
                    DeviceState(charging: true, thermalSerious: false, lowPowerMode: false, storeFull: true)] {
            #expect(RenderPolicy.plan(input(lastPlayed: a, queue: [a], device: bad, docs: [snap(a)])).isEmpty)
        }
    }

    @Test func prepareContinuesLastPlayedThenQueueWithinBudget() {
        let charging = DeviceState(charging: true, thermalSerious: false, lowPowerMode: false, storeFull: false)
        let jobs = RenderPolicy.plan(input(lastPlayed: b, queue: [a, b, c], device: charging,
                                           docs: [snap(a, resume: 50), snap(b, resume: 90), snap(c)]))
        let prepare = jobs.filter { $0.tier == .prepare }
        // b from 90: 10 utterances = 100 s; then a from 50: 200 s remaining = 20 utterances; c gets nothing.
        #expect(prepare.prefix(10).allSatisfy { $0.documentID == b })
        #expect(indices(jobs, b, .prepare) == Array(90..<100))
        #expect(indices(jobs, a, .prepare) == Array(50..<70))
        #expect(indices(jobs, c, .prepare).isEmpty)
    }

    @Test func manualRendersWholeDocumentRegardlessOfPower() {
        let jobs = RenderPolicy.plan(input(manual: [c], docs: [snap(c, rendered: [7])]))
        #expect(indices(jobs, c, .manual) == (0..<100).filter { $0 != 7 })
    }

    @Test func tiersAreOrderedAndDeduplicated() {
        let charging = DeviceState(charging: true, thermalSerious: false, lowPowerMode: false, storeFull: false)
        let jobs = RenderPolicy.plan(input(playing: .init(documentID: a, playhead: .init(utteranceIndex: 0, offset: 0), rate: 1),
                                           lastPlayed: a, queue: [a], primes: [a], manual: [a], device: charging, docs: [snap(a)]))
        #expect(jobs.map(\.tier) == jobs.map(\.tier).sorted())
        #expect(Set(jobs.map(\.utteranceIndex)).count == jobs.count)
        #expect(indices(jobs, a, .playAhead) == [0, 1, 2, 3, 4, 5])
        #expect(indices(jobs, a, .prime).isEmpty)                             // already covered by play-ahead
        #expect(indices(jobs, a, .prepare) == Array(6..<30))                  // budget 300 s counts the 60 s already ahead
        #expect(indices(jobs, a, .manual) == Array(30..<100))
    }

    @Test func unknownDocumentsAreIgnored() {
        #expect(RenderPolicy.plan(input(primes: [b], manual: [c], docs: [])).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RenderPolicyTests`
Expected: FAIL to compile, `cannot find 'RenderPolicy' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Render/RenderPolicy.swift
import Foundation

/// Spec §3.4.1 tiers, in priority order.
public enum RenderTier: Int, Hashable, Comparable, Sendable {
    case playAhead = 0, prime, prepare, manual
    public static func < (a: RenderTier, b: RenderTier) -> Bool { a.rawValue < b.rawValue }
}

public struct RenderJob: Hashable, Sendable {
    public var documentID: UUID
    public var utteranceIndex: Int
    public var tier: RenderTier
    public init(documentID: UUID, utteranceIndex: Int, tier: RenderTier) {
        self.documentID = documentID
        self.utteranceIndex = utteranceIndex
        self.tier = tier
    }
}

/// What the policy needs to know about one document.
public struct RenderSnapshot: Hashable, Sendable {
    public var documentID: UUID
    /// Current duration per utterance (estimated or actual), at 1x.
    public var seconds: [TimeInterval]
    /// Whether the store already holds each utterance's audio.
    public var rendered: [Bool]
    public var resumeIndex: Int

    public init(documentID: UUID, seconds: [TimeInterval], rendered: [Bool], resumeIndex: Int) {
        precondition(seconds.count == rendered.count)
        self.documentID = documentID
        self.seconds = seconds
        self.rendered = rendered
        self.resumeIndex = resumeIndex
    }

    public init(documentID: UUID, timeline: Timeline, rendered: [Bool], resumeIndex: Int) {
        var secs: [TimeInterval] = []
        secs.reserveCapacity(timeline.utteranceCount)
        for ch in timeline.chapters { for u in ch.utterances { secs.append(u.duration.seconds) } }
        self.init(documentID: documentID, seconds: secs, rendered: rendered, resumeIndex: resumeIndex)
    }
}

public struct PlayingState: Hashable, Sendable {
    public var documentID: UUID
    public var playhead: Playhead
    public var rate: Double
    public init(documentID: UUID, playhead: Playhead, rate: Double) {
        self.documentID = documentID
        self.playhead = playhead
        self.rate = rate
    }
}

public struct DeviceState: Hashable, Sendable {
    public var charging: Bool
    public var thermalSerious: Bool
    public var lowPowerMode: Bool
    public var storeFull: Bool
    public init(charging: Bool, thermalSerious: Bool, lowPowerMode: Bool, storeFull: Bool) {
        self.charging = charging
        self.thermalSerious = thermalSerious
        self.lowPowerMode = lowPowerMode
        self.storeFull = storeFull
    }
    public static let unplugged = DeviceState(charging: false, thermalSerious: false, lowPowerMode: false, storeFull: false)
}

public struct PolicyInput: Sendable {
    public var documents: [UUID: RenderSnapshot]
    public var playing: PlayingState?
    public var lastPlayed: UUID?
    public var queue: [UUID]
    /// Newly imported documents that have not been primed yet.
    public var primes: [UUID]
    /// "Render whole document" requests.
    public var manual: [UUID]
    public var device: DeviceState
    /// Play-ahead window at 1x (spec §3.4); multiplied by the rate.
    public var windowSeconds: TimeInterval = 60
    public var primeSeconds: TimeInterval = 30
    /// Spec §3.4.1 default: 3 hours of listening ready.
    public var prepareBudgetSeconds: TimeInterval = 3 * 3600

    public init(documents: [UUID: RenderSnapshot], playing: PlayingState? = nil, lastPlayed: UUID? = nil,
                queue: [UUID] = [], primes: [UUID] = [], manual: [UUID] = [], device: DeviceState = .unplugged) {
        self.documents = documents
        self.playing = playing
        self.lastPlayed = lastPlayed
        self.queue = queue
        self.primes = primes
        self.manual = manual
        self.device = device
    }
}

/// Pure: (library, playback, device) → ordered jobs (spec §3.4.1). Table-testable.
public enum RenderPolicy {
    public static func plan(_ input: PolicyInput) -> [RenderJob] {
        var jobs: [RenderJob] = []
        var seen: Set<Pair> = []

        /// Walks `doc` from `start`, accumulating every utterance's seconds (rendered or not) against
        /// `budget`, emitting jobs for the unrendered ones. Returns the seconds consumed.
        @discardableResult
        func walk(_ doc: RenderSnapshot, from start: Int, budget: TimeInterval?, tier: RenderTier) -> TimeInterval {
            var used: TimeInterval = 0
            var i = max(0, start)
            while i < doc.seconds.count {
                if let budget, used >= budget { break }
                if !doc.rendered[i], seen.insert(Pair(doc.documentID, i)).inserted {
                    jobs.append(RenderJob(documentID: doc.documentID, utteranceIndex: i, tier: tier))
                }
                used += doc.seconds[i]
                i += 1
            }
            return used
        }

        // Tier 1: play-ahead, window in playback-seconds at the current rate.
        if let p = input.playing, let doc = input.documents[p.documentID] {
            walk(doc, from: p.playhead.utteranceIndex, budget: input.windowSeconds * p.rate, tier: .playAhead)
        }
        // Tier 2: prime newly imported documents.
        for id in input.primes {
            if let doc = input.documents[id] { walk(doc, from: 0, budget: input.primeSeconds, tier: .prime) }
        }
        // Tier 3: prepare while charging — continue-document first, then queue order, one shared budget.
        let d = input.device
        if d.charging && !d.thermalSerious && !d.lowPowerMode && !d.storeFull {
            var order: [UUID] = []
            for id in [input.lastPlayed].compactMap({ $0 }) + input.queue where !order.contains(id) { order.append(id) }
            var remaining = input.prepareBudgetSeconds
            for id in order {
                guard remaining > 0, let doc = input.documents[id] else { continue }
                remaining -= walk(doc, from: doc.resumeIndex, budget: remaining, tier: .prepare)
            }
        }
        // Tier 4: manual whole-document renders, any power state, unless the store is full.
        if !d.storeFull {
            for id in input.manual {
                if let doc = input.documents[id] { walk(doc, from: 0, budget: nil, tier: .manual) }
            }
        }
        return jobs
    }

    private struct Pair: Hashable {
        let id: UUID, index: Int
        init(_ id: UUID, _ index: Int) { self.id = id; self.index = index }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RenderPolicyTests`
Expected: 8 tests passed. In `tiersAreOrderedAndDeduplicated`, prepare walks from `resumeIndex` 0: indices 0–5 are already play-ahead (seen), their 60 s still count against the 300 s budget, so prepare emits 6..<30.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Render/RenderPolicy.swift Tests/T2SCoreTests/Render/RenderPolicyTests.swift
git commit -m "Add RenderPolicy: tiered, budgeted render planning"
```

---

### Task 8: `RenderScheduler`

**Files:**
- Create: `Sources/T2SCore/Render/RenderScheduler.swift`
- Create: `Tests/T2SCoreTests/Render/RenderSchedulerTests.swift`

**Interfaces:**
- Produces:
  - `struct RenderRequest: Hashable, Sendable { job: RenderJob; key: RenderKey; spoken: String; voiceID: String }`
  - `struct RenderedUtterance: Hashable, Sendable { documentID; utteranceIndex; key; duration: TimeInterval; wordTimings: [WordTiming] }`
  - `enum RenderEvent: Hashable, Sendable { case rendered(RenderedUtterance); case failed(documentID: UUID, utteranceIndex: Int, message: String); case storeFull; case idle }`
  - `actor RenderScheduler { init(engine:store:timeSource:rtfWindow: = 20); nonisolated let events: AsyncStream<RenderEvent>; func setPlan(_:) ; func cancel(); func resume(); var measuredRTF: Double? ; var isPausedForStorage: Bool ; var pending: [RenderRequest] }`
  - Semantics: serial; `setPlan` replaces everything not yet started (a seek flushes; the in-flight request finishes and is stored); requests whose key the store already holds are skipped; a synthesis failure stores 200 ms of silence under the key, emits `.failed` then `.rendered` (spec §6); `capacityExceeded` from the store emits `.storeFull`, pauses, and drops the plan until `resume()`; `.idle` is emitted whenever the plan empties (backpressure); `measuredRTF` is the mean of the last `rtfWindow` samples of `synthSeconds / audioSeconds`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Render/RenderSchedulerTests.swift
import Foundation
import Testing
@testable import T2SCore

@Suite struct RenderSchedulerTests {
    let doc = UUID()
    func key(_ i: Int) -> RenderKey { RenderKey(documentID: doc, utteranceIndex: i, voiceID: "v", engineID: "fake", normalizerVersion: 1, segmenterVersion: 1) }
    func request(_ i: Int, _ spoken: String) -> RenderRequest {
        RenderRequest(job: RenderJob(documentID: doc, utteranceIndex: i, tier: .playAhead), key: key(i), spoken: spoken, voiceID: "v")
    }

    /// Encodes successfully except for the very first call, which throws.
    final class ThrowOnceCodec: AudioCodec, @unchecked Sendable {
        let identifier = "throw-once"
        private var calls = 0
        private let inner = RawPCMCodec()
        func encode(_ pcm: PCMAudio) throws -> Data {
            calls += 1
            if calls == 1 { throw AudioCodecError.malformed }
            return try inner.encode(pcm)
        }
        func decode(_ data: Data) throws -> PCMAudio { try inner.decode(data) }
    }

    /// Collects events until `.idle` has been seen `idles` times.
    func collect(_ s: RenderScheduler, idles: Int = 1) async -> [RenderEvent] {
        var out: [RenderEvent] = []
        var seen = 0
        for await e in s.events {
            out.append(e)
            if e == .idle { seen += 1; if seen == idles { break } }
        }
        return out
    }

    @Test func rendersInOrderAndReportsDurations() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let s = RenderScheduler(engine: FakeEngine(secondsPerCharacter: 0.1), store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "abc"), request(1, "abcde")])
        let got = await events
        #expect(got == [
            .rendered(RenderedUtterance(documentID: doc, utteranceIndex: 0, key: key(0), duration: 0.3, wordTimings: [WordTiming(spokenRange: 0..<3, start: 0, end: 0.3)])),
            .rendered(RenderedUtterance(documentID: doc, utteranceIndex: 1, key: key(1), duration: 0.5, wordTimings: [WordTiming(spokenRange: 0..<5, start: 0, end: 0.5)])),
            .idle,
        ])
        let has0 = await store.contains(key(0))
        let has1 = await store.contains(key(1))
        #expect(has0 && has1)
    }

    @Test func skipsKeysTheStoreAlreadyHolds() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        try await store.write(.silence(seconds: 1), for: key(0))
        let engine = FakeEngine()
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "already"), request(1, "new")])
        let got = await events
        #expect(got.count == 2)                                  // one rendered + idle
        #expect(await engine.requests.map(\.spoken) == ["new"])
    }

    @Test func setPlanFlushesPendingWork() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let engine = FakeEngine()
        await engine.hold()                                        // utterance 0 parks inside the engine
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "a"), request(1, "b"), request(2, "c")])
        while await s.pending.count != 2 { await Task.yield() }   // 0 has been dequeued and is parked in the engine
        await s.setPlan([request(7, "z")])                       // seek: 1 and 2 must never render
        await engine.release()
        let got = await events
        let renderedIndices = got.compactMap { if case .rendered(let r) = $0 { return r.utteranceIndex } else { return nil } }
        #expect(renderedIndices == [0, 7])                         // in-flight finishes, flushed ones never start
        #expect(await s.pending.isEmpty)
    }

    @Test func failureInsertsSilenceAndContinues() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let engine = FakeEngine(secondsPerCharacter: 0.1)
        await engine.fail(on: "boom")
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "boom"), request(1, "ok")])
        let got = await events
        #expect(got[0] == .failed(documentID: doc, utteranceIndex: 0, message: "failed(\"boom\")"))
        #expect(got[1] == .rendered(RenderedUtterance(documentID: doc, utteranceIndex: 0, key: key(0), duration: 0.2, wordTimings: [])))
        if case .rendered(let r) = got[2] { #expect(r.utteranceIndex == 1 && r.duration == 0.2) } else { Issue.record("expected rendered 1") }
        #expect(try await store.read(key(0))?.duration == 0.2)
    }

    @Test func writeFailureFallsBackToSilence() async throws {
        let store = InMemoryAudioStore(codec: ThrowOnceCodec(), capacityBytes: 10_000_000)
        let s = RenderScheduler(engine: FakeEngine(secondsPerCharacter: 0.1), store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "abc")])
        let got = await events
        #expect(got.count == 3)
        if case .failed(_, let i, _) = got[0] { #expect(i == 0) } else { Issue.record("expected .failed first") }
        #expect(got[1] == .rendered(RenderedUtterance(documentID: doc, utteranceIndex: 0, key: key(0), duration: 0.2, wordTimings: [])))
        #expect(try await store.read(key(0))?.duration == 0.2)
    }

    @Test func storeFullPausesUntilResumed() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 100)   // nothing fits
        let s = RenderScheduler(engine: FakeEngine(secondsPerCharacter: 0.1), store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "abc"), request(1, "def")])
        let got = await events
        #expect(got == [.storeFull, .idle])
        #expect(await s.isPausedForStorage)
        #expect(await s.pending.isEmpty)
        await store.setCapacity(bytes: 10_000_000)
        async let more = collect(s)
        await s.resume()
        await s.setPlan([request(0, "abc")])
        let got2 = await more
        #expect(got2.count == 2 && got2.last == .idle)
        #expect(!(await s.isPausedForStorage))
    }

    @Test func measuresRollingRTF() async throws {
        let clock = ManualTimeSource()
        let engine = FakeEngine(secondsPerCharacter: 0.1, simulatedRTF: 0.25, timeSource: clock)
        let s = RenderScheduler(engine: engine, store: InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000), timeSource: clock, rtfWindow: 2)
        #expect(await s.measuredRTF == nil)
        async let events = collect(s)
        await s.setPlan([request(0, "aaaa"), request(1, "bbbbbbbb"), request(2, "cc")])
        _ = await events
        #expect(abs((await s.measuredRTF ?? 0) - 0.25) < 1e-9)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RenderSchedulerTests`
Expected: FAIL to compile, `cannot find 'RenderScheduler' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SCore/Render/RenderScheduler.swift
import Foundation

public struct RenderRequest: Hashable, Sendable {
    public var job: RenderJob
    public var key: RenderKey
    public var spoken: String
    public var voiceID: String
    public init(job: RenderJob, key: RenderKey, spoken: String, voiceID: String) {
        self.job = job
        self.key = key
        self.spoken = spoken
        self.voiceID = voiceID
    }
}

public struct RenderedUtterance: Hashable, Sendable {
    public var documentID: UUID
    public var utteranceIndex: Int
    public var key: RenderKey
    /// Actual duration at 1x.
    public var duration: TimeInterval
    public var wordTimings: [WordTiming]
    public init(documentID: UUID, utteranceIndex: Int, key: RenderKey, duration: TimeInterval, wordTimings: [WordTiming]) {
        self.documentID = documentID
        self.utteranceIndex = utteranceIndex
        self.key = key
        self.duration = duration
        self.wordTimings = wordTimings
    }
}

public enum RenderEvent: Hashable, Sendable {
    case rendered(RenderedUtterance)
    /// Spec §6: logged; 200 ms of silence is stored under the key and a `.rendered` follows,
    /// unless storing the silence itself failed, in which case nothing follows.
    case failed(documentID: UUID, utteranceIndex: Int, message: String)
    /// Spec §6: the store refused the entry; rendering pauses until `resume()`.
    case storeFull
    /// The plan is empty (backpressure, spec §3.4).
    case idle
}

/// Serial executor of `RenderRequest`s (spec §3.4). Knows nothing about timelines: the
/// coordinator turns policy jobs into requests and applies the events.
public actor RenderScheduler {
    public static let failureSilenceSeconds: TimeInterval = 0.2

    public nonisolated let events: AsyncStream<RenderEvent>
    private let continuation: AsyncStream<RenderEvent>.Continuation
    private let engine: any SynthesisEngine
    private let store: any AudioStore
    private let timeSource: any TimeSource
    private let rtfWindow: Int

    public private(set) var pending: [RenderRequest] = []
    public private(set) var isPausedForStorage = false
    private var running = false
    private var rtfSamples: [Double] = []

    public init(engine: any SynthesisEngine, store: any AudioStore, timeSource: any TimeSource, rtfWindow: Int = 20) {
        self.engine = engine
        self.store = store
        self.timeSource = timeSource
        self.rtfWindow = max(1, rtfWindow)
        (events, continuation) = AsyncStream.makeStream(of: RenderEvent.self, bufferingPolicy: .unbounded)
    }

    /// Rolling mean of synth seconds per audio second over the last `rtfWindow` renders.
    public var measuredRTF: Double? {
        rtfSamples.isEmpty ? nil : rtfSamples.reduce(0, +) / Double(rtfSamples.count)
    }

    /// Replaces all pending work. The request in flight, if any, finishes and is stored.
    /// Returns true when this call will produce its own `.idle` (a new run loop started, or the
    /// immediate paused `.idle`), false when the plan was absorbed by a loop already running,
    /// whose `.idle` is already owed. Callers that wait for idleness count on this.
    @discardableResult
    public func setPlan(_ requests: [RenderRequest]) -> Bool {
        if isPausedForStorage {
            continuation.yield(.idle)                              // never leave a waiter hanging while paused
            return true
        }
        pending = requests
        if !running {
            running = true
            Task { await self.run() }
            return true
        }
        return false
    }

    public func cancel() { pending.removeAll() }

    public func resume() { isPausedForStorage = false }

    private func run() async {
        while !isPausedForStorage, !pending.isEmpty {
            let request = pending.removeFirst()
            if await store.contains(request.key) { continue }
            let t0 = timeSource.now()
            var result: SynthesisResult
            do {
                result = try await engine.synthesize(SynthesisRequest(spoken: request.spoken, voiceID: request.voiceID))
                let synthSeconds = timeSource.now() - t0
                if result.audio.duration > 0 { record(rtf: synthSeconds / result.audio.duration) }
            } catch {
                continuation.yield(.failed(documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex, message: "\(error)"))
                result = SynthesisResult(audio: .silence(seconds: Self.failureSilenceSeconds), wordTimings: [])
            }
            do {
                try await store.write(result.audio, for: request.key)
            } catch AudioStoreError.capacityExceeded {
                isPausedForStorage = true
                pending.removeAll()
                continuation.yield(.storeFull)
                break
            } catch {
                // Encoding or I/O failed for this clip: log it and fall back to the failure silence
                // so the utterance still arrives (spec §6). Only if that write fails too does a
                // bare `.failed` go out with no `.rendered` behind it.
                continuation.yield(.failed(documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex, message: "\(error)"))
                result = SynthesisResult(audio: .silence(seconds: Self.failureSilenceSeconds), wordTimings: [])
                do {
                    try await store.write(result.audio, for: request.key)
                } catch {
                    continue
                }
            }
            continuation.yield(.rendered(RenderedUtterance(
                documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex, key: request.key,
                duration: result.audio.duration, wordTimings: result.wordTimings)))
        }
        running = false
        continuation.yield(.idle)
    }

    private func record(rtf: Double) {
        rtfSamples.append(rtf)
        if rtfSamples.count > rtfWindow { rtfSamples.removeFirst(rtfSamples.count - rtfWindow) }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RenderSchedulerTests`
Expected: 7 tests passed. The `.idle` after `.storeFull` comes from the loop exiting. `hold()` on the engine is what makes `setPlanFlushesPendingWork` deterministic: the first request is parked inside `synthesize` when the second plan arrives. Note `while held { await ... }` in `FakeEngine` parks before `requests.append`, so the test waits for `requests` to be non-empty only after `release()`… which would deadlock — so the scheduler test instead waits on `s.pending.count == 2` (the scheduler removed request 0 from `pending` before calling the engine). Use that condition: `while await s.pending.count != 2 { await Task.yield() }`.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Render/RenderScheduler.swift Tests/T2SCoreTests/Render/RenderSchedulerTests.swift
git commit -m "Add RenderScheduler: serial, flushable, RTF-measuring executor"
```

---

### Task 9: `AACCodec` (T2SAudio)

**Files:**
- Create: `Sources/T2SAudio/AACCodec.swift`
- Create: `Tests/T2SAudioTests/AACCodecTests.swift`

**Interfaces:**
- Produces: `struct AACCodec: AudioCodec { identifier "aac-32k-mono-24k"; encode via AVAudioFile with kAudioFormatMPEG4AAC, 24 kHz, mono, 32 kbps; decode via AVAudioFile }`. Encoding writes through a temporary `.m4a` file, which is fine because `FileAudioStore` is file-backed anyway.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/T2SAudioTests/AACCodecTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@Suite struct AACCodecTests {
    @Test func roundTripsASecondOfToneCompactly() throws {
        let rate = 24_000.0
        let tone = PCMAudio(sampleRate: rate, samples: (0..<24_000).map { sin(Double($0) * 2 * .pi * 440 / rate) }.map(Float.init))
        let codec = AACCodec()
        let data = try codec.encode(tone)
        #expect(data.count < 12_000)                              // ~32 kbps → about 4 KB/s plus container
        let back = try codec.decode(data)
        #expect(back.sampleRate == rate)
        #expect(abs(back.duration - 1.0) < 0.05)
        let energy = back.samples.reduce(0) { $0 + Double($1 * $1) } / Double(back.samples.count)
        #expect(energy > 0.3)                                     // a sine of amplitude 1 has mean square 0.5
        #expect(codec.identifier == "aac-32k-mono-24k")
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try AACCodec().decode(Data("not audio".utf8)) }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AACCodecTests`
Expected: FAIL to compile, `cannot find 'AACCodec' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SAudio/AACCodec.swift
import AVFoundation
import Foundation
import T2SCore

/// AAC ≈ 32 kbps mono 24 kHz ≈ 14 MB/hour (spec §3.4).
public struct AACCodec: AudioCodec {
    public let identifier = "aac-32k-mono-24k"
    public init() {}

    public func encode(_ pcm: PCMAudio) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: pcm.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: pcm.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.samples.count)) else {
            throw AudioCodecError.malformed
        }
        buffer.frameLength = AVAudioFrameCount(pcm.samples.count)
        pcm.samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: pcm.samples.count)
        }
        try file.write(from: buffer)
        return try Data(contentsOf: url)
    }

    public func decode(_ data: Data) throws -> PCMAudio {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioCodecError.malformed
        }
        try file.read(into: buffer)
        let n = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: n))
        return PCMAudio(sampleRate: rate, samples: samples)
    }
}
```

The `AVAudioFile(forWriting:settings:)` initializer's file must be written with the processing format the file reports; if `file.write(from:)` throws a format mismatch, create the buffer with `file.processingFormat` instead of the standard format. Stereo input is out of scope (the engine is mono).

**Implementation note (recorded after execution).** `AVAudioFile` reserves a fixed `free` atom of about 32 KB ahead of `mdat` in every `.m4a` it writes, so a one-second clip came out near 34 KB and failed the size assertion. The shipped `AACCodec.encode` strips top-level `free` boxes and rewrites `stco`/`co64` chunk offsets, shifting each offset only by the removed boxes that precede it, and leaves the data untouched if the layout is not the one `AVAudioFile` produces; every recursion into a container box, including `meta`'s extra 4-byte header, is bounds-guarded, and the stripping function is internal so a synthetic-layout test can prove the no-op path. `AVAudioFile` also finalizes the container only on deallocation, so the write happens inside a helper whose file object goes out of scope before the bytes are read back.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter AACCodecTests`
Expected: 2 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SAudio/AACCodec.swift Tests/T2SAudioTests/AACCodecTests.swift
git commit -m "Add AACCodec: 32 kbps mono AAC through AVAudioFile"
```

---

### Task 10: `AudioPlayer` (T2SAudio)

**Files:**
- Create: `Sources/T2SAudio/AudioPlaying.swift`
- Create: `Sources/T2SAudio/AudioPlayer.swift`
- Create: `Tests/T2SAudioTests/AudioPlayerTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor protocol AudioPlaying: AnyObject { var rate: Double { get set }; var isPlaying: Bool { get }; var consumedSeconds: TimeInterval { get }; var onSegmentFinished: ((Int) -> Void)? { get set }; func enqueue(_ audio: PCMAudio, tag: Int); func play(); func pause(); func reset() }` — `consumedSeconds` is audio time at 1x since the last `reset`, so the coordinator's playhead arithmetic is rate-independent; `onSegmentFinished(tag)` fires when a segment's last frame has played.
  - `@MainActor final class AudioPlayer: AudioPlaying` over `AVAudioEngine → AVAudioPlayerNode → AVAudioUnitTimePitch → mainMixerNode`, `init(sampleRate: = 24_000, manualRendering: Bool = false) throws`; when `manualRendering` is true the engine runs in `.offline` manual rendering mode and `renderOffline(seconds:)` advances it deterministically (tests only).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SAudioTests/AudioPlayerTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@MainActor
@Suite struct AudioPlayerTests {
    @Test func consumedSecondsTracksAudioTimeAtOneX() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.enqueue(.silence(seconds: 2), tag: 1)
        p.play()
        try p.renderOffline(seconds: 0.5)
        #expect(abs(p.consumedSeconds - 0.5) < 0.05)
        try p.renderOffline(seconds: 1.0)
        #expect(abs(p.consumedSeconds - 1.5) < 0.05)
    }

    @Test func rateTwoConsumesTwiceAsFast() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.rate = 2.0
        p.enqueue(.silence(seconds: 4), tag: 1)
        p.play()
        try p.renderOffline(seconds: 1.0)
        #expect(abs(p.consumedSeconds - 2.0) < 0.15)               // time-pitch buffers a little
    }

    @Test func segmentsFinishInOrderAndGaplessly() throws {
        let p = try AudioPlayer(manualRendering: true)
        var finished: [Int] = []
        p.onSegmentFinished = { finished.append($0) }
        p.enqueue(.silence(seconds: 0.5), tag: 10)
        p.enqueue(.silence(seconds: 0.5), tag: 11)
        p.play()
        try p.renderOffline(seconds: 0.6)
        #expect(finished == [10])
        try p.renderOffline(seconds: 0.6)
        #expect(finished == [10, 11])
        #expect(abs(p.consumedSeconds - 1.0) < 0.05)               // stops consuming when the queue drains
    }

    @Test func resetClearsQueueAndClock() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.enqueue(.silence(seconds: 2), tag: 1)
        p.play()
        try p.renderOffline(seconds: 1.0)
        p.reset()
        #expect(p.consumedSeconds == 0)
        #expect(!p.isPlaying)
        p.enqueue(.silence(seconds: 1), tag: 2)
        p.play()
        try p.renderOffline(seconds: 0.25)
        #expect(abs(p.consumedSeconds - 0.25) < 0.05)
    }

    @Test func rateIsClampedToSpecRange() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.rate = 9
        #expect(p.rate == 4)
        p.rate = 0.1
        #expect(p.rate == 0.5)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AudioPlayerTests`
Expected: FAIL to compile, `cannot find 'AudioPlayer' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SAudio/AudioPlaying.swift
import Foundation
import T2SCore

/// What the coordinator needs from a player. `AudioPlayer` is the real one; tests use a fake.
@MainActor
public protocol AudioPlaying: AnyObject {
    /// 0.5…4.0 with pitch correction (spec §3.5).
    var rate: Double { get set }
    var isPlaying: Bool { get }
    /// Audio consumed since the last `reset`, in seconds at 1x, independent of `rate`.
    var consumedSeconds: TimeInterval { get }
    /// Called with the segment's tag after its last frame has played.
    var onSegmentFinished: ((Int) -> Void)? { get set }
    /// Appends a segment for gapless playback after whatever is queued.
    func enqueue(_ audio: PCMAudio, tag: Int)
    func play()
    func pause()
    /// Stops, drops every queued segment, and zeroes `consumedSeconds`.
    func reset()
}
```

```swift
// Sources/T2SAudio/AudioPlayer.swift
import AVFoundation
import Foundation
import T2SCore

/// Spec §3.5: AVAudioEngine → AVAudioPlayerNode → AVAudioUnitTimePitch → mainMixer.
@MainActor
public final class AudioPlayer: AudioPlaying {
    public enum Error: Swift.Error { case badFormat }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format: AVAudioFormat
    private let manual: Bool
    /// Frames scheduled since the last reset, used to freeze `consumedSeconds` when the queue drains.
    private var scheduledFrames: AVAudioFramePosition = 0
    private var generation = 0
    public private(set) var isPlaying = false
    public var onSegmentFinished: ((Int) -> Void)?

    public var rate: Double {
        get { Double(timePitch.rate) }
        set { timePitch.rate = Float(max(0.5, min(4.0, newValue))) }
    }

    public init(sampleRate: Double = PCMAudio.defaultSampleRate, manualRendering: Bool = false) throws {
        guard let f = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { throw Error.badFormat }
        format = f
        manual = manualRendering
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        if manualRendering {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        }
        try engine.start()
    }

    public var consumedSeconds: TimeInterval {
        guard let nodeTime = player.lastRenderTime, let t = player.playerTime(forNodeTime: nodeTime) else { return 0 }
        let frames = min(t.sampleTime, scheduledFrames)
        return Double(max(0, frames)) / format.sampleRate
    }

    public func enqueue(_ audio: PCMAudio, tag: Int) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        if !audio.samples.isEmpty {
            audio.samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress!, count: audio.samples.count)
            }
        }
        scheduledFrames += AVAudioFramePosition(audio.samples.count)
        let gen = generation
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                self.onSegmentFinished?(tag)
            }
        }
    }

    public func play() {
        player.play()
        isPlaying = true
    }

    public func pause() {
        player.pause()
        isPlaying = false
    }

    public func reset() {
        generation += 1
        player.stop()
        scheduledFrames = 0
        isPlaying = false
    }

    /// Manual rendering only: advances the offline engine by `seconds` of output.
    func renderOffline(seconds: TimeInterval) throws {
        precondition(manual, "renderOffline requires manualRendering")
        guard let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else { return }
        var remaining = AVAudioFrameCount((seconds * format.sampleRate).rounded())
        while remaining > 0 {
            let n = min(remaining, engine.manualRenderingMaximumFrameCount)
            let status = try engine.renderOffline(n, to: out)
            guard status == .success || status == .insufficientDataFromInputNode else { break }
            remaining -= n
        }
        // Completion callbacks are delivered asynchronously; let them land before the caller asserts.
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}
```

`player.stop()` resets the player node's sample time, which is why `consumedSeconds` is zero after `reset()`. If `segmentsFinishInOrderAndGaplessly` sees the second callback late, raise the run-loop drain to 0.05 s rather than loosening the assertions; if `consumedSeconds` overshoots after the queue drains, the `min(t.sampleTime, scheduledFrames)` clamp is the intended guard, so check `scheduledFrames` bookkeeping first.

**Implementation note (recorded after execution).** Two things differ from the code above, both established empirically. `.dataPlayedBack` never fires in offline manual rendering, so the shipped player uses `.dataRendered` when `manualRendering` is true and `.dataPlayedBack` otherwise, and in manual mode it collects completions in a lock-protected `CompletionQueue` (`@unchecked Sendable`, the same precedent as `ManualTimeSource`) that `renderOffline` drains synchronously after each render instead of hopping through the main actor. And with `AVAudioUnitTimePitch` in the chain, `playerTime(forNodeTime:)` reads about 1,824 frames ahead of rendered output, so manual-mode `consumedSeconds` derives from `engine.manualRenderingSampleTime × rate` from a baseline captured at `reset()`; real-mode playback still uses `playerTime`, and that constant lead is a calibration item for Plan 4. Manual-mode progress is integrated: a change of `rate` (and `reset()`) folds the output frames rendered so far at the old rate into an accumulator and restarts the baseline, so a rate change mid-stream reads correctly.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AudioPlayerTests`
Expected: 5 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SAudio Tests/T2SAudioTests/AudioPlayerTests.swift
git commit -m "Add AudioPlayer over AVAudioEngine with pitch-corrected rate and manual rendering"
```

---

### Task 11: `PlaybackCoordinator` (T2SAudio)

**Files:**
- Create: `Sources/T2SAudio/PlayheadStore.swift`
- Create: `Sources/T2SAudio/PlaybackCoordinator.swift`
- Create: `Tests/T2SAudioTests/Support/FakePlayer.swift`
- Create: `Tests/T2SAudioTests/Support/MemoryPlayheadStore.swift`
- Create: `Tests/T2SAudioTests/PlaybackCoordinatorTests.swift`

**Interfaces:**
- Produces:
  - `protocol PlayheadStore: Sendable { func save(_ position: Position, for documentID: UUID) async }`
  - `enum PlaybackState: Hashable, Sendable { idle, playing, paused, catchingUp, finished }`
  - `struct CoordinatorConfiguration: Sendable { windowSeconds = 60; primeSeconds = 30; prepareBudgetSeconds = 3×3600; queuedSegments = 2 }`
  - `@MainActor @Observable final class PlaybackCoordinator` with `init(engine:store:player:playheadStore:timeSource:configuration:)`, observable `state`, `playhead`, `highlight`, `rate`, `availableRates`, `timeline`, `document`, `measuredRTF`, settable `device: DeviceState`, `queue: [UUID]`, and methods `load(_:timeline:)`, `play() async`, `pause()`, `seek(to:) async`, `seek(toTime:) async`, `setRate(_:)`, `renderWholeDocument()`, `tick()`, `settle() async` (awaits any segment-feeding work started by a player callback or a render event), `waitForRenderIdle() async` (awaits the scheduler draining the current plan, then `settle()`).
  - Semantics: `load` resolves `document.resumePosition` to a playhead (or utterance 0), resets the player, plans (play-ahead and, while charging, prepare; **priming is an import-time concern and is not done here**); `play` fills the player with the head utterance and up to `queuedSegments - 1` more whose audio is in the store; if the head utterance is not rendered it enters `.catchingUp` with the player paused and resumes when that utterance's `.rendered` event arrives; `tick` derives `playhead.offset` from `player.consumedSeconds` minus the consumed time at the head segment's start and refreshes `highlight`; segment finished → advance the head, save position, feed the next segment (entering `.catchingUp` only if nothing is queued); last segment finished → `.finished`, playhead clamped to the end; `seek` resets the player, trims the head clip so audio and arithmetic agree, saves, replans; `setRate` clamps to `RateLimits.maxSustainableRate(measuredRTF)`, sets the player's rate, replans (the window resizes); `.rendered` events update the timeline's duration to `.actual`, word timings, and `audioRef`, rebuild the `TimeIndex`, and feed the player if it was waiting; `.idle` refreshes `measuredRTF` and `availableRates`; `.storeFull` sets `device.storeFull`; `renderWholeDocument` adds the document to the manual list and replans.

- [ ] **Step 1: Write the test doubles and failing tests**

```swift
// Tests/T2SAudioTests/Support/FakePlayer.swift
import Foundation
import T2SCore
@testable import T2SAudio

/// Deterministic player: `advance(seconds:)` consumes audio at 1x and fires segment callbacks.
@MainActor
final class FakePlayer: AudioPlaying {
    var rate: Double = 1
    private(set) var isPlaying = false
    private(set) var consumedSeconds: TimeInterval = 0
    var onSegmentFinished: ((Int) -> Void)?
    private(set) var queue: [(tag: Int, remaining: TimeInterval)] = []
    private(set) var enqueuedTags: [Int] = []
    private(set) var resets = 0
    /// Seconds of audio still queued (the head clip's remainder plus every later segment).
    var queuedRemaining: TimeInterval { queue.reduce(0) { $0 + $1.remaining } }

    func enqueue(_ audio: PCMAudio, tag: Int) {
        queue.append((tag, audio.duration))
        enqueuedTags.append(tag)
    }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func reset() { queue.removeAll(); consumedSeconds = 0; isPlaying = false; resets += 1 }

    func advance(seconds: TimeInterval) {
        guard isPlaying else { return }
        var left = seconds
        while left > 0, !queue.isEmpty {
            let step = min(left, queue[0].remaining)
            consumedSeconds += step
            queue[0].remaining -= step
            left -= step
            if queue[0].remaining <= 1e-9 {
                let tag = queue.removeFirst().tag
                onSegmentFinished?(tag)
            }
        }
    }
}
```

```swift
// Tests/T2SAudioTests/Support/MemoryPlayheadStore.swift
import Foundation
import T2SCore
@testable import T2SAudio

actor MemoryPlayheadStore: PlayheadStore {
    private(set) var saved: [(UUID, Position)] = []
    func save(_ position: Position, for documentID: UUID) { saved.append((documentID, position)) }
    var last: Position? { saved.last?.1 }
}
```

```swift
// Tests/T2SAudioTests/PlaybackCoordinatorTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@MainActor
@Suite struct PlaybackCoordinatorTests {
    /// Three sentences at 0.1 s per character: "Alpha one." (10 → 1.0 s), "Beta two." (9 → 0.9 s), "Gamma three." (12 → 1.2 s).
    /// Source offsets: "Alpha one." at 0, "Beta two." at 11, "Gamma three." at 21.
    func fixture(capacity: Int = 10_000_000, window: TimeInterval = 60)
        -> (PlaybackCoordinator, FakePlayer, FakeEngine, InMemoryAudioStore, MemoryPlayheadStore, Document, Timeline) {
        let block = SourceBlock(text: "Alpha one. Beta two. Gamma three.", position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 0))
        let timeline = TimelineBuilder.build(chapters: [ChapterInput(title: "C", position: block.position, blocks: [block])],
                                             segmenter: Segmenter(normalizer: TextNormalizer()))
        let doc = Document(title: "T", sourceType: .article)
        let engine = FakeEngine(secondsPerCharacter: 0.1)
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: capacity)
        let player = FakePlayer()
        let saves = MemoryPlayheadStore()
        let c = PlaybackCoordinator(engine: engine, store: store, player: player, playheadStore: saves, timeSource: ManualTimeSource(),
                                    configuration: CoordinatorConfiguration(windowSeconds: window, primeSeconds: 30, prepareBudgetSeconds: 300, queuedSegments: 2))
        return (c, player, engine, store, saves, doc, timeline)
    }

    @Test func loadResolvesResumePositionAndPlansFromThere() async throws {
        let (c, player, _, _, _, doc, timeline) = fixture()
        var d = doc
        d.resumePosition = Position(resourceHref: "c.xhtml", progression: 0, charOffset: 11)      // "Beta two."
        c.load(d, timeline: timeline)
        #expect(c.state == .paused)
        #expect(c.playhead == Playhead(utteranceIndex: 1, offset: 0))
        #expect(player.resets == 1)
        await c.waitForRenderIdle()
        #expect(c.timeline?[utterance: 1].duration.isActual == true)                             // play-ahead from the playhead…
        #expect(c.timeline?[utterance: 2].duration.isActual == true)
        #expect(c.timeline?[utterance: 0].duration.isActual == false)                            // …and nothing behind it
    }

    @Test func playsThroughWithHighlightsAndFinishes() async throws {
        let (c, player, _, _, saves, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        await c.play()
        #expect(c.state == .playing)
        #expect(player.enqueuedTags == [0, 1])                                                   // two segments queued
        player.advance(seconds: 0.5); c.tick()
        #expect(c.playhead == Playhead(utteranceIndex: 0, offset: 0.5))
        #expect(c.highlight?.utteranceIndex == 0)
        player.advance(seconds: 0.6); await c.settle(); c.tick()                                 // crosses into utterance 1
        #expect(c.playhead.utteranceIndex == 1)
        #expect(abs(c.playhead.offset - 0.1) < 1e-9)
        #expect(player.enqueuedTags == [0, 1, 2])
        #expect(await saves.last?.charOffset == 11)                                              // saved at the boundary
        player.advance(seconds: 5); await c.settle(); c.tick()
        #expect(c.state == .finished)
        #expect(c.playhead == Playhead(utteranceIndex: 2, offset: 1.2))
        #expect(await saves.last?.charOffset == 21 + 6)                                          // end: last word "three." starts at 6
    }

    @Test func catchesUpWhenTheFrontierIsReached() async throws {
        let (c, player, engine, _, _, doc, timeline) = fixture()
        await engine.fail(on: "Gamma three.")          // will be rendered as 0.2 s silence, still "rendered"
        c.load(doc, timeline: timeline)
        await c.play()                                  // nothing rendered yet
        #expect(c.state == .catchingUp)
        #expect(!player.isPlaying)
        await c.waitForRenderIdle()
        #expect(c.state == .playing)
        #expect(player.isPlaying)
        #expect(player.enqueuedTags.prefix(2) == [0, 1])
    }

    @Test func seekResetsPlayerTrimsHeadAndSaves() async throws {
        let (c, player, _, _, saves, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        await c.play()
        player.advance(seconds: 0.3); c.tick()
        await c.seek(to: Playhead(utteranceIndex: 2, offset: 0.4))
        #expect(player.resets == 2)
        #expect(c.playhead == Playhead(utteranceIndex: 2, offset: 0.4))
        #expect(c.state == .playing)
        #expect(player.enqueuedTags.last == 2)
        #expect(abs(player.queuedRemaining - 0.8) < 1e-9)                                        // head clip trimmed by 0.4 s
        #expect(await saves.last?.charOffset == 21)                                              // 0.4 s is inside "Gamma" (timed 0…0.5)
        player.advance(seconds: 0.2); c.tick()
        #expect(abs(c.playhead.offset - 0.6) < 1e-9)
        await c.seek(toTime: 0)
        #expect(c.playhead == Playhead(utteranceIndex: 0, offset: 0))
    }

    @Test func rateIsClampedBySustainability() async throws {
        let (c, player, _, _, _, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        c.setRate(3.0)
        #expect(c.rate == 3.0 && player.rate == 3.0)                                             // RTF unknown → everything allowed
        c.setRate(9.0)
        #expect(c.rate == 4.0)
    }

    @Test func pauseSavesPosition() async throws {
        let (c, player, _, _, saves, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        await c.play()
        player.advance(seconds: 0.7); c.tick()
        c.pause()
        #expect(c.state == .paused && !player.isPlaying)
        await c.settle()
        #expect(await saves.last?.charOffset == 6)                                               // "one." starts at 6 and is timed 0.6…1.0
    }

    @Test func renderWholeDocumentPlansManualTier() async throws {
        let (c, _, engine, _, _, doc, timeline) = fixture(window: 1)                            // play-ahead covers only utterance 0
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        #expect(c.timeline?.isFullyRendered == false)
        c.renderWholeDocument()
        await c.waitForRenderIdle()
        #expect(c.timeline?.isFullyRendered == true)
        #expect(await engine.requests.count == 3)
    }

    @Test func storeFullSurfacesAndStopsRendering() async throws {
        let (c, _, _, _, _, doc, timeline) = fixture(capacity: 100)
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        #expect(c.device.storeFull)
        #expect(c.timeline?[utterance: 0].duration.isActual == false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PlaybackCoordinatorTests`
Expected: FAIL to compile, `cannot find 'PlaybackCoordinator' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/T2SAudio/PlayheadStore.swift
import Foundation
import T2SCore

/// Where resume positions go (spec §5: local is the source of truth). Plan 3 provides SwiftData.
public protocol PlayheadStore: Sendable {
    func save(_ position: Position, for documentID: UUID) async
}
```

```swift
// Sources/T2SAudio/PlaybackCoordinator.swift
import Foundation
import Observation
import T2SCore

public enum PlaybackState: Hashable, Sendable {
    case idle, playing, paused, catchingUp, finished
}

public struct CoordinatorConfiguration: Sendable {
    public var windowSeconds: TimeInterval
    public var primeSeconds: TimeInterval
    public var prepareBudgetSeconds: TimeInterval
    /// Segments kept queued in the player for gapless playback.
    public var queuedSegments: Int

    public init(windowSeconds: TimeInterval = 60, primeSeconds: TimeInterval = 30,
                prepareBudgetSeconds: TimeInterval = 3 * 3600, queuedSegments: Int = 2) {
        self.windowSeconds = windowSeconds
        self.primeSeconds = primeSeconds
        self.prepareBudgetSeconds = prepareBudgetSeconds
        self.queuedSegments = max(1, queuedSegments)
    }
}

/// Owns the playhead, drives the scheduler and the player, publishes highlights (spec §3).
@MainActor
@Observable
public final class PlaybackCoordinator {
    public private(set) var state: PlaybackState = .idle
    public private(set) var playhead = Playhead(utteranceIndex: 0)
    public private(set) var highlight: HighlightRange?
    public private(set) var rate: Double = 1
    public private(set) var availableRates: [Double] = RateLimits.allRates
    public private(set) var measuredRTF: Double?
    public private(set) var document: Document?
    public private(set) var timeline: Timeline?
    public private(set) var timeIndex = TimeIndex(Timeline(chapters: []))
    /// Set by the app from battery, thermal, and Low Power Mode notifications.
    public var device = DeviceState.unplugged { didSet { replan() } }
    /// Queue order for the prepare tier.
    public var queue: [UUID] = [] { didSet { replan() } }

    private let engine: any SynthesisEngine
    private let store: any AudioStore
    private let player: any AudioPlaying
    private let playheadStore: any PlayheadStore
    private let scheduler: RenderScheduler
    private let configuration: CoordinatorConfiguration
    private var rendered: [Bool] = []
    private var manualRequested = false
    private var lastPlayed: UUID?
    /// Index of the segment at the head of the player and the player's consumed time when that
    /// segment started (negative right after a seek into the middle of an utterance). Index-anchored
    /// (spec §3.2): estimates turning into actuals cannot move it.
    private var headIndex = 0
    private var headStartConsumed: TimeInterval = 0
    private var lastEnqueued: Int?
    private var awaitingIndex: Int?
    private var pendingWork: Task<Void, Never>?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var renderInFlight = false
    private var eventTask: Task<Void, Never>?

    public init(engine: any SynthesisEngine, store: any AudioStore, player: any AudioPlaying,
                playheadStore: any PlayheadStore, timeSource: any TimeSource,
                configuration: CoordinatorConfiguration = CoordinatorConfiguration()) {
        self.engine = engine
        self.store = store
        self.player = player
        self.playheadStore = playheadStore
        self.configuration = configuration
        self.scheduler = RenderScheduler(engine: engine, store: store, timeSource: timeSource)
        player.onSegmentFinished = { [weak self] tag in self?.segmentFinished(tag) }
        eventTask = Task { [weak self, scheduler] in
            for await event in scheduler.events {
                guard let self else { return }
                self.apply(event)
            }
        }
    }

    // MARK: Loading

    public func load(_ document: Document, timeline: Timeline) {
        self.document = document
        self.timeline = timeline
        timeIndex = TimeIndex(timeline)
        rendered = []
        rendered.reserveCapacity(timeline.utteranceCount)
        for ch in timeline.chapters { for u in ch.utterances { rendered.append(u.audioRef != nil) } }
        manualRequested = false
        lastPlayed = document.id
        player.reset()
        playhead = timeIndex.clamp(document.resumePosition.map { PositionResolver.resolve($0, in: timeline) } ?? Playhead(utteranceIndex: 0))
        headIndex = playhead.utteranceIndex
        headStartConsumed = -playhead.offset
        lastEnqueued = nil
        awaitingIndex = nil
        state = timeline.utteranceCount == 0 ? .finished : .paused
        refreshHighlight()
        replan()
    }

    // MARK: Transport

    public func play() async {
        guard let timeline, timeline.utteranceCount > 0, state != .playing else { return }
        if state == .finished {
            await seek(to: Playhead(utteranceIndex: 0))
        }
        await fill()
        guard queuedCount > 0 else {                              // head utterance not rendered yet (spec §3.6)
            player.pause()
            state = .catchingUp
            replan()
            return
        }
        player.play()
        state = .playing
    }

    public func pause() {
        guard state == .playing || state == .catchingUp else { return }
        player.pause()
        state = .paused
        tick()
        save()
    }

    public func seek(to target: Playhead) async {
        guard let timeline, timeline.utteranceCount > 0 else { return }
        let wasPlaying = state == .playing || state == .catchingUp
        await pendingWork?.value
        player.reset()
        playhead = timeIndex.clamp(target)
        headIndex = playhead.utteranceIndex
        headStartConsumed = -playhead.offset                       // consumed 0 ⇔ `offset` into the head segment
        lastEnqueued = nil
        awaitingIndex = nil
        state = .paused
        refreshHighlight()
        save()
        replan()
        if wasPlaying { await play() }
    }

    public func seek(toTime t: TimeInterval) async { await seek(to: timeIndex.playhead(atTime: t)) }

    public func setRate(_ r: Double) {
        let clamped = min(max(r, RateLimits.allRates.first!), RateLimits.maxSustainableRate(rtf: measuredRTF))
        rate = clamped
        player.rate = clamped
        replan()
    }

    public func renderWholeDocument() {
        manualRequested = true
        replan()
    }

    /// Call on a timer while playing (and after advancing a fake player in tests): derives the
    /// playhead from the player's consumed time and refreshes the highlight.
    public func tick() {
        guard let timeline, timeline.utteranceCount > 0, state == .playing || state == .paused else { return }
        let offset = max(0, player.consumedSeconds - headStartConsumed)
        playhead = timeIndex.clamp(Playhead(utteranceIndex: headIndex, offset: offset))
        refreshHighlight()
    }

    /// Awaits segment-feeding work started by a player callback or a render event.
    public func settle() async { await pendingWork?.value }

    /// Resolves once the scheduler has drained the current plan and the resulting work has settled.
    public func waitForRenderIdle() async {
        if renderInFlight {
            await withCheckedContinuation { idleWaiters.append($0) }
        }
        await settle()
    }

    // MARK: Segments

    private var queuedCount: Int { lastEnqueued.map { max(0, $0 - headIndex + 1) } ?? 0 }

    /// Enqueues rendered segments from the head until `queuedSegments` are queued; stops at the
    /// first unrendered one and remembers it as `awaitingIndex`.
    private func fill() async {
        guard let timeline else { return }
        var next = lastEnqueued.map { $0 + 1 } ?? headIndex
        while next < timeline.utteranceCount, queuedCount < configuration.queuedSegments {
            guard rendered[next], let ref = timeline[utterance: next].audioRef,
                  let audio = try? await store.read(RenderKey(rawValue: ref)) else {
                awaitingIndex = next
                return
            }
            var clip = audio
            if next == headIndex, headStartConsumed < 0 {
                let drop = min(clip.samples.count, Int((-headStartConsumed * clip.sampleRate).rounded()))
                clip.samples.removeFirst(drop)
            }
            player.enqueue(clip, tag: next)
            lastEnqueued = next
            next += 1
        }
        awaitingIndex = nil
    }

    private func segmentFinished(_ tag: Int) {
        guard let timeline, tag == headIndex else { return }
        headStartConsumed = player.consumedSeconds
        if tag + 1 >= timeline.utteranceCount {
            state = .finished
            playhead = timeIndex.clamp(Playhead(utteranceIndex: tag, offset: .infinity))
            refreshHighlight()
            save()
            return
        }
        headIndex = tag + 1
        playhead = Playhead(utteranceIndex: headIndex, offset: 0)
        refreshHighlight()
        save()
        chain {
            await self.fill()
            if self.queuedCount == 0, self.state == .playing {     // ran into the frontier (spec §3.6)
                self.player.pause()
                self.state = .catchingUp
            }
            self.replan()
        }
    }

    /// Serializes asynchronous follow-up work so `settle()` can await all of it.
    private func chain(_ work: @escaping @MainActor () async -> Void) {
        let previous = pendingWork
        pendingWork = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    // MARK: Rendering

    private func replan() {
        guard let document, let timeline else { return }
        let snapshot = RenderSnapshot(documentID: document.id, timeline: timeline, rendered: rendered, resumeIndex: playhead.utteranceIndex)
        var input = PolicyInput(documents: [document.id: snapshot],
                                playing: PlayingState(documentID: document.id, playhead: playhead, rate: rate),
                                lastPlayed: lastPlayed, queue: queue, primes: [],
                                manual: manualRequested ? [document.id] : [], device: device)
        input.windowSeconds = configuration.windowSeconds
        input.primeSeconds = configuration.primeSeconds
        input.prepareBudgetSeconds = configuration.prepareBudgetSeconds
        let voice = document.voiceID ?? "default"
        let requests = RenderPolicy.plan(input).map { job in
            RenderRequest(job: job,
                          key: RenderKey(documentID: document.id, utteranceIndex: job.utteranceIndex, voiceID: voice,
                                         engineID: engine.engineID, normalizerVersion: timeline.normalizerVersion,
                                         segmenterVersion: timeline.segmenterVersion),
                          spoken: timeline[utterance: job.utteranceIndex].spoken, voiceID: voice)
        }
        renderInFlight = true
        let scheduler = self.scheduler
        Task { await scheduler.setPlan(requests) }
    }

    private func apply(_ event: RenderEvent) {
        switch event {
        case .rendered(let r):
            guard let document, document.id == r.documentID, timeline != nil, r.utteranceIndex < rendered.count else { return }
            var u = timeline![utterance: r.utteranceIndex]
            u.duration = .actual(r.duration)
            u.wordTimings = r.wordTimings
            u.audioRef = r.key.rawValue
            timeline![utterance: r.utteranceIndex] = u
            rendered[r.utteranceIndex] = true
            timeIndex = TimeIndex(timeline!)
            refreshHighlight()
            if awaitingIndex == r.utteranceIndex {
                chain {
                    await self.fill()
                    if self.state == .catchingUp, self.queuedCount > 0 {
                        self.player.play()
                        self.state = .playing
                    }
                }
            }
        case .failed:
            break                                                   // spec §6: logged; silence follows as .rendered
        case .storeFull:
            device.storeFull = true                                 // surfaces the storage manager (spec §6)
        case .idle:
            renderInFlight = false
            let scheduler = self.scheduler
            chain {
                self.measuredRTF = await scheduler.measuredRTF
                self.availableRates = RateLimits.availableRates(rtf: self.measuredRTF)
            }
            let waiters = idleWaiters
            idleWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    // MARK: Helpers

    private func refreshHighlight() {
        guard let timeline else { highlight = nil; return }
        highlight = Highlighter.highlight(at: playhead, in: timeline)
    }

    private func save() {
        guard let document, let timeline else { return }
        let position = PositionResolver.position(for: playhead, in: timeline)
        let store = playheadStore
        chain { await store.save(position, for: document.id) }
    }
}
```

Notes for the implementer:
- Every path that touches the store is `async` and awaited (`play`, `seek`, `fill`), and every follow-up started from a callback or an event goes through `chain`, so `settle()` and `waitForRenderIdle()` make the tests deterministic without sleeps. Do not replace `chain` with fire-and-forget `Task {}` calls.
- `headStartConsumed` is negative right after `load` or `seek` into the middle of an utterance so that `consumed − headStartConsumed == offset`; `fill` trims that many seconds off the head clip so the audio and the arithmetic agree.
- `save()` runs after `state` changes so a `.finished` save carries the clamped end position. Saved `charOffset`s in the tests reflect word timings from `FakeEngine` (the position is the start of the word being spoken), which is the same model `Highlighter` uses.
- `apply` runs on the main actor because the coordinator is `@MainActor` and the event loop is a `Task` created inside it; do not mark `apply` `nonisolated`.

**Implementation note (recorded after execution).** Idle accounting: `replan` increments `submitsInFlight`, submits through `chain`, and on return increments `expectedIdles` only when `setPlan` reported it will produce its own `.idle`; `apply(.idle)` decrements `expectedIdles`; waiters are released only when both counters are zero, so a stale `.idle` from a finished plan cannot release a waiter early. Two corrections to the code above also shipped: `fill()` must re-read `self.timeline` on every loop iteration rather than binding it once before the `await store.read`, because `.rendered` events mutate the timeline while `fill` is suspended and a stale value-type copy misses them; and the finished playhead takes its offset from the last utterance's own `duration.seconds` instead of `timeIndex.clamp(…, offset: .infinity)`, whose prefix-sum subtraction can lose a ULP against the test's exact `1.2`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PlaybackCoordinatorTests`
Expected: 8 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SAudio Tests/T2SAudioTests
git commit -m "Add PlaybackCoordinator: playhead ownership, catching-up, rate coupling, position saves"
```

---

### Task 12: End-to-end with a real `AudioPlayer`

**Files:**
- Create: `Tests/T2SAudioTests/EndToEndTests.swift`

**Interfaces:**
- Consumes everything above. No new production code.

- [ ] **Step 1: Write the test**

```swift
// Tests/T2SAudioTests/EndToEndTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@MainActor
@Suite struct EndToEndTests {
    /// Segmenter → TimelineBuilder → coordinator → FakeEngine → FileAudioStore(AAC) → real AudioPlayer (offline).
    @Test func playsAShortDocumentThroughTheRealPlayer() async throws {
        let block = SourceBlock(text: "First sentence here. Second one follows. Third ends it.",
                                position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 0))
        let timeline = TimelineBuilder.build(chapters: [ChapterInput(title: "C", position: block.position, blocks: [block])],
                                             segmenter: Segmenter(normalizer: TextNormalizer()))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-e2e-\(UUID().uuidString)")
        let store = FileAudioStore(directory: dir, codec: AACCodec(), capacityBytes: 50_000_000)
        let player = try AudioPlayer(manualRendering: true)
        let saves = MemoryPlayheadStore()
        let c = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: store, player: player,
                                    playheadStore: saves, timeSource: SystemTimeSource())
        c.load(Document(title: "E2E", sourceType: .article), timeline: timeline)
        await c.waitForRenderIdle()
        #expect(c.timeline?.isFullyRendered == true)                // 60 s window covers the whole 2.75 s document

        await c.play()
        #expect(c.state == .playing)
        try player.renderOffline(seconds: 0.5); c.tick()
        #expect(c.playhead.utteranceIndex == 0)
        #expect(c.highlight != nil)
        try player.renderOffline(seconds: 1.0)
        for _ in 0..<20 { await Task.yield() }                     // let the .dataPlayedBack hop land
        await c.settle(); c.tick()
        #expect(c.playhead.utteranceIndex >= 1)
        try player.renderOffline(seconds: 3.0)
        for _ in 0..<20 { await Task.yield() }
        await c.settle(); c.tick()
        #expect(c.state == .finished)
        #expect(await saves.last?.charOffset != nil)
        let stats = await store.stats()
        #expect(stats.entries == 3 && stats.bytes < 60_000)         // AAC, not raw PCM
    }
}
```

- [ ] **Step 2: Run it**

Run: `swift test --filter EndToEndTests`
Expected: 1 test passed. If the AAC decode of a 1 s silence clip comes back a few frames short, the coordinator's arithmetic is unaffected because `consumedSeconds` is clamped to scheduled frames; do not widen tolerances in the coordinator tests.

- [ ] **Step 3: Full suite and guard, then commit**

Run: `swift test && scripts/check-licenses.sh`
Expected: every suite passes; guard exits 0.

```bash
git add Tests/T2SAudioTests/EndToEndTests.swift
git commit -m "Add end-to-end playback test through the real AudioPlayer"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| §3.2 index-anchored runtime playhead; estimate→actual never moves it | 2 (`TimeIndex`, §8 property test), 11 |
| §3.3 phase 2 fills in actual durations and timings | 8, 11 |
| §3.4 window in playback-seconds; serial; seek flush; backpressure; AAC 32 kbps mono 24 kHz; no raw PCM persisted; LRU cap; one document at a time | 7, 8, 9, 5, 11 |
| §3.4.1 tiers, priority order, budget, guards, manual | 7, 11 |
| §3.5 engine graph, gapless per-utterance scheduling, 0.5x–4x with pitch correction, playerTime | 10 |
| §3.6 window resizes with rate; measured RTF; unsustainable rates unavailable; underrun pauses with catching-up | 6, 8, 11 |
| §5 renderKey inputs; versions from the timeline | 4, 11 |
| §6 synthesis failure → 200 ms silence; disk full → pause, evict, surface; playhead past end → clamp, finished | 8, 5, 11 |
| §8 RenderScheduler tests (window, seek flush, backpressure, rate resize, underrun) | 7, 8, 11 |
| §8 Player: playhead against known silence | 10 |
| §8 Timeline property test | 2 |
| §8 end-to-end | 12 |

Not in this plan, by design: Now Playing / remote commands, sleep timer, and the pronunciation-dictionary UI (spec §9 step 9, Plan 5); SwiftData persistence of positions (Plan 3 implements `PlayheadStore`); the Readium reader view (Plan 4).
