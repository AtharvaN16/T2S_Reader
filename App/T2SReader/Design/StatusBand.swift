// App/T2SReader/Design/StatusBand.swift
import Foundation
import Observation
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
    /// The band's colours, from the app's own object rather than from `\.readerPalette`: these
    /// rows are drawn in a window of their own, which inherits no environment. See
    /// `StatusAppearance`.
    private var palette: ReaderPalette { env.statusAppearance.palette }
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
        // `StatusGlow.leave`, not `fadeOut`. A second and a half is the right length for a light to
        // die away and much too long for words and a bar, which simply looked stuck — and it has to
        // be the same length the Reader's ground and header move in, or one uncovers the other.
        .animation(.easeInOut(duration: StatusGlow.leave), value: showing)
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
                .animation(.easeInOut(duration: 0.34), value: reading.collapsesSubtext)

            bar(reading, tint: barTint)
                .padding(.top, 7)
        }
        .frame(maxWidth: .infinity)
        // Scoped to the row that collapses, never to the stack. On the whole `VStack` it also
        // caught the *title's* text change — and the one moment both happen at once is the turn to
        // ready, so "Warming up the voice" and "Voice ready" cross-dissolved on top of each other
        // as a legible double exposure (owner, 2026-09-15: "I can see ghosting"). The title is one
        // slot whose words change; it should cut, not dissolve.
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
/// painted — and, since 2026-09-15, drawn in a window of its own rather than in any page's view
/// tree. `StatusBandHost` puts it there; the note on `StatusBandWindow.swift` says why a window.
///
/// **It does not own the ground the rows stand on, and that is on purpose.** The obvious design
/// has the band paint its own `TopFade`, and it was written that way first. It cannot work: the
/// three surfaces that show the band want three different grounds. The Reader wants solid through
/// the rows' full reach, because `topBar` brings its own ground and picks up where they end. The
/// root pager wants its solid stopped short at 36 and a 116 pt ramp below it, because the page
/// title behind it scrolls and has to be read *through* the fade rather than covered by it. A
/// pushed Settings page wants the measured, offset one it already has, because UIKit has spent its
/// top inset and a plain `ignoresSafeArea` there is a no-op. A band that painted one ground for all
/// three would have covered the root pages' titles — the exact defect `TopFade.warmSolid` was tuned
/// to avoid. So each host keeps the `TopFade` it already had, and the band is the light and the
/// words. The Reader hands its own fade the book's paper, which is the whole reason `TopFade` takes
/// a colour at all.
///
/// A second reason now, and a stronger one: those grounds cannot live up here even if they agreed.
/// The Reader's ground must sit *under* the Reader's chrome and over the Reader's text; this window
/// is above everything. A band that painted the Reader's ground from here would paint it over the
/// book's title bar.
///
/// **One layer, on top.** This is the arrangement `WarmUpVeil` arrived at the hard way. The light
/// used to sit *behind* the pages with every ground bar painting a matching copy of the same ramp
/// into itself, which holds only while every layer between the two is transparent; where one was
/// not, the glow was cut off at the bar's foot with nothing in the code to say why. Drawn over the
/// page instead, it needs nothing underneath to cooperate.
///
/// **And one owner — now literally one.** Every screen used to install this by hand: six
/// `StatusRim`s, two `StatusRows`, two differently-configured `TopFade`s and three separate copies
/// of the same fade animation, which had to agree on the same frame or the Reader's title stepped
/// down into rows that were not there. That became one `.appStatusBand()` per host, and then this:
/// no host says anything at all. The flags that modifier carried went with it, and they are worth
/// recording because both were about *two bands existing*:
///
/// - `showsRows: false` was for a pushed Settings page, which shows the light alone while the root
///   pager draws the rows over the push. With one band there is one set of rows and nothing is
///   drawn over anything.
/// - `showsRims: false` was for the root pager while a Settings subpage was up, because that page
///   painted its own pair and **two transparent rims add**. Two opaque ramps hid this for months —
///   the top one simply won — but a rim is a glow with no ground under it, so the Voice page wore
///   twice the light below the bar's foot and a 30 pt step from one to two through its fade
///   (owner, 2026-09-12: "there is a top fade messing with the glow"). One band in existence is the
///   real fix for that, and the gate is gone because there is no longer a second pair to gate.
///
/// A pushed Settings page gains an edge it never had. The root pager's foot glow went with the
/// push, so on the Voice page the light simply stopped at the top of the screen (owner, 2026-09-12:
/// "there is no glow in the bottom"), and the page's own hand-placed pair could not fix it — the
/// one place a rim still cannot reach from inside a page is the top of a pushed page, where UIKit
/// has spent the inset (see `StatusRim`). One band above every presentation lights both edges of
/// the screen wherever the reader is, and has no page's spent inset to work around.
///
/// The Reader is the surface that proves the point. It only ever had a copy of its own because a
/// `fullScreenCover` is a separate presentation the pager's band could not reach into; without that
/// copy, opening a book while the voice was still downloading took the status off the screen and
/// left two glowing rims with nothing between them to say what they were for (owner, 2026-09-13:
/// "it removes the warmup glow and progress indicator ... I need to be aware of the status"). A
/// window is above every presentation, so there is nothing left to reach into.
struct StatusBandOverlay: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let showing = env.appStatus.isShowing
        ZStack {
            if showing { rims.transition(.opacity) }
            // The safe-area inset the rows stand under, measured here rather than inside them:
            // `StatusRows` spans the screen with `ignoresSafeArea`, and a proxy under that reports
            // the inset it now covers as zero. This reader is the last view still inside it.
            GeometryReader { geo in
                StatusRows(band: geo.frame(in: .global).minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Belt and braces over `PassthroughWindow`: nothing in here is ever touchable, whatever
        // this view is later hosted in.
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: StatusGlow.fadeOut), value: showing)
        // The app's light or dark, declared a second time, for the same reason the palette is
        // handed across: `AppTheme` writes its override onto the window it is applied in
        // (`WindowTheme`), and this is a different window. Without this a reader who had chosen
        // dark on a light phone would get a band in light ink over a dark app — and, since the
        // status bar takes its style from the frontmost window, a light status bar with it. `nil`
        // for `.system`, which is the absence of an override rather than a third choice, so the
        // device's own setting comes through exactly as it does everywhere else.
        .preferredColorScheme(env.preferences.theme.colorScheme)
    }

    /// Both rims read one reading on one frame, so head and foot can never disagree about the
    /// colour they are ending on.
    ///
    /// **Gated on `showing`, and it has to be.** The rims light on `tone != nil`, and a source goes
    /// on answering long after it has stopped asking for the band — the voice's `readyAt` is never
    /// cleared, by design, so its reading outlives every warm-up. Without the gate above, the
    /// rims fed from that reading simply never went out: every launch ended with green top and
    /// bottom rims lit for the rest of the session. The gate is also what stops this `TimelineView`
    /// ticking at the refresh rate for the app's whole life, re-compositing two blurred 36 pt
    /// strokes and a dither tile over a band nobody can see.
    @ViewBuilder private var rims: some View {
        TimelineView(.animation) { context in
            let reading = env.appStatus.current(now: context.date)
            let settle = env.appStatus.endSettle(now: context.date)
            StatusRim(edge: .top, tone: reading?.tone, settle: settle)
            StatusRim(edge: .bottom, tone: reading?.tone, settle: settle)
        }
    }
}

