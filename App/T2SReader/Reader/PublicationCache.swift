import Foundation
import ReadiumAdapterGCDWebServer
import ReadiumShared
import ReadiumStreamer

/// Opens a Readium publication once per document and serves it to the navigator through one
/// shared HTTP server. Readium types stay inside the reader files (spec §3.7.2).
@MainActor
final class PublicationCache {
    let httpServer: GCDHTTPServer
    private var open: [UUID: Publication] = [:]

    init() {
        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        httpServer = GCDHTTPServer(assetRetriever: assetRetriever)
    }

    func publication(for id: UUID, at url: URL) async throws -> Publication {
        if let cached = open[id] { return cached }
        let publication = try await Self.openPublication(at: url)
        open[id] = publication
        return publication
    }

    /// Kept separate from the cache's main-actor state: Readium's parsing APIs are asynchronous
    /// but not actor-isolated. The resulting `Publication` is stored and subsequently used only
    /// by the Reader's main-actor UI.
    nonisolated private static func openPublication(at url: URL) async throws -> Publication {
        guard let fileURL = FileURL(url: url) else { throw ReaderError.cannotOpen("not a file URL") }
        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(parser: DefaultPublicationParser(
            httpClient: httpClient, assetRetriever: assetRetriever, pdfFactory: DefaultPDFDocumentFactory()))
        let asset: Asset
        switch await assetRetriever.retrieve(url: fileURL) {
        case .success(let retrieved):
            asset = retrieved
        case .failure(let error):
            throw ReaderError.cannotOpen("\(error)")
        }
        switch await opener.open(asset: asset, allowUserInteraction: false) {
        case .success(let publication):
            return publication
        case .failure(let error):
            throw ReaderError.cannotOpen("\(error)")
        }
    }

    func release(_ id: UUID) { open[id] = nil }
}
