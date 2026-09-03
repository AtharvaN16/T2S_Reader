import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

/// Per-document voice override (spec §2.2) with the spec §5 consequence: the document's rendered
/// audio is discarded because every render key embeds the voice.
@MainActor
@Observable
public final class VoiceChangeModel {
    public private(set) var lastError: String?

    private let library: Library
    private let player: PlayerModel
    private let libraryModel: LibraryModel

    public init(library: Library, player: PlayerModel, libraryModel: LibraryModel) {
        self.library = library
        self.player = player
        self.libraryModel = libraryModel
    }

    /// Rendered seconds that a voice change throws away (proportional to rendered utterances).
    public func discardedSeconds(for summary: DocumentSummary) -> TimeInterval {
        guard summary.utteranceCount > 0 else { return 0 }
        return summary.totalSeconds * Double(summary.renderedCount) / Double(summary.utteranceCount)
    }

    /// Evicts the audio, persists the override (nil = back to the default voice), reloads the
    /// document if it is the one playing. True on success.
    public func apply(voiceID: String?, to summary: DocumentSummary) async -> Bool {
        let wasCurrent = player.current?.id == summary.id
        if wasCurrent { await player.persistRenderedChapters() }

        do {
            try await library.evictAudio(for: summary.id)
            var document = summary.document
            document.voiceID = voiceID
            try await library.store.update(document)
            lastError = nil
        } catch {
            lastError = "\(error)"
            return false
        }

        if wasCurrent, let fresh = try? await library.store.summary(id: summary.id) {
            await player.load(fresh, play: false)
        }
        await libraryModel.refresh()
        return true
    }
}
