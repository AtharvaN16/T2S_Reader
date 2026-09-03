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

    private var progress: DocumentProgress? { env.libraryModel.progress(for: summary.id) }
    private var isCurrent: Bool { env.player.current?.id == summary.id }
    private var isPlayingHere: Bool { isCurrent && env.player.isPlaying }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: sourceMark).font(.system(size: 16, weight: .medium))
                Text(sourceName)
                Text("·")
                Text(DurationFormatter.age(of: summary.document.addedAt))
                if let progress, summary.document.sourceType != .article, progress.chapterCount > 1, let c = progress.chapterIndex {
                    Text("·")
                    Text("Chapter \(c + 1) of \(progress.chapterCount)")
                }
                if summary.isFullyRendered { PositiveCheck() }
            }
            .typeRole(.meta)
            .foregroundStyle(Tokens.ink2)

            Button(action: onOpen) {
                Text(summary.document.title)
                    .typeRole(.rowTitle)
                    .foregroundStyle(Tokens.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Pill(label: isPlayingHere ? "Pause" : "Play \(remainingText)",
                     glyph: isPlayingHere ? "pause.fill" : "play.fill",
                     style: .soft) {
                    Task {
                        if isCurrent { await env.player.togglePlay() } else { await env.player.load(summary, play: true) }
                    }
                }
                Pill(label: "Archive", glyph: "archivebox", style: .soft) {
                    Task { await env.libraryModel.archive(summary.id) }
                }
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
        .contextMenu { contextItems }
        .sheet(isPresented: $showSleepTimer) { SleepTimerSheet() }
    }

    @ViewBuilder private var contextItems: some View {
        Button(role: .destructive) { Task { await env.libraryModel.archive(summary.id) } } label: { Label("Archive", systemImage: "archivebox") }
        Button { Task { await env.libraryModel.markFinished(summary.id, !summary.isFinished) } } label: {
            Label(summary.isFinished ? "Mark as unfinished" : "Mark as finished", systemImage: "checkmark.circle")
        }
        Button { Task { await env.libraryModel.move(summary.id, to: 0) } } label: { Label("Move to top", systemImage: "arrow.up.to.line") }
        Button(action: onDetails) { Label("Details", systemImage: "info.circle") }
        Button { showSleepTimer = true } label: { Label("Sleep timer", systemImage: "moon.zzz") }
        Button {
            Task {
                if !isCurrent { await env.player.load(summary, play: false) }
                env.player.renderWholeDocument()
            }
        } label: { Label("Render whole document", systemImage: "waveform") }
    }

    private var remainingText: String {
        if let progress { return DurationFormatter.remaining(progress.remainingSeconds, approximate: progress.isApproximate) }
        return DurationFormatter.remaining(summary.totalSeconds, approximate: !summary.isFullyRendered)
    }

    private var sourceMark: String {
        switch summary.document.sourceType {
        case .epub: return "book.closed"
        case .pdf: return "doc.text"
        case .article: return "globe"
        }
    }

    private var sourceName: String {
        switch summary.document.sourceType {
        case .epub: return "EPUB"
        case .pdf: return "PDF"
        case .article: return summary.document.sourceURL?.host() ?? "Article"
        }
    }
}
