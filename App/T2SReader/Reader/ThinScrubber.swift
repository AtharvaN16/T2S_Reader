// App/T2SReader/Reader/ThinScrubber.swift
import SwiftUI
import T2SApp

/// The Reader page's progress bar (spec §2.4.5, after Apple Music and Podcasts): thick, no knob, the
/// app's only scrubber. With chapters it is one flat bar per chapter with a 3 pt gap between; a PDF
/// or text with none is a single unbroken bar. The played part is `ink`; ahead of it each of
/// `tickCount` segments still marks the render frontier — rendered `ink2`, unrendered `ink3` — so
/// "how much is ready ahead" stays visible without a legend. Pressing picks the chapter under the
/// finger: it rounds, stands taller, and widens to at least `activeShare` of the bar while the rest
/// shrink and dull, and the finger's travel across that widened bar maps onto that chapter alone —
/// precise scrubbing inside a chapter, however short it is on the whole. The seek fires on release.
struct ThinScrubber: View {
    var model: ScrubberModel
    /// Chapter spans as fractions of the whole, in order. Fewer than two draws one bar.
    var segments: [Range<Double>] = []
    /// Bookmarks as fractions of the whole, in any order. Drawn only while the bar is pressed, and
    /// only for the chapter under the finger (2026-09-11 spec §8): at rest the bar is 6 pt and
    /// already carries the render frontier, and a dulled 11 pt-wide chapter would show a smear.
    var bookmarkFractions: [Double] = []
    var onSeek: (Double) -> Void
    @State private var dragFraction: Double?
    /// The chapter under the finger while pressed; the layout widens it.
    @State private var activeIndex: Int?

    /// Resting and pressed bar heights; the hit area is the 44 pt frame either way.
    private static let restingHeight: CGFloat = 6
    private static let pressedHeight: CGFloat = 12
    private static let gap: CGFloat = 3
    /// The pressed chapter's share of the bar, at least: room to scrub inside it.
    private static let activeShare: Double = 0.45

    private var spans: [Range<Double>] { segments.count > 1 ? segments : [0..<1] }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fraction = dragFraction ?? model.fraction
            let ranges = layout(width: width)
            let pressed = dragFraction != nil
            ZStack(alignment: .leading) {
                ForEach(Array(spans.enumerated()), id: \.offset) { i, span in
                    let leading: CGFloat = i == 0 ? 0 : Self.gap / 2
                    let trailing: CGFloat = i == spans.count - 1 ? 0 : Self.gap / 2
                    let isActive = activeIndex == i
                    segment(span, width: max(1, ranges[i].upperBound - ranges[i].lowerBound - leading - trailing),
                            height: isActive ? Self.pressedHeight : Self.restingHeight, rounded: isActive, fraction: fraction)
                        .opacity(pressed && !isActive ? 0.5 : 1)
                        .offset(x: ranges[i].lowerBound + leading)
                }
            }
            .frame(width: width, height: Self.pressedHeight, alignment: .leading)
            .animation(.spring(duration: 0.25), value: activeIndex)
            // Low in the hit area: the finger lands above the bar, and the times sit close below it.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in scrub(to: value.location.x, width: width) }
                    .onEnded { _ in
                        if let f = dragFraction { onSeek(f) }
                        dragFraction = nil
                        activeIndex = nil
                    }
            )
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel("Scrubber")
        .accessibilityValue("\(Int((model.fraction * 100).rounded())) percent")
    }

    /// Visual x-range per span. Pressed, the active span widens to `activeShare` of the bar when it
    /// is narrower, and the rest share what is left in proportion; otherwise each has its own share.
    private func layout(width: CGFloat) -> [Range<CGFloat>] {
        let spans = spans
        var shares = spans.map { $0.upperBound - $0.lowerBound }
        let total = shares.reduce(0, +)
        shares = total > 0 ? shares.map { $0 / total } : spans.map { _ in 1 / Double(spans.count) }
        if let a = activeIndex, spans.count > 1, shares[a] < Self.activeShare {
            let scale = (1 - Self.activeShare) / max(.leastNonzeroMagnitude, 1 - shares[a])
            for i in shares.indices { shares[i] = i == a ? Self.activeShare : shares[i] * scale }
        }
        var x: CGFloat = 0
        return shares.map { share in
            let w = CGFloat(share) * width
            defer { x += w }
            return x..<(x + w)
        }
    }

    /// The finger picks the chapter under it, then travels inside that chapter's (widened) bar.
    private func scrub(to rawX: CGFloat, width: CGFloat) {
        let x = min(width, max(0, rawX))
        let under = layout(width: width).firstIndex { $0.contains(x) } ?? spans.count - 1
        if activeIndex != under { activeIndex = under }
        let r = layout(width: width)[under]                                 // after the switch, so the widened bar
        let local = Double(min(1, max(0, (x - r.lowerBound) / max(1, r.upperBound - r.lowerBound))))
        let span = spans[under]
        dragFraction = span.lowerBound + local * (span.upperBound - span.lowerBound)
    }

    /// One chapter's bar: its ticks underneath, the played part on top, square-ended unless active.
    private func segment(_ span: Range<Double>, width: CGFloat, height: CGFloat, rounded: Bool, fraction: Double) -> some View {
        let length = max(span.upperBound - span.lowerBound, .leastNonzeroMagnitude)
        let played = min(1, max(0, (fraction - span.lowerBound) / length))
        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(ticks(in: span), id: \.self) { t in
                    Rectangle().fill(model.renderedTicks[t] ? Tokens.ink2 : Tokens.ink3)
                }
            }
            /// Only the layout springs. The seek is async, so on release `fraction` falls back to the
            /// stale model value for a beat — animating the width would show the fill slide back.
            Rectangle()
                .fill(Tokens.ink)
                .frame(width: width * played)
                .transaction { $0.animation = nil }
            if rounded {
                ForEach(Array(dots(in: span).enumerated()), id: \.offset) { _, local in
                    Circle()
                        .fill(Tokens.accent)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Tokens.ground, lineWidth: 2.5))
                        .offset(x: width * local - 5)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: rounded ? height / 2 : 0, style: .continuous))
    }

    /// The ticks overlapping this chapter; at least the one under its start.
    private func ticks(in span: Range<Double>) -> [Int] {
        let n = model.tickCount
        guard n > 0 else { return [] }
        let first = min(n - 1, max(0, Int(span.lowerBound * Double(n))))
        let last = min(n - 1, max(first, Int((span.upperBound * Double(n)).rounded(.up)) - 1))
        return Array(first...last)
    }

    /// The bookmarks inside this chapter, as 0…1 along the chapter itself.
    private func dots(in span: Range<Double>) -> [Double] {
        let length = max(span.upperBound - span.lowerBound, .leastNonzeroMagnitude)
        return bookmarkFractions
            .filter { $0 >= span.lowerBound && $0 <= span.upperBound }
            .map { min(1, max(0, ($0 - span.lowerBound) / length)) }
    }
}
