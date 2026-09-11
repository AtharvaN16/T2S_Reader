// Sources/T2SSync/CloudKit/CloudKitRecordMapping.swift
import CloudKit
import Foundation
import T2SCore

/// `CKRecord` ↔ the sync records, and nothing else: CloudKit's schema is this file's business alone
/// (design spec §3.7.1). Positions travel as JSON strings so the record has no shape of its own.
enum CloudKitRecordMapping {
    static let zoneName = "t2s"
    static let documentType = "Document"
    static let bookmarkType = "Bookmark"

    static func record(for d: SyncedDocument, zone: CKRecordZone.ID, updating existing: CKRecord?) -> CKRecord {
        let record = existing ?? CKRecord(recordType: documentType, recordID: CKRecord.ID(recordName: ContentKey.recordName(for: d.contentKey), zoneID: zone))
        record["contentKey"] = d.contentKey as NSString
        record["title"] = d.title as NSString
        record["author"] = d.author.map { $0 as NSString }
        record["sourceType"] = d.sourceType.rawValue as NSString
        record["sourceURL"] = (d.sourceURL?.absoluteString).map { $0 as NSString }
        record["addedAt"] = d.addedAt as NSDate
        record["isFinished"] = (d.isFinished ? 1 : 0) as NSNumber
        record["resume"] = d.resume.flatMap { json($0) }.map { $0 as NSString }
        record["updatedAt"] = d.updatedAt as NSDate
        record["deletedAt"] = d.deletedAt.map { $0 as NSDate }
        return record
    }

    static func record(for b: SyncedBookmark, zone: CKRecordZone.ID, updating existing: CKRecord?) -> CKRecord {
        let record = existing ?? CKRecord(recordType: bookmarkType, recordID: CKRecord.ID(recordName: "bm-" + b.id.uuidString, zoneID: zone))
        record["bookmarkID"] = b.id.uuidString as NSString
        record["contentKey"] = b.contentKey as NSString
        record["position"] = json(b.position).map { $0 as NSString }
        record["note"] = b.note.map { $0 as NSString }
        record["createdAt"] = b.createdAt as NSDate
        record["updatedAt"] = b.updatedAt as NSDate
        record["deletedAt"] = b.deletedAt.map { $0 as NSDate }
        return record
    }

    static func syncRecord(from r: CKRecord) -> SyncRecord? {
        switch r.recordType {
        case documentType:
            guard let key = r["contentKey"] as? String, let title = r["title"] as? String, let type = (r["sourceType"] as? String).flatMap(SourceType.init(rawValue:)),
                  let addedAt = r["addedAt"] as? Date, let updatedAt = r["updatedAt"] as? Date else { return nil }
            return .document(SyncedDocument(contentKey: key, title: title, author: r["author"] as? String, sourceType: type,
                                            sourceURL: (r["sourceURL"] as? String).flatMap(URL.init(string:)), addedAt: addedAt,
                                            isFinished: (r["isFinished"] as? Int ?? 0) != 0,
                                            resume: (r["resume"] as? String).flatMap { decode(SyncedPosition.self, $0) },
                                            updatedAt: updatedAt, deletedAt: r["deletedAt"] as? Date))
        case bookmarkType:
            guard let id = (r["bookmarkID"] as? String).flatMap(UUID.init(uuidString:)), let key = r["contentKey"] as? String,
                  let position = (r["position"] as? String).flatMap({ decode(Position.self, $0) }),
                  let createdAt = r["createdAt"] as? Date, let updatedAt = r["updatedAt"] as? Date else { return nil }
            return .bookmark(SyncedBookmark(id: id, contentKey: key, position: position, note: r["note"] as? String,
                                            createdAt: createdAt, updatedAt: updatedAt, deletedAt: r["deletedAt"] as? Date))
        default: return nil
        }
    }

    private static func json<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) }
    }
    private static func decode<T: Decodable>(_ type: T.Type, _ string: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(string.utf8))
    }
}
