// App/T2SReader/Player/ControlPill.swift
import SwiftUI
import T2SApp
import T2SCore

/// overflow | back 15 · play · forward 30 | speed (spec §2.4.5). The play glyph becomes a ring
/// while the coordinator is catching up (spec §3.6).
struct ControlPill: View {
    @Environment(AppEnvironment.self) private var env
    var onDetails: () -> Void

    var body: some View {
        let player = env.player
        HStack(spacing: 0) {
            Menu {
                Button { player.renderWholeDocument() } label: { Label("Render whole document", systemImage: "waveform") }
                Button(action: onDetails) { Label("Details", systemImage: "info.circle") }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            Spacer()
            control("gobackward.15", "Back 15 seconds") { Task { await player.skip(by: -15) } }
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
            control("goforward.30", "Forward 30 seconds") { Task { await player.skip(by: 30) } }
            Spacer()
            Menu {
                ForEach(RateLimits.allRates, id: \.self) { rate in
                    Button { player.setRate(rate) } label: {
                        Label(Self.rateText(rate), systemImage: Self.matches(player.coordinator.rate, rate) ? "checkmark" : "")
                    }
                    .disabled(!player.coordinator.availableRates.contains { Self.matches($0, rate) })
                }
            } label: {
                Text(Self.rateText(player.coordinator.rate)).typeRole(.mono).frame(width: 44, height: 44).contentShape(Rectangle())
            }
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

    static func rateText(_ rate: Double) -> String {
        rate == rate.rounded() ? "\(Int(rate))x" : String(format: "%.1fx", rate)
    }

    private static func matches(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }
}
