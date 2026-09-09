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

    /// Removes every sibling directory under `parent` that is not `current`'s — an earlier codec's
    /// cached audio (spec §3.7.4: a codec change lands in a new directory), so a bitrate change
    /// (`AACCodec` moved from 32 kbps to 64 kbps on 2026-09-05,
    /// `spikes/findings/2026-09-05-coreml-audio-quality.md`) does not leave the old format's bytes
    /// on disk forever. Best-effort and silent: this is disk hygiene, not correctness — an
    /// `audioRef` that pointed into a namespace this sweep removed simply misses `contains` and
    /// gets re-rendered rather than served stale bytes (`PlaybackCoordinator.reconcileWithStore`).
    private static func removeStaleCodecDirectories(parent: URL, keeping current: String) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries where entry.lastPathComponent != current {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }

    /// Scans `directory` and builds the LRU index on first use, rather than in `init`, so
    /// constructing a store costs nothing and never touches the disk until it's actually needed.
    /// The old-codec sweep starts here too, on a task of its own: in `init` it ran on whichever thread
    /// built the store — the main thread, at launch, before the first frame — and inline here it would
    /// sit on the first cache probe, between the tap and the head render, deleting up to a whole old
    /// cache (Plan 17, audit §4.3). It touches only sibling directories, never this codec's, so
    /// nothing here waits for it.
    private func ensureIndexed() {
        guard !indexed else { return }
        indexed = true
        let parent = directory.deletingLastPathComponent(), current = codec.identifier
        Task.detached(priority: .utility) { Self.removeStaleCodecDirectories(parent: parent, keeping: current) }
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

    public func contains(_ keys: [RenderKey]) -> [Bool] {
        ensureIndexed()
        return keys.map { lru.sizes[$0] != nil }
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
