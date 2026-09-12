// App/T2SReader/Root/MiniPlayer.swift
import SwiftUI
import T2SStore

/// Spec §2.4.4: artwork, title, play/pause, skip-forward. Shows the playing item, or the next
/// queued item with "Play" when idle. Tap opens the Reader on the shown item.
///
/// Taller since 2026-09-12, and standing lower: the page marks below it took half the height the
/// icons there needed, and the owner asked for the room to go here. The cover grew with it. The
/// capsule's top edge has not moved — the whole of the 12 pt goes downward, into the space the
/// marks gave up — so nothing above the player had to be re-measured for it.
struct MiniPlayer: View {
    /// The cover's side, and the padding above and below it: together they are the capsule's height.
    static let artwork: CGFloat = 40
    static let vertical: CGFloat = 12
    /// What the capsule stands: what `RootPager` measures the page's bottom clearance from.
    static var height: CGFloat { artwork + 2 * vertical }

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
                Artwork(relativePath: shown.document.coverImagePath, paths: env.paths, size: Self.artwork, radius: Spacing.artworkSmall,
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
            // The cover was all but touching the rim (owner, 2026-09-12), and the reason is that a
            // capsule's end is a half-circle: 8 pt of padding is 8 pt at the widest point of the
            // curve and almost nothing at the height of a corner. At the old 36 pt cover in a 52 pt
            // capsule the corner cleared the rim by three quarters of a point. It is 14 now, into a
            // capsule 12 pt taller, which leaves the corner a genuine 7 — measured the same way:
            // the rim at the corner's height sits 7 pt in, so the gap you see is the padding beyond
            // that. The trailing side needs less; the controls there are round and their glyphs
            // stand well inside their frames.
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, Self.vertical)
            .background(Tokens.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Tokens.edge, lineWidth: 1))      // its rim in the dark, where the shadow is nothing
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
