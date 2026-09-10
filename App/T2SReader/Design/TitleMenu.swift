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

/// How the title menu moves (owner, 2026-09-10: "a nice animation when clicking filter, like the
/// spring pop we have in latest iOS"). The card drops out of the title's top-left corner and
/// overshoots a little before settling; the rows arrive after it, each a beat behind the one above,
/// which is the part that reads as iOS rather than as a card being faded in. Closing does not
/// bounce and is half the length — a menu that springs shut feels undecided, and by then the reader
/// is looking at what they picked, not at the menu.
enum TitleMenuMotion {
    /// Opening: `dampingFraction` under 1 is the overshoot.
    static let open: Animation = .spring(response: 0.34, dampingFraction: 0.66)
    /// Closing: critically damped, quick, no bounce.
    static let close: Animation = .spring(response: 0.22, dampingFraction: 1)
    /// One row after another, from the top.
    static let rowStagger: Double = 0.032
    /// The card growing out of the corner it hangs from. Asymmetric: it leaves from nearer full
    /// size than it arrives at, so the close reads as a dismissal rather than a rewind.
    /// Computed, not stored: `AnyTransition` is not `Sendable`, so a `static let` of one is a
    /// concurrency error under Swift 6.
    static var transition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.82, anchor: .topLeading)
                .combined(with: .offset(y: -12))
                .combined(with: .opacity),
            removal: .scale(scale: 0.94, anchor: .topLeading).combined(with: .opacity)
        )
    }

    /// The animation for a toggle that is about to become `opening`.
    static func toggle(opening: Bool) -> Animation { opening ? open : close }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False for the first frame the card exists, true from the next: what the rows animate on.
    /// Reduce Motion starts it true, so the rows are simply there when the card is.
    @State private var rowsIn = false

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                let isOn = option == selection
                let shown = rowsIn || reduceMotion
                Button { pick(option) } label: {
                    HStack(spacing: 16) {
                        Text(title(option)).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                        Spacer(minLength: 20)
                        if isOn { RadioMark(isOn: true) }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)                              // grows with Dynamic Type rather than clipping
                    .contentShape(Rectangle())
                }
                .buttonStyle(MenuRowStyle(isOn: isOn))
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
                // The stagger: each row a beat behind the one above it, rising the last few points
                // into place. Only on the way in — see `TitleMenuMotion`.
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : -10)
                .scaleEffect(shown ? 1 : 0.96, anchor: .top)
                .animation(reduceMotion ? nil
                           : .spring(response: 0.32, dampingFraction: 0.74)
                               .delay(Double(index) * TitleMenuMotion.rowStagger),
                           value: shown)
            }
        }
        .onAppear { rowsIn = true }
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

/// One row's film: the chosen row's faint ink, and a stronger one under a finger, with the row
/// giving a little as it is pressed. A style rather than a `.background` on the label so the two
/// states are one surface and cross into each other instead of stacking.
private struct MenuRowStyle: ButtonStyle {
    var isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background(Tokens.ink.opacity(isOn ? (pressed ? 0.13 : 0.07) : (pressed ? 0.07 : 0)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.16), value: pressed)
    }
}

/// The trigger's own pop (owner, 2026-09-10: "I want the kind frame to also scale with a pop") —
/// the title-and-chevron button that opens the card, not the card itself. Two motions share the
/// button: a finger pressing it shrinks it a touch, sprung back on release (`TitleTriggerStyle`);
/// opening or closing it scales it past 1 and back, on `TitleMenuMotion`'s own animation, so the
/// trigger and the card it opens move on the same spring.
struct TitleTriggerStyle: ButtonStyle {
    /// Whether the menu the trigger opens is up: the settled scale is a hair over 1 while open,
    /// so the title reads as "pulled out" rather than snapping to a size and stopping.
    var isOpen: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect((isOpen ? 1.035 : 1) * (configuration.isPressed ? 0.95 : 1))
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
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
