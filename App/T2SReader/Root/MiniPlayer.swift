// App/T2SReader/Root/MiniPlayer.swift
import SwiftUI
import T2SStore

/// Spec §2.4.4: artwork, title, play/pause, skip-forward. Shows the playing item, or the next
/// queued item with "Play" when idle. Tap expands to the player sheet.
struct MiniPlayer: View {
    @Environment(AppEnvironment.self) private var env
    var onExpand: () -> Void

    private var shown: DocumentSummary? { env.player.current ?? env.libraryModel.queue.first }

    var body: some View {
        if let shown {
            HStack(spacing: 12) {
                Artwork(relativePath: shown.document.coverImagePath, paths: env.paths, size: 36, radius: Spacing.artworkSmall)
                Text(shown.document.title)
                    .typeRole(.rowTitle)
                    .lineLimit(1)
                    .foregroundStyle(Tokens.ink)
                Spacer(minLength: 8)
                Button {
                    Task { await togglePlay(shown) }
                } label: {
                    Image(systemName: env.player.current?.id == shown.id && env.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(env.player.isPlaying ? "Pause" : "Play")
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
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .padding(.horizontal, Spacing.margin)
            .contentShape(Capsule())
            .onTapGesture(perform: onExpand)
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