/// What colour the band paints in, carried by hand because a window cannot inherit an environment.
///
/// The band has a palette at all for one reason: the Reader. Everywhere else in the app the paper
/// *is* `ReaderPalette.app`, so the band's ink, its bar track and its light are the app's own greys
/// and blue and nothing has to be told anything. Inside the Reader the page is one of sixteen
/// papers, and a band that went on painting app grey put a white slab and a fixed blue across the
/// top of a Cherry or Cobalt page — the defect the owner reported on 2026-09-15 ("the warm-up glow
/// in the reader looks weird, it has like a different color sometimes"), which is invisible on the
/// default Paper and glaring on the pop ones.
///
/// `@Environment(\.readerPalette)` answered that while the band was applied inside `ReaderPage`'s
/// body. It cannot now: the band lives in its own `UIWindow` (`StatusBandHost`), and a window is
/// the root of its own view tree — no environment value set anywhere in the app's window flows into
/// it. So the Reader *pushes* its paper here when it appears and whenever the reader changes it,
/// and puts `.app` back when it leaves, and every part of the band reads this one object.
///
/// It is deliberately the smallest possible object. Not "the Reader's state, shared" — one palette,
/// written by whoever owns the screen, read by the band. Anything more and the band would start
/// knowing which page is up, which is exactly what taking it out of the view tree was meant to end.
@MainActor
@Observable
final class StatusAppearance {
    /// The paper the band paints on. `.app` outside the Reader, which is the app's own greys, so
    /// nothing outside the Reader has to set anything.
    var palette: ReaderPalette = .app
}
