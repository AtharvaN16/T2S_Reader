// App/T2SReader/Design/StatusGlow.swift
import CoreGraphics
import Foundation
import SwiftUI
import T2SApp
import UIKit

/// The one-time voice warm-up, shown wherever the reader is (owner, 2026-09-10, Tabby's launch
/// gradient as the reference): a blue glow down from the very top of the screen that breathes
/// until the stages are loaded, and one short line with how long it usually takes on this phone
/// over a hairline of progress (`StatusRows`).
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
/// **One layer, on top.** The glow is `StatusRim` — the wash and the lit bezel with no ground under
/// them — laid over whatever the screen has already painted: over `TopFade` on the root, over the
/// Reader's header, over a Settings subpage's ground. Nothing underneath has to cooperate.
///
/// It was the other way round until 2026-09-12, and the way it failed is worth keeping. An opaque
/// `StatusRamp` sat at the back of each stack and every ground bar painted that same ramp into
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
/// `StatusRows` names the phase, so a breathing rim over a book that is reading aloud is captioned
/// "Downloading the voice" and not left to be guessed at.
///
/// What is left here is the band's timing, in one place, so the ground, the rims and the rows all
/// leave together. Which job is speaking, and whether it has ended, belong to `AppStatusModel`.
@MainActor
enum StatusGlow {
    /// How long the light takes to go, matched to half a breath so it leaves at the pace it moved.
    ///
    /// **The ending outlasts the fade it starts.** Whether this warm-up has ended — the glow's last
    /// beat, green — is deliberately *not* the same gate as `AppStatusModel.isShowing`: it stays
    /// true right through the fade that `isShowing` going false starts, so the green, "Voice ready"
    /// and the full bar are what leaves the screen. The two parted company when the beat's end
    /// stopped clearing `readyAt` (`KokoroStatusModel`), and `AppStatusModel.endedAt` is where that
    /// date lives now.
    static let fadeOut: Double = 1.5

    /// How long everything that is *not* light takes to leave: the rows, the ground under them, and
    /// the host header that steps aside for them.
    ///
    /// They used to leave on `fadeOut` too, and one duration for two kinds of thing was the whole
    /// defect. A glow dying over a second and a half reads as a light going out; words and a bar
    /// doing it read as stuck, and a header sliding 54 pt over it reads as a collapse. Worse, an
    /// opaque ground fading by *opacity* while a header travels by *position* uncovers the page
    /// between them — the reader watched a hole open at the top and be filled in by the title bar
    /// (owner, 2026-09-15). Everything on this number moves together and nothing is uncovered; the
    /// light alone takes its time.
    static let leave: Double = 0.35

    /// How far into the ending's colour, eased on the same curve the breath uses. The blue takes a
    /// second and a half to breathe in; the ending takes the same to arrive, rather than cutting in
    /// over a quarter-second and reading as a flash (owner, 2026-09-12).
    ///
    /// One truth, aliased rather than restated: `AppStatusModel.endSettle` eases over this same
    /// number, and two copies of a curve's length are two things to change when it is next tuned.
    static let readyEase = StatusReading.readyEase

    /// `T2S_WARMUP=1` fakes a warm-up in the everyday build (`KokoroComposition`), and holds the
    /// pulse still so two screenshots are comparable. It used to force `AppStatusModel.isShowing`'s
    /// old equivalent true as well, because the fixture book plays and the playback gate would
    /// otherwise have left nothing to photograph; the fake sets a real warming status, so with that
    /// gate gone it needs no help.
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
/// pixels (see `StatusBand`). A ramp this shallow is asking more of 8 bits than they have: it
/// would hold one value for ten or twenty rows and then step, and the eye reads every step as a
/// line (measured on a screenshot: flat runs of up to 23 px). A tile of noise a few levels wide,
/// blended over the ramp at one cell per device pixel, scatters each step's edge into a pattern
/// too fine to see — measured after: no run longer than 3 px.
enum StatusRamp {
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

