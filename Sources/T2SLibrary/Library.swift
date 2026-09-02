import Foundation
import T2SCore
import T2SStore

public struct ImportResult: Hashable, Sendable {
    public var document: Document
    public var utteranceCount: Int
    /// What the reader could not parse; the UI says so (spec §6).
    public var skippedResources: [String]

    public init(document: Document, utteranceCount: Int, skippedResources: [String]) {
        self.document = document
        self.utteranceCount = utteranceCount
        self.skippedResources = skippedResources
    }
}

/// The import / delete / re-derive facade over the store, the audio cache, and the readers
/// (spec §4). Import runs phase 1 only (spec §3.3); everything imported joins the Queue, and
/// nothing is gated on rendering (spec §3.4.1).
public actor Library {
    public let paths: LibraryPaths
    public let store: LibraryStore
    private let audioStore: any AudioStore
    private let readers: [any DocumentReader]

    public init(paths: LibraryPaths, store: LibraryStore, audioStore: any AudioStore, readers: [any DocumentReader]) {
        self.paths = paths
        self.store = store
        self.audioStore = audioStore
        self.readers = readers
    }

    // MARK: Import

    /// Copies `url` into the container (the original is never touched), reads it, segments it,
    /// stores it, and queues it. On any failure the document directory is removed.
    public func importFile(at url: URL, sourceType: SourceType) async throws -> ImportResult {
        let reader = try reader(for: sourceType)
        let id = UUID()
        let directory = paths.documentDirectory(id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: paths.sourceURL(id, type: sourceType))
            return try await ingest(id: id, sourceType: sourceType, sourceURL: nil, reader: reader)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// Writes the retained HTML and the generated EPUB (spec §2.1), then imports the EPUB as an article.
    public func importArticle(_ article: ArticleContent, originalHTML: String) async throws -> ImportResult {
        let reader = try reader(for: .article)
        let id = UUID()
        let directory = paths.documentDirectory(id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(originalHTML.utf8).write(to: paths.originalHTMLURL(id), options: .atomic)
            try ArticleEPUBWriter.write(article, to: paths.sourceURL(id, type: .article), identifier: id)
            return try await ingest(id: id, sourceType: .article, sourceURL: article.sourceURL, reader: reader)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    // MARK: Lifecycle

    /// Removes the document's cached audio, its rows, and its directory.
    public func delete(_ id: UUID) async throws {
        if let stored = try await store.timeline(for: id) { await removeAudio(of: stored.timeline) }
        try await store.delete(id: id)
        try? FileManager.default.removeItem(at: paths.documentDirectory(id))
    }

    /// The timeline to play. A stale timeline (version bump) is re-derived from the retained source
    /// first (spec §3.7.3), so playback never sees a version mismatch.
    public func timelineForPlayback(_ id: UUID) async throws -> Timeline? {
        guard let stored = try await store.timeline(for: id) else { return nil }
        return stored.isStale ? try await reprocess(id) : stored.timeline
    }

    /// Re-reads the retained source with the current segmenter, normalizer, and dictionary and
    /// replaces the chapters. The resume position survives (spec §3.2). The old utterances' audio
    /// keys are removed from the cache: they embed the old versions and would never be looked up again.
    @discardableResult
    public func reprocess(_ id: UUID) async throws -> Timeline {
        guard let document = try await store.document(id: id) else { throw LibraryStoreError.documentNotFound(id) }
        let reader = try reader(for: document.sourceType)
        let read = try await reader.read(fileURL: paths.sourceURL(id, type: document.sourceType),
                                         sourceType: document.sourceType)
        let timeline = try await build(read)
        if let old = try await store.timeline(for: id) { await removeAudio(of: old.timeline) }
        try await store.replaceTimeline(timeline, for: id)
        return timeline
    }

    /// Drops the document's rendered audio from the cache and clears every `audioRef`. Actual
    /// durations and word timings stay: they remain the best estimate until the next render.
    public func evictAudio(for id: UUID) async throws {
        guard let stored = try await store.timeline(for: id) else { return }
        await removeAudio(of: stored.timeline)
        var timeline = stored.timeline
        for c in timeline.chapters.indices where timeline.chapters[c].utterances.contains(where: { $0.audioRef != nil }) {
            for u in timeline.chapters[c].utterances.indices { timeline.chapters[c].utterances[u].audioRef = nil }
            try await store.saveChapter(timeline.chapters[c], at: c, of: id)
        }
    }

    /// What `RenderPolicy` needs for one document (spec §3.4.1). `rendered` follows `audioRef`;
    /// the coordinator reconciles against the store when it loads (Plan 2).
    public func renderSnapshot(for id: UUID) async throws -> RenderSnapshot? {
        guard let document = try await store.document(id: id),
              let timeline = try await timelineForPlayback(id) else { return nil }
        var rendered: [Bool] = []
        rendered.reserveCapacity(timeline.utteranceCount)
        for chapter in timeline.chapters { for u in chapter.utterances { rendered.append(u.audioRef != nil) } }
        let resume = document.resumePosition.map { PositionResolver.resolve($0, in: timeline).utteranceIndex } ?? 0
        return RenderSnapshot(documentID: id, timeline: timeline, rendered: rendered, resumeIndex: resume)
    }

    // MARK: Internals

    private func reader(for type: SourceType) throws -> any DocumentReader {
        guard let reader = readers.first(where: { $0.supportedTypes.contains(type) }) else {
            throw ImportError.unsupportedFormat(type.rawValue)
        }
        return reader
    }

    private func ingest(id: UUID, sourceType: SourceType, sourceURL: URL?, reader: any DocumentReader) async throws -> ImportResult {
        let read = try await reader.read(fileURL: paths.sourceURL(id, type: sourceType), sourceType: sourceType)
        let timeline = try await build(read)
        var coverPath: String?
        if let cover = read.coverImage {
            let url = paths.coverURL(id)
            try cover.write(to: url, options: .atomic)
            coverPath = paths.relativePath(of: url)
        }
        let document = Document(id: id, title: read.title, author: read.author, sourceType: sourceType,
                                sourceURL: sourceURL, coverImagePath: coverPath, addedAt: Date())
        try await store.insert(document, timeline: timeline)
        try await store.setQueued(id, true)
        return ImportResult(document: document, utteranceCount: timeline.utteranceCount, skippedResources: read.skippedResources)
    }

    /// Phase 1 (spec §3.3) with the dictionary as it stands now (Global Constraints).
    private func build(_ read: ReadDocument) async throws -> Timeline {
        let dictionary = try await store.pronunciations()
        let segmenter = Segmenter(normalizer: TextNormalizer(dictionary: dictionary))
        let timeline = TimelineBuilder.build(chapters: read.chapters, segmenter: segmenter)
        guard timeline.utteranceCount > 0 else { throw ImportError.noText }
        return timeline
    }

    private func removeAudio(of timeline: Timeline) async {
        for chapter in timeline.chapters {
            for utterance in chapter.utterances {
                if let ref = utterance.audioRef { try? await audioStore.remove(RenderKey(rawValue: ref)) }
            }
        }
    }
}
