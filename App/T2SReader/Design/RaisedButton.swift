// App/T2SReader/Design/RaisedButton.swift
import SwiftUI

/// The one raised button: a capsule that reads as a physical key — the owner's reference
/// (2026-09-10) is a "Join school" pill, blue, lit from above, with a soft coloured shadow under
/// it. Here in the accent: the top rim catches light (`gloss`), the foot falls into shade, a bevel
/// hairline runs bright along the top and dark along the bottom, and two shadows lift it — a tight
/// contact one and a wide one in the accent's own hue. A press sinks it: the light goes out of it,
/// the shadow tightens, it scales down a little. `Pill(.accent)` stays the flat one-word action in a
/// header; this is for an empty page's single "do this first".
struct RaisedButton: View {
    var label: String
    var glyph: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let glyph { Image(systemName: glyph).font(.system(size: 15, weight: .bold)) }
                Text(label).typeRole(.sectionHeader)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Tokens.onAccent)
            .padding(.horizontal, 36)
            .frame(minHeight: 56)
            .contentShape(Capsule())
        }
        .buttonStyle(RaisedStyle())
    }
}

private struct RaisedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background {
                Capsule()
                    .fill(Tokens.accent)
                    // Light from above: a gloss that is gone by the middle, shade gathering at the foot.
                    .overlay {
                        Capsule().fill(LinearGradient(stops: [
                            .init(color: Tokens.gloss.opacity(0.32), location: 0),
                            .init(color: Tokens.gloss.opacity(0.06), location: 0.42),
                            .init(color: Tokens.shade.opacity(0), location: 0.55),
                            .init(color: Tokens.shade.opacity(0.20), location: 1),
                        ], startPoint: .top, endPoint: .bottom))
                    }
                    // The bevel: a bright hairline on the top rim, a dark one on the bottom.
                    .overlay {
                        Capsule().strokeBorder(LinearGradient(stops: [
                            .init(color: Tokens.gloss.opacity(0.75), location: 0),
                            .init(color: Tokens.gloss.opacity(0), location: 0.45),
                            .init(color: Tokens.shade.opacity(0), location: 0.55),
                            .init(color: Tokens.shade.opacity(0.38), location: 1),
                        ], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                    }
                    // Pressed: the light goes out of it.
                    .overlay { Capsule().fill(Tokens.shade.opacity(pressed ? 0.18 : 0)) }
            }
            .compositingGroup()                                                // one shadow for the key, not one per layer
            .shadow(color: Tokens.shade.opacity(pressed ? 0.10 : 0.16), radius: pressed ? 1 : 2, y: pressed ? 0.5 : 1.5)
            .shadow(color: Tokens.accent.opacity(pressed ? 0.20 : 0.40), radius: pressed ? 8 : 18, y: pressed ? 4 : 10)
            .scaleEffect(pressed ? 0.965 : 1)
            .animation(.snappy(duration: 0.18), value: pressed)
    }
}
