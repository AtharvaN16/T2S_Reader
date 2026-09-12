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
    ///
    /// `resumingPlayback` carries the listener's place through the reload — the Reader's sheet
    /// changes the voice under a playing document and expects to hear the new one, not silence.
    ///
    /// `force` runs the eviction and reload even when the stored override is already what is being
    /// written. That is not a no-op for one caller: "Make default" moves the *default* and then
    /// clears the document's override, so a document that was already following the default keeps
    /// `voiceID == nil` on both sides of a change that nevertheless swaps the voice it speaks in.
    /// Without this the audio rendered in the old default's voice would survive and keep playing.
    public func apply(
        voiceID: String?,
        to summary: DocumentSummary,
        resumingPlayback: Bool = false,
        force: Bool = false
    ) async -> Bool {
        guard force || summary.document.voiceID != voiceID else {
            lastError = nil
            return true
        }

        let changed = await player.performDestructiveChange(for: summary.id, resumingPlayback: resumingPlayback) {
            try await library.evictAudio(for: summary.id)
            var document = summary.document
            document.voiceID = voiceID
            try await library.store.update(document)
        }
        guard changed else {
            lastError = player.localError
            return false
        }

        lastError = nil
        await libraryModel.refresh()
        return true
    }
}
