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
