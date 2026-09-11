// App/T2SReader/Design/RaisedButton.swift
import SwiftUI

/// The raised button: a capsule that reads as a physical key — the owner's reference
/// (2026-09-10) is a "Join school" pill, blue, lit from above, with a soft coloured shadow under
/// it. The face falls from a lit top to a shaded foot, a bevel hairline runs bright along the
/// top rim and dark along the bottom, and two shadows lift it — a tight contact one and a wide
/// one in the face's own hue. A press sinks it: the light goes out of it, the shadow tightens,
/// it scales down a little.
///
/// Two tones. `.blue` is the reference's own (`Tokens.keyTop` → `keyBottom`): the empty shelf's
/// one "do this first". `.ink` is the app's black button raised (owner, 2026-09-10: "replace the
/// black buttons with skeuomorphic versions") — the bar at the foot of an Import step, the Voice
/// page's confirm, the Reader's skip pill. In the dark the ink key is graphite, not white: see
/// `Tokens.keyInkTop`. Three sizes: `.bar` fills its width at 56 pt (what `BarButton` is),
/// `.key` hugs its label at 56, `.compact` hugs it at 40 for a pill in the Reader.
///
/// Disabled it is not a key at all but the flat `surface` slab `BarButton` always showed while
/// there was nothing to act on — a raised key that cannot be pressed would be a lie; `busyLabel`
/// puts a spinner in front of the words while the model works and disables it the same way.
struct RaisedButton: View {
    enum Tone { case blue, ink }
    enum Size { case bar, key, compact }

    var label: String
    var glyph: String? = nil
    var tone: Tone = .blue
    var size: Size = .key
    var busyLabel: String? = nil
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        let busy = busyLabel != nil
        let enabled = isEnabled && !busy
        Button(action: action) {
            HStack(spacing: size == .compact ? 6 : 8) {
                if busy { ProgressView().tint(Tokens.ink2) }
                else if let glyph { Image(systemName: glyph).font(.system(size: size == .compact ? 13 : 15, weight: .bold)) }
                Text(busyLabel ?? label).typeRole(size == .compact ? .pill : .sectionHeader)
            }
            .lineLimit(1)
            .fixedSize(horizontal: size != .bar, vertical: false)
            .foregroundStyle(enabled ? face.text : Tokens.ink2)
            .padding(.horizontal, size == .compact ? 18 : 36)
            .frame(maxWidth: size == .bar ? .infinity : nil)
            .frame(minHeight: size == .compact ? 40 : 56)
            .contentShape(Capsule())
        }
        .buttonStyle(RaisedStyle(face: face, raised: enabled))
        .disabled(!enabled)
        .animation(.snappy, value: enabled)
    }

    private var face: RaisedFace {
        switch tone {
        case .blue: return RaisedFace(top: Tokens.keyTop, bottom: Tokens.keyBottom, halo: Tokens.glow, rim: Tokens.gloss.opacity(0.75), text: Tokens.onAccent)
        case .ink: return RaisedFace(top: Tokens.keyInkTop, bottom: Tokens.keyInkBottom, halo: Tokens.shade, rim: Tokens.keyInkRim, text: Tokens.onKeyInk)
        }
    }
}

/// What a tone paints: the face's two ends, the wide shadow's hue, the top rim's light, the words.
private struct RaisedFace {
    var top: Color
    var bottom: Color
    var halo: Color
    var rim: Color
    var text: Color
}

private struct RaisedStyle: ButtonStyle {
    var face: RaisedFace
    /// False while disabled: the flat slab, no bevel, no shadow, no press.
    var raised: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && raised
        configuration.label
            .background {
                if raised {
                    Capsule()
                        .fill(LinearGradient(colors: [face.top, face.bottom], startPoint: .top, endPoint: .bottom))
                        // Light from above: a gloss that is gone by the middle, shade gathering at the foot.
                        .overlay {
                            Capsule().fill(LinearGradient(stops: [
                                .init(color: Tokens.gloss.opacity(0.22), location: 0),
                                .init(color: Tokens.gloss.opacity(0.04), location: 0.42),
                                .init(color: Tokens.shade.opacity(0), location: 0.55),
                                .init(color: Tokens.shade.opacity(0.20), location: 1),
                            ], startPoint: .top, endPoint: .bottom))
                        }
                        // The bevel: the rim light along the top, a dark hairline along the bottom.
                        .overlay {
                            Capsule().strokeBorder(LinearGradient(stops: [
                                .init(color: face.rim, location: 0),
                                .init(color: face.rim.opacity(0), location: 0.45),
                                .init(color: Tokens.shade.opacity(0), location: 0.55),
                                .init(color: Tokens.shade.opacity(0.38), location: 1),
                            ], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                        }
                        // Pressed: the light goes out of it.
                        .overlay { Capsule().fill(Tokens.shade.opacity(pressed ? 0.18 : 0)) }
                } else {
                    Capsule().fill(Tokens.surface)
                }
            }
            .compositingGroup()                                                // one shadow for the key, not one per layer
            .shadow(color: Tokens.shade.opacity(!raised ? 0 : pressed ? 0.10 : 0.16), radius: pressed ? 1 : 2, y: pressed ? 0.5 : 1.5)
            .shadow(color: face.halo.opacity(!raised ? 0 : pressed ? 0.22 : 0.40), radius: pressed ? 8 : 18, y: pressed ? 4 : 10)
            .scaleEffect(pressed ? 0.965 : 1)
            .animation(.snappy(duration: 0.18), value: pressed)
    }
}
