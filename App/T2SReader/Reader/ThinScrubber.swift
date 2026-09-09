// App/T2SReader/Reader/ThinScrubber.swift
import SwiftUI
import T2SApp

/// The Reader page's progress bar (spec §2.4.5, after Apple Music): one thick continuous track, no
/// knob, the app's only scrubber. The played part is `ink`; ahead of it each of `tickCount`
/// segments still marks the render frontier — rendered `ink2`, unrendered `ink3` — so "how much is
/// ready ahead" stays visible without a legend. Pressing thickens the whole bar in place and a drag
/// across the 44pt hit area scrubs; the seek fires on release.
struct ThinScrubber: View {
    var model: ScrubberModel
    var onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    /// Resting and pressed track heights; the hit area is the 44pt frame either way.
    private static let restingHeight: CGFloat = 6
    private static let pressedHeight: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fraction = dragFraction ?? model.fraction
            let isPressed = dragFraction != nil
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<model.tickCount, id: \.self) { i in
                        Rectangle().fill(model.renderedTicks[i] ? Tokens.ink2 : Tokens.ink3)
                    }
                }
                /// Only the height springs. The seek is async, so on release `fraction` falls back
                /// to the stale model value for a beat — animating the width would show the fill
                /// slide backwards and then jump.
                Rectangle()
                    .fill(Tokens.ink)
                    .frame(width: width * fraction)
                    .transaction { $0.animation = nil }
            }
            .frame(height: isPressed ? Self.pressedHeight : Self.restingHeight)
            .clipShape(Capsule())
            .animation(.spring(duration: 0.25), value: isPressed)
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
}
