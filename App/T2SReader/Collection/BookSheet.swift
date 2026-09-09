// App/T2SReader/Collection/BookSheet.swift
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// Spec §2.4.5 book sheet. Chapters come from the timeline (re-derived if stale) and their
/// progress from the persisted position through `DocumentProgress`.
struct BookSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerRoute) private var readerRoute
    var summary: DocumentSummary

    @State private var chapters: [ChapterEntry] = []
    @State private var bookmarks: BookmarkListModel?
    /// True only while the Play pill's own tap is resuming a paused, already-current document —
    /// the one branch that awaits playback before dismissing, otherwise silently.
    @State private var isStarting = false

    private var live: DocumentSummary { env.libraryModel.summaries.first { $0.id == summary.id } ?? summary }
    private var isQueued: Bool { live.queueOrder != nil && !live.isFinished }
    private var isCurrent: Bool { env.player.current?.id == live.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                // The same book as the Collection's tile and the Home row, larger: a tap on a book
                // should open onto that book, not a square of it.
                HStack { Spacer(); BookCover(relativePath: live.document.coverImagePath, paths: env.paths, height: 240,
                                             title: live.document.title, isPDF: live.document.sourceType == .pdf); Spacer() }
                    .padding(.top, Spacing.section)
                VStack(alignment: .leading, spacing: 8) {
                    Text(live.document.title).typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                    if let author = live.document.author { Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2) }
                }
                HStack(spacing: 6) {
                    Text("\(live.chapterCount) chapters")
                    Text("·")
                    Text(DurationFormatter.long(live.totalSeconds, approximate: !live.isFullyRendered))
                    Text("·")
                    Text("Rendered \(live.utteranceCount > 0 ? live.renderedCount * 100 / live.utteranceCount : 0)%")
                }
                .typeRole(.meta).foregroundStyle(Tokens.ink2)
                HStack(spacing: 8) {
                    Pill(label: isStarting ? "Starting…" : "Play", glyph: isStarting ? nil : "play.fill", style: .accent) {
                        Task {
                            if isCurrent, !env.player.isPlaying {
                                isStarting = true
                                await env.player.togglePlay()
                                isStarting = false
                            }
                            dismiss()
                            readerRoute.open(live)
                        }
                    }
                    .disabled(isStarting)
                    .accessibilityHint("Plays and opens the reader")
                    if isQueued {
                        Pill(label: "In Queue", glyph: "checkmark", style: .selected) { Task { await env.libraryModel.archive(live.id) } }
                    } else {
                        Pill(label: "Add to Queue", glyph: "plus", style: .soft) { Task { await env.libraryModel.enqueue(live.id) } }
                    }
                }
                // The Reader's chapter list, row for row (owner's ask, 2026-09-09): the chapter
                // the book would resume in wears the ring, the ones before it the check.
                VStack(alignment: .leading, spacing: 0) {
                    Text("Chapters").typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    let resumeIndex = chapters.first { $0.fraction < 1 }?.index ?? chapters.last?.index
                    ForEach(chapters) { chapter in
                        ChapterRow(chapter: chapter, isCurrent: chapter.index == resumeIndex,
                                   isHeard: resumeIndex.map { chapter.index < $0 } ?? false) {
                            Task {
                                if !isCurrent { await env.player.load(live, play: false) }
                                await env.player.seek(toChapter: chapter.index)
                                if !env.player.isPlaying { await env.player.togglePlay() }
                                dismiss()
                                readerRoute.open(live)
                            }
                        }
                    }
                }
                .padding(.horizontal, -12)                                 // the rows' fill runs into the margin, as in the Reader
                if let bookmarks, !bookmarks.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Bookmarks").typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
                        ForEach(bookmarks.entries) { entry in
                            BookmarkRow(entry: entry, onJump: {
                                Task {
                                    await bookmarks.jump(to: entry, in: live)
                                    dismiss()
                                    readerRoute.open(live)
                                }
                            }, onDelete: { Task { await bookmarks.delete(entry) } })
                        }
                    }
                }
                Color.clear.frame(height: Spacing.section)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.raised)
        .presentationCornerRadius(Spacing.sheetCorner)
        .task { await reload() }
    }

    /// Positions are saved by the coordinator straight to the store, so the library model is
    /// refreshed here before the chapters are rebuilt.
    private func reload() async {
        await env.libraryModel.refresh()
        await loadChapters()
        let bookmarks = self.bookmarks ?? BookmarkListModel(library: env.library, player: env.player)
        self.bookmarks = bookmarks
        await bookmarks.load(live)
    }

    private func loadChapters() async {
        guard let timeline = try? await env.library.timelineForPlayback(live.id) else { chapters = []; return }
        let progress = DocumentProgress.compute(summary: live, timeline: timeline)
        chapters = ChapterEntry.entries(timeline: timeline, timeIndex: TimeIndex(timeline), elapsed: progress.elapsedSeconds)
    }
}
