import Foundation

/// One file per key under `directory/<codec identifier>` — a codec change lands in a new
/// directory (spec §3.7.4), so switching codecs can never serve stale-format bytes back out.
/// Recency is the file's modification date, so the index survives relaunches without a sidecar
/// database.
public actor FileAudioStore: AudioStore {
    private let directory: URL
    private let codec: any AudioCodec
    private var capacity: Int
    private var lru = LRUIndex()
    private var indexed = false

    public init(directory: URL, codec: any AudioCodec, capacityBytes: Int) {
        self.directory = directory.appendingPathComponent(codec.identifier, isDirectory: true)
        self.codec = codec
        self.capacity = capacityBytes
    }

    /// Scans `directory` and builds the LRU index on first use, rather than in `init`, so
    /// constructing a store is cheap and never touches the filesystem until it's actually needed.
    private func ensureIndexed() {
        guard !indexed else { return }
        indexed = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys = [.fileSizeKey, .contentModificationDateKey] as [URLResourceKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        let entries = files.compactMap { url -> (RenderKey, Int, Date)? in
            guard url.pathExtension == "audio", Self.isValidKeyStem(url.deletingPathExtension().lastPathComponent),
                  let v = try? url.resourceValues(forKeys: Set(keys)),
                  let size = v.fileSize, let date = v.contentModificationDate else { return nil }
            return (RenderKey(rawValue: url.deletingPathExtension().lastPathComponent), size, date)
        }
        for (key, size, _) in entries.sorted(by: { $0.2 < $1.2 }) { lru.insert(key, size: size) }
    }

    /// A valid key stem is exactly 64 lowercase hex characters — `RenderKey`'s SHA-256 hex
    /// digest. Anything else found in the directory is foreign and ignored during the scan.
    private static func isValidKeyStem(_ stem: String) -> Bool {
        stem.count == 64 && stem.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private func url(_ key: RenderKey) -> URL { directory.appendingPathComponent(key.fileName) }

    public func contains(_ key: RenderKey) -> Bool {
        ensureIndexed()
        return lru.sizes[key] != nil
    }

    public func write(_ pcm: PCMAudio, for key: RenderKey) throws {
        ensureIndexed()
        let data = try codec.encode(pcm)
        // Guard before touching any state: a rejected overwrite must leave the old entry intact.
        guard data.count <= capacity else { throw AudioStoreError.capacityExceeded(needed: data.count, capacity: capacity) }
        let previousSize = lru.sizes[key]
        if previousSize != nil { lru.remove(key) }              // the atomic write below replaces the file
        for victim in lru.victims(toFit: data.count, capacity: capacity) { evict(victim) }
        do {
            try data.write(to: url(key), options: .atomic)
        } catch {
            // The write failed: restore the previous entry (if any) so the index and the disk
            // stay in agreement, then map a disk-full condition to `.diskFull`; anything else
            // propagates unchanged.
            if let previousSize { lru.insert(key, size: previousSize) }
            if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace { throw AudioStoreError.diskFull }
            if let posix = error as? POSIXError, posix.code == .ENOSPC { throw AudioStoreError.diskFull }
            throw error
        }
        lru.insert(key, size: data.count)
    }

    public func read(_ key: RenderKey) throws -> PCMAudio? {
        ensureIndexed()
        guard lru.sizes[key] != nil else { return nil }
        let data = try Data(contentsOf: url(key))
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url(key).path)
        lru.touch(key)
        return try codec.decode(data)
    }

    public func remove(_ key: RenderKey) {
        ensureIndexed()
        evict(key)
    }

    public func stats() -> AudioStoreStats {
        ensureIndexed()
        return AudioStoreStats(bytes: lru.bytes, entries: lru.sizes.count, capacityBytes: capacity)
    }

    public func setCapacity(bytes: Int) {
        ensureIndexed()
        capacity = bytes
        for victim in lru.victims(toFit: 0, capacity: capacity) { evict(victim) }
    }

    private func evict(_ key: RenderKey) {
        try? FileManager.default.removeItem(at: url(key))
        lru.remove(key)
    }
}
