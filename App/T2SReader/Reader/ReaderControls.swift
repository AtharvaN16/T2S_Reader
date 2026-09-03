import SwiftUI
import T2SApp

/// Back · play · forward · speed in the Reader bottom bar. Skip amounts stay synchronized with
/// the reading preferences.
struct ReaderControls: View {
    @Environment(AppEnvironment.self) private var env
    var onSpeed: () -> Void

    var body: some View {
        let player = env.player
        let preferences = env.preferences
        HStack(spacing: 0) {
            Spacer()
            control("gobackward.\(preferences.skipBackSeconds)", "Back \(preferences.skipBackSeconds) seconds") {
                Task { await player.skip(by: -Double(preferences.skipBackSeconds)) }
            }
            Button {
                Task { await player.togglePlay() }
            } label: {
                Group {
                    if player.isCatchingUp {
                        ProgressView().progressViewStyle(.circular).tint(Tokens.ink)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .semibold))
                    }
                }
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            control("goforward.\(preferences.skipForwardSeconds)", "Forward \(preferences.skipForwardSeconds) seconds") {
                Task { await player.skip(by: Double(preferences.skipForwardSeconds)) }
            }
            Spacer()
            Button(action: onSpeed) {
                Text(SpeedPickerModel.label(for: player.coordinator.rate))
                    .typeRole(.mono)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed")
        }
        .foregroundStyle(Tokens.ink)
        .padding(.horizontal, Spacing.grid)
        .frame(height: 56)
    }

    private func control(_ glyph: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
