// App/T2SReader/Design/RenderHoldSheet.swift
import SwiftUI
import T2SApp
import UIKit

/// The chapter queue, stopped with work still in it, said where the reader is actually looking.
///
/// It used to be a block inside the book sheet's render banner, above the chapter list. That put it
/// at the top of a sheet whose whole point is the list below it, so the reader who had just picked
/// four chapters scrolled past the sentence explaining why nothing was happening and never saw the
/// one control that would start it (owner, 2026-09-13: "I can't see it on the top of the
/// booksheet"). A held queue is also not the book sheet's business — the queue is the app's, and
/// it keeps holding while the reader is in the Reader or on Home — so this is app-wide and comes up
/// from the foot, the way every other thing that wants an answer does.
///
/// Not a `.sheet`: a real one can only be presented by the frontmost presenter, and the hold's most
/// likely moment is *while the book sheet is up*, which already owns that slot. So it is a card and
/// a scrim in a `ZStack`, drawn by each surface that can be frontmost — the same arrangement
/// `ToastHost` uses, and for the same reason.
struct RenderHoldHost: View {
    @Environment(AppEnvironment.self) private var env

    /// Nil unless the queue is held and the reader has not already put the notice away.
    private var hold: ChapterRenderRunner.Hold? {
        env.chapterRenderer.holdNoticeDismissed ? nil : env.chapterRenderer.hold
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let hold {
                // The scrim is what makes it a sheet rather than a banner: the page behind goes
                // quiet, and a tap anywhere off the card is the dismissal, as on a real one.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { env.chapterRenderer.dismissHoldNotice() }
                    .transition(.opacity)
                    .accessibilityHidden(true)
                RenderHoldSheet(hold: hold,
                                onContinue: { env.chapterRenderer.continueAnyway() },
                                onDismiss: { env.chapterRenderer.dismissHoldNotice() })
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.snappy, value: hold)
    }
}

/// The red light a held queue puts on the screen: `WarmRim`'s arrangement exactly — the warm-up's
/// wash and lit bezel with no ground under them — at the head of the screen, in `glowHot`.
///
/// **At the top, and nowhere near the card** (owner, 2026-09-13). It was tried at the foot, where
/// it lit the keys and read as a glowing button, and then on the card's own top edge, where the two
/// were one object and the light had to be clipped to keep it off the page behind. This is the
/// place the app already keeps a light that means "the phone is busy with something": the same edge
/// the blue warm-up rim uses, so red there is read the same way and needs no explaining.
///
/// **It does not breathe.** The warm-up pulses because something is working; a held queue is the
/// opposite, and `WarmRamp` already knows this — a failed warm-up settles its light to two thirds
/// and holds it there, because "a warning that keeps breathing at full reads as something still
/// working on it, and nothing is". This is that ending state from the start, so there is no
/// `TimelineView` here and nothing for Reduce Motion to turn off.
struct RenderHoldGlow: View {
    /// A shade under `WarmRamp`'s own held strength of 0.66. The owner walked this down to 0.45 and
    /// back up a notch once it was at the top of the screen instead of round the card — the light
    /// had further to travel and less to sit against there (2026-09-13, "slightly less intense",
    /// then "very slightly more intense").
    static let settled: Double = 0.55

