// App/T2SReader/Collection/CollectionPage.swift
import SwiftUI
import T2SApp
import T2SCore
import T2SStore
import UniformTypeIdentifiers

struct CollectionPage: View {
    /// Which kinds the page shows. Everything imported is in the Collection now (articles too,
    /// since 2026-09-09 — see `LibraryModel.collection`): books, PDFs, and the two kinds of
    /// article, told apart by whether one came from a web address.
    private enum Filter: CaseIterable {
        case all, books, pdfs, text, links

        var title: String {
            switch self {
            case .all: return "All"
            case .books: return "Books"
            case .pdfs: return "PDFs"
            case .text: return "Text"
            case .links: return "Links"
            }
        }

        func includes(_ document: Document) -> Bool {
            switch self {
            case .all: return true
            case .books: return document.sourceType == .epub
            case .pdfs: return document.sourceType == .pdf
            case .text: return document.sourceType == .article && document.sourceURL == nil
            case .links: return document.sourceType == .article && document.sourceURL != nil
            }
        }
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.readerRoute) private var readerRoute
    @State private var showAdd = false
    /// Set by the Import page; opened from its `onDismiss`, once it has actually gone.
    @State private var pendingOpen: DocumentSummary?
    @State private var selected: DocumentSummary?
    @State private var launchOpened = false
    @State private var details: DocumentSummary?
    @State private var voiceChange: DocumentSummary?
    /// The book a menu's Delete named; the confirmation dialog presents it and clears it.
    @State private var pendingDelete: DocumentSummary?
    /// The placeholder a tap named, waiting on the Files picker (sync spec §5); the `.fileImporter`
    /// presents it and clears it.
    @State private var pendingFill: DocumentSummary?
    /// What `fillPlaceholder` said went wrong, for the alert; nil once dismissed.
    @State private var fillMessage: String?
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var filter: Filter = .all
    /// Whether the title's kind menu is down. `T2S_OPEN=kinds` opens it at launch — a scripted
    /// simulator cannot tap a title, and this is the only way to photograph the menu.
    @State private var isPickingKind = RootPage.launchOpen == "kinds"

    /// Cells align at the top so every book in a row stands on the same shelf line — the cover
    /// slot is a fixed proportion of the width, and only the text below it varies in height.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3)

