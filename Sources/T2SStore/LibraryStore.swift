import Foundation
import SwiftData
import T2SCore

public struct StoredTimeline: Hashable, Sendable {
    public var timeline: Timeline
    /// True when any persisted stage version differs from the running `Versions`. The caller
    /// re-derives from the retained source (spec §3.7.3) instead of migrating.
    public var isStale: Bool

    public init(timeline: Timeline, isStale: Bool) {
        self.timeline = timeline
        self.isStale = isStale
    }
}

/// What list screens need per document, served without decoding a chapter blob (spec §5).
public struct DocumentSummary: Hashable, Sendable, Identifiable {
    public var document: Document
    public var chapterCount: Int
    public var utteranceCount: Int
    /// Sum of current durations at 1x; estimated until rendered (spec §3.3).
    public var totalSeconds: TimeInterval
    public var renderedCount: Int
    public var isFinished: Bool
    public var queueOrder: Int?
    public var lastPlayedAt: Date?

    public var id: UUID { document.id }
    /// The Queue row's `positive` check (spec §3.4.1): plays with no synthesis and no network.
    public var isFullyRendered: Bool { utteranceCount > 0 && renderedCount == utteranceCount }

    public init(document: Document, chapterCount: Int, utteranceCount: Int, totalSeconds: TimeInterval,
                renderedCount: Int, isFinished: Bool, queueOrder: Int?, lastPlayedAt: Date?) {
        self.document = document
        self.chapterCount = chapterCount
        self.utteranceCount = utteranceCount
        self.totalSeconds = totalSeconds
        self.renderedCount = renderedCount
        self.isFinished = isFinished
        self.queueOrder = queueOrder
        self.lastPlayedAt = lastPlayedAt
    }
}

public enum LibraryStoreError: Error, Equatable, Sendable {
    case documentNotFound(UUID)
    case duplicateDocument(UUID)
    case chapterOutOfRange(Int)
}

