// App/T2SReader/Bookmarks/BookmarkNoteSheet.swift
import SwiftUI
import T2SApp
import T2SStore

/// Writing a note on a bookmark (2026-09-11 spec §5). The passage and its span first, so it is
/// clear what is being annotated, then the field, then `BarButton` — which exists for exactly this
/// shape, "the one action of a step, as a full-width bar pinned to a page's foot", and already
/// rides above the keyboard.
///
/// Saving blank clears the note rather than storing an empty string, so the row falls back to the
/// passage (`BookmarkEntry.headline`).
struct BookmarkNoteSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var summary: DocumentSummary
    var entry: BookmarkEntry
    var onSaved: () -> Void

    @State private var text: String = ""
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry.hasNote ? "Edit note" : "Add a note")
                .typeRole(.playerTitle).foregroundStyle(Tokens.ink)
            // The whole passage, so it is plain what is being annotated; once the field has focus
            // it folds to two lines and gives the keyboard the screen (owner, 2026-09-12). A plain
            // `Text` rather than a scroller: it takes only the height it needs, where a `ScrollView`
            // holds its full frame open and leaves a short passage sitting over a gap.
            Text(entry.fullPassage)
                .typeRole(.meta).foregroundStyle(Tokens.ink2)
                .lineLimit(focused ? 2 : 16)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.rangeText)
                .typeRole(.mono).foregroundStyle(Tokens.ink2)
            TextEditor(text: $text)
                .typeRole(.rowTitle)
                .foregroundStyle(Tokens.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 120)
                // A hairline as well as the fill: on `raised` in the dark, `surface` alone is all
                // but the same grey and the field had no edge at all (owner, 2026-09-12).
                .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Tokens.ink3, lineWidth: 1)
                )
                .focused($focused)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write your note here")
                            .typeRole(.rowTitle).foregroundStyle(Tokens.ink2)
                            .padding(.horizontal, 15).padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
            Spacer(minLength: 0)
        }
        .animation(.spring(duration: 0.25), value: focused)
        .padding(.horizontal, Spacing.margin)
        .padding(.top, Spacing.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom) {
            BarButton(label: "Save note", busyLabel: isSaving ? "Saving…" : nil, isEnabled: !isSaving) {
                Task {
                    isSaving = true
                    let model = BookmarkListModel(library: env.library, player: env.player)
                    await model.load(summary)
                    await model.setNote(text, on: entry)
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.grid)
        }
        .presentationBackground(Tokens.raised)
        // One tall detent: a passage printed in full needs the room, and the sheet no longer has
        // to be dragged up to read what is being annotated (owner, 2026-09-12).
        .presentationDetents([.large])
        .presentationCornerRadius(Spacing.sheetCorner)
        // No focus on open: the passage gets the screen first, and the keyboard arrives when the
        // reader taps the field (owner, 2026-09-12).
        .task { text = entry.userNote ?? "" }
    }
}
