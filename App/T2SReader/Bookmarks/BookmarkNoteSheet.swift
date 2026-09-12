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
            Text(entry.passage)
                .typeRole(.meta).foregroundStyle(Tokens.ink2)
                .lineLimit(4).multilineTextAlignment(.leading)
            Text(entry.rangeText)
                .typeRole(.mono).foregroundStyle(Tokens.ink2)
            TextEditor(text: $text)
                .typeRole(.rowTitle)
                .foregroundStyle(Tokens.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 120)
                .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($focused)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write a note so you can find this again")
                            .typeRole(.rowTitle).foregroundStyle(Tokens.ink3)
                            .padding(.horizontal, 15).padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
            Spacer(minLength: 0)
        }
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
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
        .task {
            text = entry.userNote ?? ""
            focused = true
        }
    }
}
