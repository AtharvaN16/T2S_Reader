import SwiftUI
import T2SApp
import T2SStore

/// Per-document voice override (spec §5). Changing it invalidates rendered audio because render
/// keys include the voice identifier.
struct VoiceChangeSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let summary: DocumentSummary
    @State private var pendingVoice: VoiceOption?
    @State private var isApplying = false

    private var discardedSeconds: TimeInterval {
        env.voiceChange.discardedSeconds(for: summary)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let pendingVoice {
                    confirmation(for: pendingVoice)
                } else {
                    VoiceListPage(selection: summary.document.voiceID) { voice in
                        select(voice)
                    }
                }
            }
            .navigationTitle("Change voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Tokens.ink)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }

    private func confirmation(for voice: VoiceOption) -> some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            Spacer()
            Text("Rendered audio will be replaced")
                .typeRole(.playerTitle)
                .foregroundStyle(Tokens.ink)
            Text("Changing to \(voice.name) discards \(DurationFormatter.long(discardedSeconds)) of rendered audio. It will render again with the new voice.")
                .typeRole(.rowTitle)
                .foregroundStyle(Tokens.ink2)
            HStack(spacing: 10) {
                Pill(label: "Keep current", style: .soft) { pendingVoice = nil }
                Pill(label: isApplying ? "Changing…" : "Change voice", glyph: "trash", style: .destructiveSoft) {
                    apply(voice)
                }
                .disabled(isApplying)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .background(Tokens.ground)
    }

    private func select(_ voice: VoiceOption) {
        guard (voice.isDefault ? nil : voice.id) != summary.document.voiceID else {
            dismiss()
            return
        }
        if discardedSeconds > 0 {
            pendingVoice = voice
        } else {
            apply(voice)
        }
    }

    private func apply(_ voice: VoiceOption) {
        isApplying = true
        Task {
            let voiceID = voice.isDefault ? nil : voice.id
            if await env.voiceChange.apply(voiceID: voiceID, to: summary) {
                dismiss()
            }
            isApplying = false
        }
    }
}
