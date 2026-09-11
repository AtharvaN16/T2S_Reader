// Sources/T2SSync/FakeSyncProvider.swift
import Foundation
import T2SCore

/// A backend in memory: every accepted push gets a sequence number, `changes(since:)` returns the
/// latest version of every record numbered after the token, and a push older than what it holds is
/// a conflict — CloudKit's behaviour, without CloudKit. Used by the tests and, under `-t2s.sync
/// fake`, by a simulator run of the UI (sync spec §3, §8).
public actor FakeSyncProvider: SyncProvider {
    private var sequence = 0
    private var latest: [String: (sequence: Int, record: SyncRecord)] = [:]
    public var status: SyncAccountStatus = .available
    private var expireNextToken = false

    public init() {}

    public func setStatus(_ status: SyncAccountStatus) { self.status = status }
    public func setExpireNextToken(_ expire: Bool) { expireNextToken = expire }
    public func reset() { sequence = 0; latest = [:]; expireNextToken = false }

    public func accountStatus() -> SyncAccountStatus { status }

    public func changes(since token: SyncToken?) throws -> SyncChanges {
        let from = token.flatMap { Int(String(decoding: $0.data, as: UTF8.self)) } ?? 0
        if expireNextToken, token != nil { expireNextToken = false; throw SyncError.tokenExpired }
        let records = latest.values.filter { $0.sequence > from }.sorted { $0.sequence < $1.sequence }.map(\.record)
        return SyncChanges(records: records, token: SyncToken(data: Data(String(sequence).utf8)))
    }

    public func push(_ records: [SyncRecord]) throws -> [SyncPushResult] {
        records.map { record in
            let key = Self.key(of: record)
            if let held = latest[key], held.record.updatedAt > record.updatedAt {
                return SyncPushResult(record: record, outcome: .conflict(server: held.record))
            }
            sequence += 1
            latest[key] = (sequence, record)
            return SyncPushResult(record: record, outcome: .saved)
        }
    }

    static func key(of record: SyncRecord) -> String {
        switch record {
        case .document(let d): return "doc:" + d.contentKey
        case .bookmark(let b): return "bm:" + b.id.uuidString
        }
    }
}
