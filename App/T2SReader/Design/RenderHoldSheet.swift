// App/T2SReader/Design/RenderHoldSheet.swift
import SwiftUI
import T2SApp

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

/// The red light on the held-queue sheet's top edge: the warm-up's own rim (`WarmRamp`), lit in
/// `glowHot`. Drawn head-up and clipped to the card, so the bright edge lands on the card's top and
/// the wash falls away down into it.
///
/// **It does not breathe.** The warm-up pulses because something is working; a held queue is the
/// opposite, and `WarmRamp` already knows this — a failed warm-up settles its light to two thirds
/// and holds it there, because "a warning that keeps breathing at full reads as something still
/// working on it, and nothing is". This is that ending state from the start, so there is no
/// `TimelineView` here and nothing for Reduce Motion to turn off.
private struct HoldGlow: View {
    /// Below `WarmRamp`'s own held strength of 0.66 (owner, 2026-09-13: "slightly less intense").
    /// The warm-up's light is the app's headline event and can afford to be; this one is a notice
    /// that will sit there until the phone cools, and has to be liveable with for that long.
    private static let settled: Double = 0.45

    var body: some View {
        ZStack {
            WarmRamp.wash(pulse: Self.settled, light: Tokens.glowHot)
            WarmRamp.bezel(pulse: Self.settled, light: Tokens.glowHot)
        }
        .frame(height: WarmRamp.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        .background {
            let shape = UnevenRoundedRectangle(topLeadingRadius: Spacing.sheetCorner,
                                               topTrailingRadius: Spacing.sheetCorner, style: .continuous)
            // The light is *inside* the card, clipped to it (owner, 2026-09-13: "I can see the glow
            // in the booksheet, that's not where I want it"). Hung above the top edge it washed up
            // over the book sheet behind, which is the page the sheet is covering and has nothing to
            // do with the heat. Clipped, the lit edge is the card's own top and the wash falls into
            // the card — the sheet is what glows, and only the sheet.
            //
            // Over the fill and under the words: a glow drawn over the text would tint the sentence
            // it is there to let you read.
            ZStack(alignment: .top) {
                shape.fill(Tokens.raised)
                HoldGlow().frame(maxHeight: .infinity, alignment: .top)
            }
            .clipShape(shape)
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
}
