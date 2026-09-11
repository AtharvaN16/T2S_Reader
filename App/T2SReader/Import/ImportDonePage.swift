// App/T2SReader/Import/ImportDonePage.swift
import SwiftUI
import T2SApp
import T2SStore

/// The step after an import (owner, 2026-09-10: "don't play it immediately — give me the option to
/// play or exit"). What came in stands on its shelf slot with its title and a line about it; the
/// bar at the foot is Play, with Done under it, and the circle closes. Play hands the first
/// document back through `play`, so the Reader opens — and plays — from the cover's `onDismiss`
/// exactly as before; Done and the circle only close the page. Either way the documents are in
/// the library already, and Home and the Collection behind the page show them.
struct ImportDonePage: View {
    @Environment(AppEnvironment.self) private var env
    var documents: [DocumentSummary]
    var play: () -> Void
    var done: () -> Void

    var body: some View {
        let failures = env.importModel.fileRows.compactMap { row -> (name: String, message: String)? in
            if case .failed(let message) = row.state { return (row.name, message) }
            return nil
        }
        ImportFrame(title: documents.count == 1 ? "Added to your library" : "\(documents.count) added to your library",
                    onBack: nil,
                    action: .init(label: documents.count == 1 ? "Play" : "Play the first", perform: play),
                    secondary: .init(label: "Done", perform: done)) {
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

    /// The document as Home shows it: the cover on the shelf slot, the title, and one line under
    /// it — the author, the site, or what kind of thing it is — with its length.
    private func row(_ summary: DocumentSummary) -> some View {
        let document = summary.document
        return HStack(alignment: .top, spacing: 20) {
            if document.sourceType == .article {
                SheetCover(title: document.title, sourceURL: document.sourceURL, height: BookCover.shelfHeight).shelved
            } else {
                BookCover(relativePath: document.coverImagePath, paths: env.paths, height: BookCover.shelfHeight,
                          title: document.title, author: document.author, isPDF: document.sourceType == .pdf)
                    .shelved
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(document.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(3)
                Text(detail(summary)).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(2)
            }
            .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ summary: DocumentSummary) -> String {
        let document = summary.document
        let who: String
        if let author = document.author, !author.isEmpty {
            who = author
        } else if let host = document.sourceURL?.host() {
            who = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        } else {
            switch document.sourceType {
            case .pdf: who = "PDF"
            case .epub: who = "Book"
            case .article: who = "Text"
            }
        }
        let length = DurationFormatter.long(summary.totalSeconds, approximate: !summary.isFullyRendered)
        return summary.totalSeconds > 0 ? "\(who) · \(length)" : who
    }
}
