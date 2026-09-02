import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

public struct FileRow: Identifiable, Hashable, Sendable {
    public var id: URL
    public var name: String
    public var state: FileState
}

public enum FileState: Hashable, Sendable {
    case pending, importing
    case done(DocumentSummary)
    case failed(String)
}

public enum ImportPhase: Hashable, Sendable {
    case idle
    case fetching(URL)
    case preview(ExtractedArticle)
    case importing
    case done([DocumentSummary])
    case failed(String)
}

/// The Add sheet's state (spec §2.4.5 rev 7). Every path ends in `.done` with the imported
/// documents, already queued by `Library`, or `.failed` with a sentence for the sheet to show inline.
@MainActor
@Observable
public final class ImportModel {
    /// Below this many words the preview says the extraction looks thin (spec §6).
    public static let thinArticleWordCount = 120

    public private(set) var phase: ImportPhase = .idle
    public private(set) var fileRows: [FileRow] = []

    private let library: Library
    private let extractor: any ArticleExtracting

    public init(library: Library, extractor: any ArticleExtracting) {
        self.library = library
        self.extractor = extractor
    }

    public var isThinPreview: Bool {
        if case .preview(let article) = phase { return article.wordCount < Self.thinArticleWordCount }
        return false
    }

    public func reset() {
        phase = .idle
        fileRows = []
    }

    // MARK: Paste a link

    public func fetch(link: URL) async {
        guard let scheme = link.scheme?.lowercased(), scheme == "http" || scheme == "https", link.host() != nil else {
            phase = .failed("That doesn't look like a web address.")
            return
        }
        phase = .fetching(link)
        do {
            phase = .preview(try await extractor.extract(from: link))
        } catch let error as ExtractionError {
            phase = .failed(Self.message(for: error))
        } catch {
            phase = .failed("Couldn't load the page: \(error.localizedDescription)")
        }
    }

    public func confirmPreview() async {
        guard case .preview(let article) = phase else { return }
        phase = .importing
        await finish { try await self.library.importArticle(article.content, originalHTML: article.originalHTML) }
    }

    // MARK: Paste text

    public func importText(title: String, body: String) async {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .failed("There's no text to read.")
            return
        }
        phase = .importing
        let content = PlainTextArticle.content(title: title, body: body)
        await finish { try await self.library.importArticle(content, originalHTML: "") }
    }

    // MARK: Open a file

    /// Imports each file in turn with a row per file; `phase` ends `.done` with every success, or
    /// `.failed` when none succeeded.
    public func importFiles(_ urls: [URL]) async {
        fileRows = urls.map { FileRow(id: $0, name: $0.lastPathComponent, state: .pending) }
        phase = .importing
        var imported: [DocumentSummary] = []
        for (i, url) in urls.enumerated() {
            fileRows[i].state = .importing
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                guard let type = Self.sourceType(for: url) else {
                    throw ImportError.unsupportedFormat(url.pathExtension.lowercased())
                }
                let result = try await library.importFile(at: url, sourceType: type)
                let summary = try await library.store.summary(id: result.document.id)
                guard let summary else { throw ImportError.unreadable("imported document vanished") }
                fileRows[i].state = .done(summary)
                imported.append(summary)
            } catch {
                fileRows[i].state = .failed(Self.message(for: error))
            }
        }
        phase = imported.isEmpty ? .failed("Nothing could be imported.") : .done(imported)
    }

    // MARK: Internals

    private func finish(_ body: @escaping @Sendable () async throws -> ImportResult) async {
        do {
            let result = try await body()
            guard let summary = try await library.store.summary(id: result.document.id) else {
                phase = .failed("The document was imported but could not be found.")
                return
            }
            phase = .done([summary])
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    static func sourceType(for url: URL) -> SourceType? {
        switch url.pathExtension.lowercased() {
        case "epub": return .epub
        case "pdf": return .pdf
        default: return nil
        }
    }

    /// One plain sentence per error (spec §6: never silent, never a system alert).
    static func message(for error: any Error) -> String {
        switch error {
        case ImportError.drmProtected: return "This file is copy-protected and can't be read."
        case ImportError.unsupportedFormat(let kind): return "This kind of file isn't supported (\(kind))."
        case ImportError.unreadable(let detail): return "This file couldn't be read. \(detail)"
        case ImportError.noText: return "There's no text to read."
        case ImportError.malformedBody: return "The article text couldn't be converted."
        case ExtractionError.invalidURL: return "That doesn't look like a web address."
        case ExtractionError.network(let detail): return "Couldn't load the page: \(detail)"
        case ExtractionError.noArticle: return "No article was found on that page."
        case ExtractionError.timedOut: return "The page took too long to load."
        default: return "Something went wrong: \(error.localizedDescription)"
        }
    }
}
