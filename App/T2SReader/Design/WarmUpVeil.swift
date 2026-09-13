// App/T2SReader/Design/WarmUpVeil.swift
import CoreGraphics
import Foundation
import SwiftUI
import T2SApp
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
/// **It stays for whoever is speaking under it.** The glow used to hide the moment audio flowed
/// from the phone's own voice — a book playing with a pulse over it read as an alarm rather than a
/// wait (owner, 2026-09-10) — with the hosted voice carved out as an exception a fortnight later
/// (owner, 2026-09-12: Heart from the mirrors *is* the wait for Heart on the phone). The carve-out
/// was the tell. A reader who has started a book is precisely the one who wants to know how much
/// longer the on-device voice will be, and taking the light and the bar away on the first sound
/// left them reading in the system voice with nothing on screen to say a download was still
/// running (owner, 2026-09-13: "I need to be aware of the status"). So the rule is now the plain
/// one: the wait shows for as long as the wait lasts, whichever voice is speaking over it.
///
/// The alarm the old rule was avoiding is answered by the words rather than by hiding the light —
/// `WarmUpLine` names the phase, so a breathing rim over a book that is reading aloud is captioned
/// "Downloading the voice" and not left to be guessed at.
@MainActor
enum WarmUpVeil {
    /// How long the light takes to go, matched to half a breath so it leaves at the pace it moved.
    static let fadeOut: Double = 1.5

    /// Warming, or holding the beat that ends a warm-up. Nothing about playback: what the reader is
    /// listening to while the stages load is not what decides whether the wait is on screen (see the
    /// note above). This is the whole of the rule, and it is the whole of it on purpose — every
    /// clause this used to carry existed to punch a hole back through a playback gate that is gone.
    static func isShowing(_ env: AppEnvironment) -> Bool {
        env.kokoroStatus.status.isWarming || env.kokoroStatus.isHoldingReadyBeat
    }

    /// Whether the hosted voice is the one speaking through this wait.
    static func isHostedSpeaking(_ env: AppEnvironment) -> Bool {
        env.player.routedVoiceID?.hasPrefix("cloud:") == true
    }

    /// Whether this warm-up has ended — the glow's last beat, green. Deliberately *not* the same
    /// gate as `isShowing`: it stays true right through the fade that `isShowing` going false
    /// starts, so the green, "Voice ready" and the full bar are what leaves the screen. The two
    /// parted company when the beat's end stopped clearing `readyAt` (`KokoroStatusModel`).
    static func isReady(_ env: AppEnvironment) -> Bool {
        env.kokoroStatus.readyAt != nil && !env.kokoroStatus.endedFailed
    }

    /// Whether this wait ended amber. Shares ``isReady``'s timing — the same date, the same ease,
    /// the same hold — and only the colour and the words differ, so a failure leaves the screen the
    /// way a success does rather than flashing something new at the reader.
    static func isFailed(_ env: AppEnvironment) -> Bool {
        env.kokoroStatus.readyAt != nil && env.kokoroStatus.endedFailed
    }

    /// The colour this wait is ending in, or nil while it is still running.
    static func endColour(_ env: AppEnvironment) -> Color? {
        guard env.kokoroStatus.readyAt != nil else { return nil }
        return env.kokoroStatus.endedFailed ? Tokens.accent : Tokens.glowReady
    }

    /// How far into the green, 0…1, eased on the same curve the breath uses. The blue takes a second
    /// and a half to breathe in; the green takes the same to arrive, rather than cutting in over a
    /// quarter-second and reading as a flash (owner, 2026-09-12).
    static let readyEase: Double = 1.4

    static func endSettle(_ env: AppEnvironment, now: Date) -> Double { readySettle(env, now: now) }

    static func readySettle(_ env: AppEnvironment, now: Date) -> Double {
        guard let readyAt = env.kokoroStatus.readyAt else { return 0 }
        let t = min(1, max(0, now.timeIntervalSince(readyAt) / readyEase))
        return t * t * (3 - 2 * t)                                   // smoothstep, as the cosine is at its ends
    }

