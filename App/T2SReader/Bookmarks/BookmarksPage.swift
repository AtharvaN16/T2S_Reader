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
    /// Whether the order menu is down. `T2S_OPEN=bookmarks-order` has it down at launch — the
    /// Collection's `kinds`, for the same reason: a scripted simulator cannot tap the mark, and
    /// this is the only way to photograph the card where it lands.
    @State private var picking = RootPage.launchOpen == "bookmarks-order"

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
        // The card hangs from the mark that opens it, measured, the way the Collection's hangs from
        // its title (owner, 2026-09-12: "it should open below the button"). The `if` is outside the
        // reader, not in it: a reader left standing over a closed menu is a page-wide view with
        // nothing in it, and nothing is what a tap on the list must not hit.
        .overlayPreferenceValue(FilterAnchorKey.self) { anchor in
            if picking, let model, let anchor {
                GeometryReader { page in orderMenu(model, under: page[anchor], in: page.size) }
            }
        }
        .fullScreenCover(item: $opened) { entry in
            BookmarkDetail(entry: entry,
                           bookTitle: summary.document.title,
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
            // `T2S_OPEN=bookmarks-detail`: the first bookmark, opened, for the same reason the order
            // menu can be asked for at launch — nothing here can be tapped by a script. A beat
            // after this page has settled: a cover presented from inside one that is itself still
            // arriving is dropped on the floor.
            if RootPage.launchOpen == "bookmarks-detail", let first = model.entries.first {
                try? await Task.sleep(for: .milliseconds(500))
                opened = first
            }
        }
    }

    /// How far under the back row the title sits, in place of the `Spacing.titleTop` a root page
    /// uses: that gap assumes nothing above the title, and stacked under a back row it put
    /// "Bookmarks" a row and a half down an otherwise empty screen (owner, 2026-09-12: "bookmarks
    /// title and page start is too low"). This lands the word at about the height every root page's
    /// title sits at, with the back mark above it rather than the air.
    private static let titleGap: CGFloat = 12

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: { CircleGlyph(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                Spacer()
            }
            HStack(alignment: .top) {
                PageTitle(text: "Bookmarks", topPadding: Self.titleGap)
                Spacer(minLength: 12)
                // Beside the title rather than on its baseline: a circle has no baseline of its
                // own, so `.firstTextBaseline` hung it off the bottom of the row.
                if let model, !model.entries.isEmpty {
                    filterButton(model).padding(.top, Self.titleGap + 4)
                }
            }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, Spacing.grid + 4)
        .padding(.bottom, Spacing.grid + 4)
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
        .anchorPreference(key: FilterAnchorKey.self, value: .bounds) { $0 }
        .accessibilityLabel("Order")
        .accessibilityValue(model.sort.title)
        .accessibilityHint("Chooses the order the bookmarks are in")
        .sensoryFeedback(trigger: picking) { _, open in
            open ? .impact(weight: .light, intensity: 0.7) : nil
        }
    }

    /// The card, hanging under the mark at the top right — its trailing edge on the mark's, its top
    /// a grid below it, both from the mark's measured frame rather than from a guess at where the
    /// header put it. Over a full-page catcher, so a tap anywhere else closes it without reaching
    /// the list underneath, and on the Collection's own spring, growing out of the corner it hangs
    /// from.
    private func orderMenu(_ model: BookmarkListModel, under mark: CGRect, in page: CGSize) -> some View {
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
            .offset(x: -(page.width - mark.maxX), y: mark.maxY + Spacing.grid)
            .transition(TitleMenuMotion.transition(anchor: .topTrailing))
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
                        // `rowGap` is the air *between* two bookmarks; the first one has the title
                        // above it instead, and owes it nothing like as much.
                        .padding(.top, position == 0 ? Spacing.grid + 4 : Self.rowGap)
                        .padding(.bottom, Self.rowGap)
                }
                Color.clear.frame(height: Spacing.section)
            }
        }
        .scrollIndicators(.hidden)
        .animation(.snappy, value: model.entries.map(\.id))
        // Both ends soft (owner, 2026-09-12: "use bottom and top fade"): a row leaves the page
        // under the title and under the foot rather than being cut off at either.
        .overlay { EdgeFade(edge: .top, height: 20) }
        .overlay { EdgeFade(edge: .bottom, height: 44) }
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

/// The order mark's frame, carried up to the page that draws the card under it. Its own key rather
/// than the Collection's `TitleAnchorKey`: that one is the *title*'s frame, and a page that ever
/// reported both would have the two fight over one value.
private struct FilterAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
