// App/T2SReader/Queue/QueueRow.swift
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// One Queue row (spec §2.4.5). No card, no divider: the 28pt row gap is the rhythm.
struct QueueRow: View {
    @Environment(AppEnvironment.self) private var env
    var summary: DocumentSummary
    var onOpen: () -> Void
    var onDetails: () -> Void
    @State private var showSleepTimer = false
    @State private var showVoiceChange = false
    /// True only while the Play pill's own tap is resuming a paused, already-current document —
    /// the one branch that awaits playback before opening the reader, otherwise silently.
    @State private var isStarting = false
    /// The text at the resume position, loaded off the body so the list never decodes a chapter.
    @State private var excerpt: String?

    private var progress: DocumentProgress? { env.libraryModel.progress(for: summary.id) }
    private var isCurrent: Bool { env.player.current?.id == summary.id }
    private var isPlayingHere: Bool { isCurrent && env.player.isPlaying }
    private var isArticle: Bool { summary.document.sourceType == .article }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if isArticle {
                // A web article is not a book: flat art, no spine.
                Artwork(relativePath: summary.document.coverImagePath, paths: env.paths, size: 64, radius: Spacing.artworkSmall)
            } else {
                BookCover(relativePath: summary.document.coverImagePath, paths: env.paths, height: 96)
            }

            VStack(alignment: .leading, spacing: 10) {
                if chapterText != nil || summary.isFullyRendered {           // no empty gap when there is nothing to say
                    HStack(spacing: 6) {
                        if let chapterText { Text(chapterText) }
                        if summary.isFullyRendered { PositiveCheck() }
                    }
                    .typeRole(.meta)
                    .foregroundStyle(Tokens.ink2)
                    .accessibilityElement(children: .combine)
                }

                Button(action: onOpen) {
                    Text(summary.document.title)
                        .typeRole(.cardTitle)
                        .foregroundStyle(Tokens.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the reader")

                if let excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .typeRole(.meta)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundStyle(Tokens.ink2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Pill(label: isPlayingHere ? "Pause" : (isStarting ? "Starting…" : "Play"),
                         glyph: isPlayingHere ? "pause.fill" : (isStarting ? nil : "play.fill"),
                         style: .soft) {
                        Task {
                            if isPlayingHere { await env.player.togglePlay(); return }   // Pause stays in place
                            if isCurrent {
                                isStarting = true
                                await env.player.togglePlay()                            // resume, then read along
                                isStarting = false
                            }
                            onOpen()                                                       // the Reader loads and plays a non-current document itself
                        }
                    }
                    .disabled(isStarting)
                    .accessibilityHint(isPlayingHere ? "Pauses" : "Plays and opens the reader")
                    Menu {
                        contextItems
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tokens.ink)
                            .frame(width: 36, height: 36)
                            .background(Tokens.surface, in: Circle())
                    }
                    .accessibilityLabel("More")
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        CircularProgress(fraction: progress?.fraction ?? 0, lineWidth: 2, size: 12)
                        Text(remainingText)
                    }
                    .typeRole(.meta)
                    .foregroundStyle(Tokens.ink2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .contextMenu { contextItems }
        .sheet(isPresented: $showSleepTimer) { SleepTimerSheet() }
        .sheet(isPresented: $showVoiceChange) { VoiceChangeSheet(summary: summary) }
        .task(id: excerptKey) { excerpt = await env.libraryModel.excerpt(for: summary) }
    }

    @ViewBuilder private var contextItems: some View {
        Button(role: .destructive) { Task { await env.libraryModel.archive(summary.id) } } label: { Label("Archive", systemImage: "archivebox") }
        Button { Task { await env.libraryModel.markFinished(summary.id, !summary.isFinished) } } label: {
            Label(summary.isFinished ? "Mark as unfinished" : "Mark as finished", systemImage: "checkmark.circle")
        }
        Button { Task { await env.libraryModel.move(summary.id, to: 0) } } label: { Label("Move to top", systemImage: "arrow.up.to.line") }
        Button(action: onDetails) { Label("Details", systemImage: "info.circle") }
        Button { showSleepTimer = true } label: { Label("Sleep timer", systemImage: "moon.zzz") }
        Button { showVoiceChange = true } label: { Label("Change voice", systemImage: "person.wave.2") }
        Button {
            Task {
                if !isCurrent { await env.player.load(summary, play: false) }
                env.player.renderWholeDocument()
            }
        } label: { Label("Render whole document", systemImage: "waveform") }
    }

    /// "Chapter 7": books only, once the playhead's chapter is known and there is more than one.
    private var chapterText: String? {
        guard let progress, !isArticle, progress.chapterCount > 1, let c = progress.chapterIndex else { return nil }
        return "Chapter \(c + 1)"
    }

    /// Time left beside the ring, coarse on purpose: "22 hrs left", "42 min left". The row is read
    /// at a glance and the ring already says how far along it is, so no minutes and never a "~".
    private var remainingText: String {
        DurationFormatter.coarseRemaining(progress?.remainingSeconds ?? summary.totalSeconds) + " left"
    }

    /// What `LibraryModel.excerpt(for:)` reads: the task reloads only when the resume point or the
    /// chapters behind it could have moved, not on every row refresh.
    private struct ExcerptKey: Hashable {
        var id: UUID
        var resumePosition: Position?
        var resumeChapterIndex: Int?
        var isStale: Bool
        var chapterIndex: Int?
    }

    private var excerptKey: ExcerptKey {
        ExcerptKey(id: summary.id, resumePosition: summary.document.resumePosition, resumeChapterIndex: summary.resumeChapterIndex,
                   isStale: summary.isStale, chapterIndex: progress?.chapterIndex)
    }
}
