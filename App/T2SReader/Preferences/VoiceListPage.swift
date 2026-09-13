import SwiftUI
import T2SApp

/// The voice list, for Settings (the default voice) and for one document (`VoiceChangeSheet`).
///
/// Round 6 (2026-09-10, from the owner's first look at round 5 on the phone): no avatar disc — the
/// name carries a ♀ / ♂ mark and, on the voice that plays by default, a "Default" tag; the old
/// "Default" pointer row is gone with it. Three marks at the end of every row, each its own verb:
/// a waveform (hear), a heart (keep), a radio (choose). Choosing moves the radio and slides a bar
/// up from the foot, so nothing applies until a key is pressed and nothing needs a mode. Sections
/// by accent under no group title.
///
/// **One key, and a line you can tick** (owner, 2026-09-12). The document's bar carried two keys
/// for a while — "Done" beside a quieter "Make default" — and they were never a primary and its
/// secondary: they are two *scopes* of the same press, this book or this book and every book that
/// follows the default. Two keys put that policy question in front of a reader who only wanted to
/// hear Alloy, and the quiet key's flat slab is the same slab `RaisedButton` paints a *disabled*
/// key with, so the wider answer read as unavailable. The scope is a tick over the key now —
/// "Also make Alloy my default voice" — which is one press either way, undoes with a tap, and
/// leaves the bar with a single thing to say. The key says which voice it will use rather than
/// "Done": the sheet has a drag indicator, so "Done" could be read as "close, keep what I had",
/// and this press throws rendered audio away.
struct VoiceListPage: View {
    @Environment(AppEnvironment.self) private var env
    /// The id in effect before anything is chosen: the document's voice, or the default.
    var current: String?
    /// The key's word, per choice: "Use Alloy" for a document, "Make default" in Settings.
    var confirmLabel: (VoiceOption) -> String
    /// The line over the key: what the press costs, per choice.
    var note: (VoiceOption) -> String? = { _ in nil }
    /// Applies the choice; true dismisses the bar. The flag is the scope tick — "and every other
    /// book too". Async so a document's audio can be discarded.
    var onConfirm: (VoiceOption, Bool) async -> Bool
    /// The scope tick's words, when the caller has a wider answer to offer. The Reader's sheet
    /// does; Settings, whose only answer *is* the default, returns nil and shows no tick.
    var alsoDefaultLabel: (VoiceOption) -> String? = { _ in nil }
    /// The heart per row. Off in the Reader's sheet (owner, 2026-09-10): there it is hear and
    /// choose only; keeping favorites is Settings' job.
    var showsFavorites: Bool = true

    /// What "no override" resolves to on this device (Kokoro Heart on the phone build), loaded
    /// once: the voice that wears the "Default" tag when Settings has no pick of its own.
    @State private var resolvedDefault: String?
    @State private var filter: VoiceFilter = .all
    /// The radio's choice, not yet applied.
    @State private var pending: VoiceOption?
    /// The scope tick, cleared whenever the bar goes away: a tick left standing from a choice the
    /// reader backed out of would arm the next press with a decision they never made.
    @State private var alsoDefault = false
    @State private var isApplying = false

    /// The default voice's id: the Settings pick, else the device's own.
    private var defaultID: String? { env.preferences.defaultVoiceID ?? resolvedDefault }
    private var selectedID: String? { pending?.id ?? current ?? defaultID }
    private var isChange: Bool { pending != nil && pending?.id != (current ?? defaultID) }

