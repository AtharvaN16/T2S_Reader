// Sources/T2SSync/CloudKit/CloudKitSyncProvider.swift
import CloudKit
import Foundation
import T2SCore
import os

/// The one CloudKit caller (sync spec §3): a custom zone in the private database, zone changes
/// behind the token, saves that refuse to overwrite a newer server record so the engine can merge.
/// Records fetched or saved are kept by name so a later save carries the server's change tag.
public actor CloudKitSyncProvider: SyncProvider {
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: CloudKitRecordMapping.zoneName, ownerName: CKCurrentUserDefaultName)
    private var zoneReady = false
    private var known: [String: CKRecord] = [:]
    private let log = Logger(subsystem: "com.t2s.reader", category: "sync")

    public init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
    }

    public func accountStatus() async -> SyncAccountStatus {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .couldNotDetermine: return .unavailable("could not determine")
            case .temporarilyUnavailable: return .unavailable("temporarily unavailable")
            @unknown default: return .unavailable("unknown")
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    public func changes(since token: SyncToken?) async throws -> SyncChanges {
        try await ensureZone()
        var serverToken = try token.map { try Self.unarchive($0) }
        var records: [SyncRecord] = []
        var more = true
        do {
            while more {
                let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: serverToken)
                for (_, result) in page.modificationResultsByID {
                    if case .success(let modification) = result {
                        known[modification.record.recordID.recordName] = modification.record
                        if let mapped = CloudKitRecordMapping.syncRecord(from: modification.record) {
                            records.append(mapped)
                        } else {
                            log.warning("sync: could not read record \(modification.record.recordType, privacy: .public) \(modification.record.recordID.recordName, privacy: .public)")
                        }
                    }
                }
                serverToken = page.changeToken
                more = page.moreComing
            }
        } catch {
            throw mapping(error)
        }
        return SyncChanges(records: records, token: try serverToken.map(Self.archive))
    }

    /// CloudKit refuses a modify of more than 400 records, and a first sync of a library built up
    /// over months is easily more than that — so the push goes up in chunks, results concatenated.
    static let pushChunkSize = 200

    public func push(_ records: [SyncRecord]) async throws -> [SyncPushResult] {
        try await ensureZone()
        var results: [SyncPushResult] = []
        results.reserveCapacity(records.count)
        var start = records.startIndex
        while start < records.endIndex {
            let end = records.index(start, offsetBy: Self.pushChunkSize, limitedBy: records.endIndex) ?? records.endIndex
            results += try await pushChunk(Array(records[start..<end]))
            start = end
        }
        return results
    }

    private func pushChunk(_ records: [SyncRecord]) async throws -> [SyncPushResult] {
        let ckRecords = records.map { record -> (SyncRecord, CKRecord) in
            switch record {
            case .document(let d): return (record, CloudKitRecordMapping.record(for: d, zone: zoneID, updating: known[ContentKey.recordName(for: d.contentKey)]))
            case .bookmark(let b): return (record, CloudKitRecordMapping.record(for: b, zone: zoneID, updating: known["bm-" + b.id.uuidString]))
            }
        }
        let results: (saveResults: [CKRecord.ID: Result<CKRecord, Error>], deleteResults: [CKRecord.ID: Result<Void, Error>])
        do {
            results = try await database.modifyRecords(saving: ckRecords.map(\.1), deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
        } catch {
            throw mapping(error)
        }
        return try ckRecords.map { record, ck in
            switch results.saveResults[ck.recordID] {
            case .success(let saved)?:
                known[saved.recordID.recordName] = saved
                return SyncPushResult(record: record, outcome: .saved)
            case .failure(let error)?:
                if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                    if let server = ckError.serverRecord, let mapped = CloudKitRecordMapping.syncRecord(from: server) {
                        known[server.recordID.recordName] = server
                        return SyncPushResult(record: record, outcome: .conflict(server: mapped))
                    }
                    log.warning("sync: conflict on \(ck.recordID.recordName, privacy: .public) with an unreadable server record")
                    throw SyncError.other("conflict on \(ck.recordID.recordName) with an unreadable server record")
                }
                throw mapping(error)
            case nil:
                throw SyncError.other("no result for \(ck.recordID.recordName)")
            }
        }
    }

    private func ensureZone() async throws {
        guard !zoneReady else { return }
        // Two overlapping calls can both reach the save below before `zoneReady` flips; that's
        // fine — CloudKit's zone save is idempotent, so no locking is needed here.
        do {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
            zoneReady = true
        } catch {
            throw Self.mapped(error)
        }
    }

    /// `mapped`, plus the one piece of state a failure has to change: a zone that is gone stays gone
    /// until it is made again, so the readiness flag goes down with it and the next cycle's
    /// `ensureZone` recreates it. A token for the old zone then expires into a full pull.
    private func mapping(_ error: Error) -> SyncError {
        let mapped = Self.mapped(error)
        if case .zoneMissing = mapped { zoneReady = false }
        return mapped
    }

    static func mapped(_ error: Error) -> SyncError {
        guard let ck = error as? CKError else { return .other(error.localizedDescription) }
        switch ck.code {
        case .changeTokenExpired: return .tokenExpired
        case .quotaExceeded: return .quotaExceeded
        case .zoneNotFound, .userDeletedZone: return .zoneMissing
        case .notAuthenticated: return .account(.noAccount)
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy: return .network(ck.localizedDescription)
        default: return .other("\(ck.code.rawValue): \(ck.localizedDescription)")
        }
    }

    static func archive(_ token: CKServerChangeToken) throws -> SyncToken {
        SyncToken(data: try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true))
    }
    static func unarchive(_ token: SyncToken) throws -> CKServerChangeToken {
        guard let value = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: token.data) else { throw SyncError.tokenExpired }
        return value
    }
}
