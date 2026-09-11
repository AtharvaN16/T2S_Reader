import Foundation
import SwiftData
import T2SCore

/// The iCloud-sync schema, frozen; see `LibrarySchemaV4` in Models.swift. Never edit these
/// classes — a change is a new version and a migration stage (spec §3.7.4).
enum LibrarySchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static let models: [any PersistentModel.Type] = [StoredDocument.self, StoredChapter.self, StoredBookmark.self, StoredPronunciation.self, StoredTombstone.self]

    /// SwiftData rows. Internal on purpose (spec §3.7.1): the store hands out `T2SCore` value types,
    /// so the persistence schema never shapes the domain model.
    @Model
    final class StoredDocument {
        @Attribute(.unique) var id: UUID
        var title: String
        var author: String?
        /// `SourceType.rawValue`.
        var sourceType: String
        var sourceURL: String?
        var coverImagePath: String?
        var addedAt: Date
        var updatedAt: Date
        var lastPlayedAt: Date?
        var voiceID: String?
        /// The resume `Position`, flattened: no serialization means no decode path that can fail.
        /// `resumeHref == nil` means never saved.
        var resumeHref: String?
        var resumeProgression: Double?
        var resumeCharOffset: Int?
        var resumeCSSSelector: String?
        /// Where the resume position sits in time (`SavedPlayhead`, schema V2): the chapter, and the
        /// seconds into it. nil for a position saved without them, so a list screen falls back to the
        /// decode. The earlier chapters' durations are added when the summary is read.
        var resumeChapterIndex: Int?
        var resumeSecondsIntoChapter: Double?
        /// nil = not in the Queue; otherwise the row's rank, ascending and unique among queued rows.
        var queueOrder: Int?
        var isFinished: Bool
        var schemaVersion: Int
        var segmenterVersion: Int
        var normalizerVersion: Int
        @Relationship(deleteRule: .cascade, inverse: \StoredChapter.document)
        var chapters: [StoredChapter]
        /// `ContentKey` (sync spec §2); nil until computed (a row from before sync, or a document with
        /// no file and no URL, which never syncs).
        var contentKey: String?
        /// A document another device has that this one has no file for (sync spec §5).
        var isPlaceholder: Bool = false
        /// Changed since last pushed (sync spec §6).
        var isDirty: Bool = false
        /// When the local resume position was saved; `updatedAt` moves for other reasons too.
        var resumeSavedAt: Date?
        /// The device that saved the local position (this one, or the one a placeholder came from).
        var resumeDevice: String?
        /// The newer remote position, offered and not applied (sync spec §4), flattened like the resume.
        var pendingRemoteHref: String?
        var pendingRemoteProgression: Double?
        var pendingRemoteCharOffset: Int?
        var pendingRemoteCSSSelector: String?
        var pendingRemoteSavedAt: Date?
        var pendingRemoteDevice: String?

        init(id: UUID, title: String, author: String?, sourceType: String, sourceURL: String?,
             coverImagePath: String?, addedAt: Date, voiceID: String?,
             schemaVersion: Int, segmenterVersion: Int, normalizerVersion: Int) {
            self.id = id
            self.title = title
            self.author = author
            self.sourceType = sourceType
            self.sourceURL = sourceURL
            self.coverImagePath = coverImagePath
            self.addedAt = addedAt
            self.updatedAt = addedAt
            self.lastPlayedAt = nil
            self.voiceID = voiceID
            self.resumeHref = nil
            self.resumeProgression = nil
            self.resumeCharOffset = nil
            self.resumeCSSSelector = nil
            self.resumeChapterIndex = nil
            self.resumeSecondsIntoChapter = nil
            self.queueOrder = nil
            self.isFinished = false
            self.schemaVersion = schemaVersion
            self.segmenterVersion = segmenterVersion
            self.normalizerVersion = normalizerVersion
            self.chapters = []
            self.contentKey = nil
            self.isPlaceholder = false
            self.isDirty = false
            self.resumeSavedAt = nil
            self.resumeDevice = nil
            self.pendingRemoteHref = nil
            self.pendingRemoteProgression = nil
            self.pendingRemoteCharOffset = nil
            self.pendingRemoteCSSSelector = nil
            self.pendingRemoteSavedAt = nil
            self.pendingRemoteDevice = nil
        }
    }

    @Model
    final class StoredChapter {
        var index: Int
        var title: String
        /// JSON-encoded `Position` of the chapter start.
        var position: Data
        /// `TimelineCodec` blob of the chapter's utterances (spec §5). Large; stored outside the row so
        /// `summaries()` never faults it in.
        @Attribute(.externalStorage) var blob: Data
        var utteranceCount: Int
        /// Sum of the chapter's current durations at 1x, kept in step with `blob` so list screens
        /// never decode a blob to show a remaining time.
        var durationSeconds: Double
        /// Utterances whose `audioRef` is set.
        var renderedCount: Int
        var document: StoredDocument?

        init(index: Int, title: String, position: Data, blob: Data, utteranceCount: Int,
             durationSeconds: Double, renderedCount: Int) {
            self.index = index
            self.title = title
            self.position = position
            self.blob = blob
            self.utteranceCount = utteranceCount
            self.durationSeconds = durationSeconds
            self.renderedCount = renderedCount
            self.document = nil
        }
    }

    @Model
    final class StoredBookmark {
        @Attribute(.unique) var id: UUID
        var documentID: UUID
        /// The `Position`, flattened like the document's resume position: no serialization, so no
        /// decode path that can silently drop a bookmark.
        var href: String
        var progression: Double
        var charOffset: Int?
        var cssSelector: String?
        var note: String?
        var createdAt: Date
        /// nil on a V2 row: read as `createdAt`.
        var updatedAt: Date?
        var isDirty: Bool = false

        init(id: UUID, documentID: UUID, position: Position, note: String?, createdAt: Date) {
            self.id = id
            self.documentID = documentID
            self.href = position.resourceHref
            self.progression = position.progression
            self.charOffset = position.charOffset
            self.cssSelector = position.cssSelector
            self.note = note
            self.createdAt = createdAt
            self.updatedAt = nil
            self.isDirty = false
        }

        var position: Position {
            Position(resourceHref: href, progression: progression, charOffset: charOffset, cssSelector: cssSelector)
        }
    }

    @Model
    final class StoredPronunciation {
        @Attribute(.unique) var id: UUID
        var term: String
        var replacement: String
        var caseSensitive: Bool
        var updatedAt: Date

        init(id: UUID, term: String, replacement: String, caseSensitive: Bool, updatedAt: Date) {
            self.id = id
            self.term = term
            self.replacement = replacement
            self.caseSensitive = caseSensitive
            self.updatedAt = updatedAt
        }
    }

    /// A local deletion not yet pushed: the marker survives until the provider accepts it.
    @Model
    final class StoredTombstone {
        @Attribute(.unique) var id: UUID
        /// "document" or "bookmark".
        var kind: String
        /// The content key, or the bookmark's uuid string.
        var key: String
        var deletedAt: Date
        init(id: UUID = UUID(), kind: String, key: String, deletedAt: Date) {
            self.id = id; self.kind = kind; self.key = key; self.deletedAt = deletedAt
        }
    }
}
