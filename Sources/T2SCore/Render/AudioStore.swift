import Foundation

public struct AudioStoreStats: Hashable, Sendable {
    public var bytes: Int
    public var entries: Int
    public var capacityBytes: Int
    public init(bytes: Int, entries: Int, capacityBytes: Int) {
        self.bytes = bytes
        self.entries = entries
        self.capacityBytes = capacityBytes
    }
}

public enum AudioStoreError: Error, Equatable, Sendable {
    case capacityExceeded(needed: Int, capacity: Int)
}

/// Rendered audio is cache, never truth (spec §3.7.3). LRU against a user-configurable cap (spec §3.4).
public protocol AudioStore: Sendable {
    func contains(_ key: RenderKey) async -> Bool
    /// Evicts least-recently-used entries until the entry fits; throws when it never can.
    func write(_ pcm: PCMAudio, for key: RenderKey) async throws
    /// Refreshes the entry's recency.
    func read(_ key: RenderKey) async throws -> PCMAudio?
    func remove(_ key: RenderKey) async throws
    func stats() async -> AudioStoreStats
    /// Evicts immediately if the new cap is below current usage.
    func setCapacity(bytes: Int) async
}

/// Shared LRU bookkeeping for the two stores: keys ordered oldest → newest with their sizes.
struct LRUIndex: Sendable {
    private(set) var order: [RenderKey] = []
    private(set) var sizes: [RenderKey: Int] = [:]
    var bytes: Int { sizes.values.reduce(0, +) }

    mutating func touch(_ key: RenderKey) {
        if let i = order.firstIndex(of: key) { order.remove(at: i); order.append(key) }
    }

    mutating func insert(_ key: RenderKey, size: Int) {
        if sizes[key] != nil { order.removeAll { $0 == key } }
        sizes[key] = size
        order.append(key)
    }

    mutating func remove(_ key: RenderKey) {
        sizes[key] = nil
        order.removeAll { $0 == key }
    }

    /// Keys to evict (oldest first) so that `bytes + incoming <= capacity`.
    func victims(toFit incoming: Int, capacity: Int) -> [RenderKey] {
        var free = capacity - bytes
        var out: [RenderKey] = []
        for k in order where free < incoming {
            free += sizes[k] ?? 0
            out.append(k)
        }
        return out
    }
}
