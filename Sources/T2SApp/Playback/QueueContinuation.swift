import Foundation
import Observation

/// "Autoplay next" (spec §2.4.5 Playback): when the loaded document finishes, load and play the
/// next queued document after it. Call from the ticker or on a state change.
@MainActor
@Observable
public final class QueueContinuation {
    private let player: PlayerModel
    private let library: LibraryModel
    private let preferences: ReaderPreferences

    public init(player: PlayerModel, library: LibraryModel, preferences: ReaderPreferences) {
        self.player = player
        self.library = library
        self.preferences = preferences
    }

    /// True when it advanced.
    public func advanceIfFinished() async -> Bool {
        guard preferences.autoplayNext,
              player.state == .finished,
              let current = player.current else {
            return false
        }
        await library.refresh()
        let queue = library.queue
        guard let index = queue.firstIndex(where: { $0.id == current.id }), index + 1 < queue.count else {
            return false
        }
        await player.load(queue[index + 1], play: true)
        return player.current?.id == queue[index + 1].id
    }
}
