// App/T2SReader/Onboarding/PointingArrow.swift
import SwiftUI

/// A hand-drawn curve with an arrowhead, pointing up from the Play key to the settled book, that
/// bobs gently (the ATC replay app's "listen to this replay" arrow; the owner, 2026-09-14:
/// "animate an arrow pointing to the book"). Still under Reduce Motion.
struct PointingArrow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bobbing = false

    var body: some View {
        ArrowShape()
            .stroke(Tokens.ink2, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 56, height: 96)
            .offset(y: bobbing ? -6 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: bobbing)
            .onAppear { bobbing = true }
            .accessibilityHidden(true)
    }

    /// From the bottom right, curving up and left to a head at the top.
    private struct ArrowShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let start = CGPoint(x: rect.maxX - 6, y: rect.maxY - 2)
            let end = CGPoint(x: rect.midX - 6, y: rect.minY + 4)
            p.move(to: start)
            p.addQuadCurve(to: end, control: CGPoint(x: rect.maxX + 4, y: rect.minY + 14))
            // The head: two short strokes back from the tip.
            p.move(to: end)
            p.addLine(to: CGPoint(x: end.x - 7, y: end.y + 8))
            p.move(to: end)
            p.addLine(to: CGPoint(x: end.x + 8, y: end.y + 6))
            return p
        }
    }
}
