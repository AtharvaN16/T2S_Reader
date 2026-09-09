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
        await engine.hold()                             // nothing can render until release: catching-up is deterministic
        c.load(doc, timeline: timeline)
        await c.play()                                  // nothing rendered yet
        #expect(c.state == .catchingUp)
        #expect(!player.isPlaying)
        await engine.release()
        await c.waitForRenderIdle()
        #expect(c.state == .playing)
        #expect(player.isPlaying)
        #expect(player.enqueuedTags.prefix(2) == [0, 1])
    }

    @Test func timelineRevisionMovesOnLoadAndOnRender() async throws {
        let (c, _, engine, _, _, doc, timeline) = fixture()
        await engine.hold()                             // nothing renders until release
        let atStart = c.timelineRevision
        c.load(doc, timeline: timeline)
        let afterLoad = c.timelineRevision
        #expect(afterLoad != atStart)
        await engine.release()
        await c.waitForRenderIdle()
        #expect(c.timelineRevision != afterLoad)        // `.rendered` events rewrote the utterances
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

    /// Spec §3.6 gates the rates *offered*; a rate chosen while the RTF was unknown, or a phone that
    /// throttles mid-book, still left the current rate in place until the window drained and playback
    /// paused on "catching up" (audit §3.5). Now the rate follows the cap down, and says so once.
    @Test func rateStepsDownWhenTheMeasuredRTFCannotSustainIt() async throws {
        let block = SourceBlock(text: "Alpha one. Beta two. Gamma three.", position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 0))
        let timeline = TimelineBuilder.build(chapters: [ChapterInput(title: "C", position: block.position, blocks: [block])],
                                             segmenter: Segmenter(normalizer: TextNormalizer()))
        let clock = ManualTimeSource()
        let engine = FakeEngine(secondsPerCharacter: 0.1, simulatedRTF: 0.5, timeSource: clock)   // 0.5 sustains 1.5x, not 3x
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let player = FakePlayer()
        let c = PlaybackCoordinator(engine: engine, store: store, player: player, playheadStore: MemoryPlayheadStore(), timeSource: clock,
                                    configuration: CoordinatorConfiguration(windowSeconds: 60, primeSeconds: 30, prepareBudgetSeconds: 300, queuedSegments: 2))
        c.load(Document(title: "T", sourceType: .article), timeline: timeline)
        c.setRate(3.0)                                                   // RTF unknown: allowed
        #expect(c.rate == 3.0 && c.rateLoweredTo == nil)

        await c.waitForRenderIdle()                                      // three renders at RTF 0.5

        #expect(abs((c.measuredRTF ?? 0) - 0.5) < 1e-9)                  // the mean of the two samples after the first, skipped, one
        #expect(c.availableRates == [0.5, 0.75, 1.0, 1.25, 1.5])
        #expect(c.rate == 1.5 && player.rate == 1.5)
        #expect(c.rateLoweredTo == 1.5)
        c.setRate(1.0)
        #expect(c.rateLoweredTo == nil)                                  // the listener's own choice clears the notice
    }

    /// A phone that stops throttling gets its rate back: the coordinator remembers what the listener
    /// asked for and follows the cap in both directions, so a lowered rate is a notice, not a
    /// sentence for the session (the Plan 13 final review, finding 1).
    @Test func rateRecoversWhenTheMeasuredRTFImproves() async throws {
        let (c, player, engine, doc, timeline) = throttledFixture()
        c.load(doc, timeline: timeline)
        c.setRate(3.0)                                                   // RTF unknown: allowed
        await c.waitForRenderIdle()                                      // renders at RTF 0.5

        #expect(c.rate == 1.5 && player.rate == 1.5)
        #expect(c.rateLoweredTo == 1.5)

        await engine.setSimulatedRTF(0.1)                                // the phone cools down
        c.renderWholeDocument()
        await c.waitForRenderIdle()                                      // a window of renders at RTF 0.1

        #expect((c.measuredRTF ?? 1) < 0.2)
        #expect(c.rate == 3.0 && player.rate == 3.0)                     // back to what the listener asked for
        #expect(c.rateLoweredTo == nil)                                  // and the notice is gone
    }

    /// A rate the measured RTF can already sustain is left exactly where the listener put it — the
    /// coordinator raises towards the request, never above it.
    @Test func aSustainableRateIsNotRaisedAboveTheRequest() async throws {
        let (c, player, _, doc, timeline) = throttledFixture(window: 4)
        c.load(doc, timeline: timeline)
        c.setRate(1.0)                                                   // well under the 1.5x cap RTF 0.5 allows
        await c.waitForRenderIdle()

        #expect(abs((c.measuredRTF ?? 0) - 0.5) < 1e-9)
        #expect(c.rate == 1.0 && player.rate == 1.0)
        #expect(c.rateLoweredTo == nil)
    }

    /// Forty one-sentence utterances and a one-second window: the play-ahead window renders a
    /// handful, so the rest are left for a later plan to render at whatever RTF is current by then.
    func throttledFixture(window: TimeInterval = 1) -> (PlaybackCoordinator, FakePlayer, FakeEngine, Document, Timeline) {
        let text = (0..<40).map { "Sentence number \($0) here." }.joined(separator: " ")
        let block = SourceBlock(text: text, position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 0))
        let timeline = TimelineBuilder.build(chapters: [ChapterInput(title: "C", position: block.position, blocks: [block])],
                                             segmenter: Segmenter(normalizer: TextNormalizer()))
        let clock = ManualTimeSource()
        let engine = FakeEngine(secondsPerCharacter: 0.04, simulatedRTF: 0.5, timeSource: clock)  // 0.5 sustains 1.5x, not 3x
        let player = FakePlayer()
        let c = PlaybackCoordinator(engine: engine, store: InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000),
                                    player: player, playheadStore: MemoryPlayheadStore(), timeSource: clock,
                                    configuration: CoordinatorConfiguration(windowSeconds: window, primeSeconds: 30, prepareBudgetSeconds: 300, queuedSegments: 2))
        return (c, player, engine, Document(title: "T", sourceType: .article), timeline)
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

    @Test func mediaServicesResetRestoresPersistedPositionAndPlayingIntent() async throws {
        let (c, player, _, _, _, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        await c.play()
        player.advance(seconds: 0.7); c.tick()
        let resume = PositionResolver.position(for: c.playhead, in: c.timeline!)

        await c.recoverAfterMediaServicesReset()

        #expect(c.state == .playing)
        #expect(PositionResolver.position(for: c.playhead, in: c.timeline!) == resume)
        #expect(player.resets == 3) // load, reset recovery, and the persisted-position seek
    }

    @Test func staleAudioReferenceDoesNotCountAsRendered() async throws {
        let (c, _, engine, store, _, doc, timeline) = fixture()
        let staleKey = RenderKey(documentID: doc.id, utteranceIndex: 0, voiceID: "obsolete-voice",
                                 engineID: engine.engineID, normalizerVersion: timeline.normalizerVersion,
                                 segmenterVersion: timeline.segmenterVersion)
        try await store.write(.silence(seconds: 1), for: staleKey)
        var staleTimeline = timeline
        var first = staleTimeline[utterance: 0]
        first.audioRef = staleKey.rawValue
        staleTimeline[utterance: 0] = first

        c.load(doc, timeline: staleTimeline)
        await c.waitForRenderIdle()

        let expected = RenderKey(documentID: doc.id, utteranceIndex: 0, voiceID: "default",
                                 engineID: engine.engineID, normalizerVersion: timeline.normalizerVersion,
                                 segmenterVersion: timeline.segmenterVersion)
        #expect(c.timeline?[utterance: 0].audioRef == expected.rawValue)
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

    @Test func waitCoversAPlanAbsorbedMidRun() async throws {
        let (c, _, engine, _, _, doc, timeline) = fixture()
        await engine.hold()                                        // the first plan parks on utterance 0
        c.load(doc, timeline: timeline)
        await c.settle()                                           // plan submitted, loop running
        c.setRate(2.0)                                             // replan while the loop is running: absorbed
        await c.settle()
        await engine.release()
        await c.waitForRenderIdle()
        #expect(c.timeline?.isFullyRendered == true)               // nothing was released early
        #expect(c.rate == 2.0)
    }

    @Test func waitCoversAnEmptyPlan() async throws {
        let (c, _, _, _, _, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        c.renderWholeDocument()                                    // already fully rendered: an empty plan
        await c.waitForRenderIdle()                                // must return, not hang
        #expect(c.timeline?.isFullyRendered == true)
    }

    /// The head streams into the player at load (Plan 14), so evicting *its* clip changes nothing;
    /// the next utterance's clip is only in the store, and losing it must self-heal on the way in.
    @Test func evictedClipRecovers() async throws {
        let (c, player, _, store, _, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        let key1 = RenderKey(rawValue: c.timeline![utterance: 1].audioRef!)
        await store.remove(key1)                                   // LRU eviction is normal (spec §3.7.3)
        await c.play()
        #expect(c.state == .playing)                               // the head is already in the player
        await c.waitForRenderIdle()                                // fill found 1 missing and had it re-rendered
        #expect(player.enqueuedTags.prefix(2) == [0, 1])
        #expect(c.timeline?[utterance: 1].audioRef != nil)
    }

    @Test func cachedAudioWithoutAudioRefDoesNotHang() async throws {
        let (c, _, engine, store, _, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()                                 // store now holds all three clips
        let second = PlaybackCoordinator(engine: engine, store: store, player: FakePlayer(), playheadStore: MemoryPlayheadStore(), timeSource: ManualTimeSource(),
                                         configuration: CoordinatorConfiguration(windowSeconds: 60, primeSeconds: 30, prepareBudgetSeconds: 300, queuedSegments: 2))
        second.load(doc, timeline: timeline)                        // the original timeline: no audioRefs
        await second.play()
        await second.waitForRenderIdle()
        #expect(second.state == .playing)
        #expect(await engine.requests.count == 3)                  // nothing re-synthesized
    }

    @Test func staleAudioReferenceForAnotherVoiceIsNotAccepted() async throws {
        let (c, _, engine, _, _, doc, originalTimeline) = fixture()
        var timeline = originalTimeline
        let stale = RenderKey(documentID: doc.id, utteranceIndex: 0, voiceID: "old-voice", engineID: engine.engineID,
                              normalizerVersion: timeline.normalizerVersion, segmenterVersion: timeline.segmenterVersion)
        timeline[utterance: 0].audioRef = stale.rawValue
        await engine.hold()                                        // inspect load state before the replacement can render

        c.load(doc, timeline: timeline)

        #expect(c.timeline?[utterance: 0].audioRef == nil)
        await engine.release()
    }

    @Test func concurrentPlayEnqueuesEachSegmentOnce() async throws {
        let (c, player, _, _, _, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        async let a: Void = c.play()
        async let b: Void = c.play()
        _ = await (a, b)
        await c.settle()
        #expect(player.enqueuedTags == [0, 1])
    }

    @Test func seekPastEndFinishes() async throws {
        let (c, player, _, _, _, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        await c.seek(toTime: 99)
        #expect(c.state == .finished)
        #expect(c.playhead == Playhead(utteranceIndex: 2, offset: 1.2))
        await c.play()                                              // restarts from the top
        #expect(c.playhead.utteranceIndex == 0 && c.state == .playing)
        #expect(player.enqueuedTags.first == 0)
    }

    @Test func storeFullRecoversAfterResume() async throws {
        let (c, _, _, store, _, doc, timeline) = fixture(capacity: 100)
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        #expect(c.device.storeFull)
        await store.setCapacity(bytes: 10_000_000)
        await c.resumeRendering()
        await c.waitForRenderIdle()
        #expect(c.timeline?.isFullyRendered == true)
    }

    @Test func nonFiniteRateIsIgnored() async throws {
        let (c, player, _, _, _, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        c.setRate(.nan)
        #expect(c.rate == 1.0 && player.rate == 1.0)
    }

    @Test func failedRenderIsSurfaced() async throws {
        let (c, _, engine, _, _, doc, timeline) = fixture()
        await engine.fail(on: "Beta two.")
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        #expect(c.lastRenderError?.hasPrefix("utterance 1:") == true)
    }

    @Test func cloudKeyRejectionIsSurfacedForThePlayer() async throws {
        let (_, player, _, store, saves, doc, timeline) = fixture()
        let coordinator = PlaybackCoordinator(engine: KeyRejectedEngine(), store: store, player: player, playheadStore: saves,
                                              timeSource: ManualTimeSource())
        coordinator.load(doc, timeline: timeline)
        await coordinator.waitForRenderIdle()

        #expect(coordinator.lastRenderError?.contains("key was rejected") == true)
    }

    // MARK: Plan 14 — the head streams

    /// The same three sentences, rendered by a fake that streams each utterance in `pieces` pieces
    /// and parks between them, so a test can see the player start on the first piece.
    func streamingFixture(pieces: Int = 3) async
        -> (PlaybackCoordinator, FakePlayer, FakeEngine, InMemoryAudioStore, Document, Timeline) {
        let block = SourceBlock(text: "Alpha one. Beta two. Gamma three.", position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 0))
        let timeline = TimelineBuilder.build(chapters: [ChapterInput(title: "C", position: block.position, blocks: [block])],
                                             segmenter: Segmenter(normalizer: TextNormalizer()))
        let engine = FakeEngine(secondsPerCharacter: 0.1, pieceCount: pieces)
        await engine.holdBetweenPieces()
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let player = FakePlayer()
        let c = PlaybackCoordinator(engine: engine, store: store, player: player, playheadStore: MemoryPlayheadStore(), timeSource: ManualTimeSource(),
                                    configuration: CoordinatorConfiguration(windowSeconds: 60, primeSeconds: 30, prepareBudgetSeconds: 300, queuedSegments: 2))
        return (c, player, engine, store, Document(title: "T", sourceType: .article), timeline)
    }

    /// Waits until the player holds `count` buffers, or fails after a second.
    func waitForBuffers(_ player: FakePlayer, _ count: Int) async {
        for _ in 0 ..< 200 where player.enqueuedTags.count < count { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(player.enqueuedTags.count == count, "buffers: \(player.enqueuedTags)")
    }

    /// Audit #2: a tap on an unrendered position plays after the head's first piece, not after the
    /// whole utterance — the player holds one buffer, is playing, and nothing else is queued.
    @Test func playStartsOnTheHeadsFirstPiece() async throws {
        let (c, player, engine, _, doc, timeline) = await streamingFixture()
        await engine.hold()                                          // nothing renders until release
        c.load(doc, timeline: timeline)
        await c.play()
        #expect(c.state == .catchingUp)
        await engine.release()                                       // utterance 0 starts streaming; piece 0 arrives, piece 1 parks
        await waitForBuffers(player, 1)
        await c.settle()
        #expect(c.state == .playing && player.isPlaying)
        #expect(player.enqueuedTags == [0])
        #expect(player.queue.first?.isFinal == false)
        // The next utterance is never enqueued behind an unfinished stream.
        await engine.releasePiece()                                  // piece 1
        await waitForBuffers(player, 2)
        #expect(player.enqueuedTags == [0, 0])
        await engine.stopHoldingBetweenPieces()                      // piece 2 (last) and everything after
        await c.waitForRenderIdle()
        #expect(player.enqueuedTags.prefix(4) == [0, 0, 0, 1])       // the last piece, then utterance 1 whole (it was not streamed)
        #expect(player.queue.filter { $0.tag == 0 }.last?.isFinal == true)
        #expect(c.timeline?[utterance: 0].wordTimings?.isEmpty == false)
    }

    /// The playhead moves through a streamed head as the pieces play, and the segment finishes
    /// once, after the last piece.
    @Test func aStreamedHeadPlaysThroughAsOneSegment() async throws {
        let (c, player, engine, _, doc, timeline) = await streamingFixture(pieces: 2)
        await engine.stopHoldingBetweenPieces()                      // stream freely
        c.load(doc, timeline: timeline)
        await c.play()
        await c.waitForRenderIdle()
        #expect(c.state == .playing)
        player.advance(seconds: 0.7); c.tick()
        #expect(c.playhead == Playhead(utteranceIndex: 0, offset: 0.7))
        player.advance(seconds: 0.4); await c.settle(); c.tick()     // past 1.0 s: utterance 1
        #expect(c.playhead.utteranceIndex == 1)
        #expect(abs(c.playhead.offset - 0.1) < 1e-9)
    }

    /// A seek into the middle of an unrendered utterance drops the offset from the streamed pieces,
    /// so `consumedSeconds` still maps to the playhead.
    @Test func aSeekIntoAStreamedHeadDropsTheOffset() async throws {
        let (c, player, engine, _, doc, timeline) = await streamingFixture(pieces: 2)
        await engine.stopHoldingBetweenPieces()
        await engine.hold()                                          // nothing renders until the seek has happened
        c.load(doc, timeline: timeline)
        await c.seek(to: Playhead(utteranceIndex: 0, offset: 0.6))   // "Alpha one." is 1.0 s: 0.4 s remain
        await engine.release()                                       // the head streams from its start; the coordinator drops 0.6 s
        await c.play()
        await c.waitForRenderIdle()
        #expect(player.queuedRemaining > 0)
        let head = player.queue.filter { $0.tag == 0 }
        #expect(head.count == 1)                                     // piece 0 (0.5 s) was consumed by the drop entirely; piece 1 carries the rest
        #expect(abs(head.reduce(0) { $0 + $1.remaining } - 0.4) < 1e-9)
        player.advance(seconds: 0.3); c.tick()
        #expect(abs(c.playhead.offset - 0.9) < 1e-9)
    }

    /// A stream the coordinator did not see from its first piece — the player was reset by a seek
    /// while it ran — is ignored; the `.rendered` that follows plays from the store as before.
    @Test func aStreamJoinedLateIsIgnoredAndTheStoreCopyPlays() async throws {
        let (c, player, engine, _, doc, timeline) = await streamingFixture(pieces: 2)
        await engine.hold()
        c.load(doc, timeline: timeline)
        await c.play()                                               // catching up on utterance 0
        await engine.release()
        await waitForBuffers(player, 1)                              // piece 0 in; piece 1 parked
        await c.seek(to: Playhead(utteranceIndex: 0, offset: 0))     // resets the player mid-stream
        #expect(player.queue.isEmpty)
        await engine.stopHoldingBetweenPieces()                      // piece 1 arrives for a stream nobody follows
        await c.waitForRenderIdle()
        #expect(c.state == .playing)
        let head = player.queue.filter { $0.tag == 0 }
        #expect(head.count == 1 && head.first?.isFinal == true)      // one whole buffer from the store, not a stray piece
    }

    /// Between the pieces of a streamed head the player can run dry; the coordinator pauses on
    /// "catching up" until the next piece lands, so the playhead never runs past the audio (Plan 16).
    @Test func aStreamedHeadThatRunsDryPausesUntilTheNextPiece() async throws {
        let (c, player, engine, _, doc, timeline) = await streamingFixture(pieces: 2)
        await engine.hold()
        c.load(doc, timeline: timeline)
        await c.play()
        await engine.release()                                       // piece 0 (0.5 s) arrives; piece 1 parks
        await waitForBuffers(player, 1)
        await c.settle()
        #expect(c.state == .playing)
        player.advance(seconds: 0.5); c.tick()                       // piece 0 fully consumed: the player is dry
        #expect(c.state == .catchingUp && !player.isPlaying)
        #expect(abs(c.playhead.offset - 0.5) < 1e-9)
        await engine.releasePiece()                                  // piece 1
        await waitForBuffers(player, 2)
        await c.settle()
        #expect(c.state == .playing && player.isPlaying)
        player.advance(seconds: 0.2); c.tick()
        #expect(abs(c.playhead.offset - 0.7) < 1e-9)                 // no jump: the clock stood still while dry
    }

    /// The player model persists the chapters the coordinator changed and nothing else (Plan 16): a
    /// render marks its chapter, taking the set clears it, a load starts it empty. A save carries
    /// where the playhead sits in its chapter beside the position.
    @Test func reportsChangedChaptersAndSavesTheTimeIntoTheChapter() async throws {
        let (c, _, _, _, saves, doc, _) = fixture()
        let a = SourceBlock(text: "Alpha one.", position: Position(resourceHref: "a.xhtml", progression: 0, charOffset: 0))
        let b = SourceBlock(text: "Beta two.", position: Position(resourceHref: "b.xhtml", progression: 0, charOffset: 0))
        let timeline = TimelineBuilder.build(chapters: [ChapterInput(title: "A", position: a.position, blocks: [a]),
                                                        ChapterInput(title: "B", position: b.position, blocks: [b])],
                                             segmenter: Segmenter(normalizer: TextNormalizer()))
        c.load(doc, timeline: timeline)
        #expect(c.changedChapters.isEmpty)
        await c.waitForRenderIdle()                                                              // the window covers both
        #expect(c.changedChapters == [0, 1])
        #expect(c.takeChangedChapters() == [0, 1])
        #expect(c.changedChapters.isEmpty)
        await c.seek(to: Playhead(utteranceIndex: 1, offset: 0.3))
        await c.settle()
        let saved = try #require(await saves.lastSaved)
        #expect(saved.position.resourceHref == "b.xhtml")
        #expect(saved.chapterIndex == 1 && abs(saved.secondsIntoChapter - 0.3) < 1e-9)
    }
}

private struct KeyRejectedEngine: SynthesisEngine {
    let engineID = "routed-v1"

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        throw HTTPVoiceError.server(status: 401, message: "key rejected")
    }
}
