import SwiftUI
import T2SApp

/// Sleep timer · back 15 · play · forward 30 · speed — the Reader page's transport row (spec
/// §2.4.5, after ElevenReader). Size and weight rank the controls: play is the biggest (44pt glyph
/// in 72), the skips second (28 in 52), both at regular weight so size does the ranking rather than
/// heft, and the three huddle 12 pt apart as one transport unit in the middle; the sleep timer and
/// the speed label are the small pair at the ends — one glyph weight, one type weight, both in
/// `ink2` — flush with the margins so their centres line up with the tool row's circles below.
/// Skip amounts stay synchronized with the reading preferences.
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
                size: 20, frame: 36, action: onSleepTimer
            )
            .foregroundStyle(Tokens.ink2)
            Spacer()
            HStack(spacing: 12) {
                control(
                    "gobackward.\(preferences.skipBackSeconds)", "Back \(preferences.skipBackSeconds) seconds",
                    size: 28, frame: 52
                ) {
                    Task { await player.skip(by: -Double(preferences.skipBackSeconds)) }
                }
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
                control(
                    "goforward.\(preferences.skipForwardSeconds)", "Forward \(preferences.skipForwardSeconds) seconds",
                    size: 28, frame: 52
                ) {
                    Task { await player.skip(by: Double(preferences.skipForwardSeconds)) }
                }
            }
            Spacer()
            Button(action: onSpeed) {
                /// Tabular digits so "1x" → "1.5x" changes width only by the added glyphs.
                Text(SpeedPickerModel.label(for: player.coordinator.rate))
                    .monospacedDigit()
                    .typeRole(.rowTitle)
                    .foregroundStyle(Tokens.ink2)
                    .frame(minWidth: 36)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed")
        }
        .foregroundStyle(Tokens.ink)
        .frame(height: 72)                                                 // no side padding: ends align with the circles below
    }

    /// `size` is the glyph's point size and `frame` its square tap target.
    private func control(
        _ glyph: String, _ label: String, size: CGFloat, frame: CGFloat, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: size, weight: .regular))
                .frame(width: frame, height: frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
