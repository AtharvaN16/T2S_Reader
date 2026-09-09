// App/T2SReader/Reader/ThinScrubber.swift
import SwiftUI
import T2SApp

/// The Reader page's progress bar (spec §2.4.5, after Apple Music and Podcasts): thick, no knob, the
/// app's only scrubber. With chapters it is one capsule per chapter with a 3 pt gap between; a PDF
/// or text with none is a single unbroken bar. The played part is `ink`; ahead of it each of
/// `tickCount` segments still marks the render frontier — rendered `ink2`, unrendered `ink3` — so
/// "how much is ready ahead" stays visible without a legend. Pressing thickens the chapter under
/// the finger and dulls the others, so scrubbing inside a chapter reads as inside it; the drag
/// across the 44 pt hit area still maps 1:1 to the whole, and the seek fires on release.
struct ThinScrubber: View {
    var model: ScrubberModel
    /// Chapter spans as fractions of the whole, in order. Fewer than two draws one bar.
    var segments: [Range<Double>] = []
    var onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    /// Resting and pressed capsule heights; the hit area is the 44 pt frame either way.
    private static let restingHeight: CGFloat = 6
    private static let pressedHeight: CGFloat = 12
    private static let gap: CGFloat = 3

    private var spans: [Range<Double>] { segments.count > 1 ? segments : [0..<1] }

    /// The chapter under the finger while pressed; the last one catches a drag past the end.
    private var activeIndex: Int? {
        guard let f = dragFraction else { return nil }
        return spans.firstIndex { $0.contains(f) } ?? spans.count - 1
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fraction = dragFraction ?? model.fraction
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<model.tickCount, id: \.self) { i in
                        Rectangle().fill(model.renderedTicks[i] ? Tokens.ink2 : Tokens.ink3)
                    }
                }
                /// Only the mask springs. The seek is async, so on release `fraction` falls back to
                /// the stale model value for a beat — animating the width would show the fill
                /// slide backwards and then jump.
                Rectangle()
                    .fill(Tokens.ink)
                    .frame(width: width * fraction)
                    .transaction { $0.animation = nil }
            }
            .frame(height: Self.pressedHeight)
            .mask(alignment: .leading) { segmentMask(width: width) }
            .animation(.spring(duration: 0.25), value: activeIndex)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = min(1, max(0, $0.location.x / width)) }
                    .onEnded { value in
                        onSeek(min(1, max(0, value.location.x / width)))
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Scrubber")
        .accessibilityValue("\(Int((model.fraction * 100).rounded())) percent")
    }

    /// One capsule per span with the gaps clear between them. Pressed, the active span stands at
    /// full height and the rest sit at resting height and half opacity — the mask's alpha is what
    /// dulls them, so the played/frontier tones underneath need no second palette.
    private func segmentMask(width: CGFloat) -> some View {
        let active = activeIndex
        return ZStack(alignment: .leading) {
            ForEach(Array(spans.enumerated()), id: \.offset) { i, span in
                let leading = i == 0 ? 0 : Self.gap / 2
                let trailing = i == spans.count - 1 ? 0 : Self.gap / 2
                let x = CGFloat(span.lowerBound) * width + leading
                let w = max(1, CGFloat(span.upperBound - span.lowerBound) * width - leading - trailing)
                let isActive = active == i
                Capsule()
                    .fill(Tokens.ink.opacity(active == nil || isActive ? 1 : 0.5))
                    .frame(width: w, height: isActive ? Self.pressedHeight : Self.restingHeight)
                    .offset(x: x)
            }
        }
        .frame(width: width, height: Self.pressedHeight, alignment: .leading)
    }
}
