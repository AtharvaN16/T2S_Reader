import SwiftUI
import T2SApp

/// Spec §2.4.5 Preferences: sections as a header plus rows of title, grey subtitle, right-aligned control.
struct PreferencesPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showAppearance = false

    var body: some View {
        @Bindable var preferences = env.preferences
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    PageTitle(text: "Preferences")
                    section("Voice") {
                        NavigationLink {
                            VoiceListPage(selection: preferences.defaultVoiceID) { option in
                                preferences.defaultVoiceID = option.isDefault ? nil : option.id
                            }
                        } label: {
                            row(
                                "Default voice",
                                subtitle: env.voices.voices().first {
                                    $0.id == (preferences.defaultVoiceID ?? VoiceOption.systemDefault.id)
                                }?.name ?? "System default"
                            )
                        }
                    }
                    section("Playback") {
                        row("Skip back", subtitle: "Seconds") {
                            Menu {
                                ForEach(ReaderPreferences.skipBackOptions, id: \.self) { seconds in
                                    Button("\(seconds) s") { preferences.skipBackSeconds = seconds }
                                }
                            } label: {
                                valuePill("\(preferences.skipBackSeconds) s")
                            }
                        }
                        row("Skip forward", subtitle: "Seconds") {
                            Menu {
                                ForEach(ReaderPreferences.skipForwardOptions, id: \.self) { seconds in
                                    Button("\(seconds) s") { preferences.skipForwardSeconds = seconds }
                                }
                            } label: {
                                valuePill("\(preferences.skipForwardSeconds) s")
                            }
                        }
                        row("Default speed", subtitle: "New documents start here") {
                            Menu {
                                ForEach(SpeedPickerModel.rates.filter { $0 <= 3.0 }, id: \.self) { rate in
                                    Button(SpeedPickerModel.label(for: rate)) { preferences.defaultRate = rate }
                                }
                            } label: {
                                valuePill(SpeedPickerModel.label(for: preferences.defaultRate))
                            }
                        }
                        row("Autoplay next", subtitle: "Continue with the next queued item") {
                            Toggle("", isOn: $preferences.autoplayNext)
                                .labelsHidden()
                                .tint(Tokens.ink)
                        }
                    }
                    section("Reading") {
                        Button { showAppearance = true } label: {
                            row("Appearance", subtitle: "Text size, line height, theme")
                        }
                        .buttonStyle(.plain)
                    }
                    section("Pronunciation") {
                        NavigationLink {
                            PronunciationPage()
                        } label: {
                            row("Dictionary", subtitle: "\(env.pronunciation.entries.count) words")
                        }
                    }
                    section("Storage") {
                        NavigationLink {
                            StoragePage()
                        } label: {
                            row(
                                "Rendered audio and prepare on charge",
                                subtitle: ByteCountFormatter.string(
                                    fromByteCount: Int64(env.storage.stats.bytes),
                                    countStyle: .file
                                )
                            )
                        }
                    }
                    section("Cloud voices") {
                        NavigationLink {
                            CloudVoicesPage()
                        } label: {
                            row("Bring your own key", subtitle: "Your provider, your API key")
                        }
                    }
                    section("iCloud sync") {
                        row("Sync positions and bookmarks", subtitle: "Coming later") {
                            Toggle("", isOn: .constant(false))
                                .labelsHidden()
                                .disabled(true)
                        }
                    }
                    section("About") {
                        row("Fonts: Inter (SIL OFL) · Reader: Readium (BSD-3) · Extraction: Readability (Apache-2.0)", subtitle: "")
                    }
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, Spacing.margin)
            }
            .background(Tokens.ground)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showAppearance) { AppearanceSheet() }
        .task {
            await env.pronunciation.refresh()
            await env.storage.refresh()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: title)
            content()
        }
    }

    private func row(_ title: String, subtitle: String) -> some View {
        row(title, subtitle: subtitle) {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Tokens.ink3)
        }
    }

    private func row<Control: View>(_ title: String, subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).typeRole(.meta).foregroundStyle(Tokens.ink2)
                }
            }
            Spacer()
            control()
        }
        .contentShape(Rectangle())
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
