// Tests/T2SSyncTests/CloudKitRecordMappingTests.swift
import CloudKit
import Foundation
import Testing
import T2SCore
@testable import T2SSync

@Suite struct CloudKitRecordMappingTests {
    let zone = CKRecordZone.ID(zoneName: CloudKitRecordMapping.zoneName, ownerName: CKCurrentUserDefaultName)

    /// Design spec §3.7.1: the record is a mapping of the domain type, and the mapping is lossless.
    @Test func aDocumentSurvivesTheRoundTrip() {
        let document = SyncedDocument(contentKey: "url:https://x.y/a", title: "T", author: "A", sourceType: .article,
                                      sourceURL: URL(string: "https://x.y/a"), addedAt: Date(timeIntervalSince1970: 1), isFinished: true,
                                      resume: SyncedPosition(position: Position(resourceHref: "c.xhtml", progression: 0.5, charOffset: 12, cssSelector: "p:nth-child(3)"),
                                                             savedAt: Date(timeIntervalSince1970: 2), deviceName: "iPhone"),
                                      updatedAt: Date(timeIntervalSince1970: 3), deletedAt: Date(timeIntervalSince1970: 4))
        let record = CloudKitRecordMapping.record(for: document, zone: zone, updating: nil)
        #expect(record.recordType == "Document")
        #expect(record.recordID.recordName == ContentKey.recordName(for: document.contentKey))
        #expect(CloudKitRecordMapping.syncRecord(from: record) == .document(document))
    }

    @Test func aBookmarkSurvivesTheRoundTrip() {
        let bookmark = SyncedBookmark(id: UUID(), contentKey: "sha256:abc", position: Position(resourceHref: "c.xhtml", progression: 0.25),
                                      note: "here", createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
        let record = CloudKitRecordMapping.record(for: bookmark, zone: zone, updating: nil)
        #expect(record.recordID.recordName == "bm-" + bookmark.id.uuidString)
        #expect(CloudKitRecordMapping.syncRecord(from: record) == .bookmark(bookmark))
        let updated = CloudKitRecordMapping.record(for: bookmark, zone: zone, updating: record)
        #expect(updated === record)                                             // the server's copy is edited, its change tag kept
    }

    @Test func userNoteSurvivesTheRecordRoundTrip() throws {
        let zone = CKRecordZone.ID(zoneName: "t2s", ownerName: CKCurrentUserDefaultName)
        let bookmark = SyncedBookmark(id: UUID(), contentKey: "key", position: Position(resourceHref: "ch1.xhtml", progression: 0.5),
                                      note: "the passage", userNote: "my own words",
                                      createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
        let record = CloudKitRecordMapping.record(for: bookmark, zone: zone, updating: nil)
        guard case .bookmark(let back)? = CloudKitRecordMapping.syncRecord(from: record) else {
            Issue.record("not a bookmark record"); return
        }
        #expect(back == bookmark)
    }

    /// The old-device case, and the reason the spec adds a key instead of changing one: a record
    /// written by a build that has never heard of `userNote` must decode with it nil, and must keep
    /// its passage.
    @Test func aRecordWithoutTheUserNoteKeyDecodesWithNoNote() throws {
        let zone = CKRecordZone.ID(zoneName: "t2s", ownerName: CKCurrentUserDefaultName)
        let id = UUID()
        let record = CKRecord(recordType: "Bookmark", recordID: CKRecord.ID(recordName: "bm-" + id.uuidString, zoneID: zone))
        record["bookmarkID"] = id.uuidString as NSString
        record["contentKey"] = "key" as NSString
        record["position"] = #"{"resourceHref":"ch1.xhtml","progression":0.5}"# as NSString
        record["note"] = "the passage" as NSString
        record["createdAt"] = Date(timeIntervalSince1970: 1) as NSDate
        record["updatedAt"] = Date(timeIntervalSince1970: 2) as NSDate
        guard case .bookmark(let back)? = CloudKitRecordMapping.syncRecord(from: record) else {
            Issue.record("not a bookmark record"); return
        }
        #expect(back.userNote == nil)
        #expect(back.note == "the passage")
    }
}