    /// `T2S_WARMUP=1` fakes a warm-up in the everyday build (`KokoroComposition`), and holds the
    /// pulse still so two screenshots are comparable. It used to force ``isShowing`` true as well,
    /// because the fixture book plays and the playback gate would otherwise have left nothing to
    /// photograph; the fake sets a real warming status, so with that gate gone it needs no help.
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
///
/// **It anchors itself, and that is the whole of the arrangement.** The view fills whatever region
/// it is put in, pins its 240 pt of light to `edge`, and takes the safe-area inset on that edge, so
/// the lit rim lands on the screen's edge rather than on the inset's inner boundary. Call sites say
/// `WarmRim(edge:)` and nothing else — no frame, no `ignoresSafeArea`.
///
/// That is not tidiness. All four call sites used to spell the anchoring out, and one of them
/// spelled it in the wrong order: the Reader hung its foot rim off a ground that had already said
/// `.ignoresSafeArea(edges: .bottom)` and attached the rim as an `.overlay` *after* it. An
/// `ignoresSafeArea` bleeds a view's drawing outward but leaves the frame its own overlays align
/// against where it was, so the rim's lit edge sat on the inner boundary of the home-indicator
/// inset and the inset below it stayed dead ground — measured on the 16 Pro at exactly its 34 pt
/// (owner, 2026-09-12: "why does the warm-up glow in reader not go to the bottom of the page").
/// Nothing in the three copies that worked said which order was the load-bearing one, so there was
/// nothing to notice. With the anchoring in here there is no order left to get wrong, and a host
/// that has already bled its own safe area cannot shorten the glow, because the rim no longer hangs
/// off the host: it is a sibling over the page.
///
/// **The one place this does not reach is the top of a pushed Settings page**, which still wears a
/// status bar's worth of bare ground above the light. `ignoresSafeArea` is a no-op there — UIKit
/// has spent the inset and SwiftUI has none left to give back — and a measured `.offset` up to the
/// window's edge, the trick the page's own ground and `TopFade` use, does not show either: the
/// measurement is right (62 pt on the 16 Pro, read off the live view) and the light still does not
/// move, so something between the page and the window is clipping it. Unfinished, and deliberately
/// left as it was rather than guessed at.
struct WarmRim: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which edge of the screen the lit rim faces.
    var edge: VerticalEdge = .bottom

    var body: some View {
        // `ignoresSafeArea` on the outside, and inside it a reader that says whether the foot of
        // the light actually landed on the window's foot. Where it did — every surface on the
        // iOS 18 simulator — `shortfall` is zero and the negative padding is a no-op; where it did
        // not, `shortfall` is exactly the inset the rim still has to cross, and the padding takes
        // it there. Harsh's 17 Pro is the case that needs it: the Reader's foot came back one
        // home-indicator inset short of the glass, the same failure the Reader had on the way in
        // (owner, 2026-09-12), on a surface where the arrangement above is already correct.
        //
        // **The foot only.** The head is anchored the way it always was, because the measurement
        // lies there. On a pushed Settings page the top rim's *frame* reports the content's top —
        // a status bar down from the window — while its drawing has bled up to the glass anyway,
        // so correcting by the difference hoists the lit edge off the screen and leaves the sides
        // lit and the top gone. Measured against the previous build, the Voice page loses its top
        // rim exactly that way; the foot of every surface is pixel-identical. That asymmetry is
        // real — UIKit's navigation controller has spent the top inset and SwiftUI has none to
        // give back, which is the same thing the last paragraph above describes — so the foot is
        // the only edge where "where did I land" answers the question honestly.
        GeometryReader { geo in
            rim(shortfall: edge == .bottom ? footShortfall(in: geo) : 0)
        }
        .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
    }

