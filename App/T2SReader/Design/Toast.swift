// App/T2SReader/Design/Toast.swift
import SwiftUI
import T2SApp

/// What a toast says: a line, an optional quieter second line, and at most one action.
struct ToastContent: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var detail: String?
    var actionLabel: String?
    /// The glyph on the action pill. The bookmark toasts that came first all offer a note, so the
    /// pencil is the default rather than a value each of them repeats.
    var actionGlyph: String = "square.and.pencil"
    /// What a tap on the body of the message opens, when it opens anything — "Opens the bookmarks"
    /// on a bookmark just saved. Non-nil is what draws the chevron that says the message can be
    /// tapped (owner, 2026-09-12: the toast went somewhere and nothing on it said so) and is the
    /// VoiceOver hint; nil leaves a tap as what it was, a way of getting the message out of the way.
    var tapHint: String? = nil

    static func == (a: ToastContent, b: ToastContent) -> Bool { a.id == b.id }
}

/// A transient message over the page (2026-09-11 spec §5). `ink` with `ground` lettering — the same
/// pairing as `Pill(.selected)` — so it reads as a message rather than a surface that can be
/// scrolled or swiped. The one action sits inside it as a `soft` pill, which on `ink` is the
/// `surface` capsule the rest of the app uses.
///
/// It is not a sheet and never takes focus: the transport underneath stays live while it shows.
struct Toast: View {
    var content: ToastContent
    var onAction: () -> Void
    /// A tap anywhere but the action. Not merely a dismissal: the Reader takes it to the list.
    var onTap: () -> Void

    var body: some View {
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
}
