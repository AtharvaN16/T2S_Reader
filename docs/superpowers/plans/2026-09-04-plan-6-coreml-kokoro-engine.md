# Plan 6: Core ML Kokoro Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Kokoro the app's working voice on the owner's iPhone 11 Pro and every other phone, through the Core ML runtime that Plan 0 Task 8 measured, with real word timings for read-along.

**Architecture:** One Kokoro engine in the app, `KokoroCoreMLEngine` in `Packages/T2SKokoro`, drives `mattmireles/kokoro-coreml`'s low-level `KokoroPipeline` package (vendored as `Packages/KokoroPipeline`, the way `MLXUtilsLibrary` is). Text → MisakiSwift phonemes → Kokoro's 178-symbol vocabulary → token IDs → four fp16 Core ML stages on the CPU → 24 kHz PCM plus per-token duration frames, which fold into per-word `WordTiming`s. The engine's identity travels in the voice ID (`kokoro:kokoro-coreml-2e878c6a-misaki1.0.6:<voice>`), so `RenderKey` separates its audio from the system voice and from anything the MLX engine ever rendered; the identity deliberately omits the compute policy, because CPU versus GPU/ANE units do not change the voice, and a later policy change must not orphan cached audio. `RoutedEngine` learns to hold several Kokoro engines keyed by identity: the Core ML engine is the default route on every phone, and the existing MLX engine (`KokoroEngine`, gated on its measured decision or the development override exactly as Plan 5 left it) stays wired beside it so the collaborator's iPhone 17 Pro build can play MLX voices and be benchmarked without a second integration pass (owner's decision 2026-09-04). The resolver seam maps the app's "default" voice to Kokoro Heart on the Core ML route when it is available, so Kokoro becomes the default voice without touching any stored document; an MLX voice is chosen explicitly in Preferences and falls back per its own availability. The published MLX numbers on A14–A17 phones (RTF 0.24–0.34, an out-of-memory failure on long sentences on a 4 GB phone) are slower than Core ML's measured 0.18 at 119 MB on the A13, which is why Core ML is the default; the 17 Pro measurement decides whether MLX or the GPU/ANE Core ML policy ever earns the default on newer chips, and either is a constant change, not a plan.

**Tech Stack:** Swift 6, Core ML (`MLModel`, `MLComputeUnits.cpuOnly`), `KokoroPipeline` (Apache-2.0, vendored), MisakiSwift 1.0.6 (already linked via kokoro-ios; its out-of-lexicon fallback runs on MLX and is pinned to the CPU), `scripts/test-kokoro.sh` (xcodebuild on macOS — Core ML runs on the Mac, so the engine is exercised with the real models), xcodegen, `devicectl`.

**Spec:** `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (rev 9): §3.4, §3.6, §5, §6, §7.3–§7.5. Findings: `spikes/findings/2026-09-04-pre-a14-runtime.md` (the numbers), `spikes/findings/2026-09-03-pre-a14-runtime-options.md` (the choice). Reference implementation of the token path, model provider, and timing fold: `spikes/SpikeHarness/SpikeHarness/CoreMLBench.swift` (throwaway; port, do not import).

## Global Constraints

- **Render correctness is structural** (spec §5): every engine's identity is in the voice ID; a voice or engine change makes a different `RenderKey`; old cache entries are never accepted merely because an `audioRef` is non-nil.
- **Rate policy unchanged** (spec §3.6): the rolling RTF measures the selected engine; unavailable rates are disabled, never lowered. The Core ML decision's measured RTF is 0.181 flat out / 0.163 at 4x on the A13 → `RateLimits.maxSustainableRate` = 4.0; nothing is capped.
- **Failure policy** (spec §6): an engine failure is surfaced per utterance and filled with 200 ms of silence; it must not halt a book. Availability is decided at configuration time, whole document, never mid-utterance.
- **Licences** (spec §3.7.5): `KokoroPipeline` and the Core ML model files are Apache-2.0; vendored code keeps its LICENSE and a README naming the upstream revision and every local patch; `docs/licenses.md` gains the rows; `scripts/check-licenses.sh` stays green. No espeak-ng anywhere.
- **Resources are never committed**: `App/Resources/KokoroCoreML/` is git-ignored and filled by `scripts/fetch-kokoro-coreml.sh --app`; every fetched file is sha256-verified against the upstream manifest (files from HF revision `2e878c6a33c56b40de094ef8237bf15a83d233c5`, hashes from the manifest at `32399b333e809044c404c518cb3807a488e8f47d`, whose stale-manifest story the script header already tells).
- **Where the engine lives**: MisakiSwift links mlx-swift, and mlx-swift cannot link for the iOS Simulator, so the Core ML engine ships in the device-only `T2SReaderKokoro` target (the app the owner installs) and in the macOS test bundle. `T2SReader` (simulator, CI) keeps the system voice. HANDOFF's line saying the engine "belongs in the everyday target" is corrected in Task 6.
- **Swift 6 strict concurrency**; public types `Sendable`, actor-isolated, or `@MainActor`; token-only SwiftUI; one conventional commit per task with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`; `scripts/test-kokoro.sh` after every package edit, root `swift test` after every root edit, `scripts/build-device.sh` after app edits.
- Exact identities: engine `kokoro-coreml-2e878c6a-misaki1.0.6`; voice `kokoro:kokoro-coreml-2e878c6a-misaki1.0.6:af_heart`; sample rate 24 000; 600 samples (25 ms) per duration frame; BOS/EOS/pad token id 0; voice table rows = `clamp(phonemeUTF16Count − 1, 0, rows − 1)`; buckets 7 s and 15 s; duration models t128 and t256.

## File structure

```
Packages/KokoroPipeline/                 vendored swift/ of mattmireles/kokoro-coreml @ 66d8cf5108cce0991b8868b01b4d8a8b2e98881d
  Package.swift, LICENSE, README.md, Sources/KokoroPipeline/*.swift (unchanged upstream)
Packages/T2SKokoro/Sources/T2SKokoro/
  CoreML/KokoroCoreMLResources.swift     locate the compiled stages, voices, vocab, hnsf weights
  CoreML/KokoroCoreMLDecision.swift      the measured A13 constants (non-nil)
  CoreML/KokoroTokenizer.swift           vocab + voice tables + Misaki token → ids with word owners
  CoreML/KokoroCoreMLModels.swift        KokoroModelProvider over MLModel(contentsOf:) with CPU-only units
  CoreML/KokoroCoreMLEngine.swift        the actor: G2P, tokenize, synthesize, timings
  CoreML/KokoroCoreMLAvailability.swift  resources + decision → verdict, memoized model
  KokoroTokenTimingMapper.swift          the [] gate opens for tokens that carry times
Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/*.swift
Sources/T2SAudio/RoutedEngine.swift      several Kokoro engines keyed by identity
Sources/T2SApp/Preferences/VoiceRouting.swift   one route per identity; "default" → Kokoro Heart on Core ML
Sources/T2SApp/Preferences/KokoroVoiceCatalog.swift   unchanged API, fed the Core ML identity
App/T2SReader/System/KokoroComposition.swift    both engines; Core ML primary; warm-up + status
App/T2SReader/System/GatedKokoroCoreMLEngine.swift
App/T2SReader/Preferences/VoiceListPage.swift, PreferencesPage.swift   default-voice label
App/project.yml                          Resources/KokoroCoreML into T2SReaderKokoro
scripts/fetch-kokoro-coreml.sh           --app mode: App/Resources/KokoroCoreML, all voices
docs/licenses.md, docs/HANDOFF.md, README.md, roadmap
```

---

### Task 1: Vendor `KokoroPipeline` and stage the app's model files

**Files:**
- Create: `Packages/KokoroPipeline/Package.swift`, `Packages/KokoroPipeline/LICENSE`, `Packages/KokoroPipeline/README.md`, `Packages/KokoroPipeline/Sources/KokoroPipeline/*.swift` (copied verbatim from the pinned clone's `swift/Sources/KokoroPipeline/`)
- Modify: `scripts/fetch-kokoro-coreml.sh` (an `--app` mode), `.gitignore`, `docs/licenses.md`, `Packages/T2SKokoro/Package.swift`
- Test: `Packages/KokoroPipeline/Tests/KokoroPipelineTests/ConstantsTests.swift`

**Interfaces:**
- Consumes: the clone at `spikes/SpikeHarness/.deps/kokoro-coreml` (run `scripts/fetch-kokoro-coreml.sh` first if absent) at commit `66d8cf5108cce0991b8868b01b4d8a8b2e98881d`.
- Produces: SwiftPM product `KokoroPipeline` (`executeKokoroSynthesis(request:modelProvider:linearWeights:linearBias:tensorDump:)`, `KokoroSynthesisRequest(inputIds:attentionMask:refS:speed:)`, `KokoroModelProvider`, `DurationModelChoice`, `PipelineConstants`, `KokoroVocabulary.bosEosTokenId`, `SynthesisResult` with `audio`, `tokenDurationFrames`, `bucketSeconds`, `wallTimeSeconds`); `App/Resources/KokoroCoreML/{coreml/*.mlpackage, voices/*.bin, runtime/kokoro-vocab.json, runtime/hnsf_weights.json}` on this machine.

- [ ] **Step 1: Copy the package and write the failing constants test**

```bash
mkdir -p Packages/KokoroPipeline/Sources Packages/KokoroPipeline/Tests/KokoroPipelineTests
cp -R spikes/SpikeHarness/.deps/kokoro-coreml/swift/Sources/KokoroPipeline Packages/KokoroPipeline/Sources/
cp spikes/SpikeHarness/.deps/kokoro-coreml/LICENSE Packages/KokoroPipeline/LICENSE
```

`Packages/KokoroPipeline/Package.swift` (tools 5.9 like upstream, platforms `.iOS(.v16), .macOS(.v14)`, one library product `KokoroPipeline`, a test target). `README.md` (≤ 12 lines): upstream URL, commit `66d8cf51…`, "unchanged; vendored because the upstream repo root has no Package.swift", the exit plan (consume by URL if upstream ever moves the manifest to the root).

```swift
// Packages/KokoroPipeline/Tests/KokoroPipelineTests/ConstantsTests.swift
import Testing
@testable import KokoroPipeline

@Suite struct ConstantsTests {
    @Test func frameAndSampleConstantsMatchTheMeasuredPipeline() {
        #expect(PipelineConstants.sampleRate == 24_000)
        #expect(PipelineConstants.samplesPerDurationFrame == 600)
        #expect(PipelineConstants.voiceEmbeddingDim == 256)
        #expect(KokoroVocabulary.bosEosTokenId == 0)
        #expect(PipelineConstants.tFramesForBucket[7] == 280 && PipelineConstants.tFramesForBucket[15] == 600)
    }
}
```

- [ ] **Step 2: Run it to see it fail (no package yet resolves)**

Run: `cd Packages/KokoroPipeline && swift test`
Expected: manifest/target errors until the package is complete; then PASS after Step 3.

- [ ] **Step 3: Finish the manifest, wire T2SKokoro, extend the fetch script**

`Packages/T2SKokoro/Package.swift`: add `.package(name: "KokoroPipeline", path: "../KokoroPipeline")` and the product to both targets.

`scripts/fetch-kokoro-coreml.sh`: keep the spike mode as is; add `--app`, which stages into `App/Resources/KokoroCoreML/` the same two buckets and duration models, `runtime/kokoro-vocab.json`, `runtime/hnsf_weights.json`, and **the 28 English voices** — the `KokoroVoiceCatalog.voiceNames` set — as `.bin` files (at the pinned revision the top-level `voices/` holds only 7 of them; the full set is under `kokoro.js/voices/`; each is verified against its HF LFS oid, which is the file's sha256, with `af_heart` cross-checked against the manifest), without the `.deps` clone. `.gitignore` gains `App/Resources/KokoroCoreML/`.

`docs/licenses.md`: a "Vendored" row for KokoroPipeline (commit, Apache-2.0, `Packages/KokoroPipeline/LICENSE`) and a Kokoro-path row for the Core ML model files (Apache-2.0, inherited from Kokoro-82M; source `mattmireles/kokoro-coreml` revision `2e878c6a`).

- [ ] **Step 4: Verify**

Run: `cd Packages/KokoroPipeline && swift test` → 1 test passes. `scripts/fetch-kokoro-coreml.sh --app` twice (second run: everything already installed; list `App/Resources/KokoroCoreML` — 28 voice files). `scripts/check-licenses.sh` → exit 0. `scripts/test-kokoro.sh` → unchanged 56 tests pass (the new dependency links).

- [ ] **Step 5: Commit**

```bash
git add Packages/KokoroPipeline Packages/T2SKokoro/Package.swift Packages/T2SKokoro/Package.resolved scripts/fetch-kokoro-coreml.sh .gitignore docs/licenses.md
git commit -m "Kokoro: vendor KokoroPipeline and stage the Core ML model files for the app"
```

---

### Task 2: Resources contract, measured decision, tokenizer

**Files:**
- Create: `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLResources.swift`, `CoreML/KokoroCoreMLDecision.swift`, `CoreML/KokoroTokenizer.swift`
- Test: `Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroCoreMLResourcesTests.swift`, `KokoroCoreMLDecisionTests.swift`, `KokoroTokenizerTests.swift`

**Interfaces:**
- Consumes: `KokoroPipeline` constants; `KokoroTestSupport.haveRealFiles` pattern from the existing tests.
- Produces:

```swift
public enum KokoroCoreMLResources {
    public static let modelRevision = "2e878c6a33c56b40de094ef8237bf15a83d233c5"
    public static let revisionPrefix = "2e878c6a"
    public static let buckets = [7, 15]
    public static let durationTokenLengths = [128, 256]
    public struct Located: Hashable, Sendable {
        public let stages: [String: URL]   // "kokoro_duration_t128" → .mlmodelc or .mlpackage URL
        public let voices: [String: URL]   // "af_heart" → .bin
        public let vocab: URL
        public let hnsfWeights: URL
        public var isPrecompiled: Bool     // true when every stage URL ends in .mlmodelc
    }
    public enum Failure: Error, Hashable, Sendable, LocalizedError { case missing(String), noVoices }
    public static func stageNames(buckets: [Int] = buckets, durationTokenLengths: [Int] = durationTokenLengths) -> [String]
    public static func locate(in bundle: Bundle) -> Result<Located, Failure>          // .mlmodelc flat in the bundle root
    public static func locate(inDirectory directory: URL) -> Result<Located, Failure>  // coreml/*.mlpackage layout (dev, tests)
    public static var developmentDirectory: URL                                      // <repo>/App/Resources/KokoroCoreML via #filePath
}

public struct KokoroCoreMLDecision: Hashable, Sendable {
    public let modelRevision: String, runtime: String /* "coreml-cpu" */, measuredRTF: Double, maxSustainableRate: Double,
               peakFootprintBytes: Int, source: String
    public static let current: KokoroCoreMLDecision   // rtf 0.181, footprint 119 MiB, source "spikes/findings/2026-09-04-pre-a14-runtime.md"
}

public struct KokoroTokenizer: Sendable {
    public static let boundary: Int32 = 0
    public init(vocabURL: URL, voiceURL: URL) throws
    public var voiceRowCount: Int
    public func refS(phonemeUTF16Count: Int) -> [Float]                         // clamp(count−1, 0, rows−1)
    public func tokenize(phonemes: String, ownersByCharacter: [Int]) -> (ids: [Int32], owners: [Int], dropped: Int)
}
```

- [ ] **Step 1: Failing tests**

```swift
@Suite struct KokoroCoreMLDecisionTests {
    @Test func theMeasuredDecisionOffersEveryRate() {
        let d = KokoroCoreMLDecision.current
        #expect(d.measuredRTF == 0.181 && d.maxSustainableRate == 4.0 && d.runtime == "coreml-cpu")
        #expect(d.source.hasSuffix("2026-09-04-pre-a14-runtime.md"))
    }
}
@Suite struct KokoroCoreMLResourcesTests {
    @Test func stageNamesCoverBothBucketsAndBothDurationModels() {
        #expect(Set(KokoroCoreMLResources.stageNames()) == ["kokoro_duration_t128", "kokoro_duration_t256",
            "kokoro_f0ntrain_t280", "kokoro_f0ntrain_t600", "kokoro_decoder_pre_7s", "kokoro_decoder_pre_15s",
            "kokoro_decoder_har_post_7s", "kokoro_decoder_har_post_15s"])
    }
    @Test func anEmptyDirectoryIsMissingItsFirstStage() { /* temp dir → .failure(.missing("kokoro_duration_t128")) */ }
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles)) func theDevelopmentDirectoryLocates28Voices() {
        let located = try #require(try KokoroCoreMLResources.locate(inDirectory: KokoroCoreMLResources.developmentDirectory).get())
        #expect(located.voices.count == 28 && located.isPrecompiled == false)
    }
}
@Suite struct KokoroTokenizerTests {
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles)) func tokenizesEveryVocabSymbolAndDropsUnknowns() throws {
        let t = try KokoroTokenizer(vocabURL: ..., voiceURL: ...)   // from the development directory
        let r = t.tokenize(phonemes: "hˈɛlO wˈɜɹld❓", ownersByCharacter: Array(repeating: 0, count: 13))
        #expect(r.dropped == 1 && r.ids.count == 12 && r.owners.count == 12)
        #expect(t.refS(phonemeUTF16Count: 5).count == 256 && t.refS(phonemeUTF16Count: 10_000) == t.refS(phonemeUTF16Count: t.voiceRowCount))
    }
}
```

- [ ] **Step 2: Run** `scripts/test-kokoro.sh` → compile failures for the three types.
- [ ] **Step 3: Implement** the three files. `locate(in:)` looks up each stage as `<name>.mlmodelc` at the bundle root, every `*.bin` in the bundle as a voice (name = file stem), `kokoro-vocab.json` and `hnsf_weights.json`; `locate(inDirectory:)` uses the `coreml/`, `voices/`, `runtime/` layout with `.mlpackage`. `KokoroTestSupport.haveCoreMLFiles` = `locate(inDirectory: developmentDirectory)` succeeds. Tokenizer: port `KokoroTokenizer` from `CoreMLBench.swift` (vocab JSON `{"vocab": {...}}`, little-endian f32 voice rows of 256, drop characters without a vocab entry), but take `ownersByCharacter` (one owner index per phoneme character) instead of `[MToken]`, so the tokenizer has no MisakiSwift import.
- [ ] **Step 4: Run** `scripts/test-kokoro.sh` → all pass (model-backed ones run on this Mac).
- [ ] **Step 5: Commit** `Kokoro: Core ML resources contract, measured decision, tokenizer`

---

### Task 3: The engine and real word timings

**Files:**
- Create: `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLModels.swift`, `CoreML/KokoroCoreMLEngine.swift`
- Modify: `Packages/T2SKokoro/Sources/T2SKokoro/KokoroTokenTimingMapper.swift`
- Test: `Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroCoreMLEngineTests.swift`, `KokoroTokenTimingMapperTests.swift` (extend)

**Interfaces:**
- Consumes: Task 2 types; `KokoroPipeline`; `MisakiSwift.EnglishG2P(british:)` (`phonemize(text:) -> (String, [MToken])`); `KokoroVoiceID`; `SynthesisEngine`.
- Produces:

```swift
public actor KokoroCoreMLEngine: SynthesisEngine {
    public static let runtime = "coreml-cpu"
    public static let identity = "kokoro-coreml-\(KokoroCoreMLResources.revisionPrefix)-misaki1.0.6"
    public nonisolated let engineID = KokoroCoreMLEngine.identity
    public init(resources: KokoroCoreMLResources.Located)
    /// Loads the eight stages (compiling .mlpackage on the fly when not precompiled) and the vocab.
    public func preload() throws
    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult
}
public enum KokoroCoreMLError: Error, Equatable, Sendable, LocalizedError {
    case voiceNotForThisEngine(String), unknownVoice(String), tooManyTokens(Int), stageFailed(String), emptyAudio
}
```

`KokoroTokenTimingMapper.map` now forwards to `candidateTimings` (the §7.4 gate opened for this runtime on 2026-09-04: onset error ≤ 55 ms against the WAV); the doc comment cites the finding.

- [ ] **Step 1: Failing tests**

```swift
@Suite(.serialized) struct KokoroCoreMLEngineTests {
    @Test func identityIsPinnedToTheRevisionAndRuntime() {
        #expect(KokoroCoreMLEngine.identity == "kokoro-coreml-2e878c6a-misaki1.0.6")
    }
    @Test func refusesAnotherEngineIdentityBeforeLoading() async {
        let engine = KokoroCoreMLEngine(resources: .init(stages: [:], voices: [:], vocab: URL(filePath: "/nope"), hnsfWeights: URL(filePath: "/nope"), isPrecompiled: false))
        await #expect(throws: KokoroCoreMLError.voiceNotForThisEngine("kokoro:other:af_heart")) {
            try await engine.synthesize(.init(spoken: "Hello", voiceID: "kokoro:other:af_heart"))
        }
    }
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles)) func synthesizesWithWordTimings() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try KokoroCoreMLResources.locate(inDirectory: .developmentDirectory).get())
        let result = try await engine.synthesize(.init(spoken: "The quick brown fox jumps over the lazy dog.",
                                                      voiceID: "kokoro:\(KokoroCoreMLEngine.identity):af_heart"))
        #expect(result.audio.sampleRate == 24_000 && (1...6).contains(result.audio.duration))
        let rms = (result.audio.samples.map { $0 * $0 }.reduce(0, +) / Float(result.audio.samples.count)).squareRoot()
        #expect(rms > 0.01)
        #expect(result.wordTimings.count == 9)                         // nine words, no timing for the period
        #expect(result.wordTimings.map(\.start) == result.wordTimings.map(\.start).sorted())
        #expect(result.wordTimings.last!.end <= result.audio.duration + 0.001)
        #expect(result.wordTimings.first!.spokenRange == 0..<3)        // "The"
    }
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles)) func britishVoicesUseTheBritishG2P() async throws { /* bf_emma, duration > 0.5 */ }
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles)) func rejectsAnUnknownVoice() async throws { /* zz_nobody → .unknownVoice */ }
}
```

Mapper tests: `map` now returns the candidate timings for a well-formed token list (the earlier "always []" test is replaced by one that documents the opened gate), and still `[]` when a token cannot be located in `spoken`.

- [ ] **Step 2: Run** → compile failures.
- [ ] **Step 3: Implement**
  - `KokoroCoreMLModels: KokoroModelProvider` — port `CoreMLModelBundle` from `CoreMLBench.swift` with every stage on `.cpuOnly`; loads `MLModel(contentsOf:)` for `.mlmodelc`, and `MLModel.compileModel(at:)` into a per-process temp directory first when `isPrecompiled == false`.
  - `KokoroCoreMLEngine` — actor with `DispatchSerialQueue(label: "com.t2s.reader.kokoro-coreml", qos: .userInitiated)` as its executor (same pattern as `KokoroEngine`). `synthesize` order: parse `KokoroVoiceID` and require `engineID == self.engineID` → non-blank text → `try Task.checkCancellation()` → lazy load (models, tokenizer per voice table, `EnglishG2P(british:)` created lazily per language with MLX pinned to the CPU exactly as `CoreMLBench` does) → phonemize → tokenize with owners (build `ownersByCharacter` by walking `[MToken]`: each token contributes `(phonemes ?? "❓") + whitespace` characters owned by that token index) → frame `[0] + ids + [0]`, reject if `> 256` with `.tooManyTokens` → pad to 256 with boundary ids and a 0 mask → `executeKokoroSynthesis` with `refS(phonemeUTF16Count:)`, `speed: 1.0` → guard non-empty finite samples → fold `tokenDurationFrames` per Misaki word token (frames of the ids the word owns, **excluding its trailing whitespace character's frames**, which belong to no word; punctuation-only tokens produce no timing) into `KokoroToken(text: token.text, whitespace: token.whitespace, start:, end:)` in seconds (`frames × 600 / 24000`) → `KokoroTokenTimingMapper.map(tokens, spoken:, duration:)`.
  - Any pipeline error → `.stageFailed(String(describing: error))`; never log the text.
- [ ] **Step 4: Run** `scripts/test-kokoro.sh` → all pass; record the Mac RTF in the report.
- [ ] **Step 5: Commit** `Kokoro: Core ML engine with real word timings`

---

### Task 4: Availability, multi-engine routing, Kokoro Heart as the default voice

**Files:**
- Create: `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLAvailability.swift`
- Modify: `Sources/T2SAudio/RoutedEngine.swift`, `Sources/T2SApp/Preferences/VoiceRouting.swift`, `Sources/T2SApp/Preferences/KokoroVoiceCatalog.swift`, `Tests/T2SAudioTests/RoutedEngineTests.swift`, `Tests/T2SAppTests/VoiceRoutingTests.swift`, `Tests/T2SAppTests/KokoroVoiceCatalogTests.swift`, `Tests/T2SAppTests/PlayerModelTests.swift`, `Tests/T2SAppTests/PrepareRunnerTests.swift`
- Test: `Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroCoreMLAvailabilityTests.swift`

**Interfaces:**
- Produces:

```swift
public enum KokoroCoreMLAvailability {
    public enum Reason: Hashable, Sendable, CustomStringConvertible { case resources(KokoroCoreMLResources.Failure) }
    public enum Verdict: Hashable, Sendable { case available(decision: KokoroCoreMLDecision, resources: KokoroCoreMLResources.Located); case unavailable(Reason) }
    public static func check(bundle: Bundle) -> Verdict     // synchronous: presence only, no hashing (checksums were verified at fetch time)
}
@MainActor @Observable public final class KokoroCoreMLAvailabilityModel {
    public enum State: Hashable, Sendable { case checking, available(KokoroCoreMLDecision), unavailable(String) }
    public private(set) var state: State
    public init(bundle: Bundle = .main)
    public var verdict: KokoroCoreMLAvailability.Verdict { get }
}

// RoutedEngine — several Kokoro engines, matched by engineID; the old single-engine init stays as a convenience
public init(system: any SynthesisEngine, kokoro: [any SynthesisEngine], configuration: ..., key: ..., session: URLSession = .shared)

// VoiceRouting — one route per Kokoro identity, plus the default-voice rule
public struct KokoroVoiceRouting: VoiceRouteResolving {
    public struct Route: Sendable {
        public let engineIdentity: String
        public let isAvailable: @Sendable () async -> Bool
        public init(engineIdentity: String, isAvailable: @escaping @Sendable () async -> Bool)
    }
    /// `defaultVoice` is a full Kokoro voice ID (Heart on the Core ML identity); when that identity's route
    /// is available, "default" / VoiceOption.systemDefault.id resolve to it.
    public init(routes: [Route], defaultVoice: String?)
    public static let unavailable: KokoroVoiceRouting       // no routes, no default
}

// KokoroVoiceCatalog — voices for every identity handed to it, each name suffixed by its runtime
public init(base: any VoiceCatalog, engines: [(identity: String, label: String)])   // e.g. [(coreML, "Kokoro"), (mlx, "Kokoro · MLX")]
```

- [ ] **Step 1: Failing tests**: `RoutedEngineTests` — two recording engines with different identities each receive exactly their own IDs (request unchanged); an unknown identity throws `KokoroRouteError.unavailable`; the single-engine init still works. `VoiceRoutingTests` — with the Core ML route available and `defaultVoice` set, `"default"` and `VoiceOption.systemDefault.id` resolve to `kokoro:kokoro-coreml-2e878c6a-misaki1.0.6:af_heart`; when that route is unavailable they stay `"default"`; a Core ML ID passes through when available and falls back when not; an MLX ID (`kokoro:kokoro-4e9ecdf0-mlx-misaki1.0.6:af_heart`) passes through only when the MLX route is available and otherwise falls back to `"default"`; an identity with no route falls back; `system:` and `cloud:` IDs are untouched. `KokoroVoiceCatalogTests` — two identities produce 56 options, Core ML first, MLX names carrying " · MLX". `PlayerModelTests` — a document with a nil voice renders with the Kokoro default when the Core ML route is available (the fake engine records the request's voice ID) and its stored `voiceID` stays nil; `PrepareRunnerTests` likewise. `KokoroCoreMLAvailabilityTests` — a bundle without the stages → `.unavailable(.resources(.missing("kokoro_duration_t128")))`; `.enabled(if: haveCoreMLFiles)`: the development directory (through a test-only `check(directory:)`) → `.available` with `KokoroCoreMLDecision.current`.
- [ ] **Step 2: Run** `swift test` and `scripts/test-kokoro.sh` → failures.
- [ ] **Step 3: Implement**. `RoutedEngine` keeps a `[String: any SynthesisEngine]` by `engineID`. The resolver's rule, in order: a `kokoro:` ID whose identity has a route → pass through when that route is available, else `"default"`; a `kokoro:` ID with no route → `"default"`; `"default"` / systemDefault → `defaultVoice` when its identity's route is available, else unchanged; anything else unchanged.
- [ ] **Step 4: Run** both suites → green; `scripts/build-app.sh` still compiles.
- [ ] **Step 5: Commit** `Audio: route several Kokoro engines by identity; Kokoro Heart on Core ML is the default voice`

---

### Task 5: App wiring, warm-up, device build, first listen on the iPhone 11 Pro

**Files:**
- Create: `App/T2SReader/System/GatedKokoroCoreMLEngine.swift`
- Modify: `App/T2SReader/System/KokoroComposition.swift`, `App/T2SReader/AppEnvironment.swift`, `App/T2SReader/Preferences/VoiceListPage.swift`, `App/T2SReader/Preferences/PreferencesPage.swift`, `App/project.yml`, `scripts/build-device.sh` (header only), `.github/workflows/ci.yml` (nothing new to run; note the resources are absent in CI)

**Interfaces:**
- Consumes: Tasks 2–4. Produces: `KokoroStatus` gains `.preparing` ("Preparing the Kokoro voice…") shown during warm-up.

- [ ] **Step 1: `project.yml`** — `T2SReaderKokoro` gains `- path: Resources/KokoroCoreML, buildPhase: resources` (Xcode compiles each `.mlpackage` to `.mlmodelc` at the bundle root; add `COREML_CODEGEN_LANGUAGE: None` to that target's settings, as the spike harness did). The template's `Resources` path also excludes `KokoroCoreML`.
- [ ] **Step 2: Composition** — under `KOKORO_ENGINE`: build `KokoroCoreMLAvailabilityModel` and a `GatedKokoroCoreMLEngine` (same shape as `GatedKokoroEngine`: one `Task` that creates `KokoroCoreMLEngine` after `.available`, then `preload()`); keep the MLX `GatedKokoroEngine` and its availability model exactly as they are; pass `kokoro: [coreML, mlx]` to `RoutedEngine`; `KokoroVoiceRouting(routes: [Route(coreML identity) { Core ML verdict is .available }, Route(MLX identity) { MLX verdict is .available }], defaultVoice: "kokoro:\(KokoroCoreMLEngine.identity):af_heart")`; catalog fed `[(KokoroCoreMLEngine.identity, "Kokoro"), (KokoroEngine.identity, "Kokoro · MLX")]` — the MLX voices are listed only when the MLX route is available (17 Pro with the development override), so the picker on the owner's phone shows one set. `KokoroStatus` reports the Core ML route (`.preparing`, `.available`, `.unavailable(reason)`) and, separately, the MLX route's state on a second footer line only when it is not `.notLinked`/unavailable-by-design ("MLX route: waiting for the device measurements" / "MLX route: development override active"). At launch, when the Core ML verdict is `.available`, start a warm-up `Task` that calls the gated engine's `preload()` and moves the status `.preparing` → `.available(isDebugOverride: false)`; log the seconds. Status text: `.preparing` → "Preparing the Kokoro voice (one-time, up to a few minutes on the first launch)…".
- [ ] **Step 3: Preferences** — the "Default voice" row's subtitle resolves through the routing (shows "Heart · Kokoro" when that is what "default" means); the Kokoro group lists the Core ML voices; the footer shows the new status.
- [ ] **Step 4: Verify** — `swift test`; `scripts/build-app.sh` (everyday target unchanged); `scripts/build-device.sh` → `BUILD SUCCEEDED` and `T2SReaderKokoro.app` contains the eight `.mlmodelc` bundles, 28 `.bin` voices, both JSON files. Then, with the owner present, install on the iPhone 11 Pro with the owner's team (Xcode, scheme `T2SReaderKokoro`, or `xcodebuild … CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=V69PL7U8EX ENABLE_DEBUG_DYLIB=NO` + `devicectl install`), launch, watch the warm-up status, import an EPUB, play: Kokoro Heart speaks by default, read-along highlights follow words, 2x and 4x are offered, lock-screen controls work. Record load time, first-utterance latency, and any failure in the report.
- [ ] **Step 5: Commit** `App: Core ML Kokoro as the default voice on the device build, with first-launch warm-up`

---

### Task 6: Documentation

**Files:** `README.md`, `docs/HANDOFF.md`, `docs/superpowers/plans/2026-09-02-t2s-reader-roadmap.md`, `docs/licenses.md` (verify)

- [ ] **Step 1:** README: layout gains `Packages/KokoroPipeline/` and `App/Resources/KokoroCoreML/`; "Working on it": `scripts/fetch-kokoro-coreml.sh --app` once per machine; which scheme to build for a phone (`T2SReaderKokoro` is the app; `T2SReader` is the simulator/CI build with the system voice, because MisakiSwift links MLX); the first-launch warm-up.
- [ ] **Step 2:** HANDOFF: "What comes after" item 3 → done, and correct the sentence claiming the engine belongs in the everyday target (it cannot: MisakiSwift → mlx-swift → no simulator); the manual matrix gains the Task 5 hardware rows with what was observed; known issues: the two-target split now means "the phone app is `T2SReaderKokoro`"; next steps: unplugged thermal/battery run, the 17 Pro MLX comparison (now optional), Plan 6.
- [ ] **Step 3:** Roadmap row for Plan 7; Plan 0 row unchanged.
- [ ] **Step 4:** Commit `Docs: Plan 7 — Core ML Kokoro engine`

## Spec coverage
| Spec | Task |
|---|---|
| §3.4 render-ahead, §3.6 rates from measured RTF | 3, 4 |
| §5 render keys carry engine identity | 3, 4 |
| §6 per-utterance failure, configuration-time availability | 3, 4, 5 |
| §7.3/§7.5 Core ML measured, §7.4 timings gate opened | 2, 3 |
| §3.7.5 licences | 1, 6 |
