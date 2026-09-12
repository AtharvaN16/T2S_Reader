// App/T2SReader/Import/ImportDonePage.swift
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// The step after an import (owner, 2026-09-10: "don't play it immediately — give me the option to
/// play or exit"). What came in stands on its shelf slot with its title, a line about it, and its
/// own Play pill carrying its length — the Home row's control, so the two screens read the same
/// (owner, 2026-09-11); the bar at the foot is Done, and the circle closes too. A pill hands that
/// document back through `play`, so the Reader opens — and plays — from the cover's `onDismiss`
/// exactly as before; Done and the circle only close the page. Either way the documents are in
/// the library already, and Home and the Collection behind the page show them.
struct ImportDonePage: View {
    @Environment(AppEnvironment.self) private var env
    var documents: [DocumentSummary]
    /// The book whose pill was pressed, never "the first": every row can start.
    var play: (DocumentSummary) -> Void
    var done: () -> Void

    var body: some View {
        let failures = env.importModel.fileRows.compactMap { row -> (name: String, message: String)? in
            if case .failed(let message) = row.state { return (row.name, message) }
            return nil
        }
        ImportFrame(title: documents.count == 1 ? "Added to your library" : "\(documents.count) added to your library",
                    onBack: nil,
                    action: .init(label: "Done", perform: done)) {
            VStack(alignment: .leading, spacing: Spacing.row) {
                ForEach(documents) { summary in row(summary) }
                if !failures.isEmpty {
                    // A batch that half worked: the ones that did not, still named, so the step is
                    // never a false "all done" (spec §6: never silent).
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(failures, id: \.name) { failure in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "doc").foregroundStyle(Tokens.ink2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(failure.name).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(1)
                                    Text(failure.message).typeRole(.meta).foregroundStyle(Tokens.destructive)
                                }
                            }
                        }
                    }
                    .padding(.top, Spacing.grid)
                }
            }
        }
    }

    /// The document as Home shows it: the cover on the shelf slot, the title, one line under it —
    /// the author, the site, or what kind of thing it is — and the Play pill with the length in it.
    private func row(_ summary: DocumentSummary) -> some View {
        let document = summary.document
        return HStack(alignment: .top, spacing: 20) {
            if document.sourceType == .article {
                SheetCover(title: document.title, sourceURL: document.sourceURL, height: BookCover.shelfHeight).shelved
            } else {
                BookCover(relativePath: document.coverImagePath, paths: env.paths, height: BookCover.shelfHeight,
                          title: document.title, author: document.displayAuthor, isPDF: document.sourceType == .pdf)
                    .shelved
            }
            // 18 between the words and the pill, and the words grouped tight above it: `QueueRow`'s
            // own measure, so a book that has just come in stands the way the same book stands on
            // Home (owner, 2026-09-12). At 6 the pill sat with the author line as if it were a
            // third line of the text, rather than a tap target the reading had stopped for.
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(document.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(3)
                    Text(detail(summary)).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(2)
                }
                // Under the title, like Home's Continue Listening: the whole book's length rides in
                // the pill rather than sitting in the line above it, so one tap is the sentence.
                Pill(label: "Play", detail: length(summary), glyph: "play.fill", style: .soft) { play(summary) }
                    .accessibilityHint("Plays and opens the reader")
            }
            .padding(.top, 4)
        }
        .accessibilityElement(children: .contain)
    }

    /// Who it is by, or where it came from: the length used to be here and is now in the pill.
    private func detail(_ summary: DocumentSummary) -> String {
        let document = summary.document
        if let author = document.displayAuthor, !author.isEmpty { return author }
        if let host = document.sourceURL?.host() {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        switch document.sourceType {
        case .pdf: return "PDF"
        case .epub: return "Book"
        case .article: return "Text"
        }
    }

    /// The book's length, never with a `~` (owner, 2026-09-11): nothing has been rendered yet at
    /// this step, so every import would wear one, and an estimate the listener cannot act on reads
    /// as a fault rather than as honesty. Nil for a document with no length to state.
    private func length(_ summary: DocumentSummary) -> String? {
        summary.totalSeconds > 0 ? DurationFormatter.long(summary.totalSeconds) : nil
    }
}
