import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

/// Preferences → Storage (spec §2.4.5, §3.4.1): cache size and cap, per-document eviction, the
/// prepared amount across the Queue, and when Prepare last ran.
@MainActor
@Observable
public final class StorageModel {
    public struct Row: Hashable, Sendable, Identifiable {
        public var summary: DocumentSummary
        public var renderedFraction: Double
        public var id: UUID { summary.id }

        public init(summary: DocumentSummary, renderedFraction: Double) {
            self.summary = summary
            self.renderedFraction = renderedFraction
        }
    }

    public static let lastPrepareRunKey = "prepare.lastRun"
    public static let capacityOptions: [Int] = [
        512 * 1024 * 1024,
        1024 * 1024 * 1024,
        2 * 1024 * 1024 * 1024,
        4 * 1024 * 1024 * 1024,
    ]

    public private(set) var stats = AudioStoreStats(bytes: 0, entries: 0, capacityBytes: 0)
    public private(set) var rows: [Row] = []
    public private(set) var preparedSeconds: TimeInterval = 0
    public private(set) var lastPrepareRun: Date?
    public private(set) var lastError: String?

    private let library: Library
    private let audioStore: any AudioStore
    private let player: PlayerModel
    private let libraryModel: LibraryModel
    private let defaults: UserDefaults

    public init(
        library: Library,
        audioStore: any AudioStore,
        player: PlayerModel,
        libraryModel: LibraryModel,
        defaults: UserDefaults = .standard
    ) {
        self.library = library
        self.audioStore = audioStore
        self.player = player
        self.libraryModel = libraryModel
        self.defaults = defaults
    }

    public func refresh() async {
        stats = await audioStore.stats()
        await libraryModel.refresh()
        rows = libraryModel.summaries.map { summary in
            Row(
                summary: summary,
                renderedFraction: summary.utteranceCount > 0
                    ? Double(summary.renderedCount) / Double(summary.utteranceCount)
                    : 0
            )
        }
        preparedSeconds = libraryModel.queue.reduce(0) { preparedSeconds, summary in
            preparedSeconds + (summary.utteranceCount > 0
                ? summary.totalSeconds * Double(summary.renderedCount) / Double(summary.utteranceCount)
                : 0)
        }
        lastPrepareRun = defaults.object(forKey: Self.lastPrepareRunKey) as? Date
    }

    public func setCapacity(_ bytes: Int) async {
        defaults.set(bytes, forKey: AppPaths.audioCapacityKey)
        await audioStore.setCapacity(bytes: bytes)
        await refresh()
    }

    /// Plan 3 hand-off: after an eviction, a loaded document is reloaded paused so the player
    /// never writes stale audio references back to the store.
    public func evict(_ id: UUID) async {
        let wasCurrent = player.current?.id == id
        if wasCurrent { await player.persistRenderedChapters() }

        do {
            try await library.evictAudio(for: id)
            lastError = nil
        } catch {
            lastError = "\(error)"
            return
        }

        if wasCurrent, let summary = try? await library.store.summary(id: id) {
            await player.load(summary, play: false)
        }
        await refresh()
    }
}
