import SwiftUI
import T2SApp

/// Spec §2.4.5 Preferences, titled "Settings" since 2026-09-09: sections as a heavy header plus rows
/// of title, an optional grey subtitle that carries a value (never an explanation), and a
/// right-aligned mark — a chevron where the row opens something, an arrow where it acts at once,
/// a switch where it is one. No card, no divider: the row gap is the rhythm, as on Home.
///
/// Three groups since 2026-09-18: the two things about a book being read to you, straight under
/// the title; then Preferences; then About, with the version as a line under it rather than a row.
/// It was six headed sections for nine rows before that, three of them sections of one, with
/// "Reading" holding the app-wide theme and Storage holding Prepare-on-charge; the chevron opened
/// pages, opened sheets, replaced the page with the welcome, and on the licence line did nothing.
/// For a day it was the reference's cards of coloured tiles too, until the owner asked for the
/// app's own language back.
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    PageTitle(text: "Settings")
                    // No header: these are the page, the way Home's rows sit under its title.
                    group {
                        NavigationLink {
                            voiceList
                        } label: {
                            row("Voice", subtitle: defaultVoiceSubtitle)
                        }
                        NavigationLink {
                            RenderingPage()
                        } label: {
                            row("Rendering", subtitle: renderingSubtitle)
                        }
                    }
                    group("Preferences") {
                        NavigationLink {
                            PlaybackPage()
                        } label: {
                            row("Playback", subtitle: playbackSubtitle)
                        }
                        Button { showAppearance = true } label: {
                            row("Appearance", subtitle: appearanceSubtitle)
                        }
                        .buttonStyle(.plain)
                        row("iCloud sync", subtitle: syncSubtitle) {
                            Toggle("", isOn: Binding(get: { env.syncModel.isEnabled },
                                                     set: { on in Task { await env.syncModel.setEnabled(on) } }))
                                .labelsHidden()
                                .disabled(!env.syncModel.canEnable && !env.syncModel.isEnabled)
                        }
                    }
                    group("About") {
                        // First in About, above the welcome: the welcome is a thing to be shown
                        // again, this is a thing to be read.
                        Button { showHowItWorks = true } label: {
                            row("How it works")
                        }
                        .buttonStyle(.plain)
                        // The welcome shows once per install; this is the way back to it, for a
                        // reader who skipped it and for a photograph. An arrow, not a chevron: the
                        // tap does not open a page, it replaces this one.
                        Button { chrome.showsWelcome = true } label: {
                            row("Show the welcome again") { RowArrow() }
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            AcknowledgementsPage()
                        } label: {
                            row("Acknowledgements")
                        }
                        // A fact, not a row: nothing to tap, so nothing dressed as if there were.
                        Text(versionLine).typeRole(.meta).foregroundStyle(Tokens.ink2)
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

    // MARK: - Rows

    /// A heavy header over its rows, or the rows alone.
    private func group<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let title {
                Text(title).typeRole(.groupTitle).foregroundStyle(Tokens.ink)
            }
            content()
        }
    }

    /// A row that opens something.
    private func row(_ title: String, subtitle: String = "") -> some View {
        row(title, subtitle: subtitle) { RowChevron() }
    }

    private func row<Control: View>(_ title: String, subtitle: String = "", @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).typeRole(.settingsRow).foregroundStyle(Tokens.ink).multilineTextAlignment(.leading)
                if !subtitle.isEmpty {
                    // A value fits in one line; the sync row's line is a status sentence, and cut
                    // to "Needs an iCloud-enabled b…" it says nothing.
                    Text(subtitle).typeRole(.meta).foregroundStyle(Tokens.ink2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            control()
        }
        .contentShape(Rectangle())
    }
}
