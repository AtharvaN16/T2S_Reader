import SwiftUI
import T2SApp

/// Preferences → Voice (spec §2.4.5): the default voice, in sections, with preview. Also used by
/// the per-document voice change (Task 8) through `selection` and `onSelect`.
struct VoiceListPage: View {
    @Environment(AppEnvironment.self) private var env
    var selection: String?
    var onSelect: (VoiceOption) -> Void

    var body: some View {
        let options = env.voices.voices()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(text: "Voice")
                ForEach(VoiceGroup.allCases, id: \.self) { group in
                    let groupOptions = options.filter { $0.group == group }
                    if !groupOptions.isEmpty {
                        SectionHeader(title: group.title)
                            .padding(.top, Spacing.section)
                            .padding(.bottom, Spacing.grid)
                        ForEach(groupOptions) { option in
                            row(option)
                        }
                        if group == .kokoro {
                            Text(kokoroFooter)
                                .typeRole(.meta)
                                .foregroundStyle(Tokens.ink2)
                                .padding(.top, Spacing.grid)
                        }
                    }
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
        .navigationBarBackButtonHidden(false)
        .onDisappear { env.audioSession.stopPreview() }
    }

    private func row(_ option: VoiceOption) -> some View {
        HStack(spacing: 12) {
            Button { onSelect(option) } label: {
                HStack {
                    Text(option.name)
                        .typeRole(.rowTitle)
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(1)
                    Spacer()
                    if (selection ?? VoiceOption.systemDefault.id) == option.id {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tokens.ink)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Only the system voices preview: a cloud voice would spend the reader's quota, and a
            // Kokoro voice would load 340 MB of weights to say one line.
            switch option.group {
            case .cloud:
                Image(systemName: "cloud")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Tokens.ink2)
                    .accessibilityLabel("Preview this voice from Cloud voices")
            case .kokoro:
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Tokens.ink2)
                    .accessibilityLabel("Kokoro voice")
            case .system:
                Button { SystemVoiceCatalog.preview(option, through: env.audioSession) } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Tokens.ink2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview")
            }
        }
        .frame(height: 44)
    }

    /// The Kokoro section is only rendered by a build that links the engine, so this is only ever
    /// read there; the whole-document fallback is what the last sentence describes (spec §6).
    private var kokoroFooter: String {
        switch env.kokoroStatus.status {
        case .notLinked, .checking:
            return "Checking this device…"
        case .available(let isDebugOverride):
            return isDebugOverride ? "Runs on this device (development override)." : "Runs on this device."
        case .unavailable(let reason):
            return "Not available on this device: \(reason) Documents set to a Kokoro voice play with the system default voice."
        }
    }
}
