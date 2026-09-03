// App/T2SReader/Player/ControlPill.swift
import SwiftUI
import T2SApp

/// overflow | back 15 · play · forward 30 | speed (spec §2.4.5). The play glyph becomes a ring
/// while the coordinator is catching up (spec §3.6).
struct ControlPill: View {
    @Environment(AppEnvironment.self) private var env
    var onDetails: () -> Void
    var onSpeed: () -> Void

    var body: some View {
        let player = env.player
        let preferences = env.preferences
        HStack(spacing: 0) {
            Menu {
                Button { player.renderWholeDocument() } label: { Label("Render whole document", systemImage: "waveform") }
                Button(action: onDetails) { Label("Details", systemImage: "info.circle") }
                    .disabled(player.current == nil)                    // nothing loaded: the sheet would be empty
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }
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
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 26, weight: .semibold))
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
        }
        .foregroundStyle(Tokens.ink)
        .padding(.horizontal, 8)
        .frame(height: 64)
        .background(Tokens.surface, in: Capsule())
    }

    private func control(_ glyph: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
