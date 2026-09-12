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
    @State private var editing: BookmarkEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            Text("Bookmarks").typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                .padding(.horizontal, Spacing.margin)
            if let model {
                if model.entries.isEmpty {
                    Text("No bookmarks yet. Tap the bookmark button while listening to save your place — you can add a note to any of them.")
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                        .padding(.horizontal, Spacing.margin)
                    Spacer()
                } else {
                    List {
                        ForEach(model.entries) { entry in
                            BookmarkRow(entry: entry,
                                        onJump: { Task { await model.jump(to: entry, in: summary); dismiss() } },
                                        onEditNote: { editing = entry },
                                        onDelete: { Task { await model.delete(entry) } })
                            // Even air above and below, so the divider falls midway between two
                            // bookmarks rather than hard under one of them (owner, 2026-09-12).
                            .listRowInsets(EdgeInsets(top: 18, leading: Spacing.margin,
                                                      bottom: 18, trailing: Spacing.margin))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button { Task { await model.delete(entry) } } label: { Label("Delete bookmark", systemImage: "trash") }
                                    .tint(Tokens.destructive)
                            }
                        }
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(Tokens.ink3)
                        .listRowBackground(Tokens.ground)
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
        // `ground`, not `raised`: the rows carry `surface` pills, and `surface` on `raised` is
        // four points of grey apart in the dark — on `ground` they read as they do on Home.
        .presentationBackground(Tokens.ground)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
        .sheet(item: $editing) { entry in
            BookmarkNoteSheet(summary: summary, entry: entry,
                              onSaved: { Task { await model?.load(summary) } })
        }
        .task {
            let model = self.model ?? BookmarkListModel(library: env.library, player: env.player)
            self.model = model
            await model.load(summary)
        }
    }
}
