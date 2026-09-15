import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

/// Settings → Storage (spec §2.4.5, §3.4.1): what the app is holding, broken into the four things
/// it holds, and the two ways to give room back — the cache's ceiling, and deleting a book's audio.
///
/// Rewritten 2026-09-14 (owner): the rows are measured in bytes rather than in rendered utterances,
/// because a storage screen's unit is megabytes and "2%" answered no question a reader has; they
/// are sorted by size, because the screen exists to find what is big; and a document holding
/// nothing is left out rather than listed with a dead control beside it. Prepare moved to its own
/// page (`PrepareSettings`), so nothing here is about *making* audio any more.
@MainActor
@Observable
public final class StorageModel {
    /// One document's rendered audio: what it occupies, and enough to name it.
    public struct Row: Hashable, Sendable, Identifiable {
        public var summary: DocumentSummary
        /// What deleting this document's audio would free, as the store counts it.
        public var bytes: Int
        public var id: UUID { summary.id }

        public init(summary: DocumentSummary, bytes: Int) {
            self.summary = summary
            self.bytes = bytes
        }
    }

    public static let lastPrepareRunKey = "prepare.lastRun"
    public static let capacityOptions: [Int] = [
        512 * 1024 * 1024,
        1024 * 1024 * 1024,
        2 * 1024 * 1024 * 1024,
        4 * 1024 * 1024 * 1024,
    ]

    /// The chips say "512 MB", not "536.9 MB". `ByteCountFormatter` is faithfully rendering powers
    /// of two, and those three extra glyphs per chip were most of why the row could not fit inside
    /// the page's margins. The number the reader picked is still exactly the number that is set.
    public static func capacityLabel(_ bytes: Int) -> String {
        let mb = bytes / (1024 * 1024)
        return mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB"
    }

    public private(set) var stats = AudioStoreStats(bytes: 0, entries: 0, capacityBytes: 0)
    /// Documents holding audio, largest first. A document holding none is not here at all.
    public private(set) var rows: [Row] = []
    /// How many documents the library holds that are *not* in `rows` — the one line under the list
    /// that stops a reader wondering where the rest of their books went.
    public private(set) var documentsWithoutAudio = 0
    /// Room left on the device, as iOS reports it for content worth keeping.
    public private(set) var freeBytes: Int64 = 0
    /// The imported files, covers, retained chapters and the library database — everything the app
    /// holds that is *not* cache and not the voice. Small, and the only band on the picture that
    /// nothing on this screen offers to delete: a book leaves from the book, not from here.
    public private(set) var documentsBytes: Int = 0
    public private(set) var preparedSeconds: TimeInterval = 0
    public private(set) var lastPrepareRun: Date?
    public private(set) var lastError: String?
    /// True while `deleteAll` runs, so its one key cannot be pressed twice.
    public private(set) var isDeletingAll = false

    private let library: Library
    private let paths: LibraryPaths
    private let audioStore: any AudioStore
    private let player: PlayerModel
    private let libraryModel: LibraryModel
    private let defaults: UserDefaults

    public init(
        library: Library,
        paths: LibraryPaths,
        audioStore: any AudioStore,
        player: PlayerModel,
        libraryModel: LibraryModel,
        defaults: UserDefaults = .standard
    ) {
        self.library = library
        self.paths = paths
        self.audioStore = audioStore
        self.player = player
        self.libraryModel = libraryModel
        self.defaults = defaults
    }

    public func refresh() async {
        stats = await audioStore.stats()
        freeBytes = Self.deviceFreeBytes()
        documentsBytes = Self.directoryBytes(paths.documentsDirectory) + Self.fileBytes(paths.databaseURL)
        await libraryModel.refresh()

        var measured: [Row] = []
        var empty = 0
        for summary in libraryModel.summaries {
            // A stale document's render keys no longer match anything the store holds, so it has
            // nothing this screen can offer to delete; it counts as empty rather than as missing.
            guard let timeline = try? await library.currentTimeline(summary.id) else {
                empty += 1
                continue
            }
            let bytes = await BookAudioStatus.read(timeline: timeline, audioStore: audioStore).bytes
            if bytes > 0 { measured.append(Row(summary: summary, bytes: bytes)) } else { empty += 1 }
        }
        // Largest first, then by title so two books of the same size do not swap places between
        // refreshes for no reason the reader can see.
        rows = measured.sorted {
            $0.bytes == $1.bytes ? $0.summary.document.title < $1.summary.document.title : $0.bytes > $1.bytes
        }
        documentsWithoutAudio = empty

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

    /// Records a successful Prepare pass and updates the visible state without waiting for a full
    /// storage refresh. The runner uses this same persistence key for background launches.
    public func recordPrepareRun(_ date: Date) {
        defaults.set(date, forKey: Self.lastPrepareRunKey)
        lastPrepareRun = date
    }

    /// A loaded document is reloaded paused after eviction by `PlayerModel`, so it can never write
    /// stale audio references back to the store.
    public func evict(_ id: UUID) async {
        if await player.performDestructiveChange(for: id, {
            try await self.library.evictAudio(for: id)
        }) {
            lastError = nil
            await refresh()
        } else {
            lastError = player.localError
        }
    }

    /// The sweep the screen never had (owner, 2026-09-14): every book's audio at once, for the
    /// reader who came here because the phone is full and does not want to press a trash four times.
    ///
    /// The whole sweep runs inside the loaded document's guard rather than one guard per book — one
    /// pause and one reload for the lot, instead of the player being torn down and rebuilt once per
    /// title while it works.
    public func deleteAll() async {
        let ids = rows.map(\.id)
        guard !ids.isEmpty, !isDeletingAll else { return }
        isDeletingAll = true
        defer { isDeletingAll = false }

        let library = self.library
        let evictEverything: @MainActor () async throws -> Void = {
            for id in ids { try await library.evictAudio(for: id) }
        }

        if let loaded = player.current?.id, ids.contains(loaded) {
            if await player.performDestructiveChange(for: loaded, evictEverything) {
                lastError = nil
            } else {
                lastError = player.localError
            }
        } else {
            do {
                try await evictEverything()
                lastError = nil
            } catch {
                lastError = "\(error)"
            }
        }
        await refresh()
    }

    /// Every file under `directory`, added up. A few dozen `stat`s for a normal library, run when
    /// the page appears — not on any actor's critical path.
    private static func directoryBytes(_ directory: URL) -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total = 0
        for case let url as URL in walk {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            total += values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
        }
        return total
    }

    private static func fileBytes(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
    }

    /// What iOS will actually let the app keep, which is the number a reader recognises from
    /// Settings → General → iPhone Storage — not the raw free blocks, which include space the
    /// system is holding back and would overstate the room by gigabytes.
    private static func deviceFreeBytes() -> Int64 {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
