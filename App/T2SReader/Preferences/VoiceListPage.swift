import SwiftUI
import T2SApp

/// Preferences → Voice (spec §2.4.5): the default voice, in sections, with preview. Also the
/// per-document voice change (`VoiceChangeSheet`) through `selection`, `onSelect` and `confirm`.
///
/// Round 5 (2026-09-10, from the owner's references — Beside's "Choose Voice", Uptime's "Change
/// your default voice"): every row wears its two verbs. The avatar, with a play badge, is *hear*;
/// the radio at the end — and the name beside it — is *choose*. Nothing is a mode any more: the
/// "Change" pill and its armed state (round 4) are gone, and with them the question the owner asked
/// three rounds running, "what does tapping a row do". Without `confirm`, choosing applies at once
/// and the radio follows (Settings). With it, the radio moves and the bar at the foot applies —
/// the per-document change, where applying throws rendered audio away and deserves one more tap.
struct VoiceListPage: View {
    @Environment(AppEnvironment.self) private var env
    var selection: String?
    var onSelect: (VoiceOption) -> Void
    /// The bar at the foot, when choosing needs confirming; nil applies on the radio's tap.
    var confirm: Confirm? = nil

    struct Confirm {
        var label: String
        var busyLabel: String? = nil
        /// A line over the bar — "Replaces 12m of rendered audio" — when there is one to say.
        var note: String? = nil
        var isEnabled: Bool
        var perform: () -> Void
    }

    /// What "no override" resolves to on this device, loaded once so the right row starts checked —
    /// Kokoro Heart on the phone build; on the simulator the routing echoes "default" back, which is
    /// the `systemDefault` row's own id. Until it loads, `option.isDefault` marks a row instead (spec §6).
    @State private var resolvedDefault: String?
    /// The Kokoro list's quick filter — only the Kokoro rows carry the gender and favorite data a
    /// filter needs, so System and Cloud are unaffected.
    @State private var filter: VoiceFilter = .all

