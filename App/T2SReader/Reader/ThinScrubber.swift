// App/T2SReader/Reader/ThinScrubber.swift
import SwiftUI
import T2SApp

/// The Reader page's progress bar (spec §2.4.5, after ElevenReader): a thin continuous track
/// rather than the Player sheet's tick marks (`TickScrubber`, which stays there unchanged). Each
/// of `tickCount` segments still marks the render frontier — rendered `ink`, unrendered `ink3` —
/// so it stays visible without a legend; a small knob follows the fraction. Drag anywhere across
/// the 44pt hit area to scrub; the seek fires on release.
struct ThinScrubber: View {
    var model: ScrubberModel
    var onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    private static let trackHeight: CGFloat = 3
    private static let knobDiameter: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fraction = dragFraction ?? model.fraction
            ZStack(alignment: .leading) {
                HStack(spacing: 1) {
                    ForEach(0..<model.tickCount, id: \.self) { i in
                        Rectangle().fill(model.renderedTicks[i] ? Tokens.ink : Tokens.ink3)
                    }
                }
                .frame(height: Self.trackHeight)
                .clipShape(Capsule())
                Circle()
                    .fill(Tokens.ink)
                    .frame(width: Self.knobDiameter, height: Self.knobDiameter)
                    .offset(x: max(0, min(width - Self.knobDiameter, width * fraction - Self.knobDiameter / 2)))
            }
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
