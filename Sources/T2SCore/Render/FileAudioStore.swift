import Foundation

/// One file per key under `directory`. Recency is the file's modification date, so the index
/// survives relaunches without a sidecar database.
public actor FileAudioStore: AudioStore {
    private let directory: URL
    private let codec: any AudioCodec
    private var capacity: Int
    private var lru = LRUIndex()

    public init(directory: URL, codec: any AudioCodec, capacityBytes: Int) {
        self.directory = directory
        self.codec = codec
        self.capacity = capacityBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys = [.fileSizeKey, .contentModificationDateKey] as [URLResourceKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        let entries = files.compactMap { url -> (RenderKey, Int, Date)? in
            guard url.pathExtension == "audio", let v = try? url.resourceValues(forKeys: Set(keys)),
                  let size = v.fileSize, let date = v.contentModificationDate else { return nil }
            return (RenderKey(rawValue: url.deletingPathExtension().lastPathComponent), size, date)
        }
        for (key, size, _) in entries.sorted(by: { $0.2 < $1.2 }) { lru.insert(key, size: size) }
    }

    private func url(_ key: RenderKey) -> URL { directory.appendingPathComponent(key.fileName) }

    public func contains(_ key: RenderKey) -> Bool { lru.sizes[key] != nil }

    public func write(_ pcm: PCMAudio, for key: RenderKey) throws {
        let data = try codec.encode(pcm)
        // Guard before touching any state: a rejected overwrite must leave the old entry intact.
        guard data.count <= capacity else { throw AudioStoreError.capacityExceeded(needed: data.count, capacity: capacity) }
        if lru.sizes[key] != nil { lru.remove(key) }              // the atomic write below replaces the file
        for victim in lru.victims(toFit: data.count, capacity: capacity) { evict(victim) }
        try data.write(to: url(key), options: .atomic)
        lru.insert(key, size: data.count)
    }

    public func read(_ key: RenderKey) throws -> PCMAudio? {
        guard lru.sizes[key] != nil else { return nil }
        let data = try Data(contentsOf: url(key))
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url(key).path)
        lru.touch(key)
        return try codec.decode(data)
    }

    public func remove(_ key: RenderKey) { evict(key) }

    public func stats() -> AudioStoreStats {
        AudioStoreStats(bytes: lru.bytes, entries: lru.sizes.count, capacityBytes: capacity)
    }

    public func setCapacity(bytes: Int) {
        capacity = bytes
        for victim in lru.victims(toFit: 0, capacity: capacity) { evict(victim) }
    }

    private func evict(_ key: RenderKey) {
        try? FileManager.default.removeItem(at: url(key))
        lru.remove(key)
    }
}
