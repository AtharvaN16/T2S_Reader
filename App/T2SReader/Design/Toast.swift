// App/T2SReader/Design/Toast.swift
import SwiftUI
import T2SApp

/// What a toast says: a line, an optional quieter second line, and up to two actions.
struct ToastContent: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var detail: String?
    var actionLabel: String?
    /// The glyph on the action pill. The bookmark toasts that came first all offer a note, so the
    /// pencil is the default rather than a value each of them repeats.
    var actionGlyph: String = "square.and.pencil"
    /// A second action beside the first — the bookmark toasts' way back to the list they just
    /// added to. Nil for every toast that only ever offers the one thing.
    var secondaryActionLabel: String? = nil
    var secondaryActionGlyph: String = "bookmark"
    /// The status glyph in a circle, leading the title. Nil keeps the toast the plain single line
    /// it always was; only the bookmark toasts, which now carry actions below the text rather than
    /// beside it, set this.
    var icon: String? = nil
    /// What a tap on the body of the message opens, when it opens anything. Non-nil is what draws
    /// the chevron that says the message can be tapped (owner, 2026-09-12: the toast went
    /// somewhere and nothing on it said so) and is the VoiceOver hint; nil leaves a tap as what it
    /// was, a way of getting the message out of the way. Only `bar`-shaped toasts use it — a
    /// `card` toast says where it goes with its own "Go to bookmark" pill instead.
    var tapHint: String? = nil

    static func == (a: ToastContent, b: ToastContent) -> Bool { a.id == b.id }
}

/// A transient message over the page (2026-09-11 spec §5). `ink` with `ground` lettering — the same
/// pairing as `Pill(.selected)` — so it reads as a message rather than a surface that can be
/// scrolled or swiped. Its actions are `Pill(.softOnInk)`: the app's soft grey capsule, with the
/// grey taken from the other theme's family so it lifts off the inverted card rather than sinking
/// into it (`Tokens.surfaceOnInk`).
///
/// It is not a sheet and never takes focus: the transport underneath stays live while it shows.
struct Toast: View {
    var content: ToastContent
    var onAction: () -> Void
    /// A tap anywhere but the actions. Not merely a dismissal: the Reader takes it to the list —
    /// the same thing the "Go to bookmark" pill does, when there is one.
    var onTap: () -> Void

    var body: some View {
        Group {
            if let icon = content.icon {
                card(icon: icon)
            } else {
                bar
            }
        }
        // Squarer than it was: at 16 on a short bar it read as a lozenge, and the message wants
        // the shape of a card (owner, 2026-09-12).
        .background(Tokens.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([content.title, content.detail].compactMap { $0 }.joined(separator: ", "))
        // A message that goes somewhere is a button, and says where; one that only dismisses is
        // still what it was, a line of text that has appeared.
        .accessibilityAddTraits(content.tapHint == nil ? .isStaticText : .isButton)
        .accessibilityHint(content.tapHint ?? "")
    }

    /// The bookmark toasts: a status line with a glyph, and up to two full-width actions on their
    /// own row below — "Add a note" and the way back to the list, side by side rather than one
    /// pill trailing the title on a single cramped baseline (owner, 2026-09-12).
    private func card(icon: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                CircleGlyph(systemName: icon, tint: Tokens.ground, fill: Tokens.surfaceOnInk)
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title).typeRole(.pill).foregroundStyle(Tokens.ground)
                    if let detail = content.detail {
                        Text(detail).typeRole(.meta).foregroundStyle(Tokens.ground.opacity(0.65)).lineLimit(1)
                    }
                }
            }
            if let label = content.actionLabel {
                // `.softOnInk`, not `.soft`: the card is `ink`, so the page's grey arrives inverted
                // on it — a near-black button on a near-white toast in the dark. This pair takes
                // the grey the right way round for the card they stand on, and at the shorter
                // height (owner, 2026-09-13), so the message stays a message.
                HStack(spacing: 8) {
                    Pill(label: label, glyph: content.actionGlyph, style: .softOnInk, fillsWidth: true,
                         compact: true, action: onAction)
                    if let secondaryLabel = content.secondaryActionLabel {
                        Pill(label: secondaryLabel, glyph: content.secondaryActionGlyph, style: .softOnInk,
                             fillsWidth: true, compact: true, action: onTap)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    /// Every other toast: one line, and at most the one trailing pill (Download the voice model,
    /// say). Unchanged — these never grew a second action or a status glyph.
    private var bar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(content.title).typeRole(.pill).foregroundStyle(Tokens.ground)
                    // The signifier: the disclosure chevron a row wears when tapping it goes
                    // somewhere. On the title rather than at the far edge, where the action pill
                    // lives — it belongs to the words it opens, and two marks on the right edge
                    // would read as one control with two parts.
                    if content.tapHint != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Tokens.ground.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                }
                if let detail = content.detail {
                    Text(detail).typeRole(.meta).foregroundStyle(Tokens.ground.opacity(0.65)).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if let label = content.actionLabel {
                Pill(label: label, glyph: content.actionGlyph, style: .soft, action: onAction)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, content.actionLabel == nil ? 18 : 12)
        .padding(.vertical, 14)
    }
}