    /// The page's books: the collection, narrowed to the chip's kind, then by title or author
    /// while a search is typed.
    private var books: [DocumentSummary] {
        var books = env.libraryModel.collection.filter { filter.includes($0.document) }
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
                    header(all: all, layout: layout)
                    if isSearching {
                        TextField("Search", text: $searchText)
                            .typeRole(.rowTitle)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Tokens.surface, in: Capsule())
                    }
                }
                if all.isEmpty {
                    EmptyShelf(title: "Your shelf is empty",
                               line: "Books, PDFs, links and text you import live here.",
                               button: "Import") { showAdd = true }
                        .padding(.top, Spacing.grid)
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
        // The kind menu hangs from the title over the shelf, so it lives on the scroll view rather
        // than in the column: inside the column the grid, drawn after it, would cover it.
        // The `if` is outside the `GeometryReader`, not in it: a reader left standing over a closed
        // menu is a page-wide view with nothing in it, and nothing is exactly what a tap on the
        // shelf must not hit.
        .overlayPreferenceValue(TitleAnchorKey.self) { anchor in
            if isPickingKind, let anchor {
                GeometryReader { page in kindMenu(under: page[anchor]) }
            }
        }
        // No ground of its own: `RootPager` paints one for all three pages, and a transparent page
        // is what lets the warm-up wash sit behind this one rather than over it (owner, 2026-09-10).
        .fullScreenCover(isPresented: $showAdd, onDismiss: openPending) { ImportPage(imported: $pendingOpen) }
        .sheet(item: $selected) { BookSheet(summary: $0) }
        .onChange(of: env.libraryModel.summaries.map(\.id), initial: true) { _, _ in
            // `T2S_OPEN=book` (screenshots, see `RootPage.launchOpen`): the book sheet, once.
            if RootPage.launchOpen == "book", !launchOpened,
               let document = RootPage.launchDocument(in: env.libraryModel.summaries) {
                launchOpened = true
                selected = document
            } else if RootPage.launchOpensImport, !launchOpened {
                launchOpened = true
                showAdd = true
            }
        }
        .sheet(item: $details) { DetailsSheet(summary: $0) }
        .sheet(item: $voiceChange) { VoiceChangeSheet(summary: $0) }
        // The menu's two taps, felt: a light knock as it drops, the selection tick when a kind is
        // taken. Nothing on the close — a menu dismissed by a tap outside it has nothing to confirm.
        .sensoryFeedback(trigger: isPickingKind) { _, open in
            open ? .impact(weight: .light, intensity: 0.7) : nil
        }
        .sensoryFeedback(.selection, trigger: filter)
        .confirmationDialog(
            pendingDelete.map { "Delete “\($0.document.title)”?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { book in
            Button("Delete from this device", role: .destructive) { Task { await env.deleteDocument(book.id) } }
            if env.syncModel.isEnabled {
                Button("Delete everywhere", role: .destructive) { Task { await env.deleteDocument(book.id, everywhere: true) } }
            }
        } message: { _ in
            Text(env.syncModel.isEnabled ? AppEnvironment.deleteMessageWithSync : AppEnvironment.deleteMessage)
        }
        .fileImporter(isPresented: Binding(get: { pendingFill != nil }, set: { if !$0 { pendingFill = nil } }),
                      allowedContentTypes: [.epub, .pdf]) { result in
            guard let summary = pendingFill, case .success(let url) = result else { return }
            Task { fillMessage = await env.libraryModel.fillPlaceholder(summary.id, from: url, sourceType: summary.document.sourceType) }
        }
        .alert("Couldn't add this book", isPresented: Binding(get: { fillMessage != nil }, set: { if !$0 { fillMessage = nil } })) {
            Button("OK") { fillMessage = nil }
        } message: { Text(fillMessage ?? "") }
    }

    private func openPending() {
        guard let doc = pendingOpen else { return }
        pendingOpen = nil
        readerRoute.open(doc)
    }

    /// No count under the title (owner's call, 2026-09-09): the shelf says what is here. The title
    /// *is* the kind filter now (owner, 2026-09-10): it names what the page is showing and drops the
    /// menu that changes it, in place of the row of tabs that used to sit under it. That freed the
    /// second row, so the layout switch joins `+` and Search on the header line.
    private func header(all: [DocumentSummary], layout: CollectionLayout) -> some View {
        HStack(alignment: .top) {
            Button {
                withAnimation(TitleMenuMotion.toggle(opening: !isPickingKind)) { isPickingKind.toggle() }
            } label: {
                PageTitle(text: filter.title) { TitleChevron() }
                    // The word crossfades when the kind changes rather than snapping to the next one.
                    .contentTransition(.opacity)
                    // The title is what gives when the row runs short (accessibility text sizes
                    // with a longer kind than "All"): one line, scaled down, never wrapped.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentShape(Rectangle())
                    .anchorPreference(key: TitleAnchorKey.self, value: .bounds) { $0 }
            }
            .buttonStyle(TitleTriggerStyle(isOpen: isPickingKind))
            .accessibilityLabel("Showing \(filter.title)")
            .accessibilityHint("Chooses which kind of thing the page shows")
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button { showAdd = true } label: { CircleGlyph(systemName: "plus") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Import")                          // Home's word for the same door
                if !all.isEmpty {
                    Button {
                        withAnimation(.snappy) { env.preferences.collectionLayout = layout == .grid ? .list : .grid }
                    } label: {
                        CircleGlyph(systemName: layout == .grid ? "list.bullet" : "square.grid.2x2")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(layout == .grid ? "Show as list" : "Show as grid")
                }
                Pill(label: isSearching ? "Done" : "Search", style: isSearching ? .selected : .soft) {
                    withAnimation(.snappy) { isSearching.toggle(); if !isSearching { searchText = "" } }
                }
            }
            .padding(.top, Spacing.titleTop + 4)
        }
    }

    /// The kind menu: the card under the title, over a clear sheet that takes the tap that closes it
    /// again. Everything imported is in one Collection, so this is the only thing that narrows it.
    private func kindMenu(under title: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(TitleMenuMotion.close) { isPickingKind = false } }
            TitleMenuCard(options: Filter.allCases, title: \.title, selection: filter) { kind in
                withAnimation(TitleMenuMotion.close) { filter = kind; isPickingKind = false }
            }
            .offset(x: title.minX, y: title.maxY + Spacing.grid)
            .transition(TitleMenuMotion.transition)
        }
    }

    /// `.all` with nothing typed cannot be empty here — `all.isEmpty` is handled first — so its
    /// line is only ever the search's.
    private var emptyText: String {
        if isSearching, !searchText.isEmpty { return "No matches." }
        switch filter {
        case .books: return "No books yet."
        case .pdfs: return "No PDFs yet."
        case .text: return "No text yet."
        case .links: return "No links yet."
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
                    // A long press is the only visible way in; VoiceOver's rotor gets the same items.
                    .accessibilityActions { menuItems(for: book) }
            }
        }
    }

    private func list(_ books: [DocumentSummary]) -> some View {
        LazyVStack(alignment: .leading, spacing: Spacing.row) {
            ForEach(books) { book in
                CollectionRow(summary: book, onOpen: {
                    if book.document.isPlaceholder { addHere(book) } else { selected = book }
                }) { menuItems(for: book) }
                    .contextMenu { menuItems(for: book) }
            }
        }
    }

    /// A placeholder's row tapped (sync spec §5): a link refetches straight into it (its content
    /// key matches, so `importArticle` fills it instead of doubling it); anything else needs the
    /// reader's own file, from the Files picker.
    private func addHere(_ summary: DocumentSummary) {
        if summary.document.sourceType == .article, let url = summary.document.sourceURL {
            Task { await env.importModel.fetch(link: url); await env.importModel.confirmPreview(); await env.libraryModel.refresh() }
        } else {
            pendingFill = summary
        }
    }

    private func cover(_ book: DocumentSummary, height: CGFloat) -> BookCover {
        BookCover(relativePath: book.document.coverImagePath, paths: env.paths, height: height,
                  title: book.document.title, author: book.document.author, isPDF: book.document.sourceType == .pdf)
    }

    // MARK: Menu

    /// One menu for the grid's long press, the row's `⋯` and the row's long press — the Home row's
    /// items where they apply here, plus Play and Delete. Nothing about a queue (owner's rule,
    /// 2026-09-09): playing a book is what puts it on Home. Play resumes a paused current book before
    /// opening the Reader, as the Home row and the book sheet do; for any other book the Reader
    /// loads and plays it itself.
    @ViewBuilder private func menuItems(for book: DocumentSummary) -> some View {
        let isCurrent = env.player.current?.id == book.id
        Button {
            Task {
                if isCurrent, !env.player.isPlaying { await env.player.togglePlay() }
                readerRoute.open(book)
            }
        } label: { Label("Play", systemImage: "play.fill") }
        Button { Task { await env.libraryModel.markFinished(book.id, !book.isFinished) } } label: {
            Label(book.isFinished ? "Mark as unfinished" : "Mark as finished", systemImage: "checkmark.circle")
        }
        Button { details = book } label: { Label("Details", systemImage: "info.circle") }
        Button { voiceChange = book } label: { Label("Change voice", systemImage: "person.wave.2") }
        Button {
            Task {
                if !isCurrent { await env.player.load(book, play: false) }
                env.player.renderWholeDocument()
            }
        } label: { Label("Render whole document", systemImage: "waveform") }
        Button(role: .destructive) { pendingDelete = book } label: { Label("Delete", systemImage: "trash") }
    }
}

