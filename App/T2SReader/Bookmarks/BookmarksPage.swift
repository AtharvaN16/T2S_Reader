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
    /// Whether the order menu is down.
    @State private var picking = false

    /// The air between two bookmarks. Generous on the owner's word (2026-09-12): a bookmark is up
    /// to four lines of the book plus a note plus two buttons, and at 18 two of them ran together
    /// into one block of text with a rule somewhere in the middle of it.
    private static let rowGap: CGFloat = 30

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
        .overlay { if picking, let model { orderMenu(model) } }
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
        VStack(alignment: .leading, spacing: Spacing.grid) {
            HStack {
                Button { dismiss() } label: { CircleGlyph(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                PageTitle(text: "Bookmarks")
                Spacer(minLength: 12)
                if let model, !model.entries.isEmpty { filterButton(model) }
            }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, Spacing.grid)
        .padding(.bottom, Spacing.row)
    }

    /// The order, behind the Collection's own dropdown rather than two pills across the page (owner,
    /// 2026-09-12). The pills said the same thing but spent a row of the screen saying it, and the
    /// Collection has already settled what a filter looks like here: a mark you tap, a card that
    /// drops under it with the choices and a radio against the one in force (`TitleMenuCard`).
    private func filterButton(_ model: BookmarkListModel) -> some View {
        Button {
            withAnimation(picking ? TitleMenuMotion.close : TitleMenuMotion.open) { picking.toggle() }
        } label: {
            CircleGlyph(systemName: "line.3.horizontal.decrease")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Order")
        .accessibilityValue(model.sort.title)
        .accessibilityHint("Chooses the order the bookmarks are in")
        .sensoryFeedback(trigger: picking) { _, open in
            open ? .impact(weight: .light, intensity: 0.7) : nil
        }
    }

    /// The card, hanging from the mark at the top right. Over a full-page catcher, so a tap
    /// anywhere else closes it without reaching the list underneath.
    private func orderMenu(_ model: BookmarkListModel) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(TitleMenuMotion.close) { picking = false } }
            TitleMenuCard(options: BookmarkSort.allCases, title: \.title, selection: model.sort) { order in
                withAnimation(TitleMenuMotion.close) {
                    model.sort = order
                    picking = false
                }
            }
            .padding(.trailing, Spacing.margin)
            .padding(.top, Spacing.grid + 44)                              // clear of the mark it hangs from
        }
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
                        .padding(.vertical, Self.rowGap)
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
