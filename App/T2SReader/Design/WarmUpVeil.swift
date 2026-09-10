// App/T2SReader/Design/WarmUpVeil.swift
import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// The one-time voice warm-up, shown wherever the reader is (owner, 2026-09-10, Tabby's launch
/// gradient as the reference): an orange glow down from the very top of the screen that breathes
/// until the stages are loaded, and one short line with how long it usually takes on this phone
/// over a hairline of progress (`WarmUpLine`).
///
/// **One surface.** The glow is `WarmRamp`, and everything that shows it draws that same view:
/// this veil at the back of a host's stack, under the text; and every ground bar across the top
/// of a page — `TopFade` on the root, the Reader's header — through `WarmGround`, which is the
/// bar's ground normally and the ramp while warming. Two earlier cuts drew a second, translucent
/// strip over the bars to cover them, and the owner saw the join: two layers at opacity *p* stacked
/// do not make one layer at *p*, so the band under the status bar was always a shade stronger
/// than the page below it. The ramp is opaque and its pulse is a colour mix, not an alpha, so a
/// bar painting it over the veil shows exactly the pixels the veil would have — there is nothing
/// to line up. The pages under it are transparent so it can reach them: the root pages let
/// `RootPager`'s ground show through (Settings' stack has its container background cleared for
/// the same reason), and `ReaderTextView` draws on a clear background.
///
/// **It goes when sound does.** Warming is only worth saying while nothing is speaking; a book
/// already playing through a fallback voice with an orange pulse over it read as an alarm rather
/// than a wait (owner). So the glow hides the moment audio is actually flowing, even if the Kokoro
/// stages are still loading behind it.
struct WarmUpVeil: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if Self.isShowing(env) {
            WarmRamp()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    /// Warming, and nothing audible yet. `isCatchingUp` is the stall before the first sound, so a
    /// tapped Play that is still waiting keeps the glow; a book actually speaking loses it.
    static func isShowing(_ env: AppEnvironment) -> Bool {
        guard env.kokoroStatus.status.isWarming else { return false }
        if isFaked { return true }
        return !(env.player.isPlaying && !env.player.isCatchingUp)
    }

    /// `T2S_WARMUP=1` fakes a warm-up in the everyday build (`KokoroComposition`). A faked one has
    /// to show even while the fixture book plays, or there is nothing to screenshot, and it holds
    /// the pulse still, so two screenshots are comparable.
    static let isFaked = ProcessInfo.processInfo.environment["T2S_WARMUP"] != nil
}

/// What a ground bar paints: `ground`, or the ramp while the warm-up shows, crossfading between
/// them so a bar does not snap from orange to grey when the voice comes ready.
struct WarmGround: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let showing = WarmUpVeil.isShowing(env)
        ZStack(alignment: .top) {
            Tokens.ground
            if showing { WarmRamp().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.6), value: showing)
    }
}

