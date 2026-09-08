import SwiftUI
import T2SApp

/// Preferences → Voice (spec §2.4.5): the default voice, in sections, with preview. Also used by
/// the per-document voice change (Task 8) through `selection` and `onSelect`.
struct VoiceListPage: View {
    @Environment(AppEnvironment.self) private var env
    var selection: String?
    var onSelect: (VoiceOption) -> Void
    /// What "no override" resolves to on this device, loaded once so the right row starts checked —
    /// Kokoro Heart on the phone build; on the simulator the routing echoes "default" back, which is
    /// the `systemDefault` row's own id. Until it loads, `option.isDefault` marks a row instead (spec §6).
    @State private var resolvedDefault: String?

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
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
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
        let american = groupOptions.filter { !$0.isDefault && $0.language == "en-US" }
        let british = groupOptions.filter { !$0.isDefault && $0.language == "en-GB" }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(defaults) { row($0, options: options, hasDefaultRow: hasDefaultRow) }
            if !american.isEmpty {
                subsectionHeader("American English")
                ForEach(american) { row($0, options: options, hasDefaultRow: hasDefaultRow) }
            }
            if !british.isEmpty {
                subsectionHeader("British English")
                ForEach(british) { row($0, options: options, hasDefaultRow: hasDefaultRow) }
            }
        }
    }

    private func subsectionHeader(_ title: String) -> some View {
        Text(title)
            .typeRole(.meta)
            .foregroundStyle(Tokens.ink2)
            .padding(.top, Spacing.grid)
            .padding(.bottom, 4)
    }

    private func row(_ option: VoiceOption, options: [VoiceOption], hasDefaultRow: Bool) -> some View {
        // No override chosen: the "Default" row is the one checked wherever the list has one; where it
        // has none (the simulator's system list), the resolved default's own row is.
        let isSelected = option.id == selection
            || (selection == nil && (hasDefaultRow ? option.isDefault : (resolvedDefault.map { $0 == option.id } ?? false)))
        return HStack(spacing: 12) {
            Button { onSelect(option) } label: {
                HStack(spacing: 12) {
                    avatar(for: option)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.name)
                            .typeRole(.rowTitle)
                            .foregroundStyle(Tokens.ink)
                            .lineLimit(1)
                        if let detail = detailText(for: option, options: options) {
                            Text(detail)
                                .typeRole(.meta)
                                .foregroundStyle(Tokens.ink2)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tokens.ink)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // The "Default" row is a pointer, not a voice: the voice it points at has its own row and
            // its own preview.
            if !option.isDefault {
                previewButton(for: option)
            }
        }
        .frame(minHeight: 56)
    }

    /// The "Default" row says which voice it currently means, once the routing has answered.
    private func detailText(for option: VoiceOption, options: [VoiceOption]) -> String? {
        guard option.isDefault, option.group == .kokoro else { return option.detail }
        if let resolvedDefault, let resolved = options.first(where: { $0.id == resolvedDefault }) {
            return "Currently \(resolved.name)"
        }
        return option.detail
    }

    /// Every row previews — Kokoro, system and cloud alike (spec: Plan 9 voice quality) — through
    /// the one model `RoutedEngine` already knows how to route any of their IDs to.
    private func previewButton(for option: VoiceOption) -> some View {
        let previewing = env.voicePreview.previewing == option.id
        let rendering = previewing && env.voicePreview.isRendering
        return Button { env.voicePreview.toggle(option.id) } label: {
            Group {
                if rendering {
                    ProgressView()
                } else {
                    Image(systemName: previewing ? "stop.circle" : "play.circle")
                        .font(.system(size: 20))
                }
            }
            .foregroundStyle(Tokens.ink2)
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(previewing ? "Stop preview" : "Preview \(option.name)")
    }

    /// A neutral `surface` disc with the voice's initial: the spec allows one accent element per
    /// screen and keeps `positive`/`destructive` for states and confirmations, so a coloured orb per
    /// row is not on the table. The initial is enough to scan the list by.
    private func avatar(for option: VoiceOption) -> some View {
        Circle()
            .fill(Tokens.surface)
            .frame(width: 36, height: 36)
            .overlay(
                Text(option.name.prefix(1).uppercased())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.ink)
            )
            .accessibilityHidden(true)
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
