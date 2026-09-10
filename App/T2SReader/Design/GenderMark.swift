// App/T2SReader/Design/GenderMark.swift
import SwiftUI
import T2SApp

/// ♀ / ♂ beside a voice's name (owner, 2026-09-10, in place of the tinted avatar disc): the Venus
/// and Mars signs drawn as strokes, pink and blue (`Tokens.voiceFemale` / `voiceMale`), bold like
/// the reference glyph. Drawn, not typed: the Unicode signs fall back to emoji on some keyboards.
struct GenderMark: View {
    var gender: VoiceGender
    var size: CGFloat = 14

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width, h = canvasSize.height
            let line = size * 0.16
            var path = Path()
            switch gender {
            case .female:
                // A ring in the upper part, a stem down from it, a bar across the stem.
                let r = w * 0.32
                let center = CGPoint(x: w / 2, y: r + line / 2)
                path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                path.move(to: CGPoint(x: center.x, y: center.y + r))
                path.addLine(to: CGPoint(x: center.x, y: h - line / 2))
                let barY = center.y + r + (h - line / 2 - center.y - r) * 0.55
                path.move(to: CGPoint(x: center.x - r * 0.75, y: barY))
                path.addLine(to: CGPoint(x: center.x + r * 0.75, y: barY))
            case .male:
                // A ring in the lower left, an arrow out to the top right.
                let r = w * 0.32
                let center = CGPoint(x: r + line / 2, y: h - r - line / 2)
                path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                let tip = CGPoint(x: w - line / 2, y: line / 2)
                let start = CGPoint(x: center.x + r * 0.7071, y: center.y - r * 0.7071)
                path.move(to: start)
                path.addLine(to: tip)
                let head = w * 0.34
                path.move(to: CGPoint(x: tip.x - head, y: tip.y))
                path.addLine(to: tip)
                path.addLine(to: CGPoint(x: tip.x, y: tip.y + head))
            }
            context.stroke(path, with: .color(gender == .female ? Tokens.voiceFemale : Tokens.voiceMale),
                           style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(gender == .female ? "Female voice" : "Male voice")
    }
}

/// The favorite heart (owner, 2026-09-10): red and a little glossy — a top-lit gradient, a soft
/// highlight, a shadow under it — and it pops when it fills. Empty, it is the outline in `ink2`.
/// Sized to the row's radio so the two trailing marks read as one set.
struct HeartButton: View {
    var isOn: Bool
    var label: String
    var action: () -> Void
    @State private var pop = false

    var body: some View {
        Button {
            action()
            if !isOn {                                                                  // filling is what pops; emptying just empties
                pop = true
                Task { try? await Task.sleep(for: .milliseconds(180)); pop = false }
            }
        } label: {
            ZStack {
                if isOn {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(red: 1.0, green: 0.42, blue: 0.42), Color(red: 0.86, green: 0.09, blue: 0.16)],
                                           startPoint: .top, endPoint: .bottom))
                        .overlay {
                            // The gloss: a soft white ellipse over the top lobes.
                            Ellipse()
                                .fill(Color.white.opacity(0.45))
                                .frame(width: 11, height: 5)
                                .blur(radius: 1.2)
                                .offset(x: -3, y: -6)
                        }
                        .shadow(color: Color(red: 0.6, green: 0, blue: 0.05).opacity(0.35), radius: 2, x: 0, y: 1.5)
                } else {
                    Image(systemName: "heart")
                        .font(.system(size: 24))
                        .foregroundStyle(Tokens.ink2)
                }
            }
            .frame(width: 40, height: 40)
            .scaleEffect(pop ? 1.3 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.45), value: pop)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