/// The glow: `height` points of orange from the top of whatever frame it is given, ground below
/// that, so it fills any host and lines up with every other copy of itself as long as the host's
/// frame begins at the top of the screen (they all do — `ignoresSafeArea` on the veil, on
/// `TopFade`, on the Reader's header background). A fixed height, not a share of the screen, so
/// the glow hugs the top on every phone (owner: "move the glow more to the top").
///
/// **Opaque, and dithered.** Each stop is the colour the accent and the ground *make*
/// (`Color.mix`), and the pulse scales the mix rather than an alpha — see `WarmUpVeil` for why. A
/// ramp this shallow is asking more of 8 bits than they have: it would hold one value for ten or
/// twenty rows and then step, and the eye reads every step as a line (measured on a screenshot:
/// flat runs of up to 23 px). A tile of noise a few levels wide, blended over the ramp at one cell
/// per device pixel, scatters each step's edge into a pattern too fine to see — measured after:
/// no run longer than 3 px.
struct WarmRamp: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let height: CGFloat = 320
    /// One breath, in seconds.
    private static let period: Double = 3

    var body: some View {
        TimelineView(.animation) { context in
            let pulse = reduceMotion || WarmUpVeil.isFaked ? 1 : Self.pulse(at: context.date)
            // Ground the size of whatever frame this is given, and the ramp laid over its top as
            // an overlay — which takes no part in layout. As a child it did: a fixed 320 pt inside
            // a 90 pt bar made the stack 320 pt, the bar's frame then *centred* it, and the bar
            // showed a paler slice from 115 pt down the ramp — the band the owner saw across the
            // top of Home and Settings, while the Reader's taller header hid most of it.
            Tokens.ground
                .overlay(alignment: .top) {
                    ZStack {
                        Self.gradient(pulse: pulse)
                        Self.ditherTile
                            .resizable(resizingMode: .tile)
                            .blendMode(.overlay)
                            .opacity(0.85)
                    }
                    .compositingGroup()                                    // the noise blends with the ramp, not the page
                    .frame(height: Self.height)
                }
        }
    }

    /// 0.38 … 1 and back, once every ``period``, read from the wall clock so every copy of the
    /// ramp on screen is at the same point of the breath.
    private static func pulse(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return 0.38 + 0.62 * (0.5 + 0.5 * cos(2 * .pi * phase))
    }

    /// Strong at the top, held near-peak for the first 15 % so the colour reads as a lit edge
    /// rather than an instant fade, then out to ground.
    private static func gradient(pulse: Double) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: Tokens.ground.mix(with: Tokens.accent, by: 0.55 * pulse), location: 0),
            .init(color: Tokens.ground.mix(with: Tokens.accent, by: 0.42 * pulse), location: 0.15),
            .init(color: Tokens.ground.mix(with: Tokens.accent, by: 0.14 * pulse), location: 0.55),
            .init(color: Tokens.ground, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// A tile of grey noise around the mid-point, made once. `.overlay` leaves mid-grey alone and
    /// nudges either side of it, so the average is unchanged and only the step edges move. Scale 3
    /// so each cell is one device pixel on a 3x phone (1.5 on a 2x one): drawn point-for-point it
    /// was a 3 × 3 px speckle that read as grain.
    private static let ditherTile: Image = {
        let side = 96
        let bytes = side * side * 4
        var pixels = [UInt8](repeating: 255, count: bytes)
        var rng = SystemRandomNumberGenerator()
        for i in stride(from: 0, to: bytes, by: 4) {
            let value = UInt8.random(in: 96...160, using: &rng)
            pixels[i] = value
            pixels[i + 1] = value
            pixels[i + 2] = value
        }
        let image: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return context.makeImage()
        }
        guard let image else { return Image(uiImage: UIImage()) }
        return Image(uiImage: UIImage(cgImage: image, scale: 3, orientation: .up))
    }()
}

/// The warm-up's one line and its hairline of progress, under the status bar, over the bar there.
/// What it knows: the stage count as each compute plan finishes (`KokoroStatusModel.warmUpStages`,
/// eight stages), and the last warm-up's length on this phone (`expectedWarmUpSeconds`). The bar is
/// the larger of the two readings — stages are exact but coarse, the clock is smooth but a guess —
/// and never claims done. A first launch after install has no remembered length, and says so.
struct WarmUpLine: View {
    @Environment(AppEnvironment.self) private var env
    /// The safe-area top inset, from a host whose `GeometryProxy` still reports it: this view
    /// spans the screen with `ignoresSafeArea`, and a proxy under that reports the insets it now
    /// covers as zero.
    var band: CGFloat

    var body: some View {
        if WarmUpVeil.isShowing(env) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                message(env.kokoroStatus, now: context.date)
            }
            .padding(.top, band + 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
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
    /// minutes the first time". Past a minute and a half it counts in minutes (the owner's phone
    /// remembered a 220 s warm-up, and the line read "about 220 s"). Once the estimate is spent,
    /// "almost there" rather than a number that has gone wrong.
    private func line(_ status: KokoroStatusModel, elapsed: TimeInterval) -> String {
        guard let expected = status.expectedWarmUpSeconds else {
            return "Warming up the voice · a few minutes the first time"
        }
        let left = expected - elapsed
        if left <= 1 { return "Warming up the voice · almost there" }
        if left >= 90 { return "Warming up the voice · about \(Int((left / 60).rounded())) min" }
        let rounded = left < 10 ? Int(left.rounded(.up)) : Int((left / 5).rounded(.up)) * 5
        return "Warming up the voice · about \(rounded) s"
    }
}
