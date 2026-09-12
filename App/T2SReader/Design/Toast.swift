// App/T2SReader/Design/Toast.swift
import SwiftUI
import T2SApp

/// What a toast says: a line, an optional quieter second line, and at most one action.
struct ToastContent: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var detail: String?
    var actionLabel: String?

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
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title).typeRole(.pill).foregroundStyle(Tokens.ground)
                if let detail = content.detail {
                    Text(detail).typeRole(.meta).foregroundStyle(Tokens.ground.opacity(0.65)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let label = content.actionLabel {
                Pill(label: label, glyph: "square.and.pencil", style: .soft, action: onAction)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, content.actionLabel == nil ? 16 : 8)
        .padding(.vertical, 10)
        .background(Tokens.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([content.title, content.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isStaticText)
    }
}
