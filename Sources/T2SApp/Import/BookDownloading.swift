import Foundation

/// What went wrong on the way to a book file, as the Add sheet needs to say it.
public enum BookDownloadError: Error, Equatable, Sendable {
    case network(String)
    case server(Int)
    /// The link answered, but with something that is not a book: an HTML page, JSON, a login wall.
    case notABook(String)
}

/// Fetches a link that *is* a book rather than a page about one (spec §2.4.5). The app implements
/// this with `URLSession`; tests use a fake.
///
/// This is the way in for a book the owner found on the web (owner, 2026-09-16): on iOS a
/// downloaded EPUB is handed straight to Apple Books and never lands in Files, so the Add sheet's
/// picker — a Files browser — cannot see it, and the only way back out is Books' own Share sheet.
/// Pasting the link (or sharing it out of Safari) skips that round trip entirely.
public protocol BookDownloading: Sendable {
    /// Downloads `url` into a temporary file named with the extension of whatever came back —
    /// `epub` or `pdf`. The caller owns that file and deletes it once it has been imported.
    func downloadBook(from url: URL) async throws -> URL
}

public struct URLSessionBookDownloader: BookDownloading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func downloadBook(from url: URL) async throws -> URL {
        let temporary: URL, response: URLResponse
        do {
            (temporary, response) = try await session.download(from: url)
        } catch {
            throw BookDownloadError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: temporary)
            throw BookDownloadError.server(http.statusCode)
        }
        guard let kind = Self.bookExtension(mimeType: response.mimeType, url: url,
                                            suggestedFilename: response.suggestedFilename) else {
            try? FileManager.default.removeItem(at: temporary)
            throw BookDownloadError.notABook(response.mimeType ?? "unknown")
        }
        // `URLSession` deletes its own temporary file as soon as this call returns, so the move
        // happens here rather than in the caller.
        let name = Self.filename(from: response.suggestedFilename ?? url.lastPathComponent, kind: kind)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("t2s-download-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw BookDownloadError.network(error.localizedDescription)
        }
        return destination
    }

    /// What the answer actually is: the content type first, since a server that names its type is
    /// telling the truth more often than a URL is; then the filename the server suggested, then the
    /// link's own path. A type we recognise as *not* a book (an HTML login wall behind a `.epub`
    /// address, say) stops there rather than falling through to the address and importing a page.
    static func bookExtension(mimeType: String?, url: URL, suggestedFilename: String?) -> String? {
        let mime = mimeType?.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        switch mime {
        case "application/epub+zip", "application/epub", "application/x-epub": return "epub"
        case "application/pdf", "application/x-pdf": return "pdf"
        case "text/html", "application/xhtml+xml", "application/json", "text/plain": return nil
        default: break
        }
        for candidate in [suggestedFilename.map { URL(fileURLWithPath: $0).pathExtension }, url.pathExtension] {
            switch candidate?.lowercased() {
            case "epub": return "epub"
            case "pdf": return "pdf"
            default: continue
            }
        }
        return nil
    }

    /// The server's name for the book where there is one, so the import row and any title fallback
    /// read as the book rather than as a UUID; `book.epub` when there is nothing usable.
    static func filename(from suggested: String, kind: String) -> String {
        // An empty name must not reach `URL(fileURLWithPath:)`, which answers it with the process's
        // working directory — the app's container on the phone, the checkout in a test.
        let trimmed = suggested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "book.\(kind)" }
        let base = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty || base == "." || base == ".." ? "book.\(kind)" : "\(base).\(kind)"
    }
}
