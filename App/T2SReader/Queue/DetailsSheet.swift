// App/T2SReader/Queue/DetailsSheet.swift
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// Context-menu "Details": what the library knows about a document, and nothing to do to it.
///
/// It used to end in Reprocess, a sentence explaining Reprocess, and Delete (owner, 2026-09-18:
/// take all three out). Delete is still where a book is chosen rather than read about — the
/// Collection's menu and the book sheet's `⋯` — and a panel of facts that can also throw a book's
/// audio away is a panel you have to read carefully before opening. Reprocess has no button
/// anywhere now; `Library.reprocess` still runs by itself when a document goes stale. What is left
/// is the book, its cover the way the book sheet shows it, and what the library knows about it.
struct DetailsSheet: View {
    @Environment(AppEnvironment.self) private var env
    var summary: DocumentSummary

    /// The measured height of everything below, for the sheet's one detent. Zero until the first
    /// layout answers; `minHeight` stands in for that frame.
    @State private var contentHeight: CGFloat = 0

    /// The cover here, smaller than the book sheet's 200: this sheet is a list of facts with the
    /// book above it, not the book with its chapters under it.
    private static let coverHeight: CGFloat = 148
    /// The shortest the sheet may be: the frame it opens in before the first layout has said how
    /// tall its contents are. Nothing caps it from above — the system clamps a `.height` detent to
    /// what the screen allows, and the scroll view underneath carries the remainder on a small
    /// phone or at a large text size.
    private static let minHeight: CGFloat = 380

    private var isArticle: Bool { summary.document.sourceType == .article }

    var body: some View {
        // A sheet that opens at exactly its own height (owner, 2026-09-18: "the details sheet does
        // not open completely and information gets cut off"). It was `[.medium, .large]`, which
        // opens at medium — half the screen — with the last of the facts below the fold and nothing
        // saying so. One fitted detent has no fold to be caught behind.
        ScrollView {
            content
                .padding(.horizontal, Spacing.margin)
                .padding(.vertical, Spacing.margin)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        // Only when there is something to scroll: a fitted sheet that rubber-bands reads as if
        // something were hidden under it.
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(max(contentHeight, Self.minHeight))])
        .presentationBackground(Tokens.raised)
        .presentationCornerRadius(Spacing.sheetCorner)
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            // The book, then its name, centred over the facts — the book sheet's own opening, at
            // this sheet's size (owner, 2026-09-18).
            VStack(spacing: 14) {
                cover
                VStack(spacing: 8) {
                    Text(summary.document.title).typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                        .multilineTextAlignment(.center)
                    if let author = summary.document.displayAuthor {
                        Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                row("Source", summary.document.sourceType.rawValue.uppercased())
                if let url = summary.document.sourceURL { row("Link", url.absoluteString) }
                row("Added", summary.document.addedAt.formatted(date: .abbreviated, time: .shortened))
                row("Chapters", "\(summary.chapterCount)")
                row("Length", DurationFormatter.long(summary.totalSeconds, approximate: !summary.isFullyRendered))
                row("Rendered", summary.utteranceCount > 0 ? "\(summary.renderedCount * 100 / summary.utteranceCount)%" : "—")
            }
        }
    }

    /// The book as the book sheet stands it: the cover over the light it gives off. A web page or a
    /// pasted note is a sheet of paper here as it is on every shelf, and a sheet of paper gives off
    /// nothing — no backlight under it.
    @ViewBuilder private var cover: some View {
        if isArticle {
            SheetCover(title: summary.document.title, sourceURL: summary.document.sourceURL,
                       height: Self.coverHeight)
        } else {
            let book = BookCover(relativePath: summary.document.coverImagePath, paths: env.paths,
                                 height: Self.coverHeight, title: summary.document.title,
                                 author: summary.document.displayAuthor,
                                 isPDF: summary.document.sourceType == .pdf)
            ZStack {
                Ellipse()
                    .fill(book.backlight)
                    .frame(width: Self.coverHeight * BookCover.ratio * 1.35, height: Self.coverHeight * 0.95)
                    .blur(radius: 44)
                    .opacity(0.7)
                    .offset(y: Self.coverHeight * 0.06)
                    .accessibilityHidden(true)
                book
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).typeRole(.meta).foregroundStyle(Tokens.ink2).frame(width: 84, alignment: .leading)
            Text(value).typeRole(.rowTitle).foregroundStyle(Tokens.ink).textSelection(.enabled)
        }
    }
}
