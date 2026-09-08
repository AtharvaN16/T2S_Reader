import Foundation
import Testing
@testable import T2SCore

/// Counts decodes: the memory tier exists so the live path never decodes what it just rendered.
final class CountingCodec: AudioCodec, @unchecked Sendable {
    let identifier = "pcm-f32le"
    private let inner = RawPCMCodec()
    private let lock = NSLock()
    private var _decodes = 0
    var decodes: Int { lock.withLock { _decodes } }
    func encode(_ pcm: PCMAudio) throws -> Data { try inner.encode(pcm) }
    func decode(_ data: Data) throws -> PCMAudio {
        lock.withLock { _decodes += 1 }
        return try inner.decode(data)
    }
}

@Suite struct RecentAudioStoreTests {
    let doc = UUID()
    func key(_ i: Int) -> RenderKey { RenderKey(documentID: doc, utteranceIndex: i, voiceID: "v", engineID: "fake", normalizerVersion: 1, segmenterVersion: 1) }
    func pcm(_ i: Int) -> PCMAudio { PCMAudio(sampleRate: 1000, samples: Array(repeating: Float(i), count: 100)) }

    @Test func aRecentRenderIsReadWithoutDecoding() async throws {
        let codec = CountingCodec()
        let base = InMemoryAudioStore(codec: codec, capacityBytes: 1_000_000)
        let store = RecentAudioStore(base: base, keeping: 2)
        try await store.write(pcm(1), for: key(1))
        #expect(try await store.read(key(1)) == pcm(1))
        #expect(codec.decodes == 0)
        #expect(await store.contains(key(1)))
        #expect(await store.stats().entries == 1)                         // the base's numbers, not the tier's
    }

    @Test func onlyTheLastFewStayInMemory() async throws {
        let codec = CountingCodec()
        let base = InMemoryAudioStore(codec: codec, capacityBytes: 1_000_000)
        let store = RecentAudioStore(base: base, keeping: 2)
        for i in 1...3 { try await store.write(pcm(i), for: key(i)) }
        #expect(try await store.read(key(3)) == pcm(3))
        #expect(try await store.read(key(2)) == pcm(2))
        #expect(codec.decodes == 0)
        #expect(try await store.read(key(1)) == pcm(1))                   // evicted from memory: the base serves it
        #expect(codec.decodes == 1)
    }

    @Test func theBaseStoreStaysTheTruth() async throws {
        let codec = CountingCodec()
        let base = InMemoryAudioStore(codec: codec, capacityBytes: 1_000_000)
        let store = RecentAudioStore(base: base, keeping: 4)
        try await store.write(pcm(1), for: key(1))
        await base.remove(key(1))                                          // evicted behind the tier's back
        #expect(!(await store.contains(key(1))))
        #expect(try await store.read(key(1)) == nil)
        try await store.write(pcm(2), for: key(2))
        try await store.remove(key(2))
        #expect(try await store.read(key(2)) == nil)
        #expect(codec.decodes == 0)
    }

    @Test func aFailedWriteCachesNothing() async throws {
        let codec = CountingCodec()
        let base = InMemoryAudioStore(codec: codec, capacityBytes: 100)   // 400 B of samples never fit
        let store = RecentAudioStore(base: base, keeping: 4)
        await #expect(throws: AudioStoreError.self) { try await store.write(pcm(1), for: key(1)) }
        #expect(try await store.read(key(1)) == nil)
    }
}