    var body: some View {
        ZStack {
            WarmRamp.wash(pulse: Self.settled, light: Tokens.glowHot)
            WarmRamp.bezel(pulse: Self.settled, light: Tokens.glowHot)
        }
        .frame(height: WarmRamp.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The window the light lives in, and why it needs one.
///
/// A sheet is not drawn inside the view that presents it — UIKit puts the presented controller over
/// the presenter — so an `overlay` anywhere in the pager's hierarchy is *under* the book sheet, and
/// the sheet's own top edge cut the rim off a little way down the screen (owner, 2026-09-13: "the
/// booksheet is covering it"). Drawing a second copy inside the sheet was the arrangement this
/// replaces, and it cannot be the answer either: a sheet's frame starts below the window's top, so
/// its copy lands on the sheet's edge rather than the screen's.
///
/// A window above `.alert` has neither problem. It is the screen's edge by construction, it clears
/// every sheet and `fullScreenCover` without knowing they exist, and — `isUserInteractionEnabled`
/// being false — it is invisible to touch, so nothing underneath loses a tap. It is never made key,
/// so it never takes over the status bar's appearance from the app's own window.
///
/// The one window is enough for the whole app, which is why this is the only thing `renderHoldGlow`
/// does and why only the root pager applies it. Torn down, not merely hidden, when the hold lifts:
/// a spare `UIWindow` retained for the life of the process to show nothing is a thing that will one
/// day be wondered about.
@MainActor
enum RenderHoldGlowWindow {
    private static var window: UIWindow?
    /// The same fade `WarmRim` uses when the warm-up's light arrives and leaves.
    private static let fade: TimeInterval = 0.3

    static func setShown(_ shown: Bool) {
        shown ? show() : hide()
    }

    private static func show() {
        guard window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let host = UIHostingController(rootView: RenderHoldGlow())
        host.view.backgroundColor = .clear
        let made = UIWindow(windowScene: scene)
        made.windowLevel = .alert + 1
        made.backgroundColor = .clear
        made.isUserInteractionEnabled = false
        made.rootViewController = host
        made.alpha = 0
        made.isHidden = false
        window = made
        UIView.animate(withDuration: fade) { made.alpha = 1 }
    }

    private static func hide() {
        guard let going = window else { return }
        window = nil
        UIView.animate(withDuration: fade) { going.alpha = 0 } completion: { _ in
            going.isHidden = true
        }
    }
}

/// Puts the light up for as long as the queue is held and the reader has not dismissed the notice.
private struct RenderHoldGlowDriver: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    private var isHeld: Bool {
        !env.chapterRenderer.holdNoticeDismissed && env.chapterRenderer.hold != nil
    }

    func body(content: Content) -> some View {
        content
            // Not while the app is away: the window belongs to a foreground scene, and one built on
            // the way out would be a window with no scene to live in.
            .onChange(of: isHeld && scenePhase == .active, initial: true) { _, shown in
                RenderHoldGlowWindow.setShown(shown)
            }
    }
}

/// The card itself: why the queue stopped, and what can be done about it from here.
struct RenderHoldSheet: View {
    var hold: ChapterRenderRunner.Hold
    var onContinue: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        // Two gaps, not three (owner, 2026-09-13: "use better spacing for hierarchy"). The title
        // and the sentence under it are one thing to read, so they sit close; the choice below is
        // a different thing to do, so it stands well off. An even 20 between all three made the
        // card read as a list of three rows.
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).typeRole(.groupTitle).foregroundStyle(Tokens.ink)
                Text(message)
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Heat is the reader's call to overrule; a full store is not — there is nothing to
            // press through, so that one gets the single way out and no false choice beside it.
            //
            // Full height, not `compact` (owner, 2026-09-13: "too skinny"). A compact pill is the
            // toast's, where the message covers the page for four seconds and two tall keys would
            // read as a dialog; this *is* the dialog, and its keys belong at the app's own key
            // height — the sleep timer's Start, within a few points of a `BarButton`'s 56.
            HStack(spacing: 8) {
                if hold == .hot {
                    Pill(label: "Not now", style: .soft, fillsWidth: true, action: onDismiss)
                    Pill(label: "Continue anyway", style: .selected, fillsWidth: true,
                         action: { onContinue(); onDismiss() })
                } else {
                    Pill(label: "OK", style: .selected, fillsWidth: true, action: onDismiss)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.margin)
        // Deep at the head (owner, 2026-09-13: "make the bottom sheet a bit taller"). A card whose
        // first line starts a grid off its top edge reads as a banner that happens to be at the
        // foot; the air is what makes it a sheet the page has given way to.
        .padding(.top, 44)
        // The home indicator's strip is the card's, not the page's: a sheet that stops above it
        // leaves a sliver of the dimmed page under its foot.
        .padding(.bottom, 36)
        // Plain ground, and no light on it: the glow is `RenderHoldGlow` at the top of the screen
        // now (owner, 2026-09-13). Clipping a glow to this card is also what left its foot short —
        // a `clipShape` fixes the drawing to the frame it was applied on, so the `ignoresSafeArea`
        // outside it expanded the layout into the home-indicator strip and then had the fill
        // clipped away again, and the dimmed page showed through under the keys (owner: "the bottom
        // sheet bottom is not filled"). Nothing clips here, so the fill reaches the glass.
        .background {
            let shape = UnevenRoundedRectangle(topLeadingRadius: Spacing.sheetCorner,
                                               topTrailingRadius: Spacing.sheetCorner, style: .continuous)
            shape.fill(Tokens.raised)
                .overlay(shape.strokeBorder(Tokens.edge, lineWidth: 1))
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var title: String {
        hold == .hot ? "Rendering paused" : "No room for audio"
    }

    private var message: String {
        hold == .hot
            ? "The phone is warm. Rendering picks up on its own once it cools."
            : "There is no room left for audio. Free some in Settings → Storage."
    }
}

extension View {
    /// Draws the held-queue sheet over this surface. Placed on every layer that can be frontmost —
    /// the root pager, the Reader over it, and the book sheet over that.
    func renderHoldSheet() -> some View {
        overlay { RenderHoldHost() }
    }

    /// Puts the held-queue light at the head of the screen, in a window of its own above every
    /// sheet. The root pager alone applies it — see `RenderHoldGlowWindow` for why one is enough.
    func renderHoldGlow() -> some View {
        modifier(RenderHoldGlowDriver())
    }
}