    /// The screen's corner radius, which the bezel follows — the real one where the system will
    /// say (owner, 2026-09-13: "the glow radius should match the phone screen radius").
    ///
    /// UIKit has no public accessor for it. `UIScreen` keeps the number under a private key, and
    /// this reads it through KVC: a plain `value(forKey:)`, on purpose, rather than a name spelled
    /// out of fragments to get it past a scanner — if it is not a thing we are willing to be seen
    /// doing, it is not a thing to do. **It is private API, and App Store review can object to
    /// it**; the fallback below is what ships if it ever has to be dropped.
    ///
    /// That fallback is what this constant was until today: the iPhone 14 to 16's 55 pt, within a
    /// few points of the phones either side and blurred enough that the difference did not show as
    /// an arc leaving the corner. It is still not far off — but the 11 Pro this app is tested on is
    /// 39, and at 16 points over, the lit corner did leave the glass.
    ///
    /// It was asked of a red rim that has since been dropped; the warm-up's blue one, which was
    /// always drawn at the wrong radius and never mentioned, is what kept the correction.
    /// Main-actor because reading it touches `UIApplication`; every caller is a view body.
    @MainActor static let bezelRadius: CGFloat = {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .screen ?? UIScreen.main
        if let radius = screen.value(forKey: "_displayCornerRadius") as? CGFloat, radius > 0 {
            return radius
        }
        return 55
    }()

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
    @MainActor static func bezel(pulse: Double, light: Color) -> some View {
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
/// leaves it as `StatusRamp` draws it.
///
/// **This is the glow that can go on top.** `StatusRamp` cannot: it is opaque on purpose — it carries
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
/// `StatusRim(edge:)` and nothing else — no frame, no `ignoresSafeArea`.
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
///
/// It takes its tone and its settle from the caller rather than reading a job's state itself, so
/// both rims on a surface can be given one reading from one frame and can never disagree about the
/// colour they are ending on (`StatusBand`).
struct StatusRim: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var env
    /// The light's colours, from the app's own object rather than from `\.readerPalette`: the band
    /// is drawn in a window of its own, which inherits no environment. See `StatusAppearance`.
    private var palette: ReaderPalette { env.statusAppearance.palette }
    /// Which edge of the screen the lit rim faces.
    var edge: VerticalEdge = .bottom
    /// Nil while nothing is showing; the band's tone once there is a reading.
    ///
    /// A wait that ended amber shares a wait that ended green's timing — the same date, the same
    /// ease, the same hold — and only the colour and the words differ, so a failure leaves the
    /// screen the way a success does rather than flashing something new at the reader.
    var tone: StatusReading.Tone?
    /// 0…1 into the ending's colour, on the breath's own curve. Zero while the job is running.
    var settle: Double

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
        let showing = tone != nil
        return ZStack {
            if showing {
            TimelineView(.animation) { context in
                // Both endings ride the same curve: the breath eases up to full while the colour
                // crosses over `readyEase`, so green and amber each arrive the way the blue moved.
                // Amber settles to two thirds rather than full — a warning that keeps breathing at
                // full reads as something still working on it, and nothing is.
                // The colour this wait is ending in, or nil while it is still running.
                let ending: Color? = switch tone {
                case .ready: palette.glowReady
                case .failed: Tokens.accent
                case .waiting, .none: nil
                }
                let breath = reduceMotion || StatusGlow.isFaked ? 1 : StatusRamp.pulse(at: context.date)
                let held = tone == .failed ? 0.66 : 1.0
                let pulse = breath + (held - breath) * settle
                let light = palette.glow.mix(with: ending ?? palette.glowReady, by: settle)
                let glow = ZStack {
                    StatusRamp.wash(pulse: pulse, light: light)
                    StatusRamp.bezel(pulse: pulse, light: light)
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
                        StatusRamp.ditherTile
                            .resizable(resizingMode: .tile)
                            .blendMode(.overlay)
                            .opacity(0.3)
                            .mask(glow)
                    }
                    .frame(height: StatusRamp.height)
                    .scaleEffect(y: edge == .bottom ? -1 : 1, anchor: .center)
            }
                .frame(height: StatusRamp.height)
                .transition(.opacity)
            }
        }
        .frame(height: StatusRamp.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        // Fill the region, pin the light to the edge, and close whatever gap is left between that
        // edge and the window's. See the note above for why the gap has to be measured rather than
        // assumed away.
        .padding(edge == .top ? .top : .bottom, -shortfall)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: StatusGlow.fadeOut), value: showing)
    }
}
