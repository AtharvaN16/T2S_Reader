import Foundation

/// The last few renders, in memory, in front of a persistent store.
///
/// The scheduler writes every utterance to the AAC cache and the coordinator reads it back to play
/// it — through a temporary file each way — so every second heard was the cache, never the render
/// (`docs/superpowers/specs/2026-09-08-performance-audit.md` §3.3). This tier keeps the PCM of the
/// last `limit` writes (~1 MB each for 10 s at 24 kHz mono float) and serves a read from memory when
/// the base store still holds the key. The base store stays the truth: `contains`, `stats`, capacity
/// and eviction are its; a key the base has dropped is dropped here on the next read; a write the
/// base refuses is never remembered.
public actor RecentAudioStore: AudioStore {
    private let base: any AudioStore
    private let limit: Int
    private var recent: [RenderKey: PCMAudio] = [:]
    /// Oldest first.
    private var order: [RenderKey] = []

    public init(base: any AudioStore, keeping limit: Int = 8) {
        self.base = base
        self.limit = max(1, limit)
    }

    public func contains(_ key: RenderKey) async -> Bool { await base.contains(key) }

    public func contains(_ keys: [RenderKey]) async -> [Bool] { await base.contains(keys) }

    public func write(_ pcm: PCMAudio, for key: RenderKey) async throws {
        try await base.write(pcm, for: key)
        remember(key, pcm)
    }

    public func read(_ key: RenderKey) async throws -> PCMAudio? {
        if let pcm = recent[key] {
            if await base.contains(key) { return pcm }
            forget(key)
        }
        return try await base.read(key)
    }

    public func remove(_ key: RenderKey) async throws {
        forget(key)
        try await base.remove(key)
    }

    public func stats() async -> AudioStoreStats { await base.stats() }

    public func setCapacity(bytes: Int) async { await base.setCapacity(bytes: bytes) }

    private func remember(_ key: RenderKey, _ pcm: PCMAudio) {
        forget(key)
        recent[key] = pcm
        order.append(key)
        while order.count > limit {
            let oldest = order.removeFirst()
            recent[oldest] = nil
        }
    }

    private func forget(_ key: RenderKey) {
        guard recent.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
    }
}
