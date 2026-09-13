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

    /// Nil unless the queue is held for a reason the reader did not choose, and they have not
    /// already put the notice away. A pause they asked for is never news: the sheet's own progress
    /// block says "Paused" and offers Resume, and a modal on top of it explaining that they have
    /// paused would be the app talking back.
    private var hold: ChapterRenderRunner.Hold? {
        guard !env.chapterRenderer.holdNoticeDismissed else { return nil }
        switch env.chapterRenderer.hold {
        case .hot, .storeFull: return env.chapterRenderer.hold
        case .byReader, .none: return nil
        }
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
        // Plain ground. A red light lived on this card for an afternoon on 2026-09-13 — over its
        // top edge, then clipped inside it, then up at the head of the screen — and was dropped:
        // "it is not adding much" (owner). Worth keeping the bug it left behind, though: clipping
        // the light to this card is what left the card's foot short, because `clipShape` fixes the
        // drawing to the frame it was applied on, so the `ignoresSafeArea` outside it expanded the
        // layout into the home-indicator strip and then had the fill clipped away again (owner:
        // "the bottom sheet bottom is not filled"). Nothing clips here, so the fill reaches glass.
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
        switch hold {
        case .hot: return "Rendering paused"
        case .storeFull: return "No room for audio"
        case .byReader: return "Rendering paused"           // never shown; `RenderHoldHost` filters it out
        }
    }

    private var message: String {
        switch hold {
        case .hot: return "The phone is warm. Rendering picks up on its own once it cools."
        case .storeFull: return "There is no room left for audio. Free some in Settings → Storage."
        case .byReader: return "Paused. Resume it whenever you like."
        }
    }
}

extension View {
    /// Draws the held-queue sheet over this surface. Placed on every layer that can be frontmost —
    /// the root pager, the Reader over it, and the book sheet over that.
    func renderHoldSheet() -> some View {
        overlay { RenderHoldHost() }
    }

}
