// App/T2SReader/Collection/CollectionPage.swift
import SwiftUI
import T2SApp
import T2SStore

struct CollectionPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showAdd = false
    @State private var selected: DocumentSummary?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        let books = env.libraryModel.collection
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                HStack(alignment: .top) {
                    PageTitle(text: "Collection", subtitle: books.count == 1 ? "1 book" : "\(books.count) books")
                    Spacer(minLength: 12)
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tokens.ink).frame(width: 36, height: 36)
                            .background(Tokens.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add")
                    .padding(.top, Spacing.titleTop + 4)
                }
                if books.isEmpty {
                    Text("Books and PDFs you import appear here, whether or not they are queued.")
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
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
                    }
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
        .sheet(isPresented: $showAdd) { AddSheet() }
        .sheet(item: $selected) { BookSheet(summary: $0) }
    }
}