/// One grid cell: the Home row's book at the Home row's size, on its shelf slot, with the title and
/// author under it. No progress line — the Collection is the shelf, not the Queue.
private struct CollectionTile: View {
    @Environment(AppEnvironment.self) private var env
    var summary: DocumentSummary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            // 12 pt between the book and its text: the shadow's visible part clears it, and the
            // three-up grid has no room for the Home row's 20.
            VStack(alignment: .leading, spacing: 12) {
                // `shelfHeight`, not the column's width: the same book is the same size here and on
                // Home, and the slot (`shelved`) keeps every title's left edge under its book's.
                ShelfArt(summary: summary, height: BookCover.shelfHeight)
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.document.title).typeRole(.pill).foregroundStyle(Tokens.ink).lineLimit(2)
                    if let author = summary.document.author {
                        Text(author).typeRole(.caption).foregroundStyle(Tokens.ink2).lineLimit(1)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())                                         // the whole cell taps, not just the ink
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
                    ShelfArt(summary: summary, height: 88)                     // the text column stays put row to row
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.document.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                        if let author = summary.document.author {
                            Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
                        }
                        if summary.document.isPlaceholder {
                            Text("On \(summary.remoteDeviceName ?? "another device") · tap to add here").typeRole(.meta).foregroundStyle(Tokens.ink3)
                        }
                        Text(CollectionText.lengthLine(for: summary)).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CollectionText.accessibilityLabel(for: summary))
            .accessibilityHint("Opens the book")
            Menu {
                menuItems()
            } label: {
                CircleGlyph(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }
}

/// What stands on the shelf for one document: a book (`BookCover`, on its `shelved` slot) for an
/// EPUB or PDF; for an article — a web page or pasted text, not a book — a sheet of paper
/// (`SheetCover`) on the same slot, as the Home row draws one, or its image if the page had one.
/// Bottom-leading in the slot like the books, so the row's text column and the grid's titles hold
/// still whichever kind sits there.
private struct ShelfArt: View {
    @Environment(AppEnvironment.self) private var env
    var summary: DocumentSummary
    var height: CGFloat

    var body: some View {
        let document = summary.document
        if document.sourceType == .article {
            if document.coverImagePath != nil {
                let side = height * BookCover.widestRatio
                Artwork(relativePath: document.coverImagePath, paths: env.paths, size: side, radius: Spacing.artworkSmall)
                    .frame(width: side, height: height, alignment: .bottomLeading)
            } else {
                SheetCover(title: document.title, sourceURL: document.sourceURL, height: height)
                    .shelved
            }
        } else {
            BookCover(relativePath: document.coverImagePath, paths: env.paths, height: height,
                      title: document.title, author: document.author, isPDF: document.sourceType == .pdf)
                .shelved
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

    /// "Title, by Author, PDF" (or "link", "text"): what VoiceOver reads for a tile or a row.
    static func accessibilityLabel(for summary: DocumentSummary) -> String {
        var parts = [summary.document.title]
        if let author = summary.document.author { parts.append("by \(author)") }
        switch summary.document.sourceType {
        case .pdf: parts.append("PDF")
        case .article: parts.append(summary.document.sourceURL == nil ? "text" : "link")
        case .epub: break
        }
        return parts.joined(separator: ", ")
    }
}
