// App/T2SReader/Design/WarmUpVeil.swift
import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// The one-time voice warm-up, shown wherever the reader is (owner, 2026-09-10, Tabby's launch
/// gradient as the reference): a blue glow down from the very top of the screen that breathes
/// until the stages are loaded, and one short line with how long it usually takes on this phone
/// over a hairline of progress (`WarmUpLine`).
///
/// **It ends on green.** The last beat belongs to `Tokens.glowReady` (owner, 2026-09-10: "just as
/// the model is ready, change the glow to green before ending the animation"): the moment the stages
/// are in, the breath eases up to full and the light crosses to green over `readyEase`, holds
/// (`KokoroStatusModel.readyBeat`), and then fades over `fadeOut` — all three on the blue's own
/// timing, so the green arrives and leaves the way the blue moved rather than flashing. The beat is one date on the status model
/// (`readyAt`), so the veil and every ground bar turn on the same frame; the model marking that
/// date's beat over (`readyBeatEnded`) is what takes the glow off the screen. The date itself
/// stays, and that is the point: every "we are done" the screen shows — the green, "Voice ready",
/// the filled bar — is read from it, so it has to outlast the fade it starts.
///
/// **One layer, on top.** The glow is `WarmRim` — the wash and the lit bezel with no ground under
/// them — laid over whatever the screen has already painted: over `TopFade` on the root, over the
/// Reader's header, over a Settings subpage's ground. Nothing underneath has to cooperate.
///
/// It was the other way round until 2026-09-12, and the way it failed is worth keeping. An opaque
/// `WarmRamp` sat at the back of each stack and every ground bar painted that same ramp into
/// itself, so bar and page were one surface with nothing to line up — the ramp being opaque, and
/// its pulse a colour mix rather than an alpha, meant a bar's copy was pixel-for-pixel the veil's.
/// That holds only while every layer between the two is transparent. Where one is not, the veil
/// never reaches the screen below the bar and all that survives is the bar's own slice: the glow
/// cut off at the bar's foot, with nothing in the code to say why. It cost the Voice page a seam
/// on 2026-09-10 and the owner the same cut twice more before the arrangement itself was the
/// suspect. Drawing the light over the page instead is a shade less pure — the wash falls on the
/// top of the content rather than behind it — and cannot break this way.
///
/// **It goes when the phone's own voice sounds.** A book already playing through the system
/// voice with a pulse over it read as an alarm rather than a wait (owner, 2026-09-10), so the glow
/// hides the moment that audio flows, even if the Kokoro stages are still loading behind it. The
/// hosted voice is the exception (owner, 2026-09-12): Heart from the mirrors *is* the wait for
/// Heart on the phone, and the reader wants to watch the download and the warm-up go by over it,
/// so the glow stays until green while the hosted voice is the one speaking.
@MainActor
enum WarmUpVeil {
    /// How long the light takes to go, matched to half a breath so it leaves at the pace it moved.
    static let fadeOut: Double = 1.5

    /// Warming, and nothing audible yet. `isCatchingUp` is the stall before the first sound, so a
    /// tapped Play that is still waiting keeps the glow; a book actually speaking loses it.
    static func isShowing(_ env: AppEnvironment) -> Bool {
        guard env.kokoroStatus.status.isWarming || env.kokoroStatus.isHoldingReadyBeat else { return false }
        if isFaked { return true }
        // Sound from the phone's own voice means the wait is over. Sound from the hosted voice
        // means the wait is under way — Heart from the mirrors while Heart installs — and the
        // owner asked to watch it (cloud-first bootstrap, 2026-09-12), so the glow stays until green.
        let hostedSpeaking = env.player.routedVoiceID?.hasPrefix("cloud:") == true
        return hostedSpeaking || !(env.player.isPlaying && !env.player.isCatchingUp)
    }

