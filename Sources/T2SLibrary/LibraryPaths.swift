import Foundation
import T2SCore

/// Where things live in the app container (spec §5). Rows store paths relative to `root`, so the
/// container can move (new device, restored backup) without rewriting them.
///
/// ```
/// <root>/Library.store                    SwiftData
/// <root>/Audio/<codec>/<renderKey>.audio  FileAudioStore (cache)
/// <root>/Documents/<uuid>/source.epub|pdf original.html cover.jpg
/// ```
public struct LibraryPaths: Hashable, Sendable {
    public var root: URL

    public init(root: URL) { self.root = root.standardizedFileURL }

    public var databaseURL: URL { root.appendingPathComponent("Library.store") }
    public var audioDirectory: URL { root.appendingPathComponent("Audio", isDirectory: true) }
    public var documentsDirectory: URL { root.appendingPathComponent("Documents", isDirectory: true) }

    public func documentDirectory(_ id: UUID) -> URL {
        documentsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// The imported source. Articles are stored as their generated EPUB (spec §2.1).
    public func sourceURL(_ id: UUID, type: SourceType) -> URL {
        documentDirectory(id).appendingPathComponent(type == .pdf ? "source.pdf" : "source.epub")
    }

    /// The originally fetched article HTML, retained for reprocessing (spec §2.1).
    public func originalHTMLURL(_ id: UUID) -> URL { documentDirectory(id).appendingPathComponent("original.html") }

    public func coverURL(_ id: UUID) -> URL { documentDirectory(id).appendingPathComponent("cover.jpg") }

    /// The `Document.coverImagePath` form of a URL under `root`; nil for anything else.
    public func relativePath(of url: URL) -> String? {
        let base = root.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base), path.count > base.count else { return nil }
        return String(path.dropFirst(base.count))
    }

    public func url(forRelativePath path: String) -> URL { root.appendingPathComponent(path) }
}
