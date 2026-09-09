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
    /// The resume chapter's text and progress, loaded off the body so the list never decodes a chapter.
    @State private var glimpse: RowGlimpse?

    private var progress: DocumentProgress? { env.libraryModel.progress(for: summary.id) }
    private var isCurrent: Bool { env.player.current?.id == summary.id }
    private var isPlayingHere: Bool { isCurrent && env.player.isPlaying }
    private var isArticle: Bool { summary.document.sourceType == .article }
    /// Books with chapters show the chapter's own progress and time; a file with none shows the file's.
    private var hasChapters: Bool { !isArticle && (progress?.chapterCount ?? summary.chapterCount) > 1 }

    var body: some View {
        // 20 pt between the book and its text: the cover's shadow needs air, and the reference cell
        // (Apple Books' Continue) breathes there too.
        HStack(alignment: .top, spacing: 20) {
            if isArticle {
                // A web article is not a book: flat art, no spine.
                Artwork(relativePath: summary.document.coverImagePath, paths: env.paths, size: 64, radius: Spacing.artworkSmall)
            } else {
                BookCover(relativePath: summary.document.coverImagePath, paths: env.paths, height: 112,
                          title: summary.document.title, isPDF: summary.document.sourceType == .pdf)
            }

            VStack(alignment: .leading, spacing: 8) {
                // "Chapter 7 · ◔ 41%  ✓": the chapter, how far through it, and ready-offline.
                HStack(spacing: 6) {
                    if let chapterText { Text(chapterText) }
                    if let fraction {
                        if chapterText != nil { Text("·").accessibilityHidden(true) }
                        CircularProgress(fraction: fraction, lineWidth: 2, size: 12)
                        Text("\(Int((fraction * 100).rounded()))%")
                    }
                    if summary.isFullyRendered { PositiveCheck() }
                }
                .typeRole(.meta)
                .foregroundStyle(Tokens.ink2)
                .accessibilityElement(children: .combine)

                Button(action: onOpen) {
                    Text(summary.document.title)
                        .typeRole(.rowTitle)                                   // the Settings rows' face, by the owner's eye
                        .foregroundStyle(Tokens.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the reader")

                if let excerpt = glimpse?.excerpt, !excerpt.isEmpty {
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
                         detail: isStarting ? nil : timeDetail,
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
                }
                .padding(.top, 6)
            }
        }
        .contextMenu { contextItems }
        .sheet(isPresented: $showSleepTimer) { SleepTimerSheet() }
        .sheet(isPresented: $showVoiceChange) { VoiceChangeSheet(summary: summary) }
        .task(id: glimpseKey) { glimpse = await env.libraryModel.glimpse(for: summary) }
    }

    @ViewBuilder private var contextItems: some View {
        Button(role: .destructive) { Task { await env.libraryModel.archive(summary.id) } } label: { Label("Archive", systemImage: "archivebox") }
        Button { Task { await env.libraryModel.markFinished(summary.id, !summary.isFinished) } } label: {
            Label(summary.isFinished ? "Mark as unfinished" : "Mark as finished", systemImage: "checkmark.circle")
        }
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

    /// How far through the chapter (books) or the file (everything else). Nil until a chaptered
    /// book's glimpse has loaded, rather than flashing the whole book's number first.
    private var fraction: Double? {
        hasChapters ? glimpse?.chapterFraction : (progress?.fraction ?? 0)
    }

    /// Time left in the chapter (books) or the file, on the Play pill: "2h 28m", never "~" and no
    /// "left" — the pill is the sentence. Nil until a chaptered book's glimpse has loaded.
    private var timeDetail: String? {
        let seconds: TimeInterval?
        if hasChapters { seconds = glimpse?.chapterRemainingSeconds }
        else { seconds = progress?.remainingSeconds ?? summary.totalSeconds }
        return seconds.map { DurationFormatter.remaining($0, approximate: false) }
    }

    /// What `LibraryModel.glimpse(for:)` reads: the task reloads only when the resume point or the
    /// chapters behind it could have moved, not on every row refresh.
    private struct GlimpseKey: Hashable {
        var id: UUID
        var resumePosition: Position?
        var resumeChapterIndex: Int?
        var isStale: Bool
        var chapterIndex: Int?
    }

    private var glimpseKey: GlimpseKey {
        GlimpseKey(id: summary.id, resumePosition: summary.document.resumePosition, resumeChapterIndex: summary.resumeChapterIndex,
                   isStale: summary.isStale, chapterIndex: progress?.chapterIndex)
    }
}
