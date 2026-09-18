import SwiftUI
import T2SApp

/// Spec §2.4.5 Preferences, titled "Settings" since 2026-09-09. Three cards of rows since
/// 2026-09-18 (owner, from a reference whose rows each lead with a coloured tile): the two things
/// about a book being read to you, then Preferences, then About. A row is a tile, a title, a grey
/// line that carries its *value* — the voice, the size, the speed, the mode — and at its end the one
/// mark that says what it does: a chevron opens, an arrow acts, a switch switches.
///
/// It used to be six headed sections for nine rows, three of them sections of one, with "Reading"
/// holding the app-wide theme and Storage holding Prepare-on-charge; the chevron opened pages,
/// opened sheets, replaced the page with the welcome, and on the licence line did nothing at all.
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

    /// Between a card and the next header; tighter than `Spacing.section`, which was sized for
    /// headed sections of loose rows and leaves cards adrift.
    private let cardGap: CGFloat = 28

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: cardGap) {
                    PageTitle(text: "Settings")
                        .padding(.bottom, Spacing.section - cardGap)

                    // No header: these are the page, the way the reference's first card is.
                    card {
                        NavigationLink {
                            voiceList
                        } label: {
                            SettingsRow(icon: "waveform", color: Tokens.tilePink,
                                        title: "Voice", subtitle: defaultVoiceSubtitle)
                        }
                        NavigationLink {
                            RenderingPage()
                        } label: {
                            SettingsRow(icon: "bolt.fill", color: Tokens.glow,
                                        title: "Rendering", subtitle: renderingSubtitle, separator: true)
                        }
                    }

                    card("Preferences") {
                        NavigationLink {
                            PlaybackPage()
                        } label: {
                            SettingsRow(icon: "play.fill", color: Tokens.accent,
                                        title: "Playback", subtitle: playbackSubtitle)
                        }
                        Button { showAppearance = true } label: {
                            SettingsRow(icon: "paintpalette.fill", color: Tokens.tilePurple,
                                        title: "Appearance", subtitle: appearanceSubtitle, separator: true)
                        }
                        .buttonStyle(.plain)
                        SettingsRow(icon: "icloud.fill", color: Tokens.tileTeal,
                                    title: "iCloud sync", subtitle: syncSubtitle, separator: true) {
                            Toggle("", isOn: Binding(get: { env.syncModel.isEnabled },
                                                     set: { on in Task { await env.syncModel.setEnabled(on) } }))
                                .labelsHidden()
                                .disabled(!env.syncModel.canEnable && !env.syncModel.isEnabled)
                        }
                    }

                    card("About") {
                        // First in About, above the welcome: the welcome is a thing to be shown
                        // again, this is a thing to be read.
                        Button { showHowItWorks = true } label: {
                            SettingsRow(icon: "book.fill", color: Tokens.tileGrey, title: "How it works")
                        }
                        .buttonStyle(.plain)
                        // The welcome shows once per install; this is the way back to it, for a
                        // reader who skipped it and for a photograph. An arrow, not a chevron: the
                        // tap does not open a page, it replaces this one.
                        Button { chrome.showsWelcome = true } label: {
                            SettingsRow(icon: "hand.wave.fill", color: Tokens.positive,
                                        title: "Show the welcome again", separator: true) { RowArrow() }
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            AcknowledgementsPage()
                        } label: {
                            SettingsRow(icon: "info", color: Tokens.tileGrey,
                                        title: "Acknowledgements", separator: true)
                        }
                    }

                    // A fact, not a row: nothing to tap, so nothing dressed as if there were.
                    Text(versionLine)
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, -cardGap / 2)

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
            // The "voice model removed" toast's action, tapped from any page (`Chrome.opensStorage`).
            .navigationDestination(isPresented: Bindable(chrome).opensStorage) { RenderingPage() }
        }
        .sheet(isPresented: $showAppearance) { ReaderPreferencesSheet(showsReaderControls: false) }
        .sheet(isPresented: $showHowItWorks) { HowItWorksSheet() }
        .task {
            resolvedDefaultVoiceID = await env.voiceRouting.effectiveVoiceID(VoiceOption.systemDefault.id)
            await env.storage.refresh()
        }
        .task { await env.syncModel.refreshAvailability() }
    }

    // MARK: - Values

    /// What Rendering holds and whether it works ahead: the size of the audio on the phone, then
    /// the one word about Prepare that matters at this distance.
    private var renderingSubtitle: String {
        // The formatter's word for nothing is "Zero KB", which is a number pretending to be a size.
        let bytes = env.storage.stats.bytes == 0
            ? "No audio yet"
            : ByteCountFormatter.string(fromByteCount: Int64(env.storage.stats.bytes), countStyle: .file)
        let settings = env.prepareSettings
        guard settings.isEnabled else { return "\(bytes) · Prepare off" }
        return settings.window == .overnight ? "\(bytes) · Prepare overnight" : "\(bytes) · Prepare on charge"
    }

    /// The three playback values in one line, in the order the page under it lists them.
    private var playbackSubtitle: String {
        let preferences = env.preferences
        return "\(SpeedPickerModel.label(for: preferences.defaultRate)) · \(preferences.skipBackSeconds) s back · \(preferences.skipForwardSeconds) s forward"
    }

    private var appearanceSubtitle: String {
        env.preferences.theme == .dark ? "Dark" : "Light"
    }

    /// Status rather than a value, and the only row whose grey line is: a switch has no value
    /// beyond its own position, and what a reader wants under it is whether it is working.
    private var syncSubtitle: String {
        env.syncModel.unavailableReason ?? env.syncModel.statusText
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        return "t2s \(version) (\(build))"
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

    // MARK: - Cards

    /// A header in grey over a `SettingsGroup`, or the group alone. Grey, where the old sections'
    /// headers were ink: the rows carry the ink now, and a header's job is to say which card this
    /// is without competing with what is on it.
    private func card<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).typeRole(.groupTitle).foregroundStyle(Tokens.ink2)
            }
            SettingsGroup { content() }
        }
    }
}
