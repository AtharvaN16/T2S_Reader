import Foundation
import ReadiumShared
import ReadiumStreamer
import T2SCore
import T2SLibrary
import UIKit

/// EPUBs (and article EPUBs) through the Readium streamer's content iterator. Readium types stay in
/// this file; the output is a `ReadDocument` whose `Position`s follow the EPUB rule in the plan's
/// Global Constraints (spec §3.7.2: convert at the boundary, never persist a `Locator`).
public struct ReadiumDocumentReader: DocumentReader {
    public let supportedTypes: Set<SourceType> = [.epub, .article]

    public init() {}

    public func read(fileURL: URL, sourceType: SourceType) async throws -> ReadDocument {
        let publication = try await open(fileURL)
        if publication.isRestricted { throw ImportError.drmProtected }          // spec §6: reject DRM plainly

        // Blocks grouped by resource, in reading order. `charOffset` counts trimmed block texts joined by "\n".
        guard let content = publication.content() else { throw ImportError.noText }
        var blocksByHref: [String: [SourceBlock]] = [:]
        var hrefOrder: [String] = []
        var offsets: [String: Int] = [:]
        for await element in content.sequence() {
            guard let textElement = element as? TextContentElement,
                  let text = textElement.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
            else { continue }
            let locator = textElement.locator
            let rawHref = locator.href.string
            let href = Self.resourceKey(rawHref)
            if blocksByHref[href] == nil { hrefOrder.append(href) }
            let offset = offsets[href, default: 0]
            var cssSelector: String?
            if case .string(let selector)? = locator.locations.otherLocations["cssSelector"] { cssSelector = selector }
            blocksByHref[href, default: []].append(SourceBlock(
                text: text,
                position: Position(resourceHref: rawHref, progression: locator.locations.progression ?? 0,
                                   charOffset: offset, cssSelector: cssSelector)))
            offsets[href] = offset + text.utf16.count + 1
        }
        guard !hrefOrder.isEmpty else { throw ImportError.noText }

        // Keyed by `resourceKey` (fragment-stripped, normalized) so a locator href and a reading-order
        // href that Readium reports with different percent-encoding still identify the same resource.
        let readingOrder = publication.readingOrder.map { Self.resourceKey($0.url().string) }
        func resourceIndex(_ key: String) -> Int? {
            readingOrder.firstIndex(of: key)
        }

        // Table of contents → (title, resource index), first title per resource, ordered by resource.
        let toc = (try? await publication.tableOfContents().get()) ?? []
        var entries: [(title: String, resource: Int)] = []
        func walk(_ links: [Link]) {
            for link in links {
                if let r = resourceIndex(Self.resourceKey(link.url().string)), !entries.contains(where: { $0.resource == r }) {
                    let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    entries.append((title.isEmpty ? "Section \(entries.count + 1)" : title, r))
                }
                walk(link.children)
            }
        }
        walk(toc)
        entries.sort { $0.resource < $1.resource }

        var chapters: [ChapterInput] = []
        if entries.isEmpty {
            // No usable TOC: one chapter per resource with text, titled by the link or "Section n".
            for href in hrefOrder {
                let blocks = blocksByHref[href] ?? []
                let link = publication.readingOrder.first { Self.resourceKey($0.url().string) == href }
                let title = link?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                chapters.append(ChapterInput(title: title.isEmpty ? "Section \(chapters.count + 1)" : title,
                                             position: blocks[0].position, blocks: blocks))
            }
        } else {
            // Each TOC entry owns its resource and every following resource up to the next entry;
            // resources before the first entry are front matter.
            var groups = Array(repeating: [SourceBlock](), count: entries.count + 1)
            for href in hrefOrder {
                let r = resourceIndex(href) ?? Int.max
                let owner = entries.lastIndex(where: { $0.resource <= r }).map { $0 + 1 } ?? 0
                groups[owner].append(contentsOf: blocksByHref[href] ?? [])
            }
            if !groups[0].isEmpty {
                chapters.append(ChapterInput(title: "Front matter", position: groups[0][0].position, blocks: groups[0]))
            }
            for (i, entry) in entries.enumerated() where !groups[i + 1].isEmpty {
                chapters.append(ChapterInput(title: entry.title, position: groups[i + 1][0].position, blocks: groups[i + 1]))
            }
        }

        let title = publication.metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let authors = publication.metadata.authors.map(\.name).filter { !$0.isEmpty }
        let cover = (try? await publication.cover().get())?.flatMap { $0.jpegData(compressionQuality: 0.8) }
        let skipped = readingOrder.filter { blocksByHref[$0] == nil }
        return ReadDocument(
            title: (title?.isEmpty == false ? title : nil) ?? fileURL.deletingPathExtension().lastPathComponent,
            author: authors.isEmpty ? nil : authors.joined(separator: ", "),
            coverImage: cover,
            chapters: chapters,
            skippedResources: skipped)
    }

    private func open(_ fileURL: URL) async throws -> Publication {
        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(parser: DefaultPublicationParser(
            httpClient: httpClient, assetRetriever: assetRetriever, pdfFactory: DefaultPDFDocumentFactory()))
        guard let url = FileURL(url: fileURL) else { throw ImportError.unreadable("not a file URL: \(fileURL)") }
        let asset: Asset
        switch await assetRetriever.retrieve(url: url) {
        case .success(let a): asset = a
        case .failure(let error): throw ImportError.unreadable("\(error)")
        }
        switch await opener.open(asset: asset, allowUserInteraction: false) {
        case .success(let publication): return publication
        case .failure(.formatNotSupported): throw ImportError.unsupportedFormat(fileURL.pathExtension)
        case .failure(.reading(let error)): throw ImportError.unreadable("\(error)")
        }
    }

    /// Identifies a resource for comparison across `locator.href.string` and `link.url().string`,
    /// which Readium can report with different percent-encoding: strip any `#fragment`, then run
    /// through `AnyURL`'s normalization. `Position.resourceHref` stays the raw `locator.href.string`
    /// (spec §3.7.2: persisted positions are exactly what Readium reports) — this key is only ever
    /// used to test resource identity, never persisted.
    static func resourceKey(_ href: String) -> String {
        let stripped = withoutFragment(href)
        return AnyURL(string: stripped)?.normalized.string ?? stripped
    }

    private static func withoutFragment(_ href: String) -> String {
        href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
    }
}
