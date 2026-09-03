import Foundation
import Observation
import T2SApp
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
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    let url = try await loadedURL(from: provider)
                    imported += await importedIDs(after: { await self.model.fetch(link: url) }) {
                        await self.model.confirmPreview()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.epub.identifier) {
                    imported += try await importFile(from: provider, type: .epub)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    imported += try await importFile(from: provider, type: .pdf)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let text = try await loadedText(from: provider)
                    imported += await importedIDs(after: {
                        await self.model.importText(title: PlainTextArticle.defaultTitle(for: text), body: text)
                    })
                } else {
                    failures.append("This shared item isn't a link, EPUB, PDF, or text.")
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

    private func importFile(from provider: NSItemProvider, type: UTType) async throws -> [UUID] {
        let inbox = paths.root.appendingPathComponent("ShareInbox", isDirectory: true)
        let copy = try await copiedFile(from: provider, type: type, into: inbox)
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

    private func copiedFile(from provider: NSItemProvider, type: UTType, into inbox: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? ShareImportError.unavailable(type.identifier))
                    return
                }
                do {
                    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
                    let name = UUID().uuidString
                    let destination = inbox.appendingPathComponent(name)
                        .appendingPathExtension(type.preferredFilenameExtension ?? "bin")
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
