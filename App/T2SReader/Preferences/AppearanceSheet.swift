// App/T2SReader/Preferences/AppearanceSheet.swift
import SwiftUI
import UIKit
import T2SApp

/// Settings → Appearance (2026-09-19, after the owner's reference, Luma's Appearance page): the
/// colour scheme as three cards, and under them the app icon as a grid of its ten liveries.
///
/// Until now this was `ReaderPreferencesSheet` with the Reader's controls hidden — two pills, Light
/// and Dark, and a line saying they applied everywhere. `System` is back here: the reference has
/// it, and it is what most phones are left on. It left the Reader's *own* sheet on 2026-09-14
/// because a paper swatch that changed face at sunset was confusing, and there it stays gone; a
/// reader on System sees that sheet's pills lit for whichever face the device is showing.
///
/// The grid asks iOS which icon is on rather than keeping a preference: `alternateIconName` is
/// the one true answer, read on appear and again after every change. A change iOS refuses — a
/// name the build never carried — leaves the grid where it was. iOS also puts up its own alert
/// after each change; that is the platform's, and there is no supported way round it.
struct AppearanceSheet: View {
    @Environment(AppEnvironment.self) private var env
    @State private var icon: AppIcon = .standard
    @State private var isChangingIcon = false
    /// Opens at large: the grid is the point of the sheet, and at medium only its first row shows.
    /// Medium stays offered, for a reader who only came for the scheme.
    @State private var detent: PresentationDetent = .large

    /// The cell's picture: 64 pt, squircle-cornered at iOS's own ratio, so it is the home screen's
    /// icon at the home screen's size and not a thumbnail of one.
    private static let cell: CGFloat = 64

    var body: some View {
        @Bindable var preferences = env.preferences
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Text("Appearance")
                    .typeRole(.sectionHeader)
                    .foregroundStyle(Tokens.ink)
                    .padding(.top, Spacing.section)
                schemes($preferences.theme)
                icons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.section)
        }
        .presentationBackground(Tokens.raised)
        .appTheme()                                                    // this sheet owns the switch; it had better follow it
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationCornerRadius(Spacing.sheetCorner)
        .onAppear { icon = AppIcon(alternateIconName: UIApplication.shared.alternateIconName) }
    }

    // MARK: - Colour scheme

    /// Three cards in a row — the reference's, in the app's greys: a glyph at the top, the word at
    /// the foot, the chosen one drawn in ink with an ink border and the others in grey.
    @ViewBuilder private func schemes(_ choice: Binding<ReaderTheme>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Colour scheme").typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                Text("Turn on dark mode, or match your device.")
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                ForEach(ReaderTheme.allCases, id: \.self) { theme in
                    schemeCard(theme, isOn: choice.wrappedValue == theme) {
                        withAnimation(.snappy(duration: 0.2)) { choice.wrappedValue = theme }
                    }
                }
            }
        }
    }

    private func schemeCard(_ theme: ReaderTheme, isOn: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: theme.glyph).font(.system(size: 22, weight: .semibold))
                Text(theme.title).typeRole(.rowTitle).lineLimit(1)
            }
            .foregroundStyle(isOn ? Tokens.ink : Tokens.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Tokens.raised, in: shape)
            // `strokeBorder`, inside the shape, so the chosen card and the others are one size.
            .overlay { shape.strokeBorder(isOn ? Tokens.ink : Tokens.ink3, lineWidth: isOn ? 2 : 1.5) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - App icon

    /// Four to a row, the word under each, and the app's radio mark under the word of the one that
    /// is on — the reference's tick, in the mark the app already uses for a chosen thing. Every
    /// cell carries the mark at zero opacity so the rows keep their height as the choice moves.
    private var icons: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App icon").typeRole(.rowTitle).foregroundStyle(Tokens.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4),
                      spacing: 20) {
                ForEach(AppIcon.allCases) { choice in
                    iconCell(choice, isOn: choice == icon) { select(choice) }
                }
            }
        }
    }

    private func iconCell(_ choice: AppIcon, isOn: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cell * 0.2237, style: .continuous)
        return Button(action: action) {
            VStack(spacing: 8) {
                Image(choice.previewAssetName)
                    .resizable()
                    .frame(width: Self.cell, height: Self.cell)
                    .clipShape(shape)
                    // A hairline, or Zen's cream face on the light sheet is nothing at all.
                    .overlay { shape.strokeBorder(Tokens.edge, lineWidth: 1) }
                Text(choice.title).typeRole(.pill).foregroundStyle(Tokens.ink).lineLimit(1)
                RadioMark(isOn: true).opacity(isOn ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isChangingIcon)
        .accessibilityLabel("\(choice.title) icon")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// Ask iOS, then read back what it did. The grid moves on the answer, not on the tap, so a
    /// refusal (a name not in this build, or a device that does not do alternates) is a grid that
    /// stays where it was rather than one that lies.
    private func select(_ choice: AppIcon) {
        guard choice != icon, !isChangingIcon, UIApplication.shared.supportsAlternateIcons else { return }
        isChangingIcon = true
        Task {
            try? await UIApplication.shared.setAlternateIconName(choice.alternateIconName)
            withAnimation(.snappy(duration: 0.2)) {
                icon = AppIcon(alternateIconName: UIApplication.shared.alternateIconName)
            }
            isChangingIcon = false
        }
    }
}

extension ReaderTheme {
    /// The card's word. `System` is the device's own setting, the other two override it.
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var glyph: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}
