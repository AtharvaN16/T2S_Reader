// Sources/T2SSync/SyncEngine.swift
import Foundation
import os
import T2SCore

public struct SyncOutcome: Sendable, Hashable {
    public var pulled: Int
    public var pushed: Int
    public var error: SyncError?
    public init(pulled: Int = 0, pushed: Int = 0, error: SyncError? = nil) { self.pulled = pulled; self.pushed = pushed; self.error = error }
}

/// The cycle and the merge (sync spec §4, §7): pull since the token and apply, then push what is
/// dirty. One rule for records — the newer `updatedAt` wins, a deletion marker beats anything older
/// — and one exception: a newer remote position is stored as an offer, never applied. An actor, so
/// two triggers run one after the other; a cycle that finds nothing changed costs one fetch.
public actor SyncEngine {
    private let provider: any SyncProvider
    private let store: any SyncStore
    private let tokens: any SyncTokenStore
    private let deviceName: String
    private let log = Logger(subsystem: "com.t2s.reader", category: "sync")

    public init(provider: any SyncProvider, store: any SyncStore, tokens: any SyncTokenStore, deviceName: String) {
        self.provider = provider; self.store = store; self.tokens = tokens; self.deviceName = deviceName
    }

    public func sync() async -> SyncOutcome {
        do {
            let changes = try await pull()
            let pushed = try await push(try await store.dirtyRecords())
            log.notice("sync: pulled \(changes.records.count, privacy: .public), pushed \(pushed, privacy: .public)")
            return SyncOutcome(pulled: changes.records.count, pushed: pushed)
        } catch let error as SyncError {
            log.error("sync failed: \(String(describing: error), privacy: .public)")
            return SyncOutcome(error: error)
        } catch {
            log.error("sync failed: \(error.localizedDescription, privacy: .public)")
            return SyncOutcome(error: .other(error.localizedDescription))
        }
    }

    private func pull() async throws -> SyncChanges {
        let token = await tokens.load()
        let changes: SyncChanges
        do {
            changes = try await provider.changes(since: token)
        } catch SyncError.tokenExpired {
            changes = try await provider.changes(since: nil)
        }
        try await apply(changes.records)
        await tokens.save(changes.token)
        return changes
    }

    /// Documents before bookmarks, so a bookmark never arrives before the placeholder it belongs to.
    private func apply(_ records: [SyncRecord]) async throws {
        for case .document(let d) in records { try await apply(d) }
        for case .bookmark(let b) in records { try await apply(b) }
    }

    private func apply(_ remote: SyncedDocument) async throws {
        let local = try await store.syncedDocument(contentKey: remote.contentKey)
        if remote.deletedAt != nil {
            // A deletion beats anything older than it (sync spec §4); a local edit newer than the
            // marker outlives it, and stays dirty so its own push overwrites the marker.
            if let local, remote.updatedAt < local.updatedAt { return }
            try await store.removeDocument(contentKey: remote.contentKey)
            return
        }
        guard let local else {
            try await store.write(remote, offering: nil)
            return
        }
        var merged = remote.updatedAt > local.updatedAt ? remote : local
        merged.resume = local.resume
        var offer: SyncedPosition?
        if let theirs = remote.resume {
            if let mine = local.resume {
                if theirs.savedAt > mine.savedAt, theirs.position != mine.position { offer = theirs }
            } else {
                merged.resume = theirs
            }
        }
        try await store.write(merged, offering: offer)
    }

    private func apply(_ remote: SyncedBookmark) async throws {
        if let local = try await store.syncedBookmark(id: remote.id), local.updatedAt >= remote.updatedAt { return }
        try await store.write(remote)
    }

    /// Pushes, and on a conflict merges the server's copy in (sync spec §4) and re-reads the store:
    /// a row that comes back strictly newer than the server's `updatedAt` still carries something
    /// the server lacks, and gets pushed once more. Every other conflicted row has lost for good —
    /// most often a deletion marker that can never outlive the edit it targets — and is marked
    /// clean right away instead of retrying forever. What the second push saves also joins
    /// `accepted`; a second conflict leaves the row dirty for the next cycle.
    private func push(_ records: [SyncRecord]) async throws -> Int {
        guard !records.isEmpty else { return 0 }
        var accepted: [SyncRecord] = []
        var conflictedKeys: Set<String> = []
        var serverUpdatedAt: [String: Date] = [:]
        for result in try await provider.push(records) {
            switch result.outcome {
            case .saved: accepted.append(result.record)
            case .conflict(let server):
                try await apply([server])
                let key = Self.key(of: result.record)
                conflictedKeys.insert(key)
                serverUpdatedAt[key] = server.updatedAt
            }
        }
        if !conflictedKeys.isEmpty {
            let reread = try await store.dirtyRecords().filter { conflictedKeys.contains(Self.key(of: $0)) }
            var retry: [SyncRecord] = []
            for record in reread {
                if let serverTime = serverUpdatedAt[Self.key(of: record)], record.updatedAt > serverTime {
                    retry.append(record)
                } else {
                    accepted.append(record)
                }
            }
            if !retry.isEmpty {
                for result in try await provider.push(retry) where result.outcome == .saved { accepted.append(result.record) }
            }
        }
        try await store.markClean(accepted)
        return accepted.count
    }

    /// The content key or bookmark id a record identifies itself by, for matching a conflict back to
    /// what the store still has dirty after the server's copy is merged in.
    private static func key(of record: SyncRecord) -> String {
        switch record {
        case .document(let d): return "doc:" + d.contentKey
        case .bookmark(let b): return "bm:" + b.id.uuidString
        }
    }
}
