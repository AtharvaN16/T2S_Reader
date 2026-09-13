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
///
/// `scope` (2026-09-13) is that same widening taken to its limit: `.chapter` pins the zoom to the
/// playhead's chapter at a share of 1, so the bar becomes one unbroken rounded chapter across the
/// whole width and every other chapter collapses out of it. Deliberately not a second layout —
/// there is one place where a chapter's width is decided, and both the press and the scope go
/// through it, so the two can never disagree about where a chapter starts.
struct ThinScrubber: View {
    var model: ScrubberModel
    /// Chapter spans as fractions of the whole, in order. Fewer than two draws one bar.
    var segments: [Range<Double>] = []
    /// Bookmarks as fractions of the whole, in any order. Drawn only while the bar is pressed, and
    /// only for the chapter under the finger (2026-09-11 spec §8): at rest the bar is 6 pt and
    /// already carries the render frontier, and a dulled 11 pt-wide chapter would show a smear.
    var bookmarkFractions: [Double] = []
    /// What the bar spans. `.chapter` needs `currentChapter`; without one it falls back to `.book`.
    var scope: ScrubberScope = .book
    /// The playhead's chapter — what `.chapter` zooms to.
    var currentChapter: Int?
    var onSeek: (Double) -> Void
    /// The chapter under the finger while scrubbing, so the picker above can name where you are
    /// about to land; nil the moment the finger lifts (owner, 2026-09-12).
    var onScrub: ((Int?) -> Void)? = nil
    @State private var dragFraction: Double?
    /// The chapter under the finger while pressed; the layout widens it.
    @State private var activeIndex: Int?

    /// Resting and pressed bar heights; the hit area is the 44 pt frame either way.
    private static let restingHeight: CGFloat = 6
    private static let pressedHeight: CGFloat = 12
    private static let gap: CGFloat = 3
    /// The pressed chapter's share of the bar, at least: room to scrub inside it.
    private static let activeShare: Double = 0.45
    /// The bookmark marks above the bar: small enough to read as punctuation over a 6 pt bar
    /// rather than as a second row of controls.
    private static let dotSize: CGFloat = 4
    private static let dotGap: CGFloat = 3
    /// The scope change is slower than the chip that asks for it (0.28), so the bar reads as the
    /// consequence of the tap rather than a co-event.
    private static let scopeSpring = Animation.spring(duration: 0.34, bounce: 0.18)

    private var spans: [Range<Double>] { segments.count > 1 ? segments : [0..<1] }

    /// The chapter the layout widens and how much of the bar it takes. Scope wins over the press:
    /// pressing a bar that is already one chapter wide must not shrink it back to 45%.
    private var zoom: (index: Int, share: Double)? {
        if scope == .chapter, let c = zoomedChapter { return (c, 1) }
        if let a = activeIndex { return (a, Self.activeShare) }
        return nil
    }

    /// The chapter `.chapter` scope pins to, or nil when there is nothing to pin to — a document
    /// with one chapter or none draws its single bar either way.
    private var zoomedChapter: Int? {
        guard segments.count > 1, let c = currentChapter, spans.indices.contains(c) else { return nil }
        return c
    }

