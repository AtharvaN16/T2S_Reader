import SwiftUI
import T2SApp
import T2SStore

/// Per-document voice override (spec §5), on one screen (Uptime's "Change your default voice",
/// the owner's reference, 2026-09-10): the picker with its radios, and a "Change voice" bar at the
/// foot that applies the chosen one. Changing invalidates rendered audio because render keys
/// include the voice identifier — so the bar says what it will throw away, in a line above itself,
/// instead of a second page asking again. Swipe down (the grabber shows) to leave it as it was.
struct VoiceChangeSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let summary: DocumentSummary
    /// The radio's choice, not yet applied.
    @State private var pending: VoiceOption?
    @State private var isApplying = false

    private var discardedSeconds: TimeInterval {
        env.voiceChange.discardedSeconds(for: summary)
    }

    /// The token the choice would store: nil for "follow the app default".
    private var pendingID: String?? { pending.map { $0.isDefault ? nil : $0.id } }
    private var isChange: Bool {
        guard let pendingID else { return false }
        return pendingID != summary.document.voiceID
    }

    var body: some View {
        NavigationStack {
            VoiceListPage(
                selection: pendingID ?? summary.document.voiceID,
                onSelect: { pending = $0 },
                confirm: .init(
                    label: "Change voice",
                    busyLabel: isApplying ? "Changing…" : nil,
                    note: isChange && discardedSeconds > 0
                        ? "Replaces \(DurationFormatter.long(discardedSeconds)) of rendered audio; it renders again with the new voice."
                        : nil,
                    isEnabled: isChange,
                    perform: apply
                )
            )
            .navigationTitle("Change voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Spacing.sheetCorner)
    }

    private func apply() {
        guard let pendingID, isChange else { return }
        isApplying = true
        Task {
            if await env.voiceChange.apply(voiceID: pendingID, to: summary) {
                dismiss()
            }
            isApplying = false
        }
    }
}
