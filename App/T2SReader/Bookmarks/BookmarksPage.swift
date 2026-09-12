// App/T2SReader/Bookmarks/BookmarksPage.swift
import SwiftUI
import T2SApp
import T2SStore

/// A document's bookmarks, as a page (owner, 2026-09-12: "open the bookmarks in a page and not a
/// sheet"). Reached from the Reader's overflow and from the Book sheet's `⋯`; both present it the
/// same way, so there is one bookmarks screen rather than one per host.
///
/// **The rows are not a `List`.** A list draws a separator above its first row as well as between
/// the rest, which is the line the owner asked to lose from under the title, and the ways out of
/// that are worse than not using one: the rules live between the rows here, drawn where they
/// belong and nowhere else. What goes with the `List` is swipe-to-delete — no loss, since being
/// hidden behind a swipe is exactly why the owner reported there was "no way to delete"
/// (`BookmarkDetail` carries a Delete you can see, and the row keeps its long-press).
///
/// Tapping a row opens it (`BookmarkDetail`), never the editor. Writing is a choice you make from
/// there.
struct BookmarksPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var summary: DocumentSummary
    /// Run once a bookmark has been jumped to, after this page closes: the Reader has only to
    /// close it, the Book sheet has to close itself as well and open the Reader on the book.
    var onJumped: () -> Void = {}

    @State private var model: BookmarkListModel?
    @State private var editing: BookmarkEntry?
    @State private var opened: BookmarkEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let model {
                if model.entries.isEmpty {
                    Text("No bookmarks yet. Tap the bookmark button while listening to save your place — you can add a note to any of them.")
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                        .padding(.horizontal, Spacing.margin)
                        .padding(.top, Spacing.row)
                    Spacer()
                } else {
                    sortPills(model)
                    rows(model)
                }
                if let error = model.error {
                    Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive)
                        .padding(.horizontal, Spacing.margin)
                }
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.ground.ignoresSafeArea())
        .fullScreenCover(item: $opened) { entry in
            BookmarkDetail(entry: entry,
                           onListen: { jump(to: entry) },
                           onEditNote: { editing = entry },
                           onDelete: { Task { await model?.delete(entry) } })
        }
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

    private var header: some View {
        HStack {
            Button { dismiss() } label: { CircleGlyph(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, Spacing.grid)
        .overlay(alignment: .bottomLeading) {
            PageTitle(text: "Bookmarks")
                .padding(.horizontal, Spacing.margin)
                .offset(y: Spacing.row + 12)
        }
        .padding(.bottom, Spacing.row + 12)
    }

    /// Two pills, the Voice page's filter idiom: the order is a choice worth seeing, not one worth
    /// hunting for in a menu — and with two options a menu would be a tap to reveal a single
    /// alternative.
    private func sortPills(_ model: BookmarkListModel) -> some View {
        HStack(spacing: 8) {
            ForEach(BookmarkSort.allCases, id: \.self) { option in
                Pill(label: option.title, style: model.sort == option ? .selected : .soft) {
                    withAnimation(.snappy) { model.sort = option }
                }
            }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.bottom, Spacing.row)
        .sensoryFeedback(.selection, trigger: model.sort)
    }

    private func rows(_ model: BookmarkListModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.entries.enumerated()), id: \.element.id) { position, entry in
                    // Between the rows and nowhere else: none above the first (the line the owner
                    // asked to lose), none under the last.
                    if position > 0 {
                        Rectangle().fill(Tokens.ink3).frame(height: 1)
                            .padding(.horizontal, Spacing.margin)
                    }
                    BookmarkRow(entry: entry,
                                onOpen: { opened = entry },
                                onJump: { jump(to: entry) },
                                onEditNote: { editing = entry },
                                onDelete: { Task { await model.delete(entry) } })
                        .padding(.horizontal, Spacing.margin)
                        .padding(.vertical, 18)
                }
                Color.clear.frame(height: Spacing.section)
            }
        }
        .scrollIndicators(.hidden)
        .animation(.snappy, value: model.entries.map(\.id))
    }

    private func jump(to entry: BookmarkEntry) {
        guard let model else { return }
        Task {
            await model.jump(to: entry, in: summary)
            dismiss()
            onJumped()
        }
    }
}