/// Local is the source of truth (spec §5). One actor owns the model context; callers only ever
/// see value types.
@ModelActor
public actor LibraryStore {
    static let schema = Schema([StoredDocument.self, StoredChapter.self])

    /// A throwaway store for tests and previews.
    public static func inMemory() throws -> LibraryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return LibraryStore(modelContainer: try ModelContainer(for: schema, configurations: config))
    }

    /// The app's store at `url` (`LibraryPaths.databaseURL`). Creates the parent directory.
    public static func onDisk(at url: URL) throws -> LibraryStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = ModelConfiguration(url: url)
        return LibraryStore(modelContainer: try ModelContainer(for: schema, configurations: config))
    }

    // MARK: Documents

    public func insert(_ document: Document, timeline: Timeline) throws {
        guard try row(document.id) == nil else { throw LibraryStoreError.duplicateDocument(document.id) }
        let row = StoredDocument(id: document.id, title: document.title, author: document.author,
                                 sourceType: document.sourceType.rawValue,
                                 sourceURL: document.sourceURL?.absoluteString,
                                 coverImagePath: document.coverImagePath, addedAt: document.addedAt,
                                 voiceID: document.voiceID,
                                 schemaVersion: timeline.schemaVersion,
                                 segmenterVersion: timeline.segmenterVersion,
                                 normalizerVersion: timeline.normalizerVersion)
        row.resumePosition = try document.resumePosition.map { try JSONEncoder().encode($0) }
        modelContext.insert(row)
        try replaceChapters(of: row, with: timeline)
        try modelContext.save()
    }

    public func document(id: UUID) throws -> Document? { try row(id).map(Self.domain) }

    /// Every document, newest first.
    public func documents() throws -> [Document] {
        try modelContext.fetch(FetchDescriptor<StoredDocument>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))
            .map(Self.domain)
    }

    /// Queued documents in user order (spec §2.3).
    public func queue() throws -> [Document] { try queueRows().map(Self.domain) }

    /// Every EPUB and PDF, newest first, whether or not it is queued (spec §2.3).
    public func collection() throws -> [Document] {
        let epub = SourceType.epub.rawValue, pdf = SourceType.pdf.rawValue
        let descriptor = FetchDescriptor<StoredDocument>(
            predicate: #Predicate { $0.sourceType == epub || $0.sourceType == pdf },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        return try modelContext.fetch(descriptor).map(Self.domain)
    }

    /// Every document's summary, newest first.
    public func summaries() throws -> [DocumentSummary] {
        try modelContext.fetch(FetchDescriptor<StoredDocument>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))
            .map(Self.summary)
    }

    public func summary(id: UUID) throws -> DocumentSummary? { try row(id).map(Self.summary) }

    /// Updates title, author, voice, cover, and source URL. The resume position and the queue
    /// state have their own calls and are ignored here.
    public func update(_ document: Document) throws {
        let row = try existing(document.id)
        row.title = document.title
        row.author = document.author
        row.voiceID = document.voiceID
        row.coverImagePath = document.coverImagePath
        row.sourceURL = document.sourceURL?.absoluteString
        row.updatedAt = Date()
        try modelContext.save()
    }

    public func delete(id: UUID) throws {
        let row = try existing(id)
        modelContext.delete(row)
        try modelContext.save()
    }

    // MARK: Queue

    /// Appends to the end of the Queue, or removes (archive). No-op when already in that state.
    public func setQueued(_ id: UUID, _ queued: Bool) throws {
        let row = try existing(id)
        if queued {
            guard row.queueOrder == nil else { return }
            row.queueOrder = (try queueRows().last?.queueOrder ?? -1) + 1
        } else {
            row.queueOrder = nil
        }
        row.updatedAt = Date()
        try modelContext.save()
    }

    /// Moves a queued document to `index` (clamped) and renumbers the Queue 0…n-1.
    public func moveInQueue(_ id: UUID, to index: Int) throws {
        var rows = try queueRows()
        guard let from = rows.firstIndex(where: { $0.id == id }) else { throw LibraryStoreError.documentNotFound(id) }
        let moving = rows.remove(at: from)
        rows.insert(moving, at: max(0, min(index, rows.count)))
        for (i, r) in rows.enumerated() { r.queueOrder = i }
        moving.updatedAt = Date()
        try modelContext.save()
    }

    public func setFinished(_ id: UUID, _ finished: Bool) throws {
        let row = try existing(id)
        row.isFinished = finished
        row.updatedAt = Date()
        try modelContext.save()
    }

    // MARK: Timelines

    /// Decodes every chapter blob. `isStale` when the persisted versions differ from `Versions`.
    public func timeline(for id: UUID) throws -> StoredTimeline? {
        guard let row = try row(id) else { return nil }
        let chapters = try row.chapters.sorted { $0.index < $1.index }.map { try TimelineCodec.decode($0.blob).chapter }
        let timeline = Timeline(chapters: chapters, schemaVersion: row.schemaVersion,
                                segmenterVersion: row.segmenterVersion, normalizerVersion: row.normalizerVersion)
        let stale = row.schemaVersion != Versions.schema
            || row.segmenterVersion != Versions.segmenter
            || row.normalizerVersion != Versions.normalizer
        return StoredTimeline(timeline: timeline, isStale: stale)
    }

    public func chapter(_ index: Int, of id: UUID) throws -> Chapter? {
        guard let row = try row(id), let c = row.chapters.first(where: { $0.index == index }) else { return nil }
        return try TimelineCodec.decode(c.blob).chapter
    }

    /// Persists phase-2 results (actual durations, word timings, `audioRef`) for one chapter and
    /// refreshes the denormalized counts. The chapter keeps the document's persisted versions.
    public func saveChapter(_ chapter: Chapter, at index: Int, of id: UUID) throws {
        let row = try existing(id)
        guard let c = row.chapters.first(where: { $0.index == index }) else {
            throw LibraryStoreError.chapterOutOfRange(index)
        }
        try Self.fill(c, with: chapter, segmenterVersion: row.segmenterVersion, normalizerVersion: row.normalizerVersion)
        row.updatedAt = Date()
        try modelContext.save()
    }

    /// Replaces every chapter and the versions: re-derivation after a version bump (spec §3.7.3).
    /// The resume position is untouched because `Position` survives re-segmentation (spec §3.2).
    public func replaceTimeline(_ timeline: Timeline, for id: UUID) throws {
        let row = try existing(id)
        try replaceChapters(of: row, with: timeline)
        row.updatedAt = Date()
        try modelContext.save()
    }

    // MARK: Internals

    func row(_ id: UUID) throws -> StoredDocument? {
        var descriptor = FetchDescriptor<StoredDocument>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func existing(_ id: UUID) throws -> StoredDocument {
        guard let row = try row(id) else { throw LibraryStoreError.documentNotFound(id) }
        return row
    }

    /// Test hook.
    func chapterRowCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<StoredChapter>())
    }

    private func queueRows() throws -> [StoredDocument] {
        try modelContext.fetch(FetchDescriptor<StoredDocument>(
            predicate: #Predicate { $0.queueOrder != nil },
            sortBy: [SortDescriptor(\.queueOrder)]))
    }

    private func replaceChapters(of row: StoredDocument, with timeline: Timeline) throws {
        for c in row.chapters { modelContext.delete(c) }
        row.chapters = []
        row.schemaVersion = timeline.schemaVersion
        row.segmenterVersion = timeline.segmenterVersion
        row.normalizerVersion = timeline.normalizerVersion
        for (i, chapter) in timeline.chapters.enumerated() {
            let c = StoredChapter(index: i, title: chapter.title, position: Data(), blob: Data(),
                                  utteranceCount: 0, durationSeconds: 0, renderedCount: 0)
            try Self.fill(c, with: chapter, segmenterVersion: timeline.segmenterVersion,
                          normalizerVersion: timeline.normalizerVersion)
            modelContext.insert(c)
            row.chapters.append(c)
        }
    }

    private static func fill(_ c: StoredChapter, with chapter: Chapter,
                             segmenterVersion: Int, normalizerVersion: Int) throws {
        c.title = chapter.title
        c.position = try JSONEncoder().encode(chapter.position)
        c.blob = try TimelineCodec.encode(chapter, segmenterVersion: segmenterVersion, normalizerVersion: normalizerVersion)
        c.utteranceCount = chapter.utterances.count
        c.durationSeconds = chapter.utterances.reduce(0) { $0 + $1.duration.seconds }
        c.renderedCount = chapter.utterances.filter { $0.audioRef != nil }.count
    }

    static func domain(_ r: StoredDocument) -> Document {
        Document(id: r.id, title: r.title, author: r.author,
                 sourceType: SourceType(rawValue: r.sourceType) ?? .epub,
                 sourceURL: r.sourceURL.flatMap(URL.init(string:)),
                 coverImagePath: r.coverImagePath, addedAt: r.addedAt, voiceID: r.voiceID,
                 resumePosition: r.resumePosition.flatMap { try? JSONDecoder().decode(Position.self, from: $0) })
    }

    static func summary(_ r: StoredDocument) -> DocumentSummary {
        DocumentSummary(document: domain(r), chapterCount: r.chapters.count,
                        utteranceCount: r.chapters.reduce(0) { $0 + $1.utteranceCount },
                        totalSeconds: r.chapters.reduce(0) { $0 + $1.durationSeconds },
                        renderedCount: r.chapters.reduce(0) { $0 + $1.renderedCount },
                        isFinished: r.isFinished, queueOrder: r.queueOrder, lastPlayedAt: r.lastPlayedAt)
    }
}
