import Foundation
import SwiftData

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
    /// nil = not in the Queue; otherwise the row's rank, ascending and unique among queued rows.
    var queueOrder: Int?
    var isFinished: Bool
    var schemaVersion: Int
    var segmenterVersion: Int
    var normalizerVersion: Int
    @Relationship(deleteRule: .cascade, inverse: \StoredChapter.document)
    var chapters: [StoredChapter]

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
        self.queueOrder = nil
        self.isFinished = false
        self.schemaVersion = schemaVersion
        self.segmenterVersion = segmenterVersion
        self.normalizerVersion = normalizerVersion
        self.chapters = []
    }
}

@Model
final class StoredChapter {
    var index: Int
    var title: String
    /// JSON-encoded `Position` of the chapter start.
    var position: Data
    /// `TimelineCodec` blob of the chapter's utterances (spec §5).
    var blob: Data
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
