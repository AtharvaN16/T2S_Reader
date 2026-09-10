// App/T2SReader/Design/TitleMenu.swift
import SwiftUI

/// The stacked chevrons that turn a page title into a picker (owner's reference, 2026-09-10:
/// Snipd's "Queue ⌄"). A label, not a button — the whole title is the control — and pulled up off
/// the baseline onto the word's x-height, so it reads as part of the title rather than a footnote
/// hanging under it.
struct TitleChevron: View {
    var body: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Tokens.ink)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 12 }
            .accessibilityHidden(true)
    }
}

/// The menu that drops from a `TitleChevron`: a raised card, one row per option, the chosen one on
/// a faint ink film with the `RadioMark` the voice list already uses for "this is the one". The
/// film is `ink` at low opacity rather than `surface` so the row still reads as chosen in the dark
/// theme, where `surface` and `raised` are four values apart.
///
/// Replaced the Collection's `FilterTabs` (owner, 2026-09-10): the kind belongs in the title — the
/// page names what it is showing — not in a second row of words under it.
struct TitleMenuCard<Option: Hashable>: View {
    var options: [Option]
    var title: (Option) -> String
    var selection: Option
    var pick: (Option) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button { pick(option) } label: {
                    HStack(spacing: 16) {
                        Text(title(option)).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                        Spacer(minLength: 20)
                        if isOn { RadioMark(isOn: true) }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)                              // grows with Dynamic Type rather than clipping
                    .background(isOn ? Tokens.ink.opacity(0.07) : .clear,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        // Wide enough to look like a menu and no wider than its longest word needs — without
        // this the card is handed the whole page width and the rows' `Spacer`s take it.
        .frame(minWidth: 188)
        .fixedSize(horizontal: true, vertical: false)
        .padding(6)
        .background(Tokens.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // The edge the shadow cannot draw in the dark (`Tokens.edge`): on black a shadow is nothing,
        // and the card was a slightly-less-black rectangle with no rim.
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Tokens.edge, lineWidth: 1))
        .shadow(color: Tokens.shade.opacity(0.16), radius: 18, y: 8)
    }
}

/// Where the title sits, carried up to whoever draws the card so it can hang under the word
/// wherever Dynamic Type puts it — an anchor rather than a frame in a named coordinate space,
/// which a `ScrollView` between the two does not pass through.
struct TitleAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
