// App/T2SReader/Collection/CollectionPage.swift
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// Which kinds the Collection shows. Every EPUB and PDF is in it (spec §2.3) — articles live on
/// Home — so the chips are the two kinds and "All".
enum CollectionFilter: CaseIterable {
    case all, books, pdfs

    var title: String {
        switch self {
        case .all: return "All"
        case .books: return "Books"
        case .pdfs: return "PDFs"
        }
    }

    func includes(_ type: SourceType) -> Bool {
        switch self {
        case .all: return true
        case .books: return type == .epub
        case .pdfs: return type == .pdf
        }
    }
}

struct CollectionPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.readerRoute) private var readerRoute
    @State private var showAdd = false
    /// Set by the Import page; opened from its `onDismiss`, once it has actually gone.
    @State private var pendingOpen: DocumentSummary?
    @State private var selected: DocumentSummary?
    @State private var details: DocumentSummary?
    /// The book a menu's Delete named; the confirmation dialog presents it and clears it.
    @State private var pendingDelete: DocumentSummary?
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var filter: CollectionFilter = .all

    /// Cells align at the top so every book in a row stands on the same shelf line — the cover
    /// slot is a fixed proportion of the width, and only the text below it varies in height.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3)

    /// The page's books: the collection, narrowed to the chip's kind, then by title or author
    /// while a search is typed.
    private var books: [DocumentSummary] {
        var books = env.libraryModel.collection.filter { filter.includes($0.document.sourceType) }
        if isSearching, !searchText.isEmpty {
            books = books.filter {
                $0.document.title.localizedCaseInsensitiveContains(searchText)
                    || ($0.document.author?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return books
    }

    var body: some View {
        let all = env.libraryModel.collection
        let books = books
        let layout = env.preferences.collectionLayout
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                VStack(alignment: .leading, spacing: Spacing.row) {
                    header
                    if !all.isEmpty { controls(layout: layout) }
                    if isSearching {
                        TextField("Search", text: $searchText)
                            .typeRole(.rowTitle)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Tokens.surface, in: Capsule())
                    }
                }
                if all.isEmpty {
                    Text("Books and PDFs you import appear here, whether or not they are queued.")
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                } else if books.isEmpty {
                    Text(emptyText).typeRole(.meta).foregroundStyle(Tokens.ink2)
                } else if layout == .grid {
                    grid(books)
                } else {
                    list(books)
                }
                Color.clear.frame(height: Spacing.bottomClearance)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
        .fullScreenCover(isPresented: $showAdd, onDismiss: openPending) { ImportPage(imported: $pendingOpen) }
        .sheet(item: $selected) { BookSheet(summary: $0) }
        .sheet(item: $details) { DetailsSheet(summary: $0) }
        .confirmationDialog(
            pendingDelete.map { "Delete “\($0.document.title)”?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { book in
            Button("Delete from library", role: .destructive) { Task { await delete(book) } }
        } message: { _ in
            Text("Removes the book, its audio and its progress from this device.")
        }
    }

    private func openPending() {
        guard let doc = pendingOpen else { return }
        pendingOpen = nil
        readerRoute.open(doc)
    }

    /// No count under the title (owner's call, 2026-09-09): the chips and the shelf say what is here.
    private var header: some View {
        HStack(alignment: .top) {
            PageTitle(text: "Collection")
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                circleButton("plus", label: "Add") { showAdd = true }
                Pill(label: isSearching ? "Done" : "Search", style: isSearching ? .selected : .soft) {
                    withAnimation(.snappy) { isSearching.toggle(); if !isSearching { searchText = "" } }
                }
            }
            .padding(.top, Spacing.titleTop + 4)
        }
    }

    /// The kind chips on the left (the voice picker's filter row) and the layout switch on the
    /// right — a circle like the header's `+`, showing the layout a tap switches to.
    private func controls(layout: CollectionLayout) -> some View {
        HStack(spacing: Spacing.grid) {
            ForEach(CollectionFilter.allCases, id: \.self) { option in
                Pill(label: option.title, style: filter == option ? .selected : .soft) {
                    withAnimation(.snappy) { filter = option }
                }
            }
            Spacer(minLength: Spacing.grid)
            circleButton(layout == .grid ? "list.bullet" : "square.grid.2x2",
                         label: layout == .grid ? "Show as list" : "Show as grid") {
                withAnimation(.snappy) { env.preferences.collectionLayout = layout == .grid ? .list : .grid }
            }
        }
    }

    /// The 36 pt `surface` circle of the page headers and the row menus, with one glyph in it.
    private func circleButton(_ glyph: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tokens.ink).frame(width: 36, height: 36)
                .background(Tokens.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var emptyText: String {
        if isSearching, !searchText.isEmpty { return "No matches." }
        switch filter {
        case .books: return "No books yet."
        case .pdfs: return "No PDFs yet."
        case .all: return "No matches."
        }
    }

    // MARK: Layouts

    private func grid(_ books: [DocumentSummary]) -> some View {
        LazyVGrid(columns: columns, spacing: Spacing.row) {
            ForEach(books) { book in
                CollectionTile(summary: book) { selected = book }
                    .contextMenu {
                        menuItems(for: book)
                    } preview: {
                        // The book alone, larger, on ground — not a snapshot of the cell with its
                        // shadow cut off at the edge.
                        cover(book, height: 240).padding(Spacing.section).background(Tokens.ground)
                    }
            }
        }
    }

    private func list(_ books: [DocumentSummary]) -> some View {
        LazyVStack(alignment: .leading, spacing: Spacing.row) {
            ForEach(books) { book in
                CollectionRow(summary: book, onOpen: { selected = book }) { menuItems(for: book) }
                    .contextMenu { menuItems(for: book) }
            }
        }
    }

    private func cover(_ book: DocumentSummary, height: CGFloat) -> BookCover {
        BookCover(relativePath: book.document.coverImagePath, paths: env.paths, height: height,
                  title: book.document.title, isPDF: book.document.sourceType == .pdf)
    }

    // MARK: Menu

    /// One menu for the grid's long press, the row's `⋯` and the row's long press. Play resumes a
    /// paused current book before opening the Reader, as the Home row and the book sheet do; for
    /// any other book the Reader loads and plays it itself.
    @ViewBuilder private func menuItems(for book: DocumentSummary) -> some View {
        let isQueued = book.queueOrder != nil && !book.isFinished
        Button {
            Task {
                if env.player.current?.id == book.id, !env.player.isPlaying { await env.player.togglePlay() }
                readerRoute.open(book)
            }
        } label: { Label("Play", systemImage: "play.fill") }
        if isQueued {
            Button { Task { await env.libraryModel.archive(book.id) } } label: { Label("Remove from Queue", systemImage: "archivebox") }
        } else {
            Button { Task { await env.libraryModel.enqueue(book.id) } } label: { Label("Add to Queue", systemImage: "plus") }
        }
        Button { Task { await env.libraryModel.markFinished(book.id, !book.isFinished) } } label: {
            Label(book.isFinished ? "Mark as unfinished" : "Mark as finished", systemImage: "checkmark.circle")
        }
        Button { details = book } label: { Label("Details", systemImage: "info.circle") }
        Button(role: .destructive) { pendingDelete = book } label: { Label("Delete", systemImage: "trash") }
    }

    /// Delete removes the book from Queue and Collection both (spec §2.3). A book that is playing
    /// is paused first, so nothing keeps sounding from a document the library no longer has.
    private func delete(_ book: DocumentSummary) async {
        if env.player.current?.id == book.id, env.player.isPlaying { await env.player.togglePlay() }
        await env.libraryModel.delete(book.id)
    }
}

/// One grid cell: the Home row's book, standing at the foot of a cover-proportioned slot, with the
/// title and author under it. No progress line — the Collection is the shelf, not the Queue.
private struct CollectionTile: View {
    @Environment(AppEnvironment.self) private var env
    var summary: DocumentSummary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            // 12 pt between the book and its text: air under the cover's shadow.
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geo in
                    BookCover(relativePath: summary.document.coverImagePath, paths: env.paths, height: geo.size.height,
                              title: summary.document.title, isPDF: summary.document.sourceType == .pdf,
                              maxWidth: geo.size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .aspectRatio(BookCover.ratio, contentMode: .fit)
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.document.title).typeRole(.meta).foregroundStyle(Tokens.ink).lineLimit(2)
                    if let author = summary.document.author {
                        Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CollectionText.accessibilityLabel(for: summary))
        .accessibilityHint("Opens the book")
    }
}

/// One list row: a smaller book, the title in the row face with the author and length under it,
/// and the Home row's `⋯` circle for the same menu the grid gives on a long press.
private struct CollectionRow<Items: View>: View {
    @Environment(AppEnvironment.self) private var env
    var summary: DocumentSummary
    var onOpen: () -> Void
    @ViewBuilder var menuItems: () -> Items

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onOpen) {
                // 20 pt between the book and its text, as on the Home row: the shadow needs air.
                HStack(spacing: 20) {
                    BookCover(relativePath: summary.document.coverImagePath, paths: env.paths, height: 88,
                              title: summary.document.title, isPDF: summary.document.sourceType == .pdf)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.document.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(2)
                        if let author = summary.document.author {
                            Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
                        }
                        Text(CollectionText.lengthLine(for: summary)).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CollectionText.accessibilityLabel(for: summary))
            .accessibilityHint("Opens the book")
            Menu {
                menuItems()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.ink)
                    .frame(width: 36, height: 36)
                    .background(Tokens.surface, in: Circle())
            }
            .accessibilityLabel("More")
        }
    }
}

/// The words a tile and a row share.
private enum CollectionText {
    /// "12 chapters · ~5h 10m", in the book sheet's words.
    static func lengthLine(for summary: DocumentSummary) -> String {
        let chapters = summary.chapterCount == 1 ? "1 chapter" : "\(summary.chapterCount) chapters"
        return "\(chapters) · \(DurationFormatter.long(summary.totalSeconds, approximate: !summary.isFullyRendered))"
    }

    /// "Title, by Author, PDF": what VoiceOver reads for a tile or a row.
    static func accessibilityLabel(for summary: DocumentSummary) -> String {
        var parts = [summary.document.title]
        if let author = summary.document.author { parts.append("by \(author)") }
        if summary.document.sourceType == .pdf { parts.append("PDF") }
        return parts.joined(separator: ", ")
    }
}