    /// Whether this warm-up has ended — the glow's last beat, green. Deliberately *not* the same
    /// gate as `isShowing`: it stays true right through the fade that `isShowing` going false
    /// starts, so the green, "Voice ready" and the full bar are what leaves the screen. The two
    /// parted company when the beat's end stopped clearing `readyAt` (`KokoroStatusModel`).
    static func isReady(_ env: AppEnvironment) -> Bool { env.kokoroStatus.readyAt != nil }

    /// How far into the green, 0…1, eased on the same curve the breath uses. The blue takes a second
    /// and a half to breathe in; the green takes the same to arrive, rather than cutting in over a
    /// quarter-second and reading as a flash (owner, 2026-09-12).
    static let readyEase: Double = 1.4

    static func readySettle(_ env: AppEnvironment, now: Date) -> Double {
        guard let readyAt = env.kokoroStatus.readyAt else { return 0 }
        let t = min(1, max(0, now.timeIntervalSince(readyAt) / readyEase))
        return t * t * (3 - 2 * t)                                   // smoothstep, as the cosine is at its ends
    }

    /// `T2S_WARMUP=1` fakes a warm-up in the everyday build (`KokoroComposition`). A faked one has
    /// to show even while the fixture book plays, or there is nothing to screenshot, and it holds
    /// the pulse still, so two screenshots are comparable.
    static let isFaked = ProcessInfo.processInfo.environment["T2S_WARMUP"] != nil
}

/// The glow: `height` points from the top of whatever frame it is given, ground below that, so it
/// fills any host and lines up with every other copy of itself as long as the host's frame begins
/// at the top of the screen (they all do — `ignoresSafeArea` on the veil, on `TopFade`, on the
/// Reader's header background). A fixed height, not a share of the screen, so the glow hugs the
/// top on every phone (owner: "move the glow more to the top", then "further up").
///
/// **A bezel** (owner, 2026-09-10: "the corners are more prominent than the top — a bezel glow in
/// the top part"): one stroke of light along the screen's edge — across the top, round both
/// corners and a little way down the sides — with its halo blurred inward, over a faint wash from
/// the top. Every point of the edge is lit the same, so the corners are only where the edge turns,
/// not two lamps brighter than the top between them (the cut before: two ellipses anchored at the
/// corners under a weaker top band, and the corners won). The sides let go part-way down, so the
/// middle of the screen clears under the status bar and the light stays at the top. The breath
/// takes the whole shape almost out (`pulse` bottoms near zero) and back.
///
/// **Opaque, and dithered.** The glows are `Tokens.glow` at an alpha over `ground`, composited here
/// into one opaque layer, so a bar painting this view over the veil shows exactly the veil's
/// pixels (see `WarmUpVeil`). A ramp this shallow is asking more of 8 bits than they have: it
/// would hold one value for ten or twenty rows and then step, and the eye reads every step as a
/// line (measured on a screenshot: flat runs of up to 23 px). A tile of noise a few levels wide,
/// blended over the ramp at one cell per device pixel, scatters each step's edge into a pattern
/// too fine to see — measured after: no run longer than 3 px.
enum WarmRamp {
    static let height: CGFloat = 240
    /// One breath, in seconds.
    private static let period: Double = 3

    /// 0.05 … 1 and back, once every ``period``, read from the wall clock so every copy of the
    /// ramp on screen is at the same point of the breath. The low end is all but gone (owner:
    /// "the pulse out almost completely not visible").
    static func pulse(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return 0.05 + 0.95 * (0.5 + 0.5 * cos(2 * .pi * phase))
    }

    /// The screen's corner radius, which the bezel follows. Not asked of the system — `UIScreen`
    /// does not say — so this is the iPhone 14 to 16's 55 pt, within a few points of the phones
    /// either side (12 and 13: 47; 16 Pro: 62), and the rim is blurred enough that those few points
    /// do not show as an arc leaving the corner.
    static let bezelRadius: CGFloat = 55

