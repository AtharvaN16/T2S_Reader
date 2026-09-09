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

    private var progress: DocumentProgress? { env.libraryModel.progress(for: summary.id) }
    private var isCurrent: Bool { env.player.current?.id == summary.id }
    private var isPlayingHere: Bool { isCurrent && env.player.isPlaying }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Artwork(relativePath: summary.document.coverImagePath, paths: env.paths, size: 64, radius: Spacing.artworkSmall)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(sourceName)
                    Text("·").accessibilityHidden(true)
                    Text(DurationFormatter.age(of: summary.document.addedAt))
                    if let progress, summary.document.sourceType != .article, progress.chapterCount > 1, let c = progress.chapterIndex {
                        Text("·").accessibilityHidden(true)
                        Text("Chapter \(c + 1) of \(progress.chapterCount)")
                    }
                    if summary.isFullyRendered { PositiveCheck() }
                    Spacer(minLength: 8)
                    CircularProgress(fraction: progress?.fraction ?? 0, lineWidth: 2, size: 14)
                    Text(remainingText)
                }
                .typeRole(.meta)
                .foregroundStyle(Tokens.ink2)
                .accessibilityElement(children: .combine)

                Button(action: onOpen) {
                    Text(summary.document.title)
                        .typeRole(.cardTitle)
                        .foregroundStyle(Tokens.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the reader")

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
                }
            }
        }
        .contextMenu { contextItems }
        .sheet(isPresented: $showSleepTimer) { SleepTimerSheet() }
        .sheet(isPresented: $showVoiceChange) { VoiceChangeSheet(summary: summary) }
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

    /// Time left, shown under the progress ring: "~22h 39m left".
    private var remainingText: String {
        if let progress { return DurationFormatter.remaining(progress.remainingSeconds, approximate: progress.isApproximate) + " left" }
        return DurationFormatter.remaining(summary.totalSeconds, approximate: !summary.isFullyRendered) + " left"
    }

    private var sourceName: String {
        switch summary.document.sourceType {
        case .epub: return "EPUB"
        case .pdf: return "PDF"
        case .article: return summary.document.sourceURL?.host() ?? "Article"
        }
    }
}
