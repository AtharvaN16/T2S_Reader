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
    @State private var showPlayer = false

    private var live: DocumentSummary { env.libraryModel.summaries.first { $0.id == summary.id } ?? summary }
    private var isQueued: Bool { live.queueOrder != nil && !live.isFinished }
    private var isCurrent: Bool { env.player.current?.id == live.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                HStack { Spacer(); Artwork(relativePath: live.document.coverImagePath, paths: env.paths, size: 180, radius: Spacing.artworkLarge)
                    .shadow(color: Tokens.ink.opacity(0.18), radius: 24, y: 12); Spacer() }
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
                    Pill(label: "Play", glyph: "play.fill", style: .accent) {
                        Task {
                            if isCurrent {
                                if !env.player.isPlaying { await env.player.togglePlay() }
                            } else {
                                await env.player.load(live, play: true)
                            }
                            showPlayer = true
                        }
                    }
                    if isQueued {
                        Pill(label: "In Queue", glyph: "checkmark", style: .selected) { Task { await env.libraryModel.archive(live.id) } }
                    } else {
                        Pill(label: "Add to Queue", glyph: "plus", style: .soft) { Task { await env.libraryModel.enqueue(live.id) } }
                    }
                }
                VStack(alignment: .leading, spacing: 20) {
                    Text("Chapters").typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
                    ForEach(chapters) { chapter in
                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    if !isCurrent { await env.player.load(live, play: false) }
                                    await env.player.seek(toChapter: chapter.index)
                                    if !env.player.isPlaying { await env.player.togglePlay() }
                                    dismiss()
                                    readerRoute.open(live)
                                }
                            } label: {
                                Image(systemName: "play.fill").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Tokens.ink).frame(width: 32, height: 32)
                                    .background(Tokens.surface, in: Circle())
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(chapter.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(1)
                                ProgressBar(fraction: chapter.fraction)
                            }
                            Text(DurationFormatter.long(chapter.durationSeconds, approximate: !live.isFullyRendered))
                                .typeRole(.mono).foregroundStyle(Tokens.ink2)
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
        .onChange(of: showPlayer) { _, shown in if !shown { Task { await reload() } } }
        .sheet(isPresented: $showPlayer) {
            PlayerSheet().presentationCornerRadius(Spacing.sheetCorner).presentationBackground(Tokens.raised)
        }
    }

    /// Positions are saved by the coordinator straight to the store, so the library model is
    /// refreshed here before the chapters are rebuilt.
    private func reload() async {
        await env.libraryModel.refresh()
        await loadChapters()
    }

    private func loadChapters() async {
        guard let timeline = try? await env.library.timelineForPlayback(live.id) else { chapters = []; return }
        let progress = DocumentProgress.compute(summary: live, timeline: timeline)
        chapters = ChapterEntry.entries(timeline: timeline, timeIndex: TimeIndex(timeline), elapsed: progress.elapsedSeconds)
    }
}
