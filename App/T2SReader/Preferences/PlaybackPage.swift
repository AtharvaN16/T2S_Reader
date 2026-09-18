// App/T2SReader/Preferences/PlaybackPage.swift
import SwiftUI
import T2SApp

/// Settings → Preferences → Playback (owner, 2026-09-18): the three numbers the Player starts from,
/// each a row with its value in a pill that is the menu — exactly as they sat on Settings' root
/// before Playback became one row there.
struct PlaybackPage: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var preferences = env.preferences
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                PageTitle(text: "Playback", topPadding: Spacing.subpageTitleTop)
                VStack(alignment: .leading, spacing: 20) {
                    row("Default speed") {
                        Menu {
                            ForEach(SpeedPickerModel.rates, id: \.self) { rate in
                                Button(SpeedPickerModel.label(for: rate)) { preferences.defaultRate = rate }
                            }
                        } label: {
                            valuePill(SpeedPickerModel.label(for: preferences.defaultRate))
                        }
                    }
                    row("Skip back") {
                        Menu {
                            ForEach(ReaderPreferences.skipBackOptions, id: \.self) { seconds in
                                Button("\(seconds) s") { preferences.skipBackSeconds = seconds }
                            }
                        } label: {
                            valuePill("\(preferences.skipBackSeconds) s")
                        }
                    }
                    row("Skip forward") {
                        Menu {
                            ForEach(ReaderPreferences.skipForwardOptions, id: \.self) { seconds in
                                Button("\(seconds) s") { preferences.skipForwardSeconds = seconds }
                            }
                        } label: {
                            valuePill("\(preferences.skipForwardSeconds) s")
                        }
                    }
                }
                Text("The speed is where a book starts; the Player's own dial changes it for that book. Skips are what the two keys either side of Play do.")
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Color.clear.frame(height: Spacing.bottomClearance)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .settingsSubpage()
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).typeRole(.settingsRow).foregroundStyle(Tokens.ink)
            Spacer()
            control()
        }
    }

    private func valuePill(_ text: String) -> some View {
        Text(text)
            .typeRole(.pill)
            .foregroundStyle(Tokens.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Tokens.surface, in: Capsule())
    }
}
