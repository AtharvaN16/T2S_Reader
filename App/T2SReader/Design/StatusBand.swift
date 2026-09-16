// App/T2SReader/Design/StatusBand.swift
import Foundation
import SwiftUI
import T2SApp

/// The warm-up's three rows, under the status bar, over whatever is drawn there.
///
/// **Title, subtext, bar** (owner, 2026-09-12). A weighted line naming the phase, which never
/// moves. One faint row beneath it carrying two slots — words on the left, whatever is counting on
/// the right — of which only the words ever change. Then the bar, centred, with nothing beside it.
///
/// **What goes in the right slot, and when.** The megabytes while a download runs, then the clock
/// once one is over. Never both, and never the other way round: a download's remaining time is the
/// least trustworthy number the app has and the megabytes already say how far along it is, so the
/// first time a clock appears is also the first time one is backed by a remembered duration
/// (`expectedWarmUpSeconds`). The slot holds still while the left one cycles, because the time is
/// what a waiting reader is looking for and it cannot be the thing that rotates away.
///
/// **The row reserves its height, except at the end.** A phase with nothing to say keeps the row
/// blank rather than closing it — `.checking` has no message, and a row that collapsed there would
/// drop the bar 13 pt and pull it straight back when the download began. Ready is the exception:
/// nothing follows it but the fade, so the row closes and the bar rises to meet "Voice ready"
/// rather than leaving a gap under it.
///
/// Everything this view says is resolved by `StatusReading`, which is a plain value and is tested.
/// This file only draws it.
struct StatusRows: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.readerPalette) private var palette
    /// The safe-area top inset, from a host whose `GeometryProxy` still reports it: this view
    /// spans the screen with `ignoresSafeArea`, and a proxy under that reports the insets it now
    /// covers as zero.
    var band: CGFloat

    /// 88 × 5 (owner, 2026-09-12, choosing between four widths at true scale): thicker than the
    /// 120 × 3 hairline it replaces and narrower, so it reads as an object without becoming the
    /// download bar that 80 × 6 looked like.
    private static let barWidth: CGFloat = 88
    private static let barHeight: CGFloat = 5
    private static let segmentGap: CGFloat = 3

    /// How far below the safe-area inset the three rows reach, with a few points under the bar so
    /// the ground does not stop on its edge: 8 of top pad, the 11 pt title's ~14, the subtext row's
    /// 13 over its 2 of pad, and the bar's 5 under its 7. `TopFade` holds this much solid while the
    /// glow is up so the bar reads against ground rather than against a book row scrolled under it.
    /// The Ready row collapses 15 pt of this, and deliberately does not shrink the band: the glow is
    /// already fading out by then and a ground that stepped up on the last beat would be the one
    /// movement on screen that means nothing.
    static let bandHeight: CGFloat = 54

    var body: some View {
        let showing = env.appStatus.isShowing
        ZStack {
            if showing {
                // Half-second ticks: a retry counts down in whole seconds, and a one-second period
                // lands the change up to a second late on half of them.
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    // The slot is asked per frame rather than pushed at (`AppStatusModel`), so the
                    // rows and the rims read one model on one tick.
                    //
                    // The slot keeps answering through the fade, which is why the rows can draw
                    // from it right up to the last frame: the green, "Voice ready" and the full
                    // bar are what must leave the screen, held, going. A source stops *asking*
                    // for the band the moment its job ends (`StatusSource.isActive`, which is what
                    // `showing` above reads) and goes on *saying* what happened for as long as the
                    // fade takes. Collapse the two and the rows blank on the fade's first frame,
                    // leaving two lit rims over nothing.
                    if let reading = env.appStatus.current(now: context.date) {
                        line(reading, now: context.date)
                    }
                }
                .padding(.top, band + 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: StatusGlow.fadeOut), value: showing)
    }

    // MARK: drawing

    @ViewBuilder
    private func line(_ reading: StatusReading, now: Date) -> some View {
        // The words go amber only on a failure. The bar also goes green on a success, so the fill
        // and the glow finish on the same colour, but the title stays ink there — "Voice ready" in
        // green over a green rim is the same thing said twice.
        let tint: Color = reading.tone == .failed ? Tokens.accent : palette.ink
        let barTint: Color = switch reading.tone {
        case .failed: Tokens.accent
        case .ready: palette.glowReady
        case .waiting: palette.ink
        }
        // Read from the wall clock, like `StatusRamp.pulse`, rather than from `warmUpStarted` — that
        // date is only set for `.preparing`, so anchoring to it left the whole download stuck on the
        // first message. The cycle does not need an anchor, only a tick, and the wall clock has the
        // side benefit that every copy on screen says the same thing on the same frame.
        let message = reading.message(elapsed: now.timeIntervalSinceReferenceDate)
        VStack(spacing: 0) {
            Text(reading.title)
                .font(.custom("Inter-Medium", size: 11, relativeTo: .caption2))
                .tracking(-0.01 * 11)
                .foregroundStyle(tint)

            // `maxWidth: .infinity` matters: the clip below is only meant to hide the row as its
            // height animates to zero, but a frame sized to the content clips sideways too — and
            // because the row's width is itself animating between messages, it took a bite out of
            // both ends of every swap ("ht take some time · 123 of 35").
            subtext(message, value: reading.value, tint: tint)
                .frame(maxWidth: .infinity,
                       minHeight: reading.collapsesSubtext ? 0 : 13,
                       maxHeight: reading.collapsesSubtext ? 0 : 13)
                .opacity(reading.collapsesSubtext ? 0 : 1)
                .padding(.top, reading.collapsesSubtext ? 0 : 2)
                .clipped()

            bar(reading, tint: barTint)
                .padding(.top, 7)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.34), value: reading.collapsesSubtext)
    }

    /// The faint row. The two slots sit either side of a separator that exists only when both of
    /// them do — one slot alone is centred on its own, with no orphaned dot beside it. The message
    /// crossfades in place while the row re-centres around it, so the change is one movement.
    @ViewBuilder
    private func subtext(_ message: String?, value: String?, tint: Color) -> some View {
        HStack(spacing: 0) {
            if let message {
                Text(message)
                    .font(.custom("Inter-Regular", size: 9.5, relativeTo: .caption2))
                    .id(message)                                     // a new identity, so it crossfades
                    // Opacity only. A rise of a few points is the nicer motion, but the row is
                    // clipped to 13 pt so the lift is cut off half way up.
                    .transition(.opacity)
            }
            if message != nil, value != nil {
                Text("·").font(.custom("Inter-Regular", size: 9.5, relativeTo: .caption2)).padding(.horizontal, 3.5)
            }
            if let value {
                Text(value)
                    .font(.custom("Inter-Medium", size: 9.5, relativeTo: .caption2))
                    .monospacedDigit()                               // or the digits shuffle each tick
            }
        }
        .foregroundStyle(tint.opacity(0.5))
        .lineLimit(1)
        .fixedSize()
        .animation(.easeInOut(duration: 0.42), value: message)
    }

    /// One capsule, or three proportioned to how long each phase really takes. A download is one
    /// continuous byte count so it stays plain; the bar divides only once the install's phases are
    /// behind it, and the division is a handoff — the full-width bar contracts to the first segment
    /// and stays full while the others grow out of the space it gave up, so the download becomes
    /// step one rather than being replaced (owner, 2026-09-12, against four alternatives).
    @ViewBuilder
    private func bar(_ reading: StatusReading, tint: Color) -> some View {
        let weights = reading.segments
        let total = weights.reduce(0, +)
        let gaps = Self.segmentGap * CGFloat(max(0, weights.count - 1))
        let usable = Self.barWidth - gaps
        let filled = usable * reading.progress
        HStack(spacing: Self.segmentGap) {
            ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                let width = usable * (weight / total)
                let before = weights.prefix(index).reduce(0, +) / total * usable
                Capsule().fill(palette.ink3.opacity(0.6))
                    .frame(width: width, height: Self.barHeight)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint)
                            .frame(width: min(width, max(0, filled - before)))
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(width: Self.barWidth, alignment: .leading)
        .opacity(reading.progress > 0 || reading.tone != .waiting ? 1 : 0)
        .animation(.easeOut(duration: 0.55), value: weights.count)
        .animation(.easeOut(duration: 0.6), value: reading.progress)
    }
}

