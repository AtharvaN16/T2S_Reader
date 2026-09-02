import Foundation
import SwiftData
import T2SCore

extension LibraryStore {
    /// The user's dictionary, sorted by term without regard to case (spec §2.2, §4.1 rule 6).
    public func pronunciations() throws -> [PronunciationEntry] {
        try modelContext.fetch(FetchDescriptor<StoredPronunciation>())
            .map { PronunciationEntry(id: $0.id, term: $0.term, replacement: $0.replacement, caseSensitive: $0.caseSensitive) }
            .sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
    }

    /// Inserts, or replaces the entry with the same id.
    public func upsert(_ entry: PronunciationEntry) throws {
        if let row = try pronunciationRow(entry.id) {
            row.term = entry.term
            row.replacement = entry.replacement
            row.caseSensitive = entry.caseSensitive
            row.updatedAt = Date()
        } else {
            modelContext.insert(StoredPronunciation(id: entry.id, term: entry.term, replacement: entry.replacement,
                                                    caseSensitive: entry.caseSensitive, updatedAt: Date()))
        }
        try modelContext.save()
    }

    public func deletePronunciation(id: UUID) throws {
        guard let row = try pronunciationRow(id) else { return }
        modelContext.delete(row)
        try modelContext.save()
    }

    private func pronunciationRow(_ id: UUID) throws -> StoredPronunciation? {
        var descriptor = FetchDescriptor<StoredPronunciation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
