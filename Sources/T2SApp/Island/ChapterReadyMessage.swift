import Foundation

/// Which surface tells the reader a chapter is ready.
///
/// **Never both.** The capsule can only be seen while the app is up; a Live Activity is never
/// shown in the Dynamic Island while its own app is up. So the two are exclusive by nature,
/// and this makes that explicit rather than leaving each call site to remember it.
public enum Announcement: Equatable, Sendable {
    /// The black capsule at the top of the app's own screen.
    case island
    /// The Live Activity, which alerts on the Lock Screen and in the real island.
    case liveActivity

    public static func route(isForeground: Bool) -> Announcement {
        isForeground ? .island : .liveActivity
    }
}

/// What a finished — or failed — chapter is called.
///
/// Lifted verbatim from `RootPager.showRenderToast`, where it was worked out inline and could
/// only be read by the one caller that already had a `DocumentSummary` to hand. The wording is
/// the owner's (2026-09-14): "the sentence, not the label", because "Chapter 4: The Siege of
/// Delhi has finished rendering" says both which one and what happened to it.
public struct ChapterReadyMessage: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var isFailure: Bool

    public init(title: String, detail: String, isFailure: Bool) {
        self.title = title
        self.detail = detail
        self.isFailure = isFailure
    }

    /// - Parameter chapterCount: how many chapters the document has. One means the document is
    ///   its own single piece, and the copy takes the document's title rather than a chapter's.
    public static func make(job: ChapterRenderJob, documentTitle: String,
                            chapterCount: Int) -> ChapterReadyMessage {
        let hasChapters = chapterCount > 1
        if case .failed(let reason) = job.state {
            return ChapterReadyMessage(
                title: hasChapters ? "Chapter couldn't be rendered" : "Couldn't be rendered",
                detail: reason, isFailure: true)
        }
        let name = hasChapters
            ? ChapterLabel.text(for: job.title, ordinal: job.chapterIndex + 1)
            : documentTitle
        return ChapterReadyMessage(
            title: hasChapters ? "Chapter ready to play" : "Document ready to play",
            detail: "\(name) has finished rendering", isFailure: false)
    }
}
