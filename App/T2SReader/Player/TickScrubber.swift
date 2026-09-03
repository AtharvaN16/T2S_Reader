// App/T2SReader/Player/TickScrubber.swift
import SwiftUI
import T2SApp

/// Spec §2.4.5: uniform tick marks, rendered in `ink`, unrendered in `ink3`, so the render frontier
/// is visible without a legend. Drag anywhere to scrub; the seek fires on release.
struct TickScrubber: View {
    var model: ScrubberModel
    var onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fraction = dragFraction ?? model.fraction
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<model.tickCount, id: \.self) { i in
                        Capsule()
                            .fill(model.renderedTicks[i] ? Tokens.ink : Tokens.ink3)
                            .frame(width: 2, height: 14)
                        if i < model.tickCount - 1 { Spacer(minLength: 0) }
                    }
                }
                Capsule()
                    .fill(Tokens.ink)
                    .frame(width: 3, height: 22)
                    .offset(x: max(0, min(width - 3, width * fraction - 1.5)))
            }
            .frame(height: 22)                                          // the visuals stay 22pt…
            .frame(maxWidth: .infinity, maxHeight: .infinity)            // …centred in a 44pt hit area
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
