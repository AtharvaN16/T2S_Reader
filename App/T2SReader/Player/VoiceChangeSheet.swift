import SwiftUI
import T2SApp
import T2SStore

/// Per-document voice override (spec §5): the voice list with a "Change voice" bar that rises when
/// a radio moves off the document's voice. Changing invalidates rendered audio because render keys
/// include the voice identifier — the line above the bar says how much. Choosing the voice that
/// wears the "Default" tag stores no override, so the document follows Settings from then on.
struct VoiceChangeSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let summary: DocumentSummary

    private var discardedSeconds: TimeInterval {
        env.voiceChange.discardedSeconds(for: summary)
    }

    var body: some View {
        VoiceListPage(
            current: summary.document.voiceID,
            confirmLabel: "Change voice",
            note: { _ in
                discardedSeconds > 0
                    ? "Replaces \(DurationFormatter.long(discardedSeconds)) of rendered audio; it renders again with the new voice."
                    : nil
            },
            onConfirm: { option in
                var defaultID = env.preferences.defaultVoiceID
                if defaultID == nil { defaultID = await env.voiceRouting.effectiveVoiceID(VoiceOption.systemDefault.id) }
                let voiceID: String? = option.id == defaultID ? nil : option.id
                let applied = await env.voiceChange.apply(voiceID: voiceID, to: summary)
                if applied { dismiss() }
                return applied
            },
            showsFavorites: false
        )
        .background(Tokens.ground)
        .overlay { GeometryReader { geo in TopFade(inset: geo.safeAreaInsets.top) } }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}
