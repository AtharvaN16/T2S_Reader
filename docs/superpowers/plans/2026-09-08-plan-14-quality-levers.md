# Plan 14 — Sound quality without changing the model: blends, the voice list, pitch spread

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

_2026-09-08. Branch `plan-14-quality-levers` (first commits say Plan 13; the number moved when another session's Plan 13 merged first) off `dev` @ b951d86, in the worktree
`.worktrees/plan-13-quality-levers` (the folder keeps the old number; the main checkout carried Plans 12 and 13 meanwhile). Proposed after the owner's
question "we cannot change the model — are there other ways to improve the sound quality?"; every
lever below was measured first (`spikes/findings/2026-09-08-quality-levers.md`)._

**Goal:** Make the on-device voice sound better to the reader without a different model: new voices
from the ones we have, the best voices first, and — if the owner's ears agree — a livelier default
delivery.

**Architecture:** A Kokoro voice is a 510×256 style table; a blend is the weighted sum of two tables,
built at tokenizer load from the two parents' files and cached under its own voice name, so nothing
changes in the pipeline, the previews or the render keys. The pitch-spread hook already exists
(`KokoroSynthesisRequest.f0Spread` → `KokoroCoreMLEngine.Options.f0Spread`): it widens the F0Ntrain
stage's contour about its own log-mean before decoder-pre and the harmonic source see it. If it ships
as a setting, its value joins the voice route so a change re-renders. The voice list is reordered by
the model author's own grades.

**Tech Stack:** Swift 6.2, swift-testing; `swift test` (root); `scripts/test-kokoro.sh`
(`Packages/T2SKokoro`, xcodebuild on macOS); `scripts/quality-probe.sh` and the lever probe for evidence.

**Spec:** [docs/superpowers/specs/2026-09-01-t2s-reader-design.md](../specs/2026-09-01-t2s-reader-design.md)
§3 (engine, render keys §5), §2 Preferences → Voice; the finding above is the measurement the plan
argues from.

## Global Constraints

- Never play audio on the owner's Mac; probes write WAVs, nothing plays them.
- Anything that changes the audio of a voice is part of its render identity (spec §5): a blend is a
  voice name; a spread value is part of the voice route. `Versions.*` do not move in this plan.
- `KokoroCoreMLEngine.Options`'s initializer defaults stay upstream's; the app's choices live in
  `Options.default`.
- The vendored `KokoroPipeline` takes additions behind defaults that reproduce upstream (as Plan 9's
  `punctuationSuppression` did); every vendored change is commented as such.

---

## Tasks

| # | Task | Owns | Verification | State |
|---|---|---|---|---|
| 1 | **A slow voice no longer crashes a debug build.** The vendored pipeline's DEBUG assertion on an overflowing prediction is removed (the engine re-splits, Plan 9); a regression test renders `af_nicole` on the passage's 197-id utterance; the test support keeps a private, revision-keyed clone of the compiled stages so two sessions' runs cannot sweep each other's models. | `Packages/KokoroPipeline` (one comment block), `Packages/T2SKokoro` tests | `scripts/test-kokoro.sh`; the new test | done on this branch |
| 2 | **Blended voices as catalog rows.** `KokoroVoiceCatalog` gains recipes (`Heart & Bella` = 0.5·heart + 0.5·bella, `Heart & Emma` = 0.5·heart + 0.5·emma); `KokoroCoreMLResources.Located` resolves a recipe name to its parents; `KokoroTokenizer` builds the blended table at load. Rows preview and render like any voice. | `Sources/T2SApp/Preferences/KokoroVoiceCatalog.swift`, `Sources/T2SAudio/KokoroVoiceID.swift`, `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/{KokoroTokenizer,KokoroCoreMLResources,KokoroCoreMLEngine}.swift`, tests | `swift test`; `scripts/test-kokoro.sh`; the lever probe renders the rows | **dropped** — the owner heard the blends as "all good, too subtle to tell apart" |
| 3 | **The voice list leads with the author's best.** Order: Heart, Bella, the blends, Emma, Nicole, then the C voices; the D and F voices under a "More voices" disclosure; each row's detail keeps accent and gender. | `KokoroVoiceCatalog.swift`, `App/T2SReader/Preferences`, tests | `swift test`; `scripts/build-app.sh` | open, optional — the owner's call |
| 4 | **Delivery 1.25 as the fixed default — no setting.** The owner's listen (2026-09-08): 1.25 "feels more alive", 1.5 "not wrong", and three presets "unnecessarily complicated". The value rides on the voice route (`kokoro:<engine>:<voice>@1.25`), attached where the effective voice is resolved for rendering (`PlayerModel`, `PrepareRunner`) and honoured by the engine per request, so every render key changes and the library re-renders consistently while every stored voice choice survives. Before it became the default for every voice: Bella, Michael, Emma and Nicole rendered at 1.0 and 1.25 (the spread check) to see that none saturates. | `Sources/T2SAudio/KokoroVoiceID.swift`, `Sources/T2SApp/Preferences/Delivery.swift` (new), `PlayerModel.swift`, `PrepareRunner.swift`, `KokoroCoreMLEngine.swift`, tests | `swift test`; `scripts/test-kokoro.sh`; the spread check | done — and the owner's A/B: the Plan 9 render clicks after "Humbug", "sparkled", "poor enough"; the fixed renders do not |
| 5 | **Docs.** HANDOFF resume section, README (the lever probe), spec §2 (the voice list and, if taken, the delivery setting) with a changelog entry. | `docs/`, `README.md` | review | open |

## Decisions taken without the owner (each with its cost if wrong)

- **Blends are computed, not bundled.** Two parents' 510-KB tables summed at load is ~130 K
  multiply-adds, once per voice per launch; bundling would add files to a 347 MB staging and a
  checksum manifest for something the phone can compute in a millisecond. Cost: one small function.
- **Two curated blends, not a slider.** The probe measured every blend landing between its parents;
  a blend is a new voice, not a better one, and the picker already has 28 rows. A "make your own"
  screen is a later plan if readers ask. Cost: nothing if wrong.
- **Emma is demoted, Bella promoted, by measurement.** Plan 9's "the British voices read with more
  movement" does not survive the pitch tracker (Emma 2.1 st, Heart 4.2, Bella 4.5). The author's grades
  (Heart A, Bella A-, Nicole B-, Emma B-) set the top four. Cost: an order in a list.
- **The spread waits for the listen.** It does exactly what it claims (same duration to the sample,
  same pauses, no new clicks, 4.2 → 4.8 st at 1.25), but nothing measured says wider *sounds* better.
  Cost: a task that may close untaken.
- **Opus is not pursued.** The system encoder ignores the requested bitrate (104–136 kbps actual,
  files larger than AAC's) and a controllable encoder means libopus through a third-party package; the
  performance audit's in-memory live path removes the cache from the first listen anyway.

## Deferred

- A "make your own voice" picker (two parents and a weight) — after the curated rows have been heard.
- Loudness normalisation across voices (the voices differ by ±2 dB rms) and a gentle high-shelf — a
  mastering task after the above, if the owner still hears "dull".
- The mechanism behind the decoder's non-linear response to a widened F0 (the median drifts +24 Hz at
  2.0): a tensor question for the vendored pipeline's authors.
- The performance audit's #4 (play the render, not the cache) lives in that plan.

---

### Task 2: Blended voices as catalog rows

**Files:**
- Modify: `Sources/T2SApp/Preferences/KokoroVoiceCatalog.swift` — the recipes and their rows
- Modify: `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLResources.swift` — `Located.voices` gains blend resolution
- Modify: `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroTokenizer.swift` — an initializer over a blended table
- Modify: `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLEngine.swift` — `tokenizer(voice:url:)` resolves a blend
- Test: `Tests/T2SAppTests/…KokoroVoiceCatalogTests.swift`, `Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroTokenizerTests.swift`, `KokoroCoreMLEngineTests.swift`

**Interfaces:**
- Consumes: `KokoroTokenizer.init(vocabURL:voiceURL:)`; `KokoroCoreMLResources.Located.voices: [String: URL]`; `KokoroVoiceCatalog.voiceNames`; `PipelineConstants.voiceEmbeddingDim`.
- Produces: `KokoroVoiceBlend` (`name`, `parents: (String, String)`, `weight: Float`) in `T2SAudio` beside `KokoroVoiceID`; `KokoroVoiceBlend.curated: [KokoroVoiceBlend]`; `KokoroTokenizer.init(vocabURL:voiceURLs:weights:)`; `KokoroVoiceCatalog.voiceNames` includes the blend names.

- [ ] **Step 1: Write the failing tokenizer test**

```swift
// in KokoroTokenizerTests
    /// A blend's style table is the weighted sum of its parents', row by row — what the community
    /// tools do (`spikes/findings/2026-09-08-quality-levers.md`).
    @Test func buildsABlendedStyleTableFromTwoParents() throws {
        let dim = PipelineConstants.voiceEmbeddingDim
        let a = try Self.voiceFile(rows: 2, value: 1)      // every float 1
        let b = try Self.voiceFile(rows: 2, value: 3)      // every float 3
        let tokenizer = try KokoroTokenizer(vocabURL: Self.vocabURL, voiceURLs: [a, b], weights: [0.5, 0.5])
        #expect(tokenizer.voiceRowCount == 2)
        #expect(tokenizer.refS(phonemeUTF16Count: 1) == [Float](repeating: 2, count: dim))
        #expect(tokenizer.refS(phonemeUTF16Count: 2) == [Float](repeating: 2, count: dim))
    }

    static func voiceFile(rows: Int, value: Float) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).bin")
        var data = Data()
        for _ in 0 ..< rows * PipelineConstants.voiceEmbeddingDim {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        try data.write(to: url)
        return url
    }
```

(`Self.vocabURL` is whatever the suite already uses for the vocabulary file; keep its name.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd Packages/T2SKokoro && xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath .build/DerivedData -only-testing:T2SKokoroTests/KokoroTokenizerTests 2>&1 | grep -E "error:|passed|failed"`
Expected: `error: extra argument 'weights' in call` (no such initializer yet).

- [ ] **Step 3: Add the blended initializer**

In `KokoroTokenizer.swift`, factor the voice-table load out of `init(vocabURL:voiceURL:)` and add:

```swift
    /// A blended voice: the weighted sum of `voiceURLs`' tables, row by row. Every table must have
    /// the same row count; `weights` pairs with `voiceURLs` and normally sums to 1, though nothing
    /// enforces that — an extrapolation is a legal, if unpredictable, recipe.
    public init(vocabURL: URL, voiceURLs: [URL], weights: [Float]) throws {
        precondition(voiceURLs.count == weights.count && !voiceURLs.isEmpty, "one weight per parent")
        vocab = try Self.loadVocabulary(vocabURL)
        var mixed: [Float] = []
        for (url, weight) in zip(voiceURLs, weights) {
            let table = try Self.loadVoiceTable(url)
            if mixed.isEmpty {
                mixed = table.map { $0 * weight }
            } else {
                guard table.count == mixed.count else {
                    throw Failure.invalidVoiceTable("\(url.lastPathComponent) has \(table.count) floats, the first parent \(mixed.count)")
                }
                for i in mixed.indices { mixed[i] += table[i] * weight }
            }
        }
        voiceRows = mixed
        voiceRowCount = mixed.count / PipelineConstants.voiceEmbeddingDim
    }
```

with `loadVocabulary(_:)` and `loadVoiceTable(_:)` as `private static` functions holding the code
the existing initializer already has (the existing initializer calls them too).

- [ ] **Step 4: Run the tokenizer tests to verify they pass**

Run: the Step 2 command. Expected: `Suite KokoroTokenizerTests passed`.

- [ ] **Step 5: Write the failing recipe test**

```swift
// Sources/T2SAudio/KokoroVoiceBlend.swift is new; test in Tests/T2SAudioTests/KokoroVoiceBlendTests.swift
import Testing
@testable import T2SAudio

@Suite struct KokoroVoiceBlendTests {
    @Test func theCuratedBlendsNameTheirParentsAndWeights() {
        let heartBella = KokoroVoiceBlend.curated.first { $0.name == "af_heart_bella" }
        #expect(heartBella?.parents.0 == "af_heart" && heartBella?.parents.1 == "af_bella" && heartBella?.weight == 0.5)
        let heartEmma = KokoroVoiceBlend.curated.first { $0.name == "af_heart_emma" }
        #expect(heartEmma?.parents.1 == "bf_emma")
        #expect(KokoroVoiceBlend.curated.count == 2)
    }

    @Test func aBlendIsAmericanWhenItsFirstParentIs() {
        #expect(KokoroVoiceBlend.curated.allSatisfy { $0.name.hasPrefix("a") })
    }
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `swift test --filter KokoroVoiceBlendTests`. Expected: `cannot find 'KokoroVoiceBlend' in scope`.

- [ ] **Step 7: Add the recipes**

```swift
// Sources/T2SAudio/KokoroVoiceBlend.swift
/// A voice made from two of the bundled voices: `(1 − weight) × parents.0 + weight × parents.1`,
/// row by row of their style tables. Named like a voice so the render key, the previews and the
/// picker treat it as one. The name's first letter picks the G2P (`a` American, `b` British), so a
/// blend is named for its first parent's accent.
/// Why these two: `spikes/findings/2026-09-08-quality-levers.md` — Heart keeps its placement with
/// Bella's range; Emma lowers and calms Heart.
public struct KokoroVoiceBlend: Hashable, Sendable {
    public var name: String
    public var parents: (String, String)
    public var weight: Float

    public static let curated: [KokoroVoiceBlend] = [
        KokoroVoiceBlend(name: "af_heart_bella", parents: ("af_heart", "af_bella"), weight: 0.5),
        KokoroVoiceBlend(name: "af_heart_emma", parents: ("af_heart", "bf_emma"), weight: 0.5),
    ]

    public static func named(_ name: String) -> KokoroVoiceBlend? { curated.first { $0.name == name } }
}
```

(`Hashable` on a tuple property does not synthesize: write `==` and `hash(into:)` over `name`,
`parents.0`, `parents.1`, `weight`.)

- [ ] **Step 8: Run the recipe tests to verify they pass**

Run: `swift test --filter KokoroVoiceBlendTests`. Expected: 2 tests pass.

- [ ] **Step 9: Write the failing engine test**

```swift
// in KokoroCoreMLEngineTests, before "// MARK: The real model"
    /// A blend name resolves to a tokenizer over both parents' tables; an unknown name still fails
    /// the way it always has.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func rendersACuratedBlendLikeAnyVoice() async throws {
        let engine = try await Self.engineWithRealResources()
        let result = try await engine.synthesize(.init(spoken: "Hello there.", voiceID: Self.voiceID("af_heart_bella")))
        #expect(result.audio.duration > 0.3)
        #expect(Self.rms(result.audio.samples) > 0.01)
    }
```

- [ ] **Step 10: Run it to verify it fails**

Run: `... -only-testing:'T2SKokoroTests/KokoroCoreMLEngineTests/rendersACuratedBlendLikeAnyVoice()'`
Expected: fails with `KokoroCoreMLError.unknownVoice("af_heart_bella")`.

- [ ] **Step 11: Resolve blends in the engine**

In `KokoroCoreMLEngine.synthesize`, the voice check becomes:

```swift
        let blend = KokoroVoiceBlend.named(id.voice)
        guard blend != nil || resources.voices[id.voice] != nil else {
            throw KokoroCoreMLError.unknownVoice(id.voice)
        }
```

and `tokenizer(voice:url:)` becomes `tokenizer(voice:)`:

```swift
    private func tokenizer(voice: String) throws -> KokoroTokenizer {
        if let cached = tokenizers[voice] { return cached }
        let tokenizer: KokoroTokenizer
        if let blend = KokoroVoiceBlend.named(voice) {
            guard let a = resources.voices[blend.parents.0], let b = resources.voices[blend.parents.1] else {
                throw KokoroCoreMLError.unknownVoice(voice)
            }
            tokenizer = try KokoroTokenizer(vocabURL: resources.vocab, voiceURLs: [a, b], weights: [1 - blend.weight, blend.weight])
        } else {
            guard let url = resources.voices[voice] else { throw KokoroCoreMLError.unknownVoice(voice) }
            tokenizer = try KokoroTokenizer(vocabURL: resources.vocab, voiceURL: url)
        }
        tokenizers[voice] = tokenizer
        return tokenizer
    }
```

(`phonemization(of:voice:)` calls the same function.) `T2SKokoro` already depends on `T2SAudio`.

- [ ] **Step 12: Run the engine test to verify it passes**

Run: the Step 10 command. Expected: passes (a model-backed run, minutes).

- [ ] **Step 13: List the blends in the catalog — failing test first**

```swift
// in the existing KokoroVoiceCatalog tests (Tests/T2SAppTests)
    @Test func listsTheCuratedBlendsAfterTheirParents() {
        let names = KokoroVoiceCatalog.voiceNames
        #expect(names.contains("af_heart_bella") && names.contains("af_heart_emma"))
        #expect(names.firstIndex(of: "af_heart_bella")! > names.firstIndex(of: "af_bella")!)
    }
```

Run `swift test --filter KokoroVoiceCatalog`; expected: fails on `contains`. Then add the two names
to `voiceNames` after `af_bella` (Task 3 reorders the whole list; here they only need to exist), and
give them display names in whatever table maps a voice name to its row (`"Heart & Bella"`,
`"Heart & Emma"`, detail "a blend"). Run again; expected: passes, and every other catalog test still
passes (the row count changes from 28 to 30 — update any test that pins 28).

- [ ] **Step 14: Whole suites**

Run: `swift test` and `scripts/test-kokoro.sh`. Expected: green.

- [ ] **Step 15: Commit**

```bash
git add Sources/T2SAudio/KokoroVoiceBlend.swift Tests/T2SAudioTests/KokoroVoiceBlendTests.swift Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroTokenizer.swift Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLEngine.swift Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroTokenizerTests.swift Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroCoreMLEngineTests.swift Sources/T2SApp/Preferences/KokoroVoiceCatalog.swift Tests/T2SAppTests
git commit -m "Plan 14 Task 2: two blended voices — Heart & Bella, Heart & Emma — as catalog rows, their tables summed from the parents' at load"
```

### Task 3: The voice list leads with the author's best

**Files:**
- Modify: `Sources/T2SApp/Preferences/KokoroVoiceCatalog.swift` — `voiceNames` order; a `featured` set
- Modify: `App/T2SReader/Preferences/…` (the voice list view) — a "More voices" disclosure for the rest
- Test: the catalog tests

- [ ] **Step 1: Failing test for the order**

```swift
    /// The author grades four voices B- or better (Heart A, Bella A-, Nicole B-, Emma B-); they and
    /// the two blends lead, the D and F voices are folded away.
    @Test func leadsWithTheGradedVoicesAndFoldsTheRest() {
        #expect(Array(KokoroVoiceCatalog.voiceNames.prefix(6)) == ["af_heart", "af_bella", "af_heart_bella", "af_heart_emma", "bf_emma", "af_nicole"])
        #expect(KokoroVoiceCatalog.folded.contains("am_adam") && KokoroVoiceCatalog.folded.contains("am_santa"))
        #expect(!KokoroVoiceCatalog.folded.contains("af_heart"))
    }
```

Run `swift test --filter KokoroVoiceCatalog`; expected: fails on the prefix and on `folded`.

- [ ] **Step 2: Reorder and fold**

`voiceNames` becomes the six above, then the C+ and C voices (`af_aoede`, `af_kore`, `af_sarah`,
`am_fenrir`, `am_michael`, `am_puck`, `af_alloy`, `af_nova`, `bf_isabella`, `bm_fable`, `bm_george`,
`af_sky`), then the rest. `static let folded: Set<String>` holds every voice graded D or F:
`af_jessica`, `af_river`, `am_adam`, `am_echo`, `am_eric`, `am_liam`, `am_onyx`, `am_santa`,
`bf_alice`, `bf_lily`, `bm_daniel`, `bm_lewis`. `VoiceOption` gains nothing; the view groups rows
whose name is in `folded` under a `DisclosureGroup("More voices")`, collapsed by default unless the
selected voice is inside it.

- [ ] **Step 3: Run the catalog tests, then `scripts/build-app.sh`.** Expected: green; the Preferences
screen shows six rows, the C voices, and "More voices".

- [ ] **Step 4: Commit** — `git commit -m "Plan 14 Task 3: the voice list leads with the author's graded voices and the blends; the D and F voices fold under More voices"`.

### Task 4: Pitch spread as a setting — only if the listen says so

Gate: the owner prefers `09-heart-spread-1.25.wav` or `10-heart-spread-1.5.wav` over `01-heart.wav`.
If not, close the task with a line in HANDOFF; `Options.f0Spread` stays at 1.

- [ ] **Step 1: Failing test for the voice id**

```swift
// in the KokoroVoiceID tests
    @Test func carriesAnOptionalDeliverySpread() {
        let id = KokoroVoiceID(engineID: "e", voice: "af_heart", spread: 1.25)
        #expect(id.rawValue == "kokoro:e:af_heart@1.25")
        #expect(KokoroVoiceID(rawValue: "kokoro:e:af_heart@1.25")?.spread == 1.25)
        #expect(KokoroVoiceID(rawValue: "kokoro:e:af_heart")?.spread == nil)
        #expect(KokoroVoiceID(rawValue: "kokoro:e:af_heart")?.rawValue == "kokoro:e:af_heart")
    }
```

- [ ] **Step 2: Run it (fails: no `spread`). Implement**: `KokoroVoiceID` gains `spread: Float?`; the
raw form appends `@<value>` only when set; parsing splits the voice on `@`. `RoutedEngine` (or wherever
the Core ML engine is constructed per route) passes `Options.default` with `f0Spread = id.spread ?? 1`
— since `Options` is set at construction and the engine is shared, the engine instead reads the spread
per request: `synthesize` sets `f0Spread` from `id.spread ?? options.f0Spread` when building the
pipeline request (a local, not `setOptions`).

- [ ] **Step 3: Preferences**: `ReaderPreferences` gains `delivery: Delivery` (`.natural` 1.0,
`.lively` 1.25, `.livelier` 1.5); `VoiceRouting` folds it into the resolved `KokoroVoiceID`; a segmented
control under the voice list. Changing it changes the render key through the voice id, so the book
re-renders (the existing "voice change discards rendered audio" warning applies — reuse it).

- [ ] **Step 4: Run `swift test`, `scripts/test-kokoro.sh`, `scripts/build-app.sh`; the lever probe at
the chosen value once more; commit** — `git commit -m "Plan 14 Task 4: Delivery — Natural, Lively, Livelier — widens the pitch contour before the decoder; part of the voice route so a change re-renders"`.

### Task 5: Docs

- [ ] HANDOFF: a "Resume here — Plan 13" section (the finding in a paragraph, what shipped, the
  listen's outcome, deferred). README: the lever probe beside the other probes. Spec §2's voice list
  paragraph and, if Task 4 shipped, the Delivery setting; a changelog entry (rev 13).
- [ ] Commit — `git commit -m "Plan 14 Task 5: docs — HANDOFF, README, spec voice list and changelog"`.
