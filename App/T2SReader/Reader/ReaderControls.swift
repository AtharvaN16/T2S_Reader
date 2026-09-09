import SwiftUI
import T2SApp

/// Sleep timer · back 15 · play · forward 30 · speed — the Reader page's transport row (spec
/// §2.4.5, after ElevenReader), evenly spaced across the width. Size ranks the controls: play is
/// the biggest (44pt glyph in 72, regular weight so it is big without being heavy), the skips
/// second (32 in 56), the sleep timer stays small (20 in 44), and the speed label is bold body text
/// so it reads as a control rather than a caption. Skip amounts stay synchronized with the reading
/// preferences.
struct ReaderControls: View {
    @Environment(AppEnvironment.self) private var env
    var onSleepTimer: () -> Void
    var onSpeed: () -> Void

    var body: some View {
        let player = env.player
        let preferences = env.preferences
        HStack(spacing: 0) {
            control(
                env.sleepTimer.active == nil ? "moon.zzz" : "moon.zzz.fill", "Sleep timer",
                action: onSleepTimer
            )
            Spacer()
            control(
                "gobackward.\(preferences.skipBackSeconds)", "Back \(preferences.skipBackSeconds) seconds",
                size: 32, frame: 56
            ) {
                Task { await player.skip(by: -Double(preferences.skipBackSeconds)) }
            }
            Spacer()
            Button {
                Task { await player.togglePlay() }
            } label: {
                Group {
                    if env.isWarmingUp {
                        WarmingDot()
                    } else if player.isCatchingUp {
                        ProgressView().progressViewStyle(.circular).tint(Tokens.ink)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44, weight: .regular))
                    }
                }
                .frame(width: 72, height: 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityValue(player.isCatchingUp ? (env.isWarmingUp ? "Preparing the voice" : "Buffering") : "")
            Spacer()
            control(
                "goforward.\(preferences.skipForwardSeconds)", "Forward \(preferences.skipForwardSeconds) seconds",
                size: 32, frame: 56
            ) {
                Task { await player.skip(by: Double(preferences.skipForwardSeconds)) }
            }
            Spacer()
            Button(action: onSpeed) {
                /// Tabular digits so "1x" → "1.5x" changes width only by the added glyphs.
                Text(SpeedPickerModel.label(for: player.coordinator.rate))
                    .monospacedDigit()
                    .typeRole(.speed)
                    .frame(width: 52, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed")
        }
        .foregroundStyle(Tokens.ink)
        .padding(.horizontal, Spacing.grid)
        .frame(height: 72)
    }

    /// `size` is the glyph's point size and `frame` its square tap target; the defaults are the
    /// sleep timer's, the smallest rank.
    private func control(
        _ glyph: String, _ label: String, size: CGFloat = 20, frame: CGFloat = 44, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: size, weight: .medium))
                .frame(width: frame, height: frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
