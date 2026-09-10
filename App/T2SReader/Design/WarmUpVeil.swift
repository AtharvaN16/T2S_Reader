// App/T2SReader/Design/WarmUpVeil.swift
import Foundation
import SwiftUI
import UIKit

/// The one-time voice warm-up, shown wherever the reader is (owner, 2026-09-10, Tabby's launch
/// gradient as the reference): an orange wash down from the very top of the screen that breathes
/// until the stages are loaded, and one short line with how long it usually takes on this phone
/// over a hairline of progress.
///
/// **It sits behind the page, not over it** (owner's second look): every host puts the `.behind`
/// layer at the back of its stack, over the ground fill and under the text, so the page reads as
/// lit from behind rather than filmed over. That only works because the pages themselves are
/// transparent — the root pages let `RootPager`'s ground show through, and `ReaderTextView` draws
/// on a clear background.
///
/// **The `.chrome` layer is the top strip.** A page's ground bars — `TopFade` on the root, the
/// Reader's own header fade — are painted over the content to mask what scrolls under the status
/// bar, and being over the content they are also over the `.behind` layer, which left a pale band
/// across the top of the wash. So the same gradient is drawn a second time in front of them,
/// clipped to the safe-area inset where no app content ever sits, and the message rides with it.
/// Both layers take their pulse from the wall clock rather than their own animation state, so they
/// breathe in step no matter when each appeared.
///
/// **It goes when sound does.** Warming is only worth saying while nothing is speaking; a book
/// already playing through a fallback voice with an orange pulse over it read as an alarm rather
/// than a wait (owner). So the wash hides the moment audio is actually flowing, even if the Kokoro
/// stages are still loading behind it.
///
/// What it knows: the stage count as each compute plan finishes (`KokoroStatusModel.warmUpStages`,
/// eight stages), and the last warm-up's length on this phone (`expectedWarmUpSeconds`). The bar is
/// the larger of the two readings — stages are exact but coarse, the clock is smooth but a guess —
/// and never claims done. A first launch after install has no remembered length, and says so.
struct WarmUpVeil: View {
    enum Layer {
        /// The whole wash, for the back of a host's stack.
        case behind
        /// The top strip and the message, for the front — over whatever ground bar the host paints.
        case chrome
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var layer: Layer = .behind
    /// The line and bar under the status bar; off in the Reader, whose transport already says
    /// "preparing the voice…". Only the `.chrome` layer carries it.
    var showsMessage = true

    /// The share of the screen the wash covers, top down.
    private static let coverage: CGFloat = 0.58
    /// One breath, in seconds.
    private static let period: Double = 3

    /// `T2S_WARMUP=1` fakes a warm-up in the everyday build (`KokoroComposition`), and a faked one
    /// has to show even while the fixture book plays, or there is nothing to screenshot.
    private static let isFaked = ProcessInfo.processInfo.environment["T2S_WARMUP"] != nil

    /// The status bar's height, from the window rather than from a `GeometryProxy`: this view spans
    /// the screen with `ignoresSafeArea()`, and a proxy under that reports the insets it is now
    /// covering as zero — which put the message across the clock and gave the strip no height at
    /// all. The app is portrait-only iPhone, so one read at draw time is enough.
    private var statusBandHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.compactMap(\.keyWindow).first ?? scenes.flatMap(\.windows).first
        return window?.safeAreaInsets.top ?? 47
    }

    /// Warming, and nothing audible yet. `isCatchingUp` is the stall before the first sound, so a
    /// tapped Play that is still waiting keeps the wash; a book actually speaking loses it.
    private var isVisible: Bool {
        guard env.kokoroStatus.status.isWarming else { return false }
        if Self.isFaked { return true }
        return !(env.player.isPlaying && !env.player.isCatchingUp)
    }

    var body: some View {
        if isVisible {
            let band = statusBandHeight
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    TimelineView(.animation) { context in
                        wash(pulse: reduceMotion ? 1 : Self.pulse(at: context.date))
                            .frame(height: geo.size.height * Self.coverage)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .mask(alignment: .top) { stripMask(band: band) }
                    }
                    if layer == .chrome, showsMessage {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            message(env.kokoroStatus, now: context.date)
                        }
                        .padding(.top, band + 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            // On the GeometryReader itself, so `geo` measures the whole screen and its origin is the
            // screen's top corner. Inside the Reader the same veil had been reading a stack that
            // began below the status bar, and the wash landed in the middle of the text (owner).
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    /// The `.chrome` layer is cut to the ground bar it covers: solid through the status band, then
    /// out over `TopFade.fadeHeight` — the same span the bar underneath takes to fade to clear, so
    /// the two hand over without a seam. The `.behind` layer is not cut at all.
    @ViewBuilder private func stripMask(band: CGFloat) -> some View {
        if layer == .chrome {
            let total = band + TopFade.fadeHeight
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: band / total),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: total)
        } else {
            Color.black
        }
    }

    /// 0.38 … 1 and back, once every ``period``, read from the wall clock so two layers drawn at
    /// different moments are never out of step.
    private static func pulse(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return 0.38 + 0.62 * (0.5 + 0.5 * cos(2 * .pi * phase))
    }

    /// Strong orange at the top, held near-peak for the first fifth so the colour reads as a lit
    /// edge rather than an instant fade, then out to nothing (owner: start it higher, more orange
    /// up top).
    private func wash(pulse: Double) -> some View {
        LinearGradient(stops: [
            .init(color: Tokens.accent.opacity(0.55), location: 0),
            .init(color: Tokens.accent.opacity(0.42), location: 0.20),
            .init(color: Tokens.accent.opacity(0.14), location: 0.62),
            .init(color: Tokens.accent.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .opacity(pulse)
    }

    private func message(_ status: KokoroStatusModel, now: Date) -> some View {
        let elapsed = status.warmUpStarted.map { now.timeIntervalSince($0) } ?? 0
        let byStages = status.warmUpStages.map { Double($0.loaded) / Double(max(1, $0.total)) } ?? 0
        let byClock = status.expectedWarmUpSeconds.map { min(0.92, elapsed / max(1, $0)) } ?? 0
        let progress = max(byStages, byClock)
        return VStack(spacing: 7) {
            Text(line(status, elapsed: elapsed))
                .typeRole(.caption)
                .foregroundStyle(Tokens.ink)
            Capsule().fill(Tokens.ink3.opacity(0.6))
                .frame(width: 120, height: 3)
                .overlay(alignment: .leading) {
                    Capsule().fill(Tokens.ink).frame(width: 120 * progress)
                        .animation(.easeOut(duration: 0.6), value: progress)
                }
                .opacity(progress > 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// "Warming up the voice · about 6 s", or on a first launch "Warming up the voice · a few
    /// minutes the first time". Once the estimate is spent, "almost there" rather than a number
    /// that has gone wrong.
    private func line(_ status: KokoroStatusModel, elapsed: TimeInterval) -> String {
        guard let expected = status.expectedWarmUpSeconds else {
            return "Warming up the voice · a few minutes the first time"
        }
        let left = expected - elapsed
        if left <= 1 { return "Warming up the voice · almost there" }
        let rounded = left < 10 ? Int(left.rounded(.up)) : Int((left / 5).rounded(.up)) * 5
        return "Warming up the voice · about \(rounded) s"
    }
}
