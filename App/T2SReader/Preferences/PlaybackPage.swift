// App/T2SReader/Preferences/PlaybackPage.swift
import SwiftUI
import T2SApp

/// Settings → Preferences → Playback (owner, 2026-09-18): the three numbers the Player starts from.
/// They sat on Settings' root as pills until the root became cards of rows; a pill is `surface`,
/// and inside a `surface` group it vanishes, so each value is a word with the up-down chevron a
/// menu wears in the system's own Settings.
struct PlaybackPage: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var preferences = env.preferences
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                PageTitle(text: "Playback", topPadding: Spacing.subpageTitleTop)
                SettingsGroup {
                    SettingsGroupRow(title: "Default speed") {
                        menu(SpeedPickerModel.label(for: preferences.defaultRate)) {
                            ForEach(SpeedPickerModel.rates, id: \.self) { rate in
                                Button(SpeedPickerModel.label(for: rate)) { preferences.defaultRate = rate }
                            }
                        }
                    }
                    SettingsGroupRow(title: "Skip back", separator: true) {
                        menu("\(preferences.skipBackSeconds) s") {
                            ForEach(ReaderPreferences.skipBackOptions, id: \.self) { seconds in
                                Button("\(seconds) s") { preferences.skipBackSeconds = seconds }
                            }
                        }
                    }
                    SettingsGroupRow(title: "Skip forward", separator: true) {
                        menu("\(preferences.skipForwardSeconds) s") {
                            ForEach(ReaderPreferences.skipForwardOptions, id: \.self) { seconds in
                                Button("\(seconds) s") { preferences.skipForwardSeconds = seconds }
                            }
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

    /// The value in ink with the menu's mark after it, the whole of it the tap.
    private func menu<Items: View>(_ value: String, @ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 6) {
                Text(value).typeRole(.pill).foregroundStyle(Tokens.ink).monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Tokens.ink3)
            }
            .padding(.vertical, 10)
            .padding(.leading, 10)
            .contentShape(Rectangle())
        }
    }
}
