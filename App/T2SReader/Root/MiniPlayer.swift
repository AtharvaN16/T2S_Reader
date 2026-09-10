// App/T2SReader/Root/MiniPlayer.swift
import SwiftUI
import T2SStore

/// Spec §2.4.4: artwork, title, play/pause, skip-forward. Shows the playing item, or the next
/// queued item with "Play" when idle. Tap opens the Reader on the shown item.
struct MiniPlayer: View {
    @Environment(AppEnvironment.self) private var env
    var onOpen: (DocumentSummary) -> Void
    /// Set for the span of a tap that starts playback, so the button shows feedback even before
    /// `env.player.current`/`isCatchingUp` catch up — `load()` awaits the timeline before either
    /// changes, which is otherwise a silent gap between tap and any visible response.
    @State private var startingID: DocumentSummary.ID?

    private var shown: DocumentSummary? { env.player.current ?? env.libraryModel.queue.first }
    private func isBusy(_ shown: DocumentSummary) -> Bool {
        startingID == shown.id || (env.player.current?.id == shown.id && env.player.isCatchingUp)
    }

    var body: some View {
        if let shown {
            HStack(spacing: 12) {
                Artwork(relativePath: shown.document.coverImagePath, paths: env.paths, size: 36, radius: Spacing.artworkSmall,
                        document: shown.document)
                Button { onOpen(shown) } label: {
                    Text(shown.document.title)
                        .typeRole(.rowTitle)
                        .lineLimit(1)
                        .foregroundStyle(Tokens.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now playing: \(shown.document.title)")
                .accessibilityHint("Opens the reader")
                Spacer(minLength: 8)
                Button {
                    let alreadyPlaying = env.player.current?.id == shown.id && env.player.isPlaying
                    if !alreadyPlaying { startingID = shown.id }
                    Task {
                        await togglePlay(shown)
                        if startingID == shown.id { startingID = nil }
                    }
                } label: {
                    let busy = isBusy(shown)
                    Group {
                        if busy, env.kokoroStatus.status.isWarming {
                            WarmingDot()
                        } else if busy {
                            ProgressView().progressViewStyle(.circular).tint(Tokens.ink)
                        } else {
                            Image(systemName: env.player.current?.id == shown.id && env.player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Matches the `.disabled(isStarting)` guard BookSheet/QueueRow's Play pills already
                // carry: without it, a double-tap during the busy window re-enters `togglePlay()`
                // while `isPlaying` still reads true (it covers `.catchingUp`), which pauses
                // playback that had just started resuming.
                .disabled(isBusy(shown))
                .accessibilityLabel(isBusy(shown) ? "Loading" : (env.player.isPlaying ? "Pause" : "Play"))
                Button {
                    Task { await env.player.skip(by: 30) }
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(env.player.current == nil)
                .accessibilityLabel("Skip forward 30 seconds")
            }
            .foregroundStyle(Tokens.ink)
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Tokens.raised, in: Capsule())
            .shadow(color: Tokens.ink.opacity(0.08), radius: 12, y: 4)
            .padding(.horizontal, Spacing.margin)
            .contentShape(Capsule())
            .onTapGesture { onOpen(shown) }
        }
    }

    private func togglePlay(_ shown: DocumentSummary) async {
        if env.player.current?.id == shown.id {
            await env.player.togglePlay()
        } else {
            await env.player.load(shown, play: true)
        }
    }
}