    /// The faint wash the bezel sits on: a breath of the accent under the top edge, gone by a
    /// fifth of the height, so the rim does not end in a hard line against the page. Kept low
    /// (owner, 2026-09-10: "reduce intensity so that the glow is mostly confined to the bezel
    /// edges") — a first cut at 0.26 reaching a third of the way down lit the whole top of the page.
    static func wash(pulse: Double, light: Color) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: light.opacity(0.08 * pulse), location: 0),
            .init(color: light.opacity(0.03 * pulse), location: 0.10),
            .init(color: light.opacity(0), location: 0.20),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// The lit bezel: a rounded rectangle the width of the host and taller than the ramp — its top
    /// edge on the top of the screen, its bottom edge clipped away — stroked twice on the edge
    /// itself, half the line off-screen: a wide, soft halo and a narrow, bright rim over it. The
    /// stroke is the same the whole way round, so the top and the corners are one lit edge. A
    /// vertical mask lets the sides fade from a third of the height and be gone before the ramp
    /// ends, so nothing of the halo reaches the ramp's foot.
    static func bezel(pulse: Double, light: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: bezelRadius, style: .continuous)
        return ZStack {
            // The halo reaches about 30 pt in (half its width plus the blur); wider and softer,
            // it was a glow over the page rather than on its edge (owner).
            shape.stroke(light.opacity(0.38 * pulse), lineWidth: 36).blur(radius: 14)
            shape.stroke(light.opacity(0.78 * pulse), lineWidth: 10).blur(radius: 4)
        }
        .frame(height: height * 3)                                             // the bottom edge is outside the ramp
        .frame(height: height, alignment: .top)
        .mask(
            LinearGradient(stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.32),
                .init(color: .clear, location: 0.85),
            ], startPoint: .top, endPoint: .bottom)
        )
        .clipped()
    }

    /// A tile of grey noise around the mid-point, made once. `.overlay` leaves mid-grey alone and
    /// nudges either side of it, so the average is unchanged and only the step edges move. Scale 3
    /// so each cell is one device pixel on a 3x phone (1.5 on a 2x one): drawn point-for-point it
    /// was a 3 × 3 px speckle that read as grain.
    static let ditherTile: Image = {
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

/// The glow with no ground under it: the wash and the lit bezel alone, transparent everywhere else,
/// so it can be laid over something that has already painted (owner, 2026-09-12 — the bottom of the
/// pager is an opaque `ground` fill drawn over the veil, and it was covering the foot of the glow).
/// `edge` says which way the lit edge faces: `.bottom` flips it to the foot of the screen, `.top`
/// leaves it as `WarmRamp` draws it.
///
/// **This is the glow that can go on top.** `WarmRamp` cannot: it is opaque on purpose — it carries
/// its own `ground` so a bar painting it over the veil shows exactly the veil's pixels — so raising
/// it above the pages would hide them. That is why every bar paints the ramp itself instead of the
/// glow being drawn over the bars. The catch is that the trick only holds while *everything* between
/// the veil and the bar is transparent; the moment one layer is not, the glow is cut off at the
/// bar's foot with nothing to say so (the Voice page, 2026-09-10). Laid over the bar instead, this
/// view needs nothing underneath to cooperate.
struct WarmRim: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which edge of the screen the lit rim faces.
    var edge: VerticalEdge = .bottom

    var body: some View {
        let showing = WarmUpVeil.isShowing(env)
        ZStack {
            if showing {
            TimelineView(.animation) { context in
                let settle = WarmUpVeil.isReady(env) ? WarmUpVeil.readySettle(env, now: context.date) : 0
                let breath = reduceMotion || WarmUpVeil.isFaked ? 1 : WarmRamp.pulse(at: context.date)
                let pulse = breath + (1 - breath) * settle
                let light = Tokens.glow.mix(with: Tokens.glowReady, by: settle)
                let glow = ZStack {
                    WarmRamp.wash(pulse: pulse, light: light)
                    WarmRamp.bezel(pulse: pulse, light: light)
                }
                // Dithered like the ramp, and for the same reason: these are the same shallow
                // gradients, and 8 bits cannot hold them without stepping into lines. The ramp can
                // scatter the steps inside a `compositingGroup` because it has its own opaque
                // ground in there to blend with. This has none — it is the glow alone — so the
                // noise blends against the real backdrop instead, and is masked by the glow's own
                // alpha so it lands only where there is light to dither and never as grain over a
                // bare page.
                //
                // A third of the ramp's strength, not all of it. The ramp's tile sits on an opaque
                // ground whose average `.overlay` leaves alone, so 0.85 there only nudged the
                // steps; masked to the glow's own alpha the average goes with it, and at full
                // strength grey noise lands *on* the blue and greys it — visible as speckle, and
                // half of why the light read dull (owner's screenshot, 2026-09-12). Enough to
                // break a band, not enough to take the colour out.
                glow
                    .overlay {
                        WarmRamp.ditherTile
                            .resizable(resizingMode: .tile)
                            .blendMode(.overlay)
                            .opacity(0.3)
                            .mask(glow)
                    }
                    .frame(height: WarmRamp.height)
                    .scaleEffect(y: edge == .bottom ? -1 : 1, anchor: .center)
            }
                .frame(height: WarmRamp.height)
                .transition(.opacity)
            }
        }
        .frame(height: WarmRamp.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: WarmUpVeil.fadeOut), value: showing)
    }
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
        let showing = WarmUpVeil.isShowing(env)
        ZStack {
            if showing {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    message(env.kokoroStatus, now: context.date)
                }
                .padding(.top, band + 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: WarmUpVeil.fadeOut), value: showing)
    }

    private func message(_ status: KokoroStatusModel, now: Date) -> some View {
        // The green beat: the wait is over, so the line says so and the bar fills, rather than
        // holding the last estimate — which reads as a countdown that stopped short.
        let ready = WarmUpVeil.isReady(env)
        let elapsed = status.warmUpStarted.map { now.timeIntervalSince($0) } ?? 0
        let byStages = status.warmUpStages.map { Double($0.loaded) / Double(max(1, $0.total)) } ?? 0
        let byClock = status.expectedWarmUpSeconds.map { min(0.92, elapsed / max(1, $0)) } ?? 0
        let warming = status.status == .installing ? (status.installProgress?.fraction ?? 0) : max(byStages, byClock)
        // Never below the high-water mark (`warmUpProgressFloor`): the raw signal above resets at
        // the install-to-stages seam and on a retried stage load, and without this the bar visibly
        // slid backward at either one (owner, 2026-09-12).
        let progress = ready ? 1 : max(warming, status.warmUpProgressFloor)
        return VStack(spacing: 7) {
            Text(ready ? "Voice ready" : line(status, elapsed: elapsed))
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
        if status.status == .installing { return Self.installLine(status.installProgress) }
        guard let expected = status.expectedWarmUpSeconds else {
            return "Warming up the voice · a few minutes the first time"
        }
        let left = expected - elapsed
        if left <= 1 { return "Warming up the voice · almost there" }
        if left >= 90 { return "Warming up the voice · about \(Int((left / 60).rounded())) min" }
        let rounded = left < 10 ? Int(left.rounded(.up)) : Int((left / 5).rounded(.up)) * 5
        return "Warming up the voice · about \(rounded) s"
    }

    /// The install's line: what is being waited for, downloaded or compiled, and how far along.
    static func installLine(_ progress: KokoroInstallProgress?) -> String {
        switch progress {
        case .none:
            return "Downloading the voice · once, over Wi-Fi"
        case .waitingForNetwork(let total):
            return "Waiting for Wi-Fi to download the voice · \(megabytes(total)) MB, once"
        case .downloading(let bytes, let total):
            return "Downloading the voice · \(megabytes(bytes)) of \(megabytes(total)) MB"
        case .retrying(let attempt, let of, let after, _):
            return "Download interrupted · trying again in \(Int(after.rounded())) s (\(attempt) of \(of))"
        case .compiling(let stage, let total):
            return "Preparing the voice · \(stage) of \(total)"
        }
    }

    private static func megabytes(_ bytes: Int) -> Int { Int((Double(bytes) / 1_000_000).rounded()) }
}
