// App/T2SReader/Queue/QueuePage.swift
import SwiftUI
import T2SApp
import T2SStore

struct QueuePage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.readerRoute) private var readerRoute
    @State private var showAdd = false
    /// Set by the Import page; opened from its `onDismiss`, once it has actually gone.
    @State private var pendingOpen: DocumentSummary?
    @State private var details: DocumentSummary?
    /// The row's own touch target (owner, 2026-09-11): the book opens the sheet, Play alone opens
    /// the Reader — matching the Collection tile.
    @State private var selectedBook: DocumentSummary?

    private var rows: [DocumentSummary] { env.libraryModel.visibleRows }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                if rows.isEmpty, !env.libraryModel.hasLoaded {
                    // The first `refresh()` (`RootPager`'s launch `.task`) has not answered yet, so
                    // an empty `rows` does not yet mean an empty queue — see `CollectionPage`, which
                    // waits on the same flag so a real queue does not flash this empty state.
                    EmptyView()
                        .listRowInsets(EdgeInsets())
                } else if rows.isEmpty {
                    EmptyShelf(title: "Nothing playing yet",
                               line: "Everything you're listening to will appear right here.")
                        .padding(.top, EmptyShelf.topGap - Spacing.row)     // the header row's bottom inset is the rest
                        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                } else {
                    SectionHeader(title: "Continue Listening")
                        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                }
                ForEach(rows) { summary in
                    QueueRow(summary: summary, onOpen: {
                        readerRoute.open(summary)
                    }, onOpenBook: { selectedBook = summary }, onDetails: { details = summary })
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.homeRowGap, trailing: Spacing.margin))
                }
                Color.clear.frame(height: Spacing.bottomClearance)        // room for the mini-player, indicator and their fade
                    .listRowInsets(EdgeInsets())
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)            // the pager's ground shows through, and the warm-up wash with it
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .refreshable { await env.libraryModel.refresh() }
        .fullScreenCover(isPresented: $showAdd, onDismiss: openPending) { ImportPage(imported: $pendingOpen) }
        .sheet(item: $details) { DetailsSheet(summary: $0) }
        .sheet(item: $selectedBook) { BookSheet(summary: $0, pulseOnOpen: true) }
    }

    private func openPending() {
        guard let doc = pendingOpen else { return }
        pendingOpen = nil
        readerRoute.open(doc)
    }

    /// Search lives on Collection now; Home's one control is the way in. While the page is empty
    /// it is the blue one too — the only call to action on the page, now the shelf has no button
    /// of its own; `hasLoaded` keeps it grey until the first refresh has actually said "empty".
    private var header: some View {
        let isEmpty = rows.isEmpty && env.libraryModel.hasLoaded
        return HStack(alignment: .top) {
            PageTitle(text: "Home")
            Spacer(minLength: 12)
            Pill(label: "Import", glyph: "plus", style: isEmpty ? .glow : .soft) { showAdd = true }
                .accessibilityLabel("Import")
                .padding(.top, Spacing.titleTop + 4)
        }
    }
}