/// The status band: both lit rims and the three rows, laid over whatever the screen has already
/// painted.
///
/// **It does not own the ground the rows stand on, and that is on purpose.** The obvious design
/// has the band paint its own `TopFade`, and it was written that way first. It cannot work: the
/// three hosts want three different grounds. The Reader wants solid through the rows' full reach,
/// because `topBar` brings its own ground and picks up where they end. The root pager wants its
/// solid stopped short at 36 and a 116 pt ramp below it, because the page title behind it scrolls
/// and has to be read *through* the fade rather than covered by it. A pushed Settings page wants
/// the measured, offset one it already has, because UIKit has spent its top inset and a plain
/// `ignoresSafeArea` there is a no-op. A band that painted one ground for all three would have
/// covered the root pages' titles — the exact defect `TopFade.warmSolid` was tuned to avoid.
///
/// So each host keeps the `TopFade` it already had, and the band is the light and the words. The
/// colour is still fixed, because `TopFade` takes one now and the Reader hands it the book's paper.
///
/// **One layer, on top.** This is the arrangement `WarmUpVeil` arrived at the hard way. The light
/// used to sit *behind* the pages with every ground bar painting a matching copy of the same ramp
/// into itself, which holds only while every layer between the two is transparent; where one was
/// not, the glow was cut off at the bar's foot with nothing in the code to say why. Drawn over the
/// page instead, it needs nothing underneath to cooperate.
///
/// **And one owner.** Every screen used to install this by hand — six `StatusRim`s, two `StatusRows`,
/// two differently-configured `TopFade`s and three separate copies of the same fade animation, which
/// had to agree on the same frame or the Reader's title stepped down into rows that were not there.
/// A host says `.appStatusBand()` and nothing else.
private struct StatusBand: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    /// Whether this host draws the rows. A pushed Settings page shows the light alone, as it
    /// always has — the root pager draws the rows over the push.
    var showsRows: Bool

    /// Whether this host draws the rims.
    ///
    /// The root pager passes false while a Settings subpage is up, because that page paints its
    /// own pair and **two transparent rims add**. Two opaque ramps hid this for months — the top
    /// one simply won — but the rim is a glow with no ground under it, so the Voice page wore
    /// twice the light below the bar's foot and a 30 pt step from one to two through its fade
    /// (owner, 2026-09-12: "there is a top fade messing with the glow"). The old hand-placed pair
    /// was gated for exactly this reason, and the gate has to survive the move into one modifier.
    var showsRims: Bool

    func body(content: Content) -> some View {
        let showing = env.appStatus.isShowing
        content
            .overlay { if showsRims { rims } }
            .overlay {
                if showsRows {
                    GeometryReader { geo in
                        StatusRows(band: geo.frame(in: .global).minY)
                    }
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: StatusGlow.fadeOut), value: showing)
    }

    /// Both rims read one reading on one frame, so head and foot can never disagree about the
    /// colour they are ending on.
    @ViewBuilder private var rims: some View {
        TimelineView(.animation) { context in
            let reading = env.appStatus.current(now: context.date)
            let settle = env.appStatus.endSettle(now: context.date)
            StatusRim(edge: .top, tone: reading?.tone, settle: settle)
            StatusRim(edge: .bottom, tone: reading?.tone, settle: settle)
        }
    }
}

extension View {
    /// Draws the app's status band over this surface: both lit rims, and the three rows.
    ///
    /// The ground under the rows is the host's own `TopFade` — see the note on `StatusBand` for
    /// why the band cannot paint one that suits all three surfaces. Pass `showsRows: false` for a
    /// surface that shows the light alone, and `showsRims: false` for one that is about to have
    /// another surface pushed over it that paints its own.
    func appStatusBand(showsRows: Bool = true, showsRims: Bool = true) -> some View {
        modifier(StatusBand(showsRows: showsRows, showsRims: showsRims))
    }
}
