// Sources/T2SCore/Sync/SyncProvider.swift
import Foundation

/// An opaque cursor into the provider's change stream (CloudKit's `CKServerChangeToken`, or a
/// counter in the fake). Persisted by `SyncTokenStore`.
public struct SyncToken: Sendable, Hashable, Codable {
    public var data: Data
    public init(data: Data) { self.data = data }
}

public enum SyncAccountStatus: Sendable, Hashable {
    case available, noAccount, restricted
    case unavailable(String)
}

public struct SyncChanges: Sendable {
    public var records: [SyncRecord]
    public var token: SyncToken?
    public init(records: [SyncRecord], token: SyncToken?) { self.records = records; self.token = token }
}

public enum SyncPushOutcome: Sendable, Hashable {
    case saved
    /// The server had a newer record; it is handed back so the engine can merge and push again.
    case conflict(server: SyncRecord)
}

public struct SyncPushResult: Sendable, Hashable {
    public var record: SyncRecord
    public var outcome: SyncPushOutcome
    public init(record: SyncRecord, outcome: SyncPushOutcome) { self.record = record; self.outcome = outcome }
}

public enum SyncError: Error, Sendable, Hashable {
    /// The provider forgot the token; the caller drops it and pulls everything.
    case tokenExpired
    case quotaExceeded
    case zoneMissing
    case network(String)
    case account(SyncAccountStatus)
    case other(String)
}

/// The one door to a backend (design spec §3.7.1): CloudKit today, a fake in tests, a server later.
public protocol SyncProvider: Sendable {
    func accountStatus() async -> SyncAccountStatus
    /// Every record changed since `token` (all of them for nil), oldest first, and the new token.
    func changes(since token: SyncToken?) async throws -> SyncChanges
    /// Saves each record unless the server has a newer one, in which case that one comes back.
    func push(_ records: [SyncRecord]) async throws -> [SyncPushResult]
}

public protocol SyncTokenStore: Sendable {
    func load() async -> SyncToken?
    func save(_ token: SyncToken?) async
}
