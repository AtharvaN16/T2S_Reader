import Foundation
import T2SCore

/// What one chapter of a book has on this device: how much of it became audio, and what that audio
/// occupies. The Book sheet's render mode reads a row's size and its trash from here, and its
/// summary line from the ``BookAudioStatus`` these come in.
public struct ChapterAudioStatus: Hashable, Sendable, Identifiable {
    public var chapterIndex: Int
    public var title: String
    /// The chapter's utterances — the denominator, whether or not any of them are rendered.
    public var utteranceCount: Int
    /// How many of them the store actually holds.
    public var rendered: Int
    /// What those clips occupy, and so what evicting this chapter would free.
    public var bytes: Int

    public var id: Int { chapterIndex }

    /// Nothing left to render. An empty chapter is not "ready": there is no audio in it to play,
    /// and calling it ready would put a tick and a trash on a row with nothing behind either.
    public var isFullyRendered: Bool { utteranceCount > 0 && rendered >= utteranceCount }
    /// Selectable in render mode, and what it renders is the remainder.
    public var isPartlyRendered: Bool { rendered > 0 && !isFullyRendered }
    /// 0…1, for a row that has no job of its own to report a fraction from.
    public var fraction: Double {
        guard utteranceCount > 0 else { return 0 }
        return min(1, max(0, Double(rendered) / Double(utteranceCount)))
    }

    /// The row's size, once there is any — nil rather than "Zero KB" for a chapter that has none.
    public var sizeText: String? { bytes > 0 ? BookAudioStatus.sizeText(bytes) : nil }

    public init(chapterIndex: Int, title: String, utteranceCount: Int, rendered: Int, bytes: Int) {
        self.chapterIndex = chapterIndex
        self.title = title
        self.utteranceCount = utteranceCount
        self.rendered = rendered
        self.bytes = bytes
    }
}

/// One book's rendered audio, chapter by chapter — *this* book's, not the whole cache, which
/// Settings → Storage keeps (chapter-rendering design, "Storage and eviction").
public struct BookAudioStatus: Hashable, Sendable {
    public var chapters: [ChapterAudioStatus]

    public init(chapters: [ChapterAudioStatus] = []) { self.chapters = chapters }

    public var readyChapters: Int { chapters.count { $0.isFullyRendered } }
    public var bytes: Int { chapters.reduce(0) { $0 + $1.bytes } }
    /// Whether there is anything for "Evict all" to take.
    public var hasAudio: Bool { chapters.contains { $0.rendered > 0 } }

    /// The line above the chapter list: "4 chapters ready · 38 MB". A book with whole chapters on
    /// the device counts them; one with only pieces of chapters — the fill tier's five-minute
    /// window, or a render stopped halfway — says so rather than reporting "0 chapters ready",
    /// which reads as "nothing here" over audio that is taking up room.
    public var summary: String {
        let ready = readyChapters
        if ready > 0 {
            return "\(ready) \(ready == 1 ? "chapter" : "chapters") ready · \(Self.sizeText(bytes))"
        }
        if hasAudio { return "Partly rendered · \(Self.sizeText(bytes))" }
        return "Nothing rendered yet"
    }

    /// The line under the storage box's bar: "9 of 40 chapters rendered". Always the fraction, even
    /// at nought — a book holding a few part-chapters really does have none finished, and the bar's
    /// dim segments are already saying where those bytes went (owner, 2026-09-14).
    public var countLine: String {
        let word = chapters.count == 1 ? "chapter" : "chapters"
        return "\(readyChapters) of \(chapters.count) \(word) rendered"
    }

    public func chapter(_ index: Int) -> ChapterAudioStatus? {
        chapters.first { $0.chapterIndex == index }
    }

    /// The app's one spelling of a size, as Settings → Storage writes it.
    public static func sizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Reads the book off its timeline and the store, without loading anything into the player.
    ///
    /// `renderSnapshot` reports `rendered` from each utterance's `audioRef`, which is the right
    /// answer for deciding what to render but the wrong one for a screen that says what is *on the
    /// device*: rendered audio is cache, so the LRU can drop a clip and leave its reference behind.
    /// A row built from references alone would then show a tick and a trash over nothing. So the
    /// references — which are the render keys — are checked against the store in one hop, and only
    /// the clips it still holds are counted and measured.
    public static func read(timeline: Timeline, audioStore: any AudioStore) async -> BookAudioStatus {
        let keys: [[RenderKey]] = timeline.chapters.map { chapter in
            chapter.utterances.compactMap { $0.audioRef.map(RenderKey.init(rawValue:)) }
        }
        let flat = keys.flatMap { $0 }
        let present = await audioStore.contains(flat)
        var next = 0
        var chapters: [ChapterAudioStatus] = []
        chapters.reserveCapacity(timeline.chapters.count)
        for (index, chapter) in timeline.chapters.enumerated() {
            let held = keys[index].indices.filter { present[next + $0] }.map { keys[index][$0] }
            next += keys[index].count
            // A key given twice counts once, and one the store does not hold counts nothing
            // (`AudioStore.bytes(for:)`), so this is the space evicting the chapter would free.
            let bytes = held.isEmpty ? 0 : await audioStore.bytes(for: held)
            chapters.append(ChapterAudioStatus(chapterIndex: index, title: chapter.title,
                                               utteranceCount: chapter.utterances.count,
                                               rendered: held.count, bytes: bytes))
        }
        return BookAudioStatus(chapters: chapters)
    }
}
