import SwiftUI
import T2SApp

/// Preferences → Voice (spec §2.4.5): the default voice, with preview. Also used by the per-document
/// voice change (Task 8) through `selection` and `onSelect`.
struct VoiceListPage: View {
    @Environment(AppEnvironment.self) private var env
    var selection: String?
    var onSelect: (VoiceOption) -> Void

    var body: some View {
        let options = env.voices.voices()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(text: "Voice")
                ForEach(options) { option in
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

                        if option.id.hasPrefix("cloud:") {
                            Image(systemName: "cloud")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Tokens.ink2)
                                .accessibilityLabel("Preview this voice from Cloud voices")
                        } else {
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
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
        .navigationBarBackButtonHidden(false)
        .onDisappear { env.audioSession.stopPreview() }
    }
}
