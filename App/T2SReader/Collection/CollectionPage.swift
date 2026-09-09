// App/T2SReader/Collection/CollectionPage.swift
import SwiftUI
import T2SApp
import T2SStore

struct CollectionPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.readerRoute) private var readerRoute
    @State private var showAdd = false
    /// Set by the Import page; opened from its `onDismiss`, once it has actually gone.
    @State private var pendingOpen: DocumentSummary?
    @State private var selected: DocumentSummary?
    @State private var searchText = ""
    @State private var isSearching = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    /// The grid's books: the whole collection, narrowed by title while a search is typed.
    private var books: [DocumentSummary] {
        let all = env.libraryModel.collection
        guard isSearching, !searchText.isEmpty else { return all }
        return all.filter { $0.document.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        let all = env.libraryModel.collection
        let books = books
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                VStack(alignment: .leading, spacing: Spacing.row) {
                    header(count: all.count)
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
                    Text("No matches.").typeRole(.meta).foregroundStyle(Tokens.ink2)
                }
                LazyVGrid(columns: columns, spacing: Spacing.row) {
                    ForEach(books) { book in
                        Button { selected = book } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                GeometryReader { geo in
                                    Artwork(relativePath: book.document.coverImagePath, paths: env.paths,
                                            size: geo.size.width, radius: Spacing.artworkLarge)
                                }
                                .aspectRatio(1, contentMode: .fit)
                                ProgressBar(fraction: env.libraryModel.progress(for: book.id)?.fraction ?? 0)
                                Text(book.document.title).typeRole(.meta).foregroundStyle(Tokens.ink).lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(book.document.title), \(Int(((env.libraryModel.progress(for: book.id)?.fraction ?? 0) * 100).rounded())) percent read")
                        .accessibilityHint("Opens the book")
                    }
                }
                Color.clear.frame(height: Spacing.bottomClearance)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
        .fullScreenCover(isPresented: $showAdd, onDismiss: openPending) { ImportPage(imported: $pendingOpen) }
        .sheet(item: $selected) { BookSheet(summary: $0) }
    }

    private func openPending() {
        guard let doc = pendingOpen else { return }
        pendingOpen = nil
        readerRoute.open(doc)
    }

    /// The subtitle counts the whole collection, not the search's matches.
    private func header(count: Int) -> some View {
        HStack(alignment: .top) {
            PageTitle(text: "Collection", subtitle: count == 1 ? "1 book" : "\(count) books")
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.ink).frame(width: 36, height: 36)
                        .background(Tokens.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add")
                Pill(label: isSearching ? "Done" : "Search", style: isSearching ? .selected : .soft) {
                    withAnimation(.snappy) { isSearching.toggle(); if !isSearching { searchText = "" } }
                }
            }
            .padding(.top, Spacing.titleTop + 4)
        }
    }
}
