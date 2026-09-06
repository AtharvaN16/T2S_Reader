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

    @Test func fileStoreNamespacesByCodec() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-store-\(UUID().uuidString)")
        let s = FileAudioStore(directory: dir, codec: RawPCMCodec(), capacityBytes: 10_000)
        try await s.write(pcm(1), for: key(1))
        let expected = dir.appendingPathComponent("pcm-f32le", isDirectory: true).appendingPathComponent(key(1).fileName)
        #expect(FileManager.default.fileExists(atPath: expected.path))
    }

    /// A codec change (spec §3.7.4) lands in a new namespace; the previous codec's directory must
    /// not sit on disk forever (`AACCodec` moved from 32 kbps to 64 kbps on 2026-09-05,
    /// `spikes/findings/2026-09-05-coreml-audio-quality.md`).
    @Test func removesStaleCodecDirectoriesOnInit() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-store-\(UUID().uuidString)")
        let staleDir = dir.appendingPathComponent("aac-32k-mono-24k", isDirectory: true)
        try FileManager.default.createDirectory(at: staleDir, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: staleDir.appendingPathComponent("leftover.audio"))

        // The current codec's own directory, as if from an earlier launch — the sweep must never
        // touch it.
        let currentDir = dir.appendingPathComponent("pcm-f32le", isDirectory: true)
        try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        let keptFile = currentDir.appendingPathComponent("keep.audio")
        try Data("keep".utf8).write(to: keptFile)

        let s = FileAudioStore(directory: dir, codec: RawPCMCodec(), capacityBytes: 10_000)

        #expect(!FileManager.default.fileExists(atPath: staleDir.path))
        #expect(FileManager.default.fileExists(atPath: keptFile.path))
        try await s.write(pcm(1), for: key(1))
        #expect(await s.contains(key(1)))
    }

    @Test func fileStoreIgnoresForeignFilesOnScan() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-store-\(UUID().uuidString)")
        let codecDir = dir.appendingPathComponent("pcm-f32le", isDirectory: true)
        try FileManager.default.createDirectory(at: codecDir, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: codecDir.appendingPathComponent("not-a-key.audio"))
        try Data("junk".utf8).write(to: codecDir.appendingPathComponent(String(repeating: "Z", count: 64) + ".audio"))
        let s = FileAudioStore(directory: dir, codec: RawPCMCodec(), capacityBytes: 10_000)
        #expect(await s.stats().entries == 0)
    }

    @Test func runningByteTotalMatchesEntries() async throws {
        for (name, s) in stores() {
            try await s.write(pcm(1), for: key(1))
            try await s.write(pcm(1), for: key(1))      // overwrite must not double count
            try await s.write(pcm(1), for: key(2))
            #expect(await s.stats().bytes == 8_016, "\(name)")
            try await s.remove(key(1))
            #expect(await s.stats().bytes == 4_008, "\(name)")
        }
    }
}
