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

    @Test func evictedHeadClipRecovers() async throws {
        let (c, player, _, store, _, doc, timeline) = fixture()
        c.load(doc, timeline: timeline)
        await c.waitForRenderIdle()
        let key0 = RenderKey(rawValue: c.timeline![utterance: 0].audioRef!)
        await store.remove(key0)                                   // LRU eviction is normal (spec §3.7.3)
        await c.play()
        #expect(c.state == .catchingUp)
        await c.waitForRenderIdle()
        #expect(c.state == .playing)
        #expect(player.enqueuedTags.first == 0)
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
}
