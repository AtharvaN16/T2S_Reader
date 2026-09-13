import SwiftUI
import T2SApp
import T2SStore

/// Per-document voice override (spec §5): the voice list with a bar that rises when a radio moves
/// off the document's voice. Changing invalidates rendered audio because render keys include the
/// voice identifier — the line above the bar says how much.
///
/// **One key and a scope tick** (owner, 2026-09-12). The key on its own changes this book and
/// leaves Settings alone. Ticked, it changes this book *and* every book that has not been given a
/// voice of its own — it moves `defaultVoiceID` and then clears this document's override, so the
/// book goes back to following Settings rather than pinning a copy of the new default. Choosing the
/// voice that wears the "Default" tag stores no override either way. It was two keys for a day, and
/// `VoiceListPage` carries why that was the wrong shape for a question about scope.
///
/// **Both keys resume.** The change pauses the player to throw the rendered audio away and reload;
/// before today it left it paused, and a listener who swapped voices mid-chapter had to find the
/// play button again to hear what they had chosen (owner, 2026-09-12).
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
            // The voice's name, not "Done": the press applies a change and throws rendered audio
            // away, and the sheet's drag indicator is what closes it without doing either.
            confirmLabel: { "Use \($0.name)" },
            note: { _ in
                discardedSeconds > 0
                    ? "Replaces \(DurationFormatter.long(discardedSeconds)) of rendered audio; it renders again with the new voice."
                    : nil
            },
            onConfirm: { option, alsoDefault in
                let applied: Bool
                if alsoDefault {
                    env.preferences.defaultVoiceID = option.id
                    // `force`: the override is cleared to nil, and for a book that was already
                    // following the old default that is no change to the stored value — but the
                    // voice it speaks in has changed, so the audio still has to go. The bar is only
                    // on screen when the effective voice is moving, so forcing here is never a
                    // wasted eviction.
                    applied = await env.voiceChange.apply(voiceID: nil, to: summary,
                                                          resumingPlayback: true, force: true)
                } else {
                    let resolved = await resolvedDefaultID()
                    let voiceID: String? = option.id == resolved ? nil : option.id
                    applied = await env.voiceChange.apply(voiceID: voiceID, to: summary, resumingPlayback: true)
                }
                if applied { dismiss() }
                return applied
            },
            alsoDefaultLabel: { "Also make \($0.name) my default voice" },
            showsFavorites: false
        )
        .background(Tokens.ground)
        .overlay { GeometryReader { geo in TopFade(inset: geo.safeAreaInsets.top) } }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Spacing.sheetCorner)
    }

    /// What "no override" plays as: the Settings pick, else whatever this device routes the system
    /// default to. Choosing it stores nothing, so the book follows Settings from then on.
    private func resolvedDefaultID() async -> String? {
        if let chosen = env.preferences.defaultVoiceID { return chosen }
        return await env.voiceRouting.effectiveVoiceID(VoiceOption.systemDefault.id)
    }
}
