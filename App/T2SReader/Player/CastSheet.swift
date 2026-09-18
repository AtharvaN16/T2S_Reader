// App/T2SReader/Player/CastSheet.swift
import SwiftUI
import T2SApp

/// Cast: the name, the system's AirPlay picker on a `surface` circle, and one line saying what it
/// does. Nothing else on purpose (owner, 2026-09-18) — the picker opens the system's own list of
/// speakers and TVs, and that list is the whole feature. Reached from the Reader's overflow, and
/// again from the "Casting to …" pill that replaces the title while a cast is on.
struct CastSheet: View {
    @Environment(AppEnvironment.self) private var env
    /// True when the Reader presented this, and so when it should wear the book's paper.
    var wearsPaper = false

    /// Read on every pass, like the other Reader sheets: a paper chosen while this is open should
    /// repaint it.
    private var palette: ReaderPalette { wearsPaper ? ReaderPalette(env.preferences.readerPaper) : .app }

    private static let pickerSize: CGFloat = 76
    private static let height: CGFloat = 240

    var body: some View {
        let device = env.audioSession.castingTo
        VStack(spacing: 0) {
            // No glyph over the name, unlike the other sheets: the picker under it *is* the
            // AirPlay glyph, and two of the same symbol stacked read as a mistake.
            Text("Cast").typeRole(.sectionHeader).foregroundStyle(palette.ink)
                .padding(.top, Spacing.margin)
                .padding(.bottom, Spacing.row)

            RoutePickerView(tint: palette.ink)
                .frame(width: Self.pickerSize, height: Self.pickerSize)
                .background(palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Tokens.edge, lineWidth: 1))
                .accessibilityLabel("Choose where to play")

            Text(device.map { "Casting to \($0)" } ?? "Pick a speaker or a TV")
                .typeRole(.meta)
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
                .padding(.top, Spacing.row)
                .animation(.easeInOut(duration: 0.2), value: device)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.margin)
        .padding(.bottom, Spacing.margin)
        .presentationBackground(palette.sheet)
        .appTheme()
        .environment(\.readerPalette, palette)
        .presentationDetents([.height(Self.height)])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}