    /// How far this view's foot still falls short of the window's, in points, clamped to the
    /// largest inset a phone has so a bad window read can never throw the light off the screen.
    private func footShortfall(in geo: GeometryProxy) -> CGFloat {
        guard let height = Self.windowHeight else { return 0 }
        return min(max(0, height - geo.frame(in: .global).maxY), 80)
    }

    /// The window the rim is measured against. `.global` is the hosting view's space, and every
    /// surface that draws a rim is full-screen (the root pager, a pushed Settings page, the
    /// Reader's `fullScreenCover`), so the hosting view *is* the window. nil rather than a guess
    /// when there is no key window to read: the rim then anchors the way it always did.
    private static var windowHeight: CGFloat? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .bounds.height
    }

    private func rim(shortfall: CGFloat) -> some View {
        let showing = WarmUpVeil.isShowing(env)
        return ZStack {
            if showing {
            TimelineView(.animation) { context in
                // Both endings ride the same curve: the breath eases up to full while the colour
                // crosses over `readyEase`, so green and amber each arrive the way the blue moved.
                // Amber settles to two thirds rather than full — a warning that keeps breathing at
                // full reads as something still working on it, and nothing is.
                let ending = WarmUpVeil.endColour(env)
                let settle = ending != nil ? WarmUpVeil.endSettle(env, now: context.date) : 0
                let breath = reduceMotion || WarmUpVeil.isFaked ? 1 : WarmRamp.pulse(at: context.date)
                let held = WarmUpVeil.isFailed(env) ? 0.66 : 1.0
                let pulse = breath + (held - breath) * settle
                let light = Tokens.glow.mix(with: ending ?? Tokens.glowReady, by: settle)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        // Fill the region, pin the light to the edge, and close whatever gap is left between that
        // edge and the window's. See the note above for why the gap has to be measured rather than
        // assumed away.
        .padding(edge == .top ? .top : .bottom, -shortfall)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: WarmUpVeil.fadeOut), value: showing)
    }
}

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
/// Everything this view says is resolved by `WarmUpReading`, which is a plain value and is tested.
/// This file only draws it.
struct WarmUpLine: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        let showing = WarmUpVeil.isShowing(env)
        ZStack {
            if showing {
                // Half-second ticks: a retry counts down in whole seconds, and a one-second period
                // lands the change up to a second late on half of them.
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    line(reading(now: context.date), now: context.date)
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

    // MARK: drawing

    @ViewBuilder
    private func line(_ reading: WarmUpReading, now: Date) -> some View {
        // The words go amber only on a failure. The bar also goes green on a success, so the fill
        // and the glow finish on the same colour, but the title stays ink there — "Voice ready" in
        // green over a green rim is the same thing said twice.
        let tint: Color = reading.tone == .failed ? Tokens.accent : Tokens.ink
        let barTint: Color = switch reading.tone {
        case .failed: Tokens.accent
        case .ready: Tokens.glowReady
        case .waiting: Tokens.ink
        }
        // Read from the wall clock, like `WarmRamp.pulse`, rather than from `warmUpStarted` — that
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
    private func bar(_ reading: WarmUpReading, tint: Color) -> some View {
        let weights = reading.segments
        let total = weights.reduce(0, +)
        let gaps = Self.segmentGap * CGFloat(max(0, weights.count - 1))
        let usable = Self.barWidth - gaps
        let filled = usable * reading.progress
        HStack(spacing: Self.segmentGap) {
            ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                let width = usable * (weight / total)
                let before = weights.prefix(index).reduce(0, +) / total * usable
                Capsule().fill(Tokens.ink3.opacity(0.6))
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

    // MARK: what the status means

    /// Maps this launch's state onto the phase `WarmUpReading` answers about. The mapping is the
    /// only part of the line that knows about `KokoroStatus`.
    private func reading(now: Date) -> WarmUpReading {
        let status = env.kokoroStatus
        return WarmUpReading(phase: phase(status, now: now),
                             progress: progress(status, now: now),
                             afterAnInstall: status.launchIncludedInstall)
    }

    private func phase(_ status: KokoroStatusModel, now: Date) -> WarmUpReading.Phase {
        if status.readyAt != nil {
            guard !status.endedFailed else {
                return .failed(status.endedFailedDuringInstall ? .install : .warmUp)
            }
            return .ready(buildingBackgroundSet: status.isBuildingBackgroundSet)
        }
        if case .installing = status.status { return installPhase(status, now: now) }
        // Heart from the mirrors is speaking while Heart installs on the phone. The glow stays up
        // through that audio on purpose, and this is the only line that explains why it is there.
        if WarmUpVeil.isHostedSpeaking(env) {
            return .hostedVoiceSpeaking(secondsLeft: secondsLeft(status, now: now))
        }
        if case .checking = status.status { return .checking }
        let left = secondsLeft(status, now: now)
        return .warming(secondsLeft: left, stalled: isStalled(status, now: now))
    }

    private func installPhase(_ status: KokoroStatusModel, now: Date) -> WarmUpReading.Phase {
        switch status.installProgress {
        case .none:
            // The split second after the install begins and before its first callback: nothing has
            // been counted yet, so there is nothing to count with.
            return .waitingForNetwork
        case .waitingForNetwork:
            return .waitingForNetwork
        case .downloading(let bytes, let total):
            return .downloading(received: megabytes(bytes), total: megabytes(total))
        case .retrying(_, _, let after, _):
            // `after` is the delay the retry was scheduled with, so on its own it never counts down
            // — the line read "trying again in 7 s" for the whole seven seconds. Subtracting the
            // time since the model took it makes it tick.
            let left = after - now.timeIntervalSince(status.installProgressAt)
            return .retrying(secondsLeft: Int(max(0, left).rounded(.up)))
        case .compiling(let stage, let total):
            return .preparing(step: stage, of: total, secondsLeft: nil)
        }
    }

    /// The clock: what is left of the length this phone remembered. Nil before there is one to
    /// remember, once it is spent, and while the warm-up has not started counting.
    private func secondsLeft(_ status: KokoroStatusModel, now: Date) -> Int? {
        guard let expected = status.expectedWarmUpSeconds, let started = status.warmUpStarted else { return nil }
        let left = expected - now.timeIntervalSince(started)
        guard left > 1 else { return nil }
        // Rounded up to the next five above ten seconds, so it does not tick every second for
        // minutes; below that it counts honestly, because a reader is watching the last few.
        return left < 10 ? Int(left.rounded(.up)) : Int((left / 5).rounded(.up)) * 5
    }

    /// Well past what this phone remembered, the estimate has stopped being a fact about anything.
    /// The title admits it and the clock goes, rather than freezing on a number that went wrong.
    private func isStalled(_ status: KokoroStatusModel, now: Date) -> Bool {
        guard let expected = status.expectedWarmUpSeconds, let started = status.warmUpStarted else { return false }
        return now.timeIntervalSince(started) > expected * 2
    }

    /// The floor and the clock's own guess, whichever is further on. Stages are exact but coarse and
    /// the clock is smooth but a guess; the floor is what keeps either of them from retreating at
    /// the install-to-stages seam or on a retried stage load.
    private func progress(_ status: KokoroStatusModel, now: Date) -> Double {
        if status.readyAt != nil { return status.endedFailed ? status.warmUpProgressFloor : 1 }
        guard let expected = status.expectedWarmUpSeconds, let started = status.warmUpStarted else {
            return status.warmUpProgressFloor
        }
        let byClock = min(0.92, now.timeIntervalSince(started) / max(1, expected))
        let scaled = status.launchIncludedInstall
            ? KokoroStatusModel.installShare + (1 - KokoroStatusModel.installShare) * byClock
            : byClock
        return max(status.warmUpProgressFloor, scaled)
    }

    private func megabytes(_ bytes: Int) -> Int { Int((Double(bytes) / 1_000_000).rounded()) }
}
