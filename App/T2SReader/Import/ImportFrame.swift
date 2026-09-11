// App/T2SReader/Import/ImportFrame.swift
import SwiftUI

/// The frame every import path shares (owner's reference, 2026-09-09: ElevenReader's "Paste
/// website link"): a circle to go back and the step's title centred in a bar where the hub's big
/// title was, the path's own content under it, and its one action as a full-width bar pinned to
/// the foot — above the keyboard, since it is a safe-area inset of the scroll view — grey and inert
/// until there is something to act on. A path is a step, and a step has a bar, not a page title.
/// Content scrolls up under the status bar, so the top wears the same fade as the root pages.
struct ImportFrame<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    /// Nil when there is no hub to go back to (files handed in from another app): the circle
    /// closes the page instead.
    var onBack: (() -> Void)?
    var action: ImportAction?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                bar
                content()
            }
            .padding(.horizontal, Spacing.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if let action {
                button(action)
                    .padding(.horizontal, Spacing.margin)
                    .padding(.top, 12)
                    .padding(.bottom, Spacing.grid)
                    .background(Tokens.ground)
            }
        }
        .overlay { GeometryReader { geo in TopFade(inset: geo.safeAreaInsets.top) } }
    }

    private var bar: some View {
        HStack {
            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                CircleGlyph(systemName: onBack == nil ? "xmark" : "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(onBack == nil ? "Close" : "Back")
            Spacer(minLength: 12)
            Text(title).typeRole(.sectionHeader).foregroundStyle(Tokens.ink).lineLimit(1)
            Spacer(minLength: 12)
            Color.clear.frame(width: 36, height: 36)                            // balances the circle so the title centres
        }
        .padding(.top, Spacing.grid * 2)
    }

    private func button(_ action: ImportAction) -> some View {
        BarButton(label: action.label, busyLabel: action.busyLabel, isEnabled: action.isEnabled, action: action.perform)
    }
}

/// `ImportFrame`'s bar at the foot: `label` while it can be pressed; `busyLabel` with a spinner,
/// inert, while the model works; `isEnabled` false makes it grey and inert with `label` still shown.
struct ImportAction {
    var label: String
    var busyLabel: String? = nil
    var isEnabled: Bool = true
    var perform: () -> Void
}
