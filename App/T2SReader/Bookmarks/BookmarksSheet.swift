// App/T2SReader/Bookmarks/BookmarksSheet.swift
import SwiftUI
import T2SApp
import T2SStore

/// Player and Reader overflow → "Bookmarks": the document's bookmarks, newest first, swipe to
/// delete (the Queue's pattern), tap to play from there.
struct BookmarksSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var summary: DocumentSummary
    @State private var model: BookmarkListModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            Text("Bookmarks").typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                .padding(.horizontal, Spacing.margin)
            if let model {
                if model.entries.isEmpty {
                    Text("No bookmarks yet. Tap the bookmark button while listening to save your place.")
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                        .padding(.horizontal, Spacing.margin)
                    Spacer()
                } else {
                    List {
                        ForEach(model.entries) { entry in
                            BookmarkRow(entry: entry,
                                        onJump: { Task { await model.jump(to: entry, in: summary); dismiss() } },
                                        onDelete: { Task { await model.delete(entry) } })
                            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button { Task { await model.delete(entry) } } label: { Label("Delete bookmark", systemImage: "trash") }
                                    .tint(Tokens.destructive)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Tokens.raised)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
                if let error = model.error {
                    Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive).padding(.horizontal, Spacing.margin)
                }
            }
        }
        .padding(.top, Spacing.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationBackground(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
        .task {
            let model = self.model ?? BookmarkListModel(library: env.library, player: env.player)
            self.model = model
            await model.load(summary)
        }
    }
}
