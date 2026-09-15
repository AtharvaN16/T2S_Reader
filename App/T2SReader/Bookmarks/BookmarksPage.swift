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
    /// The list turned into a selection list, mirroring the Book sheet's render-selection flow.
    @State private var isSelecting = false
    @State private var selection: Set<BookmarkEntry.ID> = []
    @State private var confirmingBulkDelete = false

    /// The air between two bookmarks. Generous on the owner's word (2026-09-12): a bookmark is up
    /// to four lines of the book plus a note plus two buttons, and at 18 two of them ran together
    /// into one block of text with a rule somewhere in the middle of it.
    private static let rowGap: CGFloat = 30
    /// How far the top `EdgeFade` runs, and — paired with it — the first row's own gap under the
    /// header: the two have to agree, or the fade either cuts short of `EdgeFade`'s own default
    /// (owner, 2026-09-14: "the fade is abrupt") or reaches past the gap into the first row's words.
    /// Longer still on the owner's second word the same day ("increase space below the header so
    /// the fade is longer and more gradual") — the header's own ground runs further down the page
    /// before it starts thinning, so the ramp has more room to be gentle in.
    private static let topFadeHeight: CGFloat = 40

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
        .safeAreaInset(edge: .bottom) {
            // The Book sheet's render-mode bar (owner, 2026-09-14: "we can use the pattern we used
            // in voice sheet and render mode") — no header pill, no header close mark; the key
            // itself is the only door out. One line over it throughout, not only once something is
            // picked (owner, 2026-09-14: "keep select all option above the done button, which
            // changes to clear selection"): "Select all" with nothing ticked, "Clear selection"
            // once something is.
            if isSelecting, let model {
                VStack(spacing: Spacing.grid) {
                    selectAllRow(model)
                    BarButton(label: selection.isEmpty ? "Done" : "Delete (\(selection.count))",
                              tone: selection.isEmpty ? .ink : .destructive) {
                        if selection.isEmpty { exitSelecting() } else { confirmingBulkDelete = true }
                    }
                }
                .padding(.horizontal, Spacing.margin)
                .padding(.top, Spacing.grid * 2)
                .padding(.bottom, Spacing.grid)
                .background { BottomFade(color: Tokens.ground) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog(selection.count == 1 ? "Delete this bookmark?" : "Delete \(selection.count) bookmarks?",
                             isPresented: $confirmingBulkDelete, titleVisibility: .visible) {
            Button(selection.count == 1 ? "Delete bookmark" : "Delete \(selection.count) bookmarks", role: .destructive) {
                Task {
                    await model?.delete(selection)
                    exitSelecting()
                }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .task {
            let model = self.model ?? BookmarkListModel(library: env.library, player: env.player)
            self.model = model
            await model.load(summary)
        }
    }

    /// How far under the back row the title sits, in place of the `Spacing.titleTop` a root page
    /// uses: that gap assumes nothing above the title, and stacked under a back row it put
    /// "Bookmarks" a row and a half down an otherwise empty screen (owner, 2026-09-12: "bookmarks
    /// title and page start is too low"). Slightly more than that first landing (owner, 2026-09-14:
    /// "move bookmark header slightly lower") now that the row above carries the filter and select
    /// marks as well as the back one — a title sitting right under a row of glyphs read as crowding
    /// them rather than sitting under its own back mark.
    private static let titleGap: CGFloat = 18

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: { CircleGlyph(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                Spacer()
                // On the back row, not beside the title (owner, 2026-09-14: "move the filter and
                // check buttons to align with the back button") — three marks in one row read as
                // the page's controls, and the title's own row is free to hold only the word.
                //
                // Nothing here at all once selecting (owner, 2026-09-14: "we don't need select all
                // and deselect to be there") — the render-mode header carries no clear/close mark
                // either; the bar at the foot is the whole of that mode's controls.
                if let model, !model.entries.isEmpty, !isSelecting {
                    HStack(spacing: 8) {
                        Button { enterSelecting() } label: { CircleGlyph(systemName: "checkmark.circle") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select bookmarks")
                        filterButton(model)
                    }
                }
            }
            // A step under `.pageTitle` (owner, 2026-09-14): the word now sits under a row that
            // carries three marks instead of one, and at full size it crowded them from below as
            // well as beside. Still `.playerTitle` — a step over a row's own `.rowTitle` — so it
            // reads as the page, not one more row in the list under it.
            PageTitle(text: "Bookmarks", topPadding: Self.titleGap, role: .playerTitle)
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
                                onDelete: { Task { await model.delete(entry) } },
                                isSelecting: isSelecting,
                                isSelected: selection.contains(entry.id),
                                onToggleSelect: { toggleSelection(entry) })
                        // Always the page's own margin, in or out of select mode (owner, 2026-09-14:
                        // "the margin is not right for the rows when selected, they don't follow
                        // page margin") — borrowing width from it to hold the check even width made
                        // the rows narrower than the header above them. The check instead comes out
                        // of the text's own room while selecting, same as the first cut.
                        .padding(.horizontal, Spacing.margin)
                        // `rowGap` is the air *between* two bookmarks; the first one has the title
                        // above it instead, and owes it nothing like as much — but at least
                        // `Self.topFadeHeight`, so the fade below has clear ground to run over
                        // rather than biting into the first row's own words at rest.
                        .padding(.top, position == 0 ? Self.topFadeHeight : Self.rowGap)
                        .padding(.bottom, Self.rowGap)
                }
                Color.clear.frame(height: Spacing.section)
            }
        }
        .scrollIndicators(.hidden)
        .animation(.snappy, value: model.entries.map(\.id))
        // Both ends soft (owner, 2026-09-12: "use bottom and top fade"): a row leaves the page
        // under the title and under the foot rather than being cut off at either. The top one was
        // shorter than `EdgeFade`'s own default and shorter than the gap it had to run over, so a
        // row scrolling under the header met the last few points of it as a cut rather than a fade
        // (owner, 2026-09-14: "make the fade gradual, currently there is an abrupt fade").
        .overlay { EdgeFade(edge: .top, height: Self.topFadeHeight) }
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

    private func enterSelecting() {
        withAnimation(.snappy) { isSelecting = true }
    }

    private func exitSelecting() {
        withAnimation(.snappy) { isSelecting = false; selection.removeAll() }
    }

    private func selectAll(_ model: BookmarkListModel) {
        withAnimation(.snappy) { selection = Set(model.entries.map(\.id)) }
    }

    /// Puts every tick back down without leaving the mode — `BookSheet.clearSelection()`'s own
    /// reason applies here too: undoing a selection a row at a time is the one thing this mode
    /// makes the reader do by hand otherwise.
    private func clearSelection() {
        withAnimation(.snappy) { selection.removeAll() }
    }

    /// One line over the key throughout select mode, not only once something is picked
    /// (`BookSheet.clearRow`'s shape, its job doubled): a glyph, the words in the pill's type, no
    /// capsule — it must not read as a second key. "Select all" with nothing ticked, since a mode
    /// with nothing picked has nothing to clear; "Clear selection" from the first tick on.
    ///
    /// Both labels are always laid out, stacked, and only ever faded — the same fix as the row's
    /// own check (`BookmarkRow`), for the same reason. A `Text`/`Image` whose *content* changes
    /// under `withAnimation` tries to morph the old glyphs into the new ones, and "Select all" →
    /// "Clear selection" is also a width change fighting that morph at the same time, which is
    /// what read as ghosting (owner, 2026-09-14: "please use a better animation"). Two fixed views
    /// crossfading past each other has neither problem: nothing's content ever changes, so there
    /// is nothing to morph, and the `ZStack` is already the wider label's width before either tap.
    private func selectAllRow(_ model: BookmarkListModel) -> some View {
        let isEmpty = selection.isEmpty
        return Button { isEmpty ? selectAll(model) : clearSelection() } label: {
            ZStack {
                selectAllLabel("checkmark.circle", "Select all").opacity(isEmpty ? 1 : 0)
                selectAllLabel("xmark.circle.fill", "Clear selection").opacity(isEmpty ? 0 : 1)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            // Both labels sit in the tree at all times now, opacity or not — VoiceOver does not
            // care which one is invisible, so left alone it would read both on every visit.
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isEmpty ? "Select all" : "Clear selection")
        .accessibilityHint(isEmpty ? "Selects every bookmark" : "Unticks every bookmark")
    }

    private func selectAllLabel(_ glyph: String, _ text: String) -> some View {
        HStack(spacing: Spacing.grid + 2) {
            Image(systemName: glyph).font(.system(size: 15, weight: .semibold))
            Text(text).typeRole(.pill)
        }
        .foregroundStyle(Tokens.ink2)
    }

    private func toggleSelection(_ entry: BookmarkEntry) {
        withAnimation(.snappy) {
            if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
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
