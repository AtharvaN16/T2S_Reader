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

    /// How many UTF-16 units of consecutive sentences one utterance may pack (`Segmenter.packLength`);
    /// the app passes the default, tests that count sentences pass 0.
    private let segmenterPackLength: Int
    /// The removal of a re-derived document's old audio, running behind the load path (`reprocess`).
    private var audioGC: Task<Void, Never>?

    public init(paths: LibraryPaths, store: LibraryStore, audioStore: any AudioStore, readers: [any DocumentReader],
                segmenterPackLength: Int = Segmenter.appPackLength) {
        self.paths = paths
        self.store = store
        self.audioStore = audioStore
        self.readers = readers
        self.segmenterPackLength = segmenterPackLength
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

    /// Removes the document's cached audio, its rows, and its directory. An undecodable chapter blob
    /// must never make a document undeletable: the timeline fetch is tolerant, so a corrupt blob at
    /// worst leaks its audio keys rather than blocking the one recovery action the user has.
    public func delete(_ id: UUID) async throws {
        if let stored = try? await store.timeline(for: id) { await removeAudio(of: stored.timeline) }
        try await store.delete(id: id)
        try? FileManager.default.removeItem(at: paths.documentDirectory(id))
    }

    /// The timeline to play. Staleness (version bump) is read from the row's version columns only,
    /// with no chapter decode (spec §3.7.3); a stale document is re-derived from the retained source
    /// before anything is decoded, so playback never sees a version mismatch and never pays for a
    /// decode of a timeline it is about to discard.
    public func timelineForPlayback(_ id: UUID) async throws -> Timeline? {
        guard let stale = try await store.isStale(id: id) else { return nil }
        return stale ? try await reprocess(id) : try await store.timeline(for: id)?.timeline
    }

    /// The timeline as it currently stands, for callers that only want to *read* it — list refresh,
    /// row progress. Never reprocesses: a stale document (or a missing one) returns `nil` rather
    /// than paying for a re-derivation, because re-derivation belongs on the load path
    /// (`timelineForPlayback`), where it is asked for once and the user is waiting for that document.
    public func currentTimeline(_ id: UUID) async throws -> Timeline? {
        guard let stale = try await store.isStale(id: id), !stale else { return nil }
        return try await store.timeline(for: id)?.timeline
    }

    /// Re-segments the retained chapters with the current segmenter, normalizer, and dictionary and
    /// replaces the stored ones. The resume position survives (spec §3.2). The reader is opened only
    /// for a document imported before its chapters were retained, and then retained for next time
    /// (Plan 17, audit §5.1). The old utterances' audio is removed from the cache — from the old blobs
    /// read raw before the replacement. When the re-derivation moves the segmenter or normalizer
    /// version, the new render keys differ from the old (`RenderKey` carries both) and the removal
    /// runs behind this call: the load path pays for neither the decode nor the removals. When it
    /// does not — a dictionary change from the Details sheet, a schema-only bump — the keys are the
    /// same bytes, and the removal must finish before the replacement, or the next render's cache
    /// probe would adopt the old pronunciation (the Plan 17 review's blocker). An undecodable old
    /// blob just leaks its keys rather than blocking re-derivation, the very thing meant to recover
    /// from it.
    @discardableResult
    public func reprocess(_ id: UUID) async throws -> Timeline {
        guard let document = try await store.document(id: id) else { throw LibraryStoreError.documentNotFound(id) }
        let retainedURL = paths.retainedChaptersURL(id)
        let chapters: [ChapterInput]
        if let retained = try? RetainedChapters.read(from: retainedURL) {
            chapters = retained
        } else {
            let reader = try reader(for: document.sourceType)
            let read = try await reader.read(fileURL: paths.sourceURL(id, type: document.sourceType),
                                             sourceType: document.sourceType)
            chapters = read.chapters
            try? RetainedChapters.write(chapters, to: retainedURL)
        }
        let timeline = try await build(chapters)
        let oldBlobs = (try? await store.chapterBlobs(for: id)) ?? []
        let old = try await store.versions(of: id)
        let keysChange = old?.segmenter != timeline.segmenterVersion || old?.normalizer != timeline.normalizerVersion
        if keysChange {
            try await store.replaceTimeline(timeline, for: id)
            removeAudioInBackground(ofBlobs: oldBlobs)
        } else {
            await Self.removeAudio(ofBlobs: oldBlobs, from: audioStore)
            try await store.replaceTimeline(timeline, for: id)
        }
        return timeline
    }

    /// Waits for the old audio a `reprocess` left to remove in the background; tests only.
    func awaitAudioGC() async { await audioGC?.value }

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
    /// the coordinator reconciles against the store when it loads (Plan 2). Never re-derives: a stale
    /// document is nil here and is re-derived when it is opened (`timelineForPlayback`).
    public func renderSnapshot(for id: UUID) async throws -> RenderSnapshot? {
        guard let document = try await store.document(id: id),
              let timeline = try await currentTimeline(id) else { return nil }
        return Self.renderSnapshot(for: document, timeline: timeline)
    }

    public static func renderSnapshot(for document: Document, timeline: Timeline) -> RenderSnapshot {
        var rendered: [Bool] = []
        rendered.reserveCapacity(timeline.utteranceCount)
        for chapter in timeline.chapters { for u in chapter.utterances { rendered.append(u.audioRef != nil) } }
        let resume = document.resumePosition.map { PositionResolver.resolve($0, in: timeline).utteranceIndex } ?? 0
        return RenderSnapshot(documentID: document.id, timeline: timeline, rendered: rendered, resumeIndex: resume)
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
        let timeline = try await build(read.chapters)
        // Best effort: without the retained file a re-derivation reads the source once more.
        try? RetainedChapters.write(read.chapters, to: paths.retainedChaptersURL(id))
        var coverPath: String?
        if let cover = read.coverImage {
            let url = paths.coverURL(id)
            try cover.write(to: url, options: .atomic)
            coverPath = paths.relativePath(of: url)
        }
        let document = Document(id: id, title: read.title, author: read.author, sourceType: sourceType,
                                sourceURL: sourceURL, coverImagePath: coverPath, addedAt: Date())
        try await store.insert(document, timeline: timeline, queued: true)
        return ImportResult(document: document, utteranceCount: timeline.utteranceCount, skippedResources: read.skippedResources)
    }

    /// Phase 1 (spec §3.3) with the dictionary as it stands now (Global Constraints).
    private func build(_ chapters: [ChapterInput]) async throws -> Timeline {
        let dictionary = try await store.pronunciations()
        let segmenter = Segmenter(normalizer: TextNormalizer(dictionary: dictionary), packLength: segmenterPackLength)
        let timeline = TimelineBuilder.build(chapters: chapters, segmenter: segmenter)
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

    /// Decodes the replaced chapters and drops their audio, off this actor and after the caller has
    /// its timeline. One task at a time: a second re-derivation waits for the first's removals.
    private func removeAudioInBackground(ofBlobs blobs: [Data]) {
        guard !blobs.isEmpty else { return }
        let audioStore = self.audioStore
        let previous = audioGC
        audioGC = Task.detached(priority: .utility) {
            await previous?.value
            await Self.removeAudio(ofBlobs: blobs, from: audioStore)
        }
    }

    private static func removeAudio(ofBlobs blobs: [Data], from audioStore: any AudioStore) async {
        for blob in blobs {
            guard let chapter = try? TimelineCodec.decode(blob).chapter else { continue }
            for utterance in chapter.utterances {
                if let ref = utterance.audioRef { try? await audioStore.remove(RenderKey(rawValue: ref)) }
            }
        }
    }
}
