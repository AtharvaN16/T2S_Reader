import Foundation
import Observation
import T2SCore
import T2SStore

/// The pronunciation dictionary (spec §2.2, §4.1 rule 6). Edits apply to documents imported or
/// reprocessed from now on; the Details sheet offers "Reprocess" for existing ones.
@MainActor
@Observable
public final class PronunciationModel {
    public private(set) var entries: [PronunciationEntry] = []
    public private(set) var lastError: String?
    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func refresh() async {
        do {
            entries = try await store.pronunciations()
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    /// Blank terms and replacements are ignored; `id` nil adds, otherwise replaces.
    public func save(term: String, replacement: String, caseSensitive: Bool, id: UUID?) async {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty, !trimmedReplacement.isEmpty else { return }

        do {
            try await store.upsert(PronunciationEntry(
                id: id ?? UUID(),
                term: trimmedTerm,
                replacement: trimmedReplacement,
                caseSensitive: caseSensitive
            ))
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
        await refresh()
    }

    public func delete(id: UUID) async {
        do {
            try await store.deletePronunciation(id: id)
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
        await refresh()
    }
}
