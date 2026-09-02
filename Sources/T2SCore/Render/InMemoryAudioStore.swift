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
        if blobs[key] != nil { lru.remove(key); blobs[key] = nil }
        guard data.count <= capacity else { throw AudioStoreError.capacityExceeded(needed: data.count, capacity: capacity) }
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