    private var isChapterScoped: Bool { zoom?.share == 1 }
    /// Zero while one chapter owns the whole bar: a 1.5 pt half-gap either side would leave the
    /// full-width bar short of both margins and offset from the clocks under it.
    private var gap: CGFloat { isChapterScoped ? 0 : Self.gap }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fraction = dragFraction ?? model.fraction
            let ranges = layout(width: width)
            let pressed = dragFraction != nil
            ZStack(alignment: .leading) {
                ForEach(Array(spans.enumerated()), id: \.offset) { i, span in
                    let leading: CGFloat = i == 0 ? 0 : gap / 2
                    let trailing: CGFloat = i == spans.count - 1 ? 0 : gap / 2
                    let isZoomed = zoom?.index == i
                    segment(span, width: max(1, ranges[i].upperBound - ranges[i].lowerBound - leading - trailing),
                            height: isZoomed ? Self.pressedHeight : Self.restingHeight, rounded: isZoomed,
                            isCurrent: zoomedChapter == i,
                            chapterTicks: isZoomed && isChapterScoped, fraction: fraction)
                        .opacity(opacity(of: i, pressed: pressed))
                        .offset(x: ranges[i].lowerBound + leading)
                }
            }
            .frame(width: width, height: Self.pressedHeight, alignment: .leading)
            // Above the bar rather than on it (owner, 2026-09-13). On it they were drawn inside
            // the segment's own `clipShape`, which is six points tall at rest and twelve pressed,
            // so a ten-point mark was shaved to a sliver — visible, and covered. Up here nothing
            // clips them, they need no ground ring to cut themselves out of the fill, and they can
            // stay up permanently instead of only under a finger.
            .overlay(alignment: .topLeading) { bookmarkDots(ranges: ranges) }
            .animation(.spring(duration: 0.25), value: activeIndex)
            .animation(Self.scopeSpring, value: scope)
            // Low in the hit area, but not on its floor: 14 pt rather than 4 (owner, 2026-09-13)
            // lifts the bar toward the chapter picker and opens the same 10 pt again under it,
            // where the scope chip now sits — without shrinking the 40 pt frame the finger aims at.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in scrub(to: value.location.x, width: width) }
                    .onEnded { _ in
                        if let f = dragFraction { onSeek(f) }
                        dragFraction = nil
                        activeIndex = nil
                        onScrub?(nil)
                    }
            )
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel("Scrubber")
        // The same percentage means two different things in the two scopes, so the scope is part
        // of the value rather than a hint that a VoiceOver reader would have to ask for.
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let percent = Int((model.fraction * 100).rounded())
        guard isChapterScoped, let c = zoomedChapter else { return "\(percent) percent" }
        let span = spans[c]
        let length = max(span.upperBound - span.lowerBound, .leastNonzeroMagnitude)
        let local = Int((min(1, max(0, (model.fraction - span.lowerBound) / length)) * 100).rounded())
        return "\(local) percent of chapter \(c + 1)"
    }

    /// Collapsed chapters are gone, not merely narrow: `max(1, …)` keeps every segment a point
    /// wide so the layout maths never divides by zero, and a row of 1 pt slivers either side of
    /// the chapter bar would read as dirt on the glass.
    private func opacity(of index: Int, pressed: Bool) -> Double {
        if isChapterScoped { return zoom?.index == index ? 1 : 0 }
        return pressed && activeIndex != index ? 0.5 : 1
    }

    /// Visual x-range per span. The zoomed span takes `zoom.share` of the bar when it is narrower
    /// than that, and the rest share what is left in proportion; otherwise each has its own share.
    /// At a share of 1 the rest are left with nothing, which is chapter scope.
    private func layout(width: CGFloat) -> [Range<CGFloat>] {
        let spans = spans
        var shares = spans.map { $0.upperBound - $0.lowerBound }
        let total = shares.reduce(0, +)
        shares = total > 0 ? shares.map { $0 / total } : spans.map { _ in 1 / Double(spans.count) }
        if let zoom, spans.count > 1, shares[zoom.index] < zoom.share {
            let scale = (1 - zoom.share) / max(.leastNonzeroMagnitude, 1 - shares[zoom.index])
            for i in shares.indices { shares[i] = i == zoom.index ? zoom.share : shares[i] * scale }
        }
        var x: CGFloat = 0
        return shares.map { share in
            let w = CGFloat(share) * width
            defer { x += w }
            return x..<(x + w)
        }
    }

    /// The finger picks the chapter under it, then travels inside that chapter's (widened) bar. In
    /// chapter scope the chapter is already chosen, and picking by hit-test would be wrong at the
    /// far edge: the collapsed chapters after it all start at `width`, so a drag to the right end
    /// would land in the last chapter of the book.
    private func scrub(to rawX: CGFloat, width: CGFloat) {
        let x = min(width, max(0, rawX))
        let under = zoomedChapter.flatMap { scope == .chapter ? $0 : nil }
            ?? (layout(width: width).firstIndex { $0.contains(x) } ?? spans.count - 1)
        if activeIndex != under {
            activeIndex = under
            onScrub?(under)
        }
        let r = layout(width: width)[under]                                 // after the switch, so the widened bar
        let local = Double(min(1, max(0, (x - r.lowerBound) / max(1, r.upperBound - r.lowerBound))))
        let span = spans[under]
        dragFraction = span.lowerBound + local * (span.upperBound - span.lowerBound)
    }

    /// One chapter's bar: its ticks underneath, the played part on top, square-ended unless zoomed.
    private func segment(_ span: Range<Double>, width: CGFloat, height: CGFloat, rounded: Bool,
                         isCurrent: Bool, chapterTicks: Bool, fraction: Double) -> some View {
        let length = max(span.upperBound - span.lowerBound, .leastNonzeroMagnitude)
        let played = min(1, max(0, (fraction - span.lowerBound) / length))
        return ZStack(alignment: .leading) {
            // Two frontiers, cross-faded rather than swapped: the book pass gives this chapter
            // about five of the 48 ticks, which stretched over the whole bar is a smear, and the
            // chapter pass squeezed into a tenth of the bar is sub-point. Changing the tick *count*
            // mid-spring re-lays-out the fill under a bar that is still moving, which flickers; a
            // cross-fade of two fixed grids does not.
            //
            // Only the playhead's own chapter carries the second grid. It used to be drawn by every
            // segment — the condition was on the array being non-empty, which has nothing to do
            // with *which* bar this is — so a fourteen-chapter book built 672 tick views to show 48
            // of them (2026-09-13).
            tickRow(bookTicks(in: span)).opacity(chapterTicks ? 0 : 1)
            if isCurrent, !model.chapterTicks.isEmpty {
                tickRow(TickSlice(ticks: model.chapterTicks)).opacity(chapterTicks ? 1 : 0)
            }
            /// Only the layout springs. The seek is async, so on release `fraction` falls back to the
            /// stale model value for a beat — animating the width would show the fill slide back.
            Rectangle()
                .fill(Tokens.ink)
                .frame(width: width * played)
                .transaction { $0.animation = nil }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: rounded ? height / 2 : 0, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: chapterTicks)
    }

    /// The frontier as two fills rather than as one view per tick: unrendered ground, with the
    /// rendered runs drawn over it. `TickMarks` has no layout children, so a bar whose width is
    /// springing costs one path rebuild a frame instead of a width negotiation per tick.
    private func tickRow(_ ticks: TickSlice) -> some View {
        ZStack {
            Tokens.ink3
            TickMarks(ticks: ticks.ticks, slice: ticks.slice).fill(Tokens.ink2)
        }
    }

    /// The book-wide ticks overlapping this chapter; at least the one under its start. A range into
    /// the shared array rather than a copy of it: `Array(slice)` here allocated once per segment per
    /// body, and the body runs at 10 Hz while playing.
    private func bookTicks(in span: Range<Double>) -> TickSlice {
        let n = model.tickCount
        guard n > 0, model.renderedTicks.count == n else { return TickSlice(ticks: [], slice: 0..<0) }
        let first = min(n - 1, max(0, Int(span.lowerBound * Double(n))))
        let last = min(n - 1, max(first, Int((span.upperBound * Double(n)).rounded(.up)) - 1))
        return TickSlice(ticks: model.renderedTicks, slice: first..<(last + 1))
    }

    /// Every bookmark the bar can currently show, as a tick of its own above it. A bookmark is
    /// placed through the same `ranges` the segments are, so the marks travel with the chapters
    /// under them: in chapter scope they spread across the one bar that is left, and a collapsed
    /// chapter takes its marks with it rather than stacking them on the seam.
    @ViewBuilder private func bookmarkDots(ranges: [Range<CGFloat>]) -> some View {
        let pressed = dragFraction != nil
        ZStack(alignment: .topLeading) {
            ForEach(Array(spans.enumerated()), id: \.offset) { i, span in
                if opacity(of: i, pressed: pressed) > 0 {
                    let leading: CGFloat = i == 0 ? 0 : gap / 2
                    let trailing: CGFloat = i == spans.count - 1 ? 0 : gap / 2
                    let w = max(1, ranges[i].upperBound - ranges[i].lowerBound - leading - trailing)
                    ForEach(Array(dots(in: span).enumerated()), id: \.offset) { _, local in
                        Circle()
                            .fill(Tokens.accent)
                            .frame(width: Self.dotSize, height: Self.dotSize)
                            .offset(x: ranges[i].lowerBound + leading + w * local - Self.dotSize / 2,
                                    y: -(Self.dotSize + Self.dotGap))
                    }
                }
            }
        }
    }

    /// The bookmarks inside this chapter, as 0…1 along the chapter itself.
    private func dots(in span: Range<Double>) -> [Double] {
        let length = max(span.upperBound - span.lowerBound, .leastNonzeroMagnitude)
        return bookmarkFractions
            .filter { $0 >= span.lowerBound && $0 <= span.upperBound }
            .map { min(1, max(0, ($0 - span.lowerBound) / length)) }
    }
}

/// A window onto a shared tick array, so passing one costs nothing.
struct TickSlice: Equatable {
    var ticks: [Bool]
    var slice: Range<Int>

    init(ticks: [Bool], slice: Range<Int>? = nil) {
        self.ticks = ticks
        self.slice = slice ?? 0..<ticks.count
    }
}

/// The rendered part of a frontier, as merged rectangles. A realistic frontier — the opening ready
/// and a patch the reader jumped ahead to — is two or three of them rather than forty-eight views.
private struct TickMarks: Shape {
    var ticks: [Bool]
    var slice: Range<Int>

    func path(in rect: CGRect) -> Path {
        let count = min(ticks.count, slice.upperBound) - max(0, slice.lowerBound)
        guard count > 0 else { return Path() }
        let width = rect.width / CGFloat(count)
        var path = Path()
        for run in ScrubberModel.runs(of: true, in: ticks, over: slice) {
            path.addRect(CGRect(x: CGFloat(run.lowerBound) * width, y: 0,
                                width: CGFloat(run.count) * width, height: rect.height))
        }
        return path
    }
}