    var body: some View {
        let options = env.voices.voices()
        let hasDefaultRow = options.contains(where: \.isDefault)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(text: "Voice")
                ForEach(VoiceGroup.allCases, id: \.self) { group in
                    let groupOptions = options.filter { $0.group == group }
                    if !groupOptions.isEmpty {
                        SectionHeader(title: group.title)
                            .padding(.top, Spacing.section)
                            .padding(.bottom, Spacing.grid)
                        if group == .kokoro {
                            kokoroRows(groupOptions, options: options, hasDefaultRow: hasDefaultRow)
                        } else {
                            ForEach(groupOptions) { option in row(option, options: options, hasDefaultRow: hasDefaultRow) }
                        }
                        if group == .kokoro {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kokoroFooter)
                                if let mlxLine = env.kokoroStatus.mlxLine {
                                    Text(mlxLine)
                                }
                            }
                            .typeRole(.meta)
                            .foregroundStyle(Tokens.ink2)
                            .padding(.top, Spacing.grid)
                        }
                    }
                }
                if let error = env.voicePreview.lastError {
                    Text(error)
                        .typeRole(.meta)
                        .foregroundStyle(Tokens.destructive)
                        .padding(.top, Spacing.section)
                }
                Color.clear.frame(height: confirm == nil ? 160 : Spacing.section)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
        .safeAreaInset(edge: .bottom) {
            if let confirm {
                VStack(spacing: 10) {
                    if let note = confirm.note {
                        Text(note).typeRole(.meta).foregroundStyle(Tokens.ink2).multilineTextAlignment(.center)
                    }
                    BarButton(label: confirm.label, busyLabel: confirm.busyLabel, isEnabled: confirm.isEnabled, action: confirm.perform)
                }
                .padding(.horizontal, Spacing.margin)
                .padding(.top, 12)
                .padding(.bottom, Spacing.grid)
                .background(Tokens.ground)
            }
        }
        .navigationBarBackButtonHidden(false)
        .onDisappear { env.voicePreview.stop() }
        .task {
            resolvedDefault = await env.voiceRouting.effectiveVoiceID(VoiceOption.systemDefault.id)
        }
    }

    /// The Kokoro section reads as two sub-sections by language, under the one group header above
    /// them (spec: Plan 9 voice quality) — "American English" leads because the default route's
    /// default voice is American (Heart).
    private func kokoroRows(_ groupOptions: [VoiceOption], options: [VoiceOption], hasDefaultRow: Bool) -> some View {
        let defaults = groupOptions.filter(\.isDefault)
        let candidates = groupOptions.filter { !$0.isDefault && matchesFilter($0) }
        let american = candidates.filter { $0.language == "en-US" }
        let british = candidates.filter { $0.language == "en-GB" }
        return VStack(alignment: .leading, spacing: 0) {
            FilterTabs(options: VoiceFilter.allCases, title: \.title, selection: $filter)
                .padding(.bottom, Spacing.row)
            ForEach(defaults) { row($0, options: options, hasDefaultRow: hasDefaultRow) }
            if !american.isEmpty {
                subsectionHeader("American English", flag: "🇺🇸")
                ForEach(american) { row($0, options: options, hasDefaultRow: hasDefaultRow) }
            }
            if !british.isEmpty {
                subsectionHeader("British English", flag: "🇬🇧")
                ForEach(british) { row($0, options: options, hasDefaultRow: hasDefaultRow) }
            }
            if american.isEmpty && british.isEmpty {
                emptyFilterMessage
            }
        }
    }

    /// One filter is live at a time — "All" clears it. Only the Kokoro rows carry `gender`, and only
    /// they can be starred, so this is the Kokoro list's own filter, not a picker-wide one. Tabs, not
    /// pills, since the Collection's round (a pill is what this app presses).
    private enum VoiceFilter: CaseIterable {
        case all, favorites, female, male

        var title: String {
            switch self {
            case .all: return "All"
            case .favorites: return "Favorites"
            case .female: return "Female"
            case .male: return "Male"
            }
        }
    }

    private func matchesFilter(_ option: VoiceOption) -> Bool {
        switch filter {
        case .all: return true
        case .favorites: return env.preferences.favoriteVoiceIDs.contains(option.id)
        case .female: return option.gender == .female
        case .male: return option.gender == .male
        }
    }

    private var emptyFilterMessage: some View {
        Text(filter == .favorites
             ? "No favorites yet — tap the heart on a voice to add one."
             : "No voices match this filter.")
            .typeRole(.meta)
            .foregroundStyle(Tokens.ink2)
            .padding(.top, Spacing.grid)
    }

    /// A flag and the accent's name, with room above and below so each accent reads as its own
    /// block rather than as one more row. The flag is decorative: the title already says which.
    private func subsectionHeader(_ title: String, flag: String) -> some View {
        HStack(spacing: Spacing.grid) {
            Text(flag)
                .font(.system(size: 22))
                .accessibilityHidden(true)
            Text(title)
                .typeRole(.sectionHeader)
                .foregroundStyle(Tokens.ink)
        }
        .padding(.top, Spacing.row)
        .padding(.bottom, Spacing.grid)
    }

    /// One row, three buttons that each look like what they do: the avatar with its play badge
    /// (hear), the name through to the radio (choose), the heart (keep). The "Default" pointer row
    /// has no voice of its own to hear and nothing to keep, so it is the name and the radio alone.
    private func row(_ option: VoiceOption, options: [VoiceOption], hasDefaultRow: Bool) -> some View {
        // No override chosen: the "Default" row is the one checked wherever the list has one; where it
        // has none (the simulator's system list), the resolved default's own row is.
        let isSelected = option.id == selection
            || (selection == nil && (hasDefaultRow ? option.isDefault : (resolvedDefault.map { $0 == option.id } ?? false)))
        let previewing = env.voicePreview.previewing == option.id
        let rendering = previewing && env.voicePreview.isRendering
        return HStack(spacing: 12) {
            if option.isDefault {
                avatar(for: option, previewing: false, rendering: false)
            } else {
                Button { env.voicePreview.toggle(option.id) } label: {
                    avatar(for: option, previewing: previewing, rendering: rendering)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(previewing ? "Stop preview" : "Preview \(option.name)")
            }

            Button { onSelect(option) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(option.name)
                            .typeRole(.rowTitle)
                            .foregroundStyle(Tokens.ink)
                            .lineLimit(1)
                        if let detail = detailText(for: option, options: options) {
                            Text(detail)
                                .typeRole(.meta)
                                .foregroundStyle(Tokens.ink2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 0)
                    if !option.isDefault { favoriteButton(for: option) }
                    RadioMark(isOn: isSelected)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityHint(confirm == nil ? "Makes this the voice" : "Chooses this voice")
        }
        .frame(minHeight: 56)
        .padding(.vertical, Spacing.grid)   // room between rows, on top of the tap-target minimum
    }

    /// The "Default" row says which voice it currently means, once the routing has answered.
    private func detailText(for option: VoiceOption, options: [VoiceOption]) -> String? {
        guard option.isDefault, option.group == .kokoro else { return option.detail }
        if let resolvedDefault, let resolved = options.first(where: { $0.id == resolvedDefault }) {
            return "Currently \(resolved.name)"
        }
        return option.detail
    }

    /// The voice's initial, tinted by gender — pink for female, blue for male, neutral `surface`
    /// where there is none (the "Default" pointer row, a system or cloud voice) — with a small ink
    /// play badge at its foot that says the disc can be heard; the badge turns to pause while this
    /// row's voice is the one playing, and the disc shows a spinner while its preview is rendering.
    private func avatar(for option: VoiceOption, previewing: Bool, rendering: Bool) -> some View {
        let tint: Color? = switch option.gender {
        case .female: Tokens.voiceFemale
        case .male: Tokens.voiceMale
        case nil: nil
        }
        let foreground = tint == nil ? Tokens.ink : Tokens.onAccent
        return ZStack {
            Circle().fill(tint ?? Tokens.surface)
            if rendering {
                ProgressView().tint(foreground)
            } else {
                Text(option.name.prefix(1).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(foreground)
            }
        }
        .frame(width: 44, height: 44)
        .overlay(alignment: .bottomTrailing) {
            if !option.isDefault {
                Image(systemName: previewing ? "pause.fill" : "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Tokens.ground)
                    .frame(width: 18, height: 18)
                    .background(Tokens.ink, in: Circle())
                    .overlay(Circle().strokeBorder(Tokens.ground, lineWidth: 2))
                    .offset(x: 3, y: 3)
            }
        }
        .accessibilityHidden(true)
    }

    /// A heart, independent of the radio: the checked row is what plays by default, the starred
    /// rows are what "Favorites" filters to. A voice can be both, neither, or starred without being
    /// default. Persisted in `ReaderPreferences.favoriteVoiceIDs`, so it survives a relaunch.
    private func favoriteButton(for option: VoiceOption) -> some View {
        let isFavorite = env.preferences.favoriteVoiceIDs.contains(option.id)
        return Button { env.preferences.toggleFavoriteVoice(option.id) } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 20))
                .foregroundStyle(isFavorite ? Tokens.accent : Tokens.ink2)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove \(option.name) from favorites" : "Add \(option.name) to favorites")
    }

    /// The Kokoro section is only rendered by a build that links the engine, so this is only ever
    /// read there; the whole-document fallback is what the last sentence describes (spec §6).
    private var kokoroFooter: String {
        switch env.kokoroStatus.status {
        case .notLinked, .checking:
            return "Checking this device…"
        case .preparing:
            // The eight Core ML stages load once per launch, and on a first launch the system may
            // still be building their compute plans — minutes on an A13. Say so, rather than let a
            // reader wonder why the first sentence is slow to arrive.
            return "Preparing the Kokoro voice (one-time, up to a few minutes on the first launch)…"
        case .available(let isDebugOverride):
            return isDebugOverride ? "Runs on this device (development override)." : "Runs on this device."
        case .unavailable(let reason):
            return "Not available on this device: \(reason) Documents set to a Kokoro voice play with the system default voice."
        }
    }
}
