# Cloud-First Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A first launch speaks Kokoro Heart from the Heroku mirrors within one render of tapping play, with no route configured and no voice chosen, and hands playback to the on-device engine at the next chapter boundary once it is ready.

**Architecture:** The route and key ship with the app (defaults seeded once into settings; the key seeded once into the Keychain from an Info.plist value that comes from the git-ignored `Local.xcconfig`). The routing layer's one fallback-to-system branch returns the hosted voice instead while the on-device default is unavailable. The player notices a chapter change while routed to the hosted voice, re-asks the routing, and tells the coordinator to key everything from that chapter on to the on-device voice; earlier chapters keep their cloud keys for the session. Background prepare skips while standing in.

**Tech Stack:** Swift 6 (SwiftPM, Swift Testing), xcodegen, Xcode, devicectl.

**Spec:** `docs/superpowers/specs/2026-09-11-cloud-first-bootstrap-design.md`

## Global Constraints

- The key never appears in a tracked file, a log, a test fixture, or a terminal. It lives in `~/.t2s/heroku-voice-key` (0600) and `App/Local.xcconfig` (git-ignored).
- No store schema change; the handoff lives in the session only.
- The server and the mirrors are untouched.
- Swift 6 language mode; Swift Testing (`@Test`, `#expect`, `#require`).
- Full Swift run is two commands: `swift test --skip T2SStoreTests` then `swift test --filter T2SStoreTests` (the store's sync suite races other containers when run in parallel; pre-existing).
- Every commit stages only the task's own files; messages are declarative sentences.

## File Map

| File | Responsibility |
|---|---|
| `Sources/T2SApp/Preferences/CloudVoiceDefaults.swift` (new) | The shipped route: four mirrors, `kokoro`, `af_heart`, rate 20. |
| `Sources/T2SApp/Preferences/CloudVoiceSettings.swift` | Seeds shipped defaults once into empty settings. |
| `Sources/T2SApp/Preferences/CloudVoiceKeySeeder.swift` (new) | Info.plist key → Keychain, once, never logged. |
| `Sources/T2SApp/Preferences/VoiceRouting.swift` | The hosted voice stands in for the unavailable default. |
| `Sources/T2SCore/Render/RenderScheduler.swift` | A batch never spans voices. |
| `Sources/T2SAudio/PlaybackCoordinator.swift` | `handOff(to:fromChapter:)`; keys and requests by chapter. |
| `Sources/T2SApp/Player/PlayerModel.swift` | Hands off on the first chapter change after the on-device voice answers. |
| `Sources/T2SApp/Playback/PrepareRunner.swift` | Skips a run while standing in. |
| `App/T2SReader/System/KokoroComposition.swift` | Passes the stand-in into both routings. |
| `App/T2SReader/AppEnvironment.swift` | Seeds defaults and key; builds the stand-in; gates prepare. |
| `App/project.yml`, `App/Local.xcconfig.example` | `T2SCloudVoiceKey` from `T2S_CLOUD_VOICE_KEY`. |

---

### Task 1: The route ships with the app

**Files:**
- Create: `Sources/T2SApp/Preferences/CloudVoiceDefaults.swift`
- Modify: `Sources/T2SApp/Preferences/CloudVoiceSettings.swift:95-112` (`init`)
- Test: `Tests/T2SAppTests/CloudVoiceSettingsTests.swift`

**Interfaces:**
- Produces: `CloudVoiceDefaults` (`endpointText`, `model`, `voice`, `requestRatePerMinute`, `static let pilot`), and `CloudVoiceSettings(defaults:shipped:)` with `shipped: CloudVoiceDefaults? = nil`. Task 8 passes `.pilot`.

- [ ] **Step 1: Write the failing tests**

Add to the `CloudVoiceSettingsTests` suite, after `aBadMirrorLineInvalidatesTheRoute`:

```swift
    @Test func shippedDefaultsAreWrittenOnceIntoEmptySettings() throws {
        let settings = CloudVoiceSettings(defaults: freshDefaults(), shipped: .pilot)
        #expect(settings.endpointText == CloudVoiceDefaults.pilot.endpointText)
        #expect(settings.model == "kokoro" && settings.voice == "af_heart" && settings.requestRatePerMinute == 20)
        let configuration = try #require(settings.configurationStore.current())
        #expect(configuration.endpoints.count == 4)
        #expect(settings.cloudVoiceID?.hasPrefix("cloud:") == true)
    }

    /// The reader's edit wins, even an edit to nothing: the shipped route is a first-launch value,
    /// never a reset.
    @Test func aStoredEndpointIsNeverOverwrittenByTheShippedOne() {
        let defaults = freshDefaults()
        let first = CloudVoiceSettings(defaults: defaults, shipped: .pilot)
        first.endpointText = ""
        let again = CloudVoiceSettings(defaults: defaults, shipped: .pilot)
        #expect(again.endpointText == "")
        #expect(again.configurationStore.current() == nil)
    }

    @Test func noShippedDefaultsLeaveTheSettingsEmpty() {
        let settings = CloudVoiceSettings(defaults: freshDefaults())
        #expect(settings.endpointText == "" && settings.configurationStore.current() == nil)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CloudVoiceSettingsTests`
Expected: compilation fails, `cannot find 'CloudVoiceDefaults' in scope`.

- [ ] **Step 3: Add the defaults and the seeding**

Create `Sources/T2SApp/Preferences/CloudVoiceDefaults.swift`:

```swift
import Foundation

/// The hosted route the app ships with (cloud-first bootstrap spec): written into empty settings on
/// the first launch, so a reader hears Kokoro Heart before choosing anything. Non-secret; the key
/// travels separately (`CloudVoiceKeySeeder`).
public struct CloudVoiceDefaults: Hashable, Sendable {
    /// One endpoint per line, the primary first, as the Cloud voices screen stores it.
    public var endpointText: String
    public var model: String
    public var voice: String
    public var requestRatePerMinute: Int

    public init(endpointText: String, model: String, voice: String, requestRatePerMinute: Int) {
        self.endpointText = endpointText
        self.model = model
        self.voice = voice
        self.requestRatePerMinute = requestRatePerMinute
    }

    /// The four Eco mirrors (`Server/HerokuVoice/scripts/mirrors.sh`), primary first.
    public static let pilot = CloudVoiceDefaults(
        endpointText: """
        https://kokoro-t2s-a007171ff076.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m2-d13cbe083bd3.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m3-71b4e3836076.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m4-b46b9e051494.herokuapp.com/v1/audio/speech
        """,
        model: "kokoro",
        voice: "af_heart",
        requestRatePerMinute: 20
    )
}
```

In `Sources/T2SApp/Preferences/CloudVoiceSettings.swift`, change the initializer's signature and add the seeding as its first statement after `self.defaults = defaults`:

```swift
    public init(defaults: UserDefaults = .standard, shipped: CloudVoiceDefaults? = nil) {
        self.defaults = defaults
        if let shipped, defaults.string(forKey: Key.endpoint) == nil {
            // First launch: the shipped route becomes the stored one, once. An edit later — even
            // to nothing — is never overwritten.
            defaults.set(shipped.endpointText, forKey: Key.endpoint)
            defaults.set(shipped.model, forKey: Key.model)
            defaults.set(shipped.voice, forKey: Key.voice)
            defaults.set(shipped.requestRatePerMinute, forKey: Key.rate)
        }
        let savedEndpoint = defaults.string(forKey: Key.endpoint) ?? ""
```

leaving the rest of the initializer as it is.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CloudVoiceSettingsTests`
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp/Preferences/CloudVoiceDefaults.swift Sources/T2SApp/Preferences/CloudVoiceSettings.swift Tests/T2SAppTests/CloudVoiceSettingsTests.swift
git commit -m "The hosted route ships with the app and is written once into empty settings"
```

---

### Task 2: The key seeds the Keychain once

**Files:**
- Create: `Sources/T2SApp/Preferences/CloudVoiceKeySeeder.swift`
- Test: `Tests/T2SAppTests/CloudVoiceKeySeederTests.swift` (new)

**Interfaces:**
- Consumes: `SecretStoring` (`save(_:)`, `load()`), `InMemorySecretStore(value:)`.
- Produces: `CloudVoiceKeySeeder.seed(infoValue: String?, into: any SecretStoring) throws -> Bool`. Task 8 calls it with `Bundle.main.infoDictionary?["T2SCloudVoiceKey"] as? String`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/T2SAppTests/CloudVoiceKeySeederTests.swift`:

```swift
import Testing
import T2SApp

@Suite struct CloudVoiceKeySeederTests {
    @Test func seedsAnEmptyStore() throws {
        let store = InMemorySecretStore()
        #expect(try CloudVoiceKeySeeder.seed(infoValue: "built-key", into: store) == true)
        #expect(try store.load() == "built-key")
    }

    @Test func leavesAStoredKeyAlone() throws {
        let store = InMemorySecretStore(value: "typed-key")
        #expect(try CloudVoiceKeySeeder.seed(infoValue: "built-key", into: store) == false)
        #expect(try store.load() == "typed-key")
    }

    /// An unset build setting reaches the plist as its own name.
    @Test func ignoresAnEmptyValueAndAnUnsetBuildSetting() throws {
        let values: [String?] = [nil, "", "  ", "$(T2S_CLOUD_VOICE_KEY)"]
        for value in values {
            let store = InMemorySecretStore()
            #expect(try CloudVoiceKeySeeder.seed(infoValue: value, into: store) == false)
            #expect(try store.load() == nil)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CloudVoiceKeySeederTests`
Expected: compilation fails, `cannot find 'CloudVoiceKeySeeder' in scope`.

- [ ] **Step 3: Implement the seeder**

Create `Sources/T2SApp/Preferences/CloudVoiceKeySeeder.swift`:

```swift
import Foundation

/// Moves the bearer key the build carries (Info.plist `T2SCloudVoiceKey`, from the per-Mac
/// `Local.xcconfig`) into the Keychain once, so the shipped route works from the first launch
/// without anything typed (cloud-first bootstrap spec). A key already stored is left alone;
/// nothing is logged.
public enum CloudVoiceKeySeeder {
    /// True when a key was stored. An empty value, or an unset build setting — which reaches the
    /// plist as its own name, `$(T2S_CLOUD_VOICE_KEY)` — seeds nothing.
    @discardableResult
    public static func seed(infoValue: String?, into store: any SecretStoring) throws -> Bool {
        guard let value = infoValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.hasPrefix("$(")
        else { return false }
        if let existing = try store.load(), !existing.isEmpty { return false }
        try store.save(value)
        return true
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CloudVoiceKeySeederTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp/Preferences/CloudVoiceKeySeeder.swift Tests/T2SAppTests/CloudVoiceKeySeederTests.swift
git commit -m "The build's key seeds the Keychain once, and an unset build setting seeds nothing"
```

---

### Task 3: The hosted voice stands in

**Files:**
- Modify: `Sources/T2SApp/Preferences/VoiceRouting.swift:31-85` (`KokoroVoiceRouting`)
- Test: `Tests/T2SAppTests/VoiceRoutingTests.swift`

**Interfaces:**
- Produces: `KokoroVoiceRouting(routes:defaultVoice:standIn:)` with `standIn: @escaping @Sendable () -> String? = { nil }`. The single-route initializer and `.unavailable` are unchanged. Task 8 supplies the closure.

- [ ] **Step 1: Write the failing tests**

Add to the `VoiceRoutingTests` suite, after `routing(coreML:mlx:defaultVoice:)`:

```swift
    // MARK: The hosted voice standing in

    private let hostedVoiceID = "cloud:fingerprint:af_heart"

    private func routing(coreML: Bool, mlx: Bool, defaultVoice: String?, standIn: String?) -> KokoroVoiceRouting {
        KokoroVoiceRouting(
            routes: [
                .init(engineIdentity: coreMLIdentity, isAvailable: { coreML }),
                .init(engineIdentity: identity, isAvailable: { mlx }),
            ],
            defaultVoice: defaultVoice,
            standIn: { standIn }
        )
    }

    @Test func theHostedVoiceStandsInForTheDefaultWhileItsRouteIsNotAvailable() async {
        let installing = routing(coreML: false, mlx: false, defaultVoice: coreMLVoiceID, standIn: hostedVoiceID)
        #expect(await installing.effectiveVoiceID("default") == hostedVoiceID)
        #expect(await installing.effectiveVoiceID(VoiceOption.systemDefault.id) == hostedVoiceID)
        // Only for the default: an explicit system voice, or a cloud voice, is what it was.
        #expect(await installing.effectiveVoiceID("system:com.example.voice") == "system:com.example.voice")
        #expect(await installing.effectiveVoiceID("cloud:other:v") == "cloud:other:v")
    }

    @Test func theHostedVoiceStandsInForAKokoroVoiceWhoseRuntimeIsNotAvailable() async {
        let installing = routing(coreML: false, mlx: false, defaultVoice: coreMLVoiceID, standIn: hostedVoiceID)
        #expect(await installing.effectiveVoiceID(coreMLVoiceID) == hostedVoiceID)
        #expect(await installing.effectiveVoiceID(kokoroVoiceID) == hostedVoiceID)
    }

    @Test func anAvailableDefaultIgnoresTheStandIn() async {
        let ready = routing(coreML: true, mlx: false, defaultVoice: coreMLVoiceID, standIn: hostedVoiceID)
        #expect(await ready.effectiveVoiceID("default") == coreMLVoiceID)
        #expect(await ready.effectiveVoiceID(coreMLVoiceID) == coreMLVoiceID)
    }

    @Test func withoutAStandInTheFallbacksAreWhatTheyWere() async {
        let installing = routing(coreML: false, mlx: false, defaultVoice: coreMLVoiceID, standIn: nil)
        #expect(await installing.effectiveVoiceID("default") == VoiceOption.systemDefault.id)
        #expect(await installing.effectiveVoiceID(coreMLVoiceID) == VoiceOption.systemDefault.id)
    }

    /// The everyday build has no on-device route at all, so its default is the hosted voice.
    @Test func aBuildWithoutKokoroStandsInForTheDefaultToo() async {
        let everyday = KokoroVoiceRouting(routes: [], defaultVoice: nil, standIn: { "cloud:fingerprint:af_heart" })
        #expect(await everyday.effectiveVoiceID("default") == "cloud:fingerprint:af_heart")
        #expect(await everyday.effectiveVoiceID("system:com.example.voice") == "system:com.example.voice")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VoiceRoutingTests`
Expected: compilation fails, `extra argument 'standIn' in call`.

- [ ] **Step 3: Add the stand-in**

In `Sources/T2SApp/Preferences/VoiceRouting.swift`, inside `KokoroVoiceRouting`, add after `private let defaultVoice: String?`:

```swift
    /// The hosted voice that stands in wherever the on-device default is not available: the cloud
    /// route's ID while one is configured with a key, else nil (cloud-first bootstrap spec).
    private let standIn: @Sendable () -> String?
```

Change the main initializer to:

```swift
    public init(routes: [Route], defaultVoice: String?, standIn: @escaping @Sendable () -> String? = { nil }) {
        // First wins, matching `RoutedEngine`: one identity is one runtime.
        self.routes = Dictionary(routes.map { ($0.engineIdentity, $0) }, uniquingKeysWith: { first, _ in first })
        self.defaultVoice = defaultVoice
        self.standIn = standIn
    }
```

Replace `effectiveVoiceID` with:

```swift
    public func effectiveVoiceID(_ requested: String) async -> String {
        if let kokoroID = KokoroVoiceID(rawValue: requested) {
            // Identity first: an unrouted engine identity is refused without waking a probe.
            guard await isAvailable(kokoroID.engineID) else {
                // The hosted voice first — Heart from the mirrors while Heart installs — else
                // whatever "default" means on this device, which is the Kokoro default voice
                // wherever its route is open. Exactly one level of recursion —
                // `VoiceOption.systemDefault.id` is not a `kokoro:` ID, so it takes the branch
                // below, which never comes back here.
                if let hosted = standIn() { return hosted }
                return await effectiveVoiceID(VoiceOption.systemDefault.id)
            }
            return requested
        }
        guard requested == VoiceOption.systemDefault.id,
              let defaultVoice,
              let defaultID = KokoroVoiceID(rawValue: defaultVoice),
              await isAvailable(defaultID.engineID)
        else {
            // The default's route is not open, or there is no default voice: the hosted voice
            // stands in for the default and for nothing else — a system or cloud voice named
            // outright is what it was.
            if requested == VoiceOption.systemDefault.id, let hosted = standIn() { return hosted }
            return requested
        }
        return defaultVoice
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter VoiceRoutingTests`
Expected: all pass, the five new ones and every pre-existing one.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp/Preferences/VoiceRouting.swift Tests/T2SAppTests/VoiceRoutingTests.swift
git commit -m "The hosted voice stands in for the default wherever the on-device route is not yet open"
```

---

### Task 4: A batch never spans voices

**Files:**
- Modify: `Sources/T2SCore/Render/RenderScheduler.swift` (`takeBatch`)
- Test: `Tests/T2SCoreTests/Render/RenderSchedulerTests.swift`

- [ ] **Step 1: Write the failing test**

Add to the `RenderSchedulerTests` suite, after `aBatchNeverSpansTiers`:

```swift
    /// A batch stops at a change of voice as it stops at a change of tier: a hosted batch (width
    /// four) and an on-device one (width one) never share a lease.
    @Test func aBatchNeverSpansVoices() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let engine = FakeEngine(concurrentRenders: 4)
        await engine.hold()
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        func req(_ i: Int, _ voice: String) -> RenderRequest {
            RenderRequest(job: RenderJob(documentID: doc, utteranceIndex: i, tier: .playAhead), key: key(i), spoken: "x\(i)", voiceID: voice)
        }
        await s.setPlan([req(0, "cloud:a:v"), req(1, "cloud:a:v"), req(2, "kokoro:b:v"), req(3, "kokoro:b:v")])
        var spins = 0
        while await engine.parkedCount != 2, spins < 10_000 { await Task.yield(); spins += 1 }
        #expect(await engine.parkedCount == 2)                            // only the two hosted
        #expect(await s.pending.count == 2)
        await engine.release()
        _ = await events
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RenderSchedulerTests`
Expected: `aBatchNeverSpansVoices` fails (`parkedCount` reaches 4); everything else passes.

- [ ] **Step 3: Stop the batch at a voice change**

In `Sources/T2SCore/Render/RenderScheduler.swift`, in `takeBatch`, change the while condition to:

```swift
        while batch.count < width, let next = pending.first,
              next.job.tier == first.job.tier, next.voiceID == first.voiceID {
```

and extend the method's doc comment: `/// never across a tier or a voice: an urgent plan then waits behind at most one batch of its own tier, and a hosted batch never shares a lease with an on-device one.`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RenderSchedulerTests`
Expected: 21 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Render/RenderScheduler.swift Tests/T2SCoreTests/Render/RenderSchedulerTests.swift
git commit -m "A batch never spans voices"
```

---

### Task 5: The coordinator hands off from a chapter

**Files:**
- Modify: `Sources/T2SAudio/PlaybackCoordinator.swift` (properties near line 52; `load`, `unload`; `replan`'s request; `renderKey(for:timeline:utteranceIndex:)`)
- Test: `Tests/T2SAudioTests/PlaybackCoordinatorTests.swift`

**Interfaces:**
- Produces: `public struct VoiceHandoff: Hashable, Sendable { fromChapter: Int; voiceID: String }`, `PlaybackCoordinator.voiceHandoff: VoiceHandoff?` (read-only), `PlaybackCoordinator.handOff(to voiceID: String, fromChapter chapter: Int)`. Task 6 calls it.

- [ ] **Step 1: Write the failing tests**

Add to the `PlaybackCoordinatorTests` suite, after `fixture(capacity:window:)`:

```swift
    /// Two chapters of two sentences each, 0.1 s per character, so a 60 s window renders the whole book.
    func twoChapterFixture() -> (PlaybackCoordinator, FakeEngine, Document, Timeline) {
        let one = SourceBlock(text: "Alpha one. Beta two.", position: Position(resourceHref: "a.xhtml", progression: 0, charOffset: 0))
        let two = SourceBlock(text: "Gamma three. Delta four.", position: Position(resourceHref: "b.xhtml", progression: 0, charOffset: 0))
        let timeline = TimelineBuilder.build(chapters: [ChapterInput(title: "One", position: one.position, blocks: [one]),
                                                        ChapterInput(title: "Two", position: two.position, blocks: [two])],
                                             segmenter: Segmenter(normalizer: TextNormalizer()))
        let engine = FakeEngine(secondsPerCharacter: 0.1)
        let c = PlaybackCoordinator(engine: engine, store: InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000),
                                    player: FakePlayer(), playheadStore: MemoryPlayheadStore(), timeSource: ManualTimeSource(),
                                    configuration: CoordinatorConfiguration(windowSeconds: 60, primeSeconds: 30, prepareBudgetSeconds: 300, queuedSegments: 2))
        return (c, engine, Document(title: "T", sourceType: .article), timeline)
    }

    /// From the boundary on, requests carry the new voice; before it, the old keys stand, and a
    /// seek back is a cache hit, not a render.
    @Test func aHandoffRendersFromItsChapterOnAndKeepsWhatCameBefore() async throws {
        let (c, engine, doc, timeline) = twoChapterFixture()
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        let before = await engine.requests
        #expect(Set(before.map(\.voiceID)) == ["default"])
        #expect(before.count == timeline.utteranceCount)
        let chapterOne = timeline.utteranceRange(ofChapter: 0)
        let chapterTwo = timeline.utteranceRange(ofChapter: 1)
        let oldRefsOne = chapterOne.map { c.timeline?[utterance: $0].audioRef }
        let oldRefsTwo = chapterTwo.map { c.timeline?[utterance: $0].audioRef }

        c.handOff(to: "kokoro:local:af_heart", fromChapter: 1)
        await c.waitForRenderIdle()

        let after = Array((await engine.requests).dropFirst(before.count))
        #expect(!after.isEmpty && after.allSatisfy { $0.voiceID == "kokoro:local:af_heart" })
        #expect(Set(after.map(\.spoken)) == Set(chapterTwo.map { timeline[utterance: $0].spoken }))
        for (i, old) in zip(chapterOne, oldRefsOne) { #expect(c.timeline?[utterance: i].audioRef == old) }
        for (i, old) in zip(chapterTwo, oldRefsTwo) { #expect(c.timeline?[utterance: i].audioRef != old) }

        let renders = (await engine.requests).count
        await c.seek(to: Playhead(utteranceIndex: 0))
        await c.waitForRenderIdle()
        #expect((await engine.requests).count == renders)                           // both chapters: cache hits
    }

    @Test func aLoadClearsTheHandoffAndNothingHandsOffWithoutADocument() {
        let (c, _, doc, timeline) = twoChapterFixture()
        c.handOff(to: "kokoro:local:af_heart", fromChapter: 0)
        #expect(c.voiceHandoff == nil)
        c.load(doc, timeline: timeline)
        c.handOff(to: "kokoro:local:af_heart", fromChapter: 1)
        #expect(c.voiceHandoff == VoiceHandoff(fromChapter: 1, voiceID: "kokoro:local:af_heart"))
        c.load(doc, timeline: timeline)
        #expect(c.voiceHandoff == nil)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PlaybackCoordinatorTests`
Expected: compilation fails, `value of type 'PlaybackCoordinator' has no member 'handOff'`.

- [ ] **Step 3: Implement the handoff**

In `Sources/T2SAudio/PlaybackCoordinator.swift`, above the `PlaybackCoordinator` class, add:

```swift
/// A voice the document renders with from a chapter on — the on-device engine taking over from the
/// hosted one mid-session (cloud-first bootstrap spec). Chapters before it keep the voice they were
/// rendered with, so nothing already heard is thrown away or rendered twice.
public struct VoiceHandoff: Hashable, Sendable {
    public var fromChapter: Int
    public var voiceID: String

    public init(fromChapter: Int, voiceID: String) {
        self.fromChapter = fromChapter
        self.voiceID = voiceID
    }
}
```

Inside the class, after `public private(set) var document: Document?`, add:

```swift
    /// Set by `handOff(to:fromChapter:)`; cleared by `load` and `unload`.
    public private(set) var voiceHandoff: VoiceHandoff?
```

In `load`, add `voiceHandoff = nil` as the first statement. In `unload`, add `voiceHandoff = nil` after `document = nil`.

In `replan`, change the request's voice line to:

```swift
                          voiceID: voiceID(forUtterance: job.utteranceIndex, in: timeline, document: document),
```

Replace `renderKey(for:timeline:utteranceIndex:)` with:

```swift
    private func renderKey(for document: Document, timeline: Timeline, utteranceIndex: Int) -> RenderKey {
        RenderKey(documentID: document.id, utteranceIndex: utteranceIndex,
                  voiceID: voiceID(forUtterance: utteranceIndex, in: timeline, document: document),
                  engineID: engine.engineID, normalizerVersion: timeline.normalizerVersion,
                  segmenterVersion: timeline.segmenterVersion)
    }

    /// The voice utterance `index` renders with: the handoff's from its chapter on, the document's
    /// before it.
    private func voiceID(forUtterance index: Int, in timeline: Timeline, document: Document) -> String {
        if let handoff = voiceHandoff, let chapter = timeline.chapterIndex(forUtterance: index), chapter >= handoff.fromChapter {
            return handoff.voiceID
        }
        return document.voiceID ?? "default"
    }

    /// From `chapter` on, render with `voiceID`. Chapters before it keep their keys and play as they
    /// are; a render in flight for a later chapter lands under its old key and is superseded by the
    /// plan this triggers. Nothing without a document.
    public func handOff(to voiceID: String, fromChapter chapter: Int) {
        guard document != nil, timeline != nil else { return }
        voiceHandoff = VoiceHandoff(fromChapter: chapter, voiceID: voiceID)
        replan()
    }
```

`load` keeps building its validation keys from `let voice = document.voiceID ?? "default"`: it has just cleared the handoff, so that is the same answer.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PlaybackCoordinatorTests`
Expected: all pass.

- [ ] **Step 5: Run the two-command full suite**

Run: `swift test --skip T2SStoreTests` then `swift test --filter T2SStoreTests`
Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SAudio/PlaybackCoordinator.swift Tests/T2SAudioTests/PlaybackCoordinatorTests.swift
git commit -m "The coordinator hands a document to another voice from a chapter on, keeping what came before"
```

---

### Task 6: The player hands off at the first chapter change after readiness

**Files:**
- Modify: `Sources/T2SApp/Player/PlayerModel.swift` (properties near line 63; `load`'s tail near line 232; `unload`; `tick` near line 353)
- Test: `Tests/T2SAppTests/PlayerModelTests.swift`

**Interfaces:**
- Consumes: `PlaybackCoordinator.handOff(to:fromChapter:)`, `voiceHandoff` (Task 5), `VoiceRouteResolving`, `Delivery.applied(to:)`, `KokoroVoiceID(rawValue:)`.
- Produces: `PlayerModel.settleHandoff()` (internal, for tests).

- [ ] **Step 1: Write the failing tests**

Add to the `PlayerModelTests` suite, after `anUnavailableKokoroVoiceRendersTheWholeDocumentWithTheSystemDefault`:

```swift
    /// A route that answers one thing until told otherwise: the hosted voice while Heart installs,
    /// then the on-device voice.
    private final class FlippingRouting: VoiceRouteResolving, @unchecked Sendable {
        private let lock = NSLock()
        private var answer: String
        init(_ answer: String) { self.answer = answer }
        func flip(to answer: String) { lock.lock(); self.answer = answer; lock.unlock() }
        func effectiveVoiceID(_ requested: String) async -> String { lock.lock(); defer { lock.unlock() }; return answer }
    }

    @Test func aChapterChangeWhileStillHostedHandsNothingOff() async throws {
        let hosted = "cloud:fingerprint:af_heart"
        let f = try AppFixtures()
        let id = try await f.importFake()
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let player = try makePlayer(f, engine: engine)
        player.voiceRouting = FlippingRouting(hosted)
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.coordinator.waitForRenderIdle()
        #expect(Set(await engine.requests.map(\.voiceID)) == [hosted])

        await player.seek(toChapter: 1)
        player.tick()
        await player.settleHandoff()
        #expect(player.coordinator.voiceHandoff == nil)
        #expect(player.routedVoiceID == hosted)
    }

    @Test func theFirstChapterChangeAfterTheOnDeviceVoiceAnswersHandsOff() async throws {
        let hosted = "cloud:fingerprint:af_heart"
        let local = "kokoro:kokoro-coreml-2e878c6a-misaki1.0.6:af_heart"
        let f = try AppFixtures()
        let id = try await f.importFake()
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let player = try makePlayer(f, engine: engine)
        let routing = FlippingRouting(hosted)
        player.voiceRouting = routing
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.coordinator.waitForRenderIdle()
        let rendered = await engine.requests.count

        // Ready, but no chapter change yet: nothing happens on a tick.
        routing.flip(to: local)
        player.tick()
        await player.settleHandoff()
        #expect(player.coordinator.voiceHandoff == nil)

        // The next chapter boundary hands the rest of the book to the on-device voice.
        await player.seek(toChapter: 1)
        player.tick()
        await player.settleHandoff()
        #expect(player.coordinator.voiceHandoff == VoiceHandoff(fromChapter: 1, voiceID: Delivery.applied(to: local)))
        #expect(player.routedVoiceID == local)
        await player.coordinator.waitForRenderIdle()
        let after = Array((await engine.requests).dropFirst(rendered))
        #expect(!after.isEmpty && after.allSatisfy { $0.voiceID == Delivery.applied(to: local) })
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PlayerModelTests`
Expected: compilation fails, `value of type 'PlayerModel' has no member 'settleHandoff'`.

- [ ] **Step 3: Implement the trigger**

In `Sources/T2SApp/Player/PlayerModel.swift`, after `public var voiceRouting: any VoiceRouteResolving = PassthroughVoiceRouting()`, add:

```swift
    /// The voice `load` asked the routing about — the stored or default choice — kept so a chapter
    /// change can ask again (cloud-first bootstrap spec).
    private var requestedVoiceID: String?
    /// The chapter the last `tick` saw the playhead in; a change is the handoff's moment.
    private var lastChapter: Int?
    private var handoffCheck: Task<Void, Never>?
```

In `load`, after `routedVoiceID = routed`, add:

```swift
            self.requestedVoiceID = requestedVoiceID
            lastChapter = chapterIndex
```

In `unload`, where `routedVoiceID` is cleared, also clear the three: `requestedVoiceID = nil`, `lastChapter = nil`, `handoffCheck?.cancel(); handoffCheck = nil`.

Replace `tick()` with:

```swift
    /// Drive from a 10 Hz timer while playing (spec §3: the coordinator polls the player clock).
    public func tick() {
        coordinator.tick()
        handOffIfChapterChanged()
        persistIfDue()
    }

    /// The on-device engine takes over at the first chapter boundary after it is ready (cloud-first
    /// bootstrap spec): on a chapter change while the book plays through the hosted voice, the route
    /// is asked again, and a `kokoro:` answer hands the rest of the book to it. One question at a
    /// time; a boundary crossed while one is in flight is caught by the next.
    private func handOffIfChapterChanged() {
        let chapter = chapterIndex
        guard chapter != lastChapter else { return }
        lastChapter = chapter
        guard let chapter, current != nil, handoffCheck == nil,
              let requested = requestedVoiceID, routedVoiceID?.hasPrefix("cloud:") == true
        else { return }
        handoffCheck = Task { [weak self] in
            guard let self else { return }
            let routed = await self.voiceRouting.effectiveVoiceID(requested)
            self.handoffCheck = nil
            guard KokoroVoiceID(rawValue: routed) != nil else { return }
            self.routedVoiceID = routed
            self.coordinator.handOff(to: Delivery.applied(to: routed), fromChapter: chapter)
        }
    }

    /// Awaits the handoff question in flight, if any — for tests that tick by hand.
    func settleHandoff() async { await handoffCheck?.value }
```

(`routedVoiceID` is `public private(set)`, so the class may assign it.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PlayerModelTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp/Player/PlayerModel.swift Tests/T2SAppTests/PlayerModelTests.swift
git commit -m "The player hands the book to the on-device voice at the first chapter change after it answers"
```

---

### Task 7: Prepare waits for the on-device voice

**Files:**
- Modify: `Sources/T2SApp/Playback/PrepareRunner.swift` (`PrepareSkipReason`; the property block near line 66; the private `run(reason:lastPlayed:queue:device:)`)
- Test: `Tests/T2SAppTests/PrepareRunnerTests.swift`

**Interfaces:**
- Produces: `PrepareRunner.isStandingIn: @Sendable () async -> Bool` (default `{ false }`), `PrepareSkipReason.waitingForVoice`. Task 8 sets the closure.

- [ ] **Step 1: Write the failing test**

Add to the `PrepareRunnerTests` suite, after `unsafeDeviceDoesNoWorkAndDoesNotClaimARun`:

```swift
    /// While the hosted voice stands in, a charger must not render a library through the mirrors.
    @Test func aRunWhileTheHostedVoiceStandsInPlansNothing() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let engine = FakeEngine()
        let runner = PrepareRunner(library: fixtures.library, store: fixtures.store, audioStore: fixtures.audio,
                                   engine: engine, defaults: UserDefaults(suiteName: "prepare-\(UUID())")!, arbiter: RenderArbiter())
        let charging = DeviceState(charging: true, thermalSerious: false, lowPowerMode: false, storeFull: false)

        runner.isStandingIn = { true }
        let waiting = await runner.run(lastPlayed: id, queue: [id], device: charging)
        #expect(waiting.stopReason == .skipped(.waitingForVoice))
        #expect(waiting.renderedUtterances == 0)
        #expect(await engine.requests.isEmpty)

        runner.isStandingIn = { false }
        let later = await runner.run(lastPlayed: id, queue: [id], device: charging)
        #expect(later.renderedUtterances > 0)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter PrepareRunnerTests`
Expected: compilation fails, `value of type 'PrepareRunner' has no member 'isStandingIn'`.

- [ ] **Step 3: Add the gate**

In `Sources/T2SApp/Playback/PrepareRunner.swift`, add `case waitingForVoice` to `PrepareSkipReason`. After `public var voiceRouting: any VoiceRouteResolving = PassthroughVoiceRouting()`, add:

```swift
    /// True while the app's default voice resolves to the hosted stand-in (cloud-first bootstrap
    /// spec): a run then does nothing rather than render a library through the mirrors on a charger.
    public var isStandingIn: @Sendable () async -> Bool = { false }
```

In the private `run(reason:lastPlayed:queue:device:)`, after the `Self.isSafe(device)` guard and before `beginRun()`, add:

```swift
        guard await !isStandingIn() else {
            return finish(PrepareRunResult(reason: reason, stopReason: .skipped(.waitingForVoice)))
        }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PrepareRunnerTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SApp/Playback/PrepareRunner.swift Tests/T2SAppTests/PrepareRunnerTests.swift
git commit -m "Prepare waits for the on-device voice instead of rendering a library through the mirrors"
```

---

### Task 8: Wire the app

**Files:**
- Modify: `App/T2SReader/System/KokoroComposition.swift:266` (`make`), `:413-426` (Kokoro routing), `:451` (everyday routing)
- Modify: `App/T2SReader/AppEnvironment.swift:155-170` (`live`), `:96-108` (the `init` that assigns `prepareRunner.voiceRouting`)
- Modify: `App/project.yml:90`, `App/Local.xcconfig.example`
- Untracked: `App/Local.xcconfig` (the key)

**Interfaces:**
- Consumes: everything Tasks 1–7 produced.
- Produces: `KokoroComposition.make(gate:defaults:standIn:)`; both schemes build.

- [ ] **Step 1: The composition takes the stand-in**

In `App/T2SReader/System/KokoroComposition.swift`, change `make`'s signature to:

```swift
    static func make(gate: ForegroundGate, defaults: UserDefaults = .standard,
                     standIn: @escaping @Sendable () -> String? = { nil }) -> KokoroComposition {
```

In the Kokoro build's `KokoroVoiceRouting(` construction, after the `defaultVoice:` argument, add `standIn: standIn`. In the everyday build's return, replace `voiceRouting: KokoroVoiceRouting.unavailable` with `voiceRouting: KokoroVoiceRouting(routes: [], defaultVoice: nil, standIn: standIn)`.

- [ ] **Step 2: The environment seeds, builds the stand-in, gates prepare**

In `App/T2SReader/AppEnvironment.swift`, in `live()`, replace

```swift
        let cloudVoiceSettings = CloudVoiceSettings()
        let cloudVoiceSecrets = KeychainSecretStore()
```

with

```swift
        let cloudVoiceSettings = CloudVoiceSettings(shipped: .pilot)
        let cloudVoiceSecrets = KeychainSecretStore()
        // The build's key into the Keychain, once (cloud-first bootstrap spec). A failure to store
        // is not fatal: the route then waits for a key typed in Cloud voices, as before.
        _ = try? CloudVoiceKeySeeder.seed(infoValue: Bundle.main.infoDictionary?["T2SCloudVoiceKey"] as? String,
                                          into: cloudVoiceSecrets)
```

and replace `let kokoro = KokoroComposition.make(gate: foregroundGate)` with:

```swift
        // Hosted Heart stands in for the default wherever the on-device route is not yet open —
        // while a route is configured and the Keychain holds its key.
        let standIn: @Sendable () -> String? = {
            guard let configuration = configurationStore.current(),
                  let key = try? cloudVoiceSecrets.load(), !key.isEmpty
            else { return nil }
            return CloudVoiceID(configuration: configuration, voice: configuration.voice).rawValue
        }
        let kokoro = KokoroComposition.make(gate: foregroundGate, standIn: standIn)
```

In the initializer, after `prepareRunner.voiceRouting = voiceRouting`, add:

```swift
        // A charger never renders a library through the mirrors: prepare waits for the on-device voice.
        prepareRunner.isStandingIn = { await voiceRouting.effectiveVoiceID(VoiceOption.systemDefault.id).hasPrefix("cloud:") }
```

- [ ] **Step 3: The key's path from xcconfig to Info.plist**

In `App/project.yml`, directly after the line `        T2SICloudContainer: $(T2S_ICLOUD_CONTAINER)`, add:

```yaml
        T2SCloudVoiceKey: $(T2S_CLOUD_VOICE_KEY)
```

Append to `App/Local.xcconfig.example`:

```
//
// The hosted voice's bearer key (cloud-first bootstrap spec). Seeded into the Keychain on the first
// launch, so a fresh install speaks from the mirrors with nothing typed. The value in
// ~/.t2s/heroku-voice-key on the owner's Mac; leave the line commented to ship without it.
// T2S_CLOUD_VOICE_KEY =
```

Append the real key to the git-ignored `App/Local.xcconfig` without printing it:

```bash
printf 'T2S_CLOUD_VOICE_KEY = %s\n' "$(<~/.t2s/heroku-voice-key)" >> App/Local.xcconfig
grep -c "T2S_CLOUD_VOICE_KEY" App/Local.xcconfig      # 1
git status --short App/Local.xcconfig                 # nothing: it is ignored
```

- [ ] **Step 4: Regenerate and build both schemes**

Run: `(cd App && xcodegen generate --quiet) && grep -c T2SCloudVoiceKey App/T2SReader/Info.plist App/T2SReader/Info-Kokoro.plist`
Expected: `1` for each generated plist.

Run: `xcodebuild -project App/T2SReader.xcodeproj -scheme Simulator -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Run: `xcodebuild -project App/T2SReader.xcodeproj -scheme Phone -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData-Phone -allowProvisioningUpdates build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the two-command full suite once more**

Run: `swift test --skip T2SStoreTests` then `swift test --filter T2SStoreTests`
Expected: both pass.

- [ ] **Step 6: Commit (the xcconfig itself is ignored and stays out)**

```bash
git add App/T2SReader/System/KokoroComposition.swift App/T2SReader/AppEnvironment.swift App/project.yml App/Local.xcconfig.example
git commit -m "The app ships its hosted route and key, stands in with hosted Heart, and keeps prepare off the mirrors"
```

---

### Task 9: Live acceptance on the 17 Pro

**Files:**
- Create: `docs/superpowers/evidence/2026-09-11-cloud-first-acceptance.log`
- Modify: `docs/HANDOFF.md`

- [ ] **Step 1: Install**

```bash
app="$(find .build/DerivedData-Phone/Build/Products/Debug-iphoneos -maxdepth 1 -name '*.app' | head -1)"
xcrun devicectl device install app --device 47017566-BBC0-5AF1-83F1-0384F6E32C9C "$app" 2>&1 | tail -3
```

A new build makes the on-device engine rebuild its compute plans (159–199 s on this phone), which is the installing window the stand-in exists for.

- [ ] **Step 2: First sound from the mirrors, nothing typed**

On the phone, immediately after install: open the app, open a book, tap play within ten seconds. Expect Heart from the mirrors within one render (~15–25 s), the veil still warming. Settings → Cloud voices should read "Cloud route active" with the four endpoints filled in; the Reader's voice chip should show the hosted voice. On the Mac, confirm the requests arrived:

```bash
for a in kokoro-t2s kokoro-t2s-m2 kokoro-t2s-m3 kokoro-t2s-m4; do
  printf '%-14s renders in the last 10 min: %s\n' "$a" "$(heroku logs -a $a -n 300 2>/dev/null | grep -c 'POST /v1/audio/speech' )"
done
```

- [ ] **Step 3: The handoff**

Keep listening past the green beat, into the next chapter (skip to it if the current one is long). Expect no audible seam. Then confirm the mirrors stopped receiving requests for that chapter and later:

```bash
for a in kokoro-t2s kokoro-t2s-m2 kokoro-t2s-m3 kokoro-t2s-m4; do
  echo "== $a"; heroku logs -a $a -n 200 2>/dev/null | grep 'POST /v1/audio/speech' | tail -2 | cut -c1-60
done
```

Expected: the last request timestamps on every mirror precede the chapter change.

- [ ] **Step 4: Seek back**

Seek into the chapter before the boundary. Expect it to play at once (cache) with no new mirror request in the logs.

- [ ] **Step 5: Record**

Write `docs/superpowers/evidence/2026-09-11-cloud-first-acceptance.log` with the observations from Steps 2–4 verbatim, and add to `docs/HANDOFF.md` at the end of the Heroku section:

```markdown
**Cloud-first bootstrap (2026-09-11, late):** the route and key ship with the app
(`CloudVoiceDefaults.pilot`; `T2S_CLOUD_VOICE_KEY` in `App/Local.xcconfig`, seeded into the Keychain
once), hosted Heart stands in wherever the on-device default is not open, and the player hands the
book to the on-device voice at the first chapter change after it answers; prepare waits. Design:
`docs/superpowers/specs/2026-09-11-cloud-first-bootstrap-design.md`; run:
`docs/superpowers/evidence/2026-09-11-cloud-first-acceptance.log`. Still owed: per-reader tokens
before any reader beyond the two phones; server streaming for a first sound under ~3 s.
```

```bash
git add docs/superpowers/evidence/2026-09-11-cloud-first-acceptance.log docs/HANDOFF.md
git commit -m "Record the cloud-first bootstrap's acceptance run"
```

If the first sound never comes or the seam is audible: remove the `T2S_CLOUD_VOICE_KEY` line from `App/Local.xcconfig`, rebuild, reinstall — the stand-in then has no key and the app behaves as before — and record what was heard instead of an acceptance.
