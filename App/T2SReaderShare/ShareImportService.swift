import Foundation
import Observation
import T2SApp
import T2SCore
import T2SLibrary
import UniformTypeIdentifiers
import UIKit

enum ShareImportError: LocalizedError, Sendable {
    case unavailable(String)
    case tooManyItems
    case failed([String])

    var errorDescription: String? {
        switch self {
        case .unavailable(let type): return "This shared \(type) item couldn't be read."
        case .tooManyItems: return "Share up to eight items at a time."
        case .failed(let messages): return messages.joined(separator: "\n")
        }
    }
}

enum ShareImportStatus: Hashable, Sendable {
    case idle
    case importing
    case completed(Int)
}

/// Converts extension providers into the same phase-one imports the host uses. Provider-owned URLs
/// are copied into the app-group inbox before their callback returns and are never retained.
@MainActor
@Observable
final class ShareImportService {
    private let paths: LibraryPaths
    private let model: ImportModel
    private(set) var status: ShareImportStatus = .idle
    private(set) var errorMessage: String?

    init(paths: LibraryPaths, model: ImportModel) {
        self.paths = paths
        self.model = model
    }

    static func attachmentCount(in items: [NSExtensionItem]) -> Int {
        items.reduce(0) { $0 + ($1.attachments?.count ?? 0) }
    }

    func importItems(_ items: [NSExtensionItem]) async -> Result<[UUID], ShareImportError> {
        let providers = items.flatMap { $0.attachments ?? [] }
        guard providers.count <= 8 else {
            errorMessage = ShareImportError.tooManyItems.localizedDescription
            return .failure(.tooManyItems)
        }
        guard !providers.isEmpty else {
            let error = ShareImportError.failed(["There are no shareable items."])
            errorMessage = error.localizedDescription
            return .failure(error)
        }

        status = .importing
        errorMessage = nil
        var imported: [UUID] = []
        var failures: [String] = []
        for provider in providers {
            do {
                // What the item is, decided from every type it registers and the name it suggests
                // rather than from the order we happen to ask in (`SharedItemKind`). Two senders
                // taught us the order matters. A file shared out of Files conforms to
                // `public.file-url`, which conforms to `public.url` — so asking about `.url` first
                // sent every shared EPUB down the web-link path, where `ImportModel.fetch(link:)`
                // rejected its `file://` scheme with "That doesn't look like a web address."
                // (owner, 2026-09-10). And a book AirDropped from the Mac arrives as its bytes
                // *and* its name as plain text — asking about text early enough imported the name
                // alone, so the library got a book that was only a title (owner, 2026-09-16).
                switch SharedItemKind.of(typeIdentifiers: provider.registeredTypeIdentifiers,
                                         suggestedName: provider.suggestedName) {
                case .book(let type, let identifier):
                    imported += try await importFile(from: provider, sourceType: type, typeIdentifier: identifier)
                case .link:
                    let url = try await loadedURL(from: provider)
                    // A file URL is the file it points at, not a page to fetch.
                    if url.isFileURL {
                        if ["epub", "pdf"].contains(url.pathExtension.lowercased()) {
                            imported += await importedIDs(after: { await self.model.importFiles([url]) })
                        } else {
                            failures.append("This shared file isn't an EPUB or a PDF.")
                        }
                    } else {
                        imported += await importedIDs(after: { await self.model.fetch(link: url) }) {
                            await self.model.confirmPreview()
                        }
                    }
                case .text:
                    let text = try await loadedText(from: provider)
                    // Text that is only a file's name is the sender describing a book it did not
                    // actually hand over; importing it would make that title-only book again.
                    guard !SharedItemKind.isJustAFileName(text) else {
                        failures.append("Only the file's name came through, not the book itself. Share the EPUB from Files, or open it with t2s.")
                        break
                    }
                    imported += await importedIDs(after: {
                        await self.model.importText(title: PlainTextArticle.defaultTitle(for: text), body: text)
                    })
                case .unknown:
                    // The types it did offer, so a failure on the phone says what to fix rather
                    // than only that something went wrong.
                    let offered = provider.registeredTypeIdentifiers.joined(separator: ", ")
                    failures.append("This shared item isn't a link, EPUB, PDF, or text (\(offered)).")
                }
            } catch {
                failures.append(error.localizedDescription)
            }
            retainFailureIfPresent(into: &failures)
            model.reset()
        }

        if !imported.isEmpty {
            status = .completed(imported.count)
            errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
            return .success(imported)
        }
        let error = ShareImportError.failed(failures.isEmpty ? ["Nothing could be imported."] : failures)
        status = .idle
        errorMessage = error.localizedDescription
        return .failure(error)
    }

    private func importFile(from provider: NSItemProvider, sourceType: SourceType,
                            typeIdentifier: String) async throws -> [UUID] {
        let inbox = paths.root.appendingPathComponent("ShareInbox", isDirectory: true)
        // The copy is named for the kind we decided it is, not for the identifier it arrived under:
        // a provider that hands its bytes over as `public.data` still writes `…/<uuid>.epub`, which
        // is what `ImportModel` reads the type from.
        let copy = try await copiedFile(from: provider, typeIdentifier: typeIdentifier,
                                        fileExtension: sourceType == .pdf ? "pdf" : "epub", into: inbox)
        defer { try? FileManager.default.removeItem(at: copy) }
        return await importedIDs(after: { await self.model.importFiles([copy]) })
    }

    private func retainFailureIfPresent(into failures: inout [String]) {
        if case .failed(let message) = model.phase { failures.append(message) }
    }

    private func importedIDs(after operation: @escaping () async -> Void) async -> [UUID] {
        await operation()
        guard case .done(let summaries) = model.phase else { return [] }
        return summaries.map(\.id)
    }

    private func importedIDs(after operation: @escaping () async -> Void,
                             then confirmation: @escaping () async -> Void) async -> [UUID] {
        await operation()
        // A link that is the book itself — an `.epub` or `.pdf` address shared out of Safari —
        // downloads and imports in one move, with no preview to confirm (`ImportModel.fetch`).
        if case .done(let summaries) = model.phase { return summaries.map(\.id) }
        guard case .preview = model.phase else { return [] }
        await confirmation()
        guard case .done(let summaries) = model.phase else { return [] }
        return summaries.map(\.id)
    }

    private func loadedURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                } else {
                    continuation.resume(throwing: error ?? ShareImportError.unavailable(UTType.url.identifier))
                }
            }
        }
    }

    private func loadedText(from provider: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let text = item as? NSString {
                    continuation.resume(returning: text as String)
                } else {
                    continuation.resume(throwing: error ?? ShareImportError.unavailable(UTType.plainText.identifier))
                }
            }
        }
    }

    private func copiedFile(from provider: NSItemProvider, typeIdentifier: String,
                            fileExtension: String, into inbox: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? ShareImportError.unavailable(typeIdentifier))
                    return
                }
                do {
                    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
                    let name = UUID().uuidString
                    let destination = inbox.appendingPathComponent(name)
                        .appendingPathExtension(fileExtension)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
