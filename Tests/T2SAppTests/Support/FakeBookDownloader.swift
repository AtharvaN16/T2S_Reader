import Foundation
@testable import T2SApp

/// Stands in for `URLSessionBookDownloader`: writes the bytes it was given into the same kind of
/// scratch folder the real one uses, and remembers the file so a test can check it was cleaned up.
struct FakeBookDownloader: BookDownloading {
    final class Delivered: @unchecked Sendable {
        var url: URL?
    }

    var name = "book.epub"
    var data = Data("PK".utf8)
    var error: BookDownloadError?
    var delivered = Delivered()

    func downloadBook(from url: URL) async throws -> URL {
        if let error { throw error }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("t2s-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        try data.write(to: file)
        delivered.url = file
        return file
    }
}