    var body: some View {
        let options = env.voices.voices().filter { !$0.isDefault }             // the pointer row is a tag now
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(text: "Voice")
                ForEach(VoiceGroup.allCases, id: \.self) { group in
                    let groupOptions = options.filter { $0.group == group }
                    if !groupOptions.isEmpty {
                        if group != .kokoro {                                          // the on-device voices need no banner (owner)
                            SectionHeader(title: group.title)
                                .padding(.top, Spacing.section)
                                .padding(.bottom, Spacing.grid)
                        }
                        if group == .kokoro {
                            kokoroRows(groupOptions)
                        } else {
                            ForEach(groupOptions) { row($0) }
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
                Color.clear.frame(height: Spacing.section + 80)
            }
            .padding(.horizontal, Spacing.margin)
        }
        // No ground of its own: pushed from Settings, `settingsSubpage()` paints the warm one so the
        // warm-up glow is not cut at the bar; in `VoiceChangeSheet` the sheet adds a plain one.
        .safeAreaInset(edge: .bottom) {
            if isChange, let pending {
                // Cost, then scope, then the press. The first two are what the key means, so they
                // sit together a grid apart; the key stands off twice that, since it is the only
                // thing here that does anything.
                VStack(spacing: Spacing.grid * 2) {
                    VStack(spacing: Spacing.grid) {
                        if let line = note(pending) {
                            Text(line).typeRole(.fine).foregroundStyle(Tokens.ink2).multilineTextAlignment(.center)
                        }
                        if let label = alsoDefaultLabel(pending) { scopeTick(label) }
                    }
                    BarButton(label: confirmLabel(pending),
                              busyLabel: isApplying ? "Applying…" : nil,
                              isEnabled: !isApplying) {
                        apply(pending)
                    }
                }
                .padding(.horizontal, Spacing.margin)
                .padding(.top, Spacing.grid * 2)
                .padding(.bottom, Spacing.grid)
                // Not a flat `ground` slab: the list fades out under the bar (`BottomFade`) the way
                // it does under the root pages' bottom bar, so the bar has no edge to cut a row on.
                .background { BottomFade() }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: isChange)
        .onChange(of: isChange) { _, live in if !live { alsoDefault = false } }
        .onDisappear { env.voicePreview.stop() }
        .task {
            resolvedDefault = await env.voiceRouting.effectiveVoiceID(VoiceOption.systemDefault.id)
        }
    }

    /// The wider scope as a line over the key rather than a key of its own. The whole row is the
    /// button, at a full 44 pt, so the tick never has to be hit at its own 22.
    private func scopeTick(_ label: String) -> some View {
        Button { alsoDefault.toggle() } label: {
            HStack(spacing: Spacing.grid + 2) {
                CheckMark(isOn: alsoDefault)
                Text(label).typeRole(.pill).foregroundStyle(Tokens.ink).lineLimit(2)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isApplying)
        .accessibilityAddTraits(alsoDefault ? [.isSelected] : [])
        .accessibilityHint("Uses this voice for every book that has no voice of its own")
    }

    private func apply(_ option: VoiceOption) {
        isApplying = true
        Task {
            if await onConfirm(option, alsoDefault) { pending = nil; alsoDefault = false }
            isApplying = false
        }
    }

    /// The on-device voices in two blocks by accent, the filter pills above them — "American
    /// English" leads because the default route's default voice is American (Heart).
    private func kokoroRows(_ groupOptions: [VoiceOption]) -> some View {
        let candidates = groupOptions.filter { matchesFilter($0) }
        let american = candidates.filter { $0.language == "en-US" }
        let british = candidates.filter { $0.language == "en-GB" }
        return VStack(alignment: .leading, spacing: 0) {
            filterPills().padding(.top, Spacing.section)
            if !american.isEmpty {
                subsectionHeader("American English", flag: "🇺🇸")
                ForEach(american) { row($0) }
            }
            if !british.isEmpty {
                subsectionHeader("British English", flag: "🇬🇧")
                ForEach(british) { row($0) }
            }
            if american.isEmpty && british.isEmpty {
                emptyFilterMessage
            }
        }
    }

    /// One filter is live at a time — "All" clears it. Only the Kokoro rows carry `gender`, and only
    /// they can be starred, so this is the Kokoro list's own filter, not a picker-wide one.
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

    /// Pills, as the owner wants them here (round 6 put them back after a round as tabs).
    private func filterPills() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.grid) {
                ForEach(VoiceFilter.allCases, id: \.self) { option in
                    Pill(label: option.title, style: filter == option ? .selected : .soft) { filter = option }
                }
            }
        }
    }

    private var emptyFilterMessage: some View {
        Text(filter == .favorites
             ? "No favorites yet — tap the heart on a voice to add one."
             : "No voices match this filter.")
            .typeRole(.meta)
            .foregroundStyle(Tokens.ink2)
            .padding(.top, Spacing.row)
    }

