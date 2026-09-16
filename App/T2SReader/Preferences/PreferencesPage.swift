import SwiftUI
import T2SApp

/// Spec §2.4.5 Preferences, titled "Settings" since 2026-09-09: sections as a heavy header plus rows
/// of title, an optional grey subtitle that carries a value (never an explanation), and a
/// right-aligned control.
struct PreferencesPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Chrome.self) private var chrome
    @State private var showAppearance = false
    @State private var showHowItWorks = false
    /// What "System default" actually resolves to on this device: Kokoro Heart where the Core ML
    /// route is available, the system voice otherwise (spec §6). Resolved in `.task` because
    /// `VoiceRouteResolving` is `async`, not because the answer is slow: resolving `"default"`
    /// consults only the default voice's own route — the Core ML one, whose closure reads a lock and
    /// returns at once — so the subtitle is settled a redraw after the page appears. The MLX probe
    /// is not on this path; it is only ever woken by an MLX voice ID.
    @State private var resolvedDefaultVoiceID: String?
    @State private var showVoices = false

    var body: some View {
        @Bindable var preferences = env.preferences
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    PageTitle(text: "Settings")
                    section("Voice") {
                        NavigationLink {
                            voiceList
                        } label: {
                            row("Default voice", subtitle: defaultVoiceSubtitle)
                        }
                    }
                    section("Playback") {
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
                        row("Default speed") {
                            Menu {
                                ForEach(SpeedPickerModel.rates, id: \.self) { rate in
                                    Button(SpeedPickerModel.label(for: rate)) { preferences.defaultRate = rate }
                                }
                            } label: {
                                valuePill(SpeedPickerModel.label(for: preferences.defaultRate))
                            }
                        }
                    }
                    section("Reading") {
                        Button { showAppearance = true } label: {
                            row("Appearance")
                        }
                        .buttonStyle(.plain)
                    }
                    section("Storage") {
                        NavigationLink {
                            StoragePage()
                        } label: {
                            row(
                                storageRowTitle,
                                subtitle: ByteCountFormatter.string(
                                    fromByteCount: Int64(env.storage.stats.bytes),
                                    countStyle: .file
                                )
                            )
                        }
                        // Its own row rather than a section of Storage (owner, 2026-09-14): making
                        // audio ahead and capping how much room it may take are two questions, and
                        // sharing a screen taught each other's numbers to be misread.
                        NavigationLink {
                            PreparePage()
                        } label: {
                            row("Prepare on charge", subtitle: prepareSubtitle)
                        }
                    }
                    section("iCloud sync") {
                        row("Sync positions and bookmarks", subtitle: env.syncModel.unavailableReason ?? env.syncModel.statusText) {
                            Toggle("", isOn: Binding(get: { env.syncModel.isEnabled },
                                                     set: { on in Task { await env.syncModel.setEnabled(on) } }))
                                .labelsHidden()
                                .disabled(!env.syncModel.canEnable && !env.syncModel.isEnabled)
                        }
                    }
                    section("About") {
                        // First in About, above the welcome: the welcome is a thing to be shown
                        // again, this is a thing to be read, and a reader who has come looking for
                        // "why is my phone warm" is looking for prose.
                        Button { showHowItWorks = true } label: {
                            row("How the app works")
                        }
                        .buttonStyle(.plain)
                        // The welcome shows once per install; this is the way back to it, for a
                        // reader who skipped it and for a photograph.
                        Button { chrome.showsWelcome = true } label: {
                            row("Show the welcome again")
                        }
                        .buttonStyle(.plain)
                        row("Fonts: Inter (SIL OFL) · Reader: Readium (BSD-3) · Extraction: Readability (Apache-2.0)")
                    }
                    Color.clear.frame(height: Spacing.bottomClearance)
                }
                .padding(.horizontal, Spacing.margin)
            }
            .scrollIndicators(.hidden)
            .background(PagerLock())                                           // holds the pager while a subpage is up
            // The stack paints its own opaque background over the pager's ground, which is what
            // kept the warm-up glow off this page alone (owner, 2026-09-10); cleared, the page is
            // as transparent as Home and the Collection.
            .pageTopEdge()
            .containerBackground(Color.clear, for: .navigation)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showVoices) { voiceList }
            // The "voice model removed" toast's action, tapped from any page (`Chrome.opensStorage`).
            .navigationDestination(isPresented: Bindable(chrome).opensStorage) { StoragePage() }
        }
        .sheet(isPresented: $showAppearance) { ReaderPreferencesSheet(showsReaderControls: false) }
        .sheet(isPresented: $showHowItWorks) { HowItWorksSheet() }
        .task {
            resolvedDefaultVoiceID = await env.voiceRouting.effectiveVoiceID(VoiceOption.systemDefault.id)
            await env.storage.refresh()
        }
        .task { await env.syncModel.refreshAvailability() }
    }

    /// What Prepare is set to, in the fewest words that are still true: off, or the mode and — when
    /// it is not the default — the window it keeps to.
    private var prepareSubtitle: String {
        let settings = env.prepareSettings
        guard settings.isEnabled else { return "Off" }
        let what = settings.mode == .keepUp ? "Keeping up with your reading" : picksSubtitle
        return settings.window == .overnight ? "\(what) · overnight" : what
    }

    private var picksSubtitle: String {
        let count = env.prepareSettings.pickedChapterCount
        guard count > 0 else { return "Nothing picked" }
        return "\(count) \(count == 1 ? "chapter" : "chapters") picked"
    }

    /// The row names the voice model only where there is one to name: the everyday build has no
    /// model, and a row offering to manage what does not exist is worse than a shorter row.
    private var storageRowTitle: String {
        env.kokoroModel.isSupported ? "Voice model and rendered audio" : "Rendered audio"
    }

    /// The default voice: the radio moves, "Make default" applies.
    private var voiceList: some View {
        // No scope tick here: the default *is* this page's only answer, so the key says so.
        VoiceListPage(current: nil, confirmLabel: { _ in "Make default" }, onConfirm: { option, _ in
            env.preferences.defaultVoiceID = option.id
            return true
        })
        .settingsSubpage()
    }

    /// The row shows the voice that will speak, not the token stored for it: a reader who has never
    /// chosen one is on "System default", and on a phone with the on-device engine that means Kokoro
    /// Heart. Until the routing answers — and always, in the everyday build — this reads as it
    /// always has.
    private var defaultVoiceSubtitle: String {
        let chosen = env.preferences.defaultVoiceID ?? VoiceOption.systemDefault.id
        let effective = chosen == VoiceOption.systemDefault.id ? (resolvedDefaultVoiceID ?? chosen) : chosen
        guard let option = env.voices.voices().first(where: { $0.id == effective }) else { return "System default" }
        guard let detail = option.detail else { return option.name }
        return "\(option.name) · \(detail)"
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).typeRole(.groupTitle).foregroundStyle(Tokens.ink)
            content()
        }
    }

    private func row(_ title: String, subtitle: String = "") -> some View {
        row(title, subtitle: subtitle) {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Tokens.ink3)
        }
    }

    private func row<Control: View>(_ title: String, subtitle: String = "", @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // A title that wraps ("Rendered audio and prepare on charge") stays on the left edge.
                Text(title).typeRole(.settingsRow).foregroundStyle(Tokens.ink).multilineTextAlignment(.leading)
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