    /// A flag and the accent's name at group-title weight, with a section's air above and a row's
    /// air below (owner, 2026-09-10: bigger, and further from its list).
    private func subsectionHeader(_ title: String, flag: String) -> some View {
        HStack(spacing: Spacing.grid) {
            Text(flag)
                .font(.system(size: 24))
                .accessibilityHidden(true)
            Text(title)
                .typeRole(.groupTitle)
                .foregroundStyle(Tokens.ink)
        }
        .padding(.top, Spacing.section)
        .padding(.bottom, 20)
    }

    /// One row: the name with its ♀ / ♂ mark and, on the default voice, a "Default" tag; the
    /// character line under it; then a waveform (hear), a heart (keep) and a radio (choose). The
    /// name and the radio are one button; the other two are their own.
    private func row(_ option: VoiceOption) -> some View {
        let isSelected = option.id == selectedID
        let isDefault = option.id == defaultID
        let previewing = env.voicePreview.previewing == option.id
        let rendering = previewing && env.voicePreview.isRendering
        let isFavorite = env.preferences.favoriteVoiceIDs.contains(option.id)
        return HStack(spacing: 4) {
            Button { pending = option } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(option.name)
                            .typeRole(.rowTitle)
                            .foregroundStyle(Tokens.ink)
                            .lineLimit(1)
                        if let gender = option.gender { GenderMark(gender: gender) }
                        if isDefault { tag("Default") }
                    }
                    if let detail = option.detail {
                        Text(detail)
                            .typeRole(.meta)
                            .foregroundStyle(Tokens.ink2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityHint("Chooses this voice")

            Button { env.voicePreview.toggle(option.id) } label: {
                ZStack {
                    if rendering {
                        ProgressView().tint(Tokens.ink)
                    } else {
                        Image(systemName: previewing ? "pause.fill" : "waveform")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(previewing ? Tokens.ink : Tokens.ink2)
                    }
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(previewing ? "Stop preview" : "Preview \(option.name)")

            if showsFavorites, option.gender != nil {                                // only the on-device voices are starred
                HeartButton(isOn: isFavorite,
                            label: isFavorite ? "Remove \(option.name) from favorites" : "Add \(option.name) to favorites") {
                    env.preferences.toggleFavoriteVoice(option.id)
                }
            }

            Button { pending = option } label: {
                RadioMark(isOn: isSelected).frame(width: 40, height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "\(option.name), chosen" : "Choose \(option.name)")
        }
        .frame(minHeight: 56)
        .padding(.vertical, Spacing.grid)   // room between rows, on top of the tap-target minimum
    }

    /// Light blue with dark blue text (owner, 2026-09-10): a grey tag on grey rows was missed.
    private func tag(_ text: String) -> some View {
        Text(text)
            .typeRole(.caption)
            .fontWeight(.medium)
            .foregroundStyle(Tokens.tagBlueInk)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Tokens.tagBlue, in: Capsule())
    }

    /// The Kokoro section is only rendered by a build that links the engine, so this is only ever
    /// read there; the whole-document fallback is what the last sentence describes (spec §6).
    private var kokoroFooter: String {
        switch env.kokoroStatus.status {
        case .notLinked, .checking:
            return "Checking this device…"
        case .installing:
            return "Downloading the Kokoro voice (about 620 MB, over Wi-Fi, once per install)…"
        case .preparing:
            // The Core ML stages load once per launch, and on a first launch the system may still
            // be building their compute plans — minutes on an A13. Say so, rather than let a
            // reader wonder why the first sentence is slow to arrive.
            return "Preparing the Kokoro voice (one-time, up to a few minutes on the first launch)…"
        case .removed:
            return "Removed from this device (Settings → Storage). Documents set to a Kokoro voice play with the system default voice until it is downloaded again."
        case .available(let isDebugOverride):
            return isDebugOverride ? "Runs on this device (development override)." : "Runs on this device."
        case .unavailable(let reason):
            return "Not available on this device: \(reason) Documents set to a Kokoro voice play with the system default voice."
        }
    }
}
