// App/T2SReader/AppEnvironment.swift
import Foundation
import Observation
import T2SApp
import T2SAudio
import T2SCore
import T2SLibrary
import T2SReadium
import T2SStore

/// Builds the object graph once (spec §3): store → library → coordinator → models. Rendered audio
/// is cache, so its directory is excluded from backup (spec §3.7.3).
@MainActor
@Observable
final class AppEnvironment {
    let paths: LibraryPaths
    let store: LibraryStore
    let audioStore: FileAudioStore
    let library: Library
    let coordinator: PlaybackCoordinator
    /// The one inference lease shared by the live player and Prepare.
    let renderArbiter: RenderArbiter
    let libraryModel: LibraryModel
    let player: PlayerModel
    let importModel: ImportModel
    let publications = PublicationCache()
    let preferences: ReaderPreferences
    let voices: any VoiceCatalog
    let pronunciation: PronunciationModel
    let storage: StorageModel
    let prepareRunner: PrepareRunner
    let voiceChange: VoiceChangeModel
    let readerModel: ReaderModel
    let sleepTimer: SleepTimer
    let continuation: QueueContinuation
    let audioSession = AudioSessionController()
    let nowPlaying: NowPlayingController
    let deviceMonitor: DeviceMonitor

    init(paths: LibraryPaths, store: LibraryStore, audioStore: FileAudioStore, library: Library,
         coordinator: PlaybackCoordinator, engine: any SynthesisEngine, renderArbiter: RenderArbiter) {
        self.paths = paths
        self.store = store
        self.audioStore = audioStore
        self.library = library
        self.coordinator = coordinator
        self.renderArbiter = renderArbiter
        libraryModel = LibraryModel(library: library)
        player = PlayerModel(coordinator: coordinator, library: library)
        preferences = ReaderPreferences()
        voices = SystemVoiceCatalog()
        pronunciation = PronunciationModel(store: store)
        storage = StorageModel(library: library, audioStore: audioStore, player: player, libraryModel: libraryModel)
        prepareRunner = PrepareRunner(library: library, store: store, audioStore: audioStore,
                                      engine: engine, arbiter: renderArbiter)
        voiceChange = VoiceChangeModel(library: library, player: player, libraryModel: libraryModel)
        readerModel = ReaderModel(player: player)
        sleepTimer = SleepTimer(player: player)
        continuation = QueueContinuation(player: player, library: libraryModel, preferences: preferences)
        nowPlaying = NowPlayingController(player: player, libraryModel: libraryModel, preferences: preferences, paths: paths)
        player.defaultVoiceID = preferences.defaultVoiceID
        prepareRunner.defaultVoiceID = preferences.defaultVoiceID
        coordinator.setRate(preferences.defaultRate)
        importModel = ImportModel(library: library, extractor: ArticleExtractor())
        deviceMonitor = DeviceMonitor(audioStore: audioStore)
    }

    static func live() throws -> AppEnvironment {
        let paths = LibraryPaths(root: try AppPaths.defaultContainerRoot())
        try FileManager.default.createDirectory(at: paths.audioDirectory, withIntermediateDirectories: true)
        var audioDirectory = paths.audioDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try audioDirectory.setResourceValues(values)

        let store = try LibraryStore.onDisk(at: paths.databaseURL)
        let capacity = UserDefaults.standard.object(forKey: AppPaths.audioCapacityKey) as? Int ?? AppPaths.defaultAudioCapacityBytes
        let audioStore = FileAudioStore(directory: paths.audioDirectory, codec: AACCodec(), capacityBytes: capacity)
        let library = Library(paths: paths, store: store, audioStore: audioStore,
                              readers: [PDFDocumentReader(), ReadiumDocumentReader()])
        let storedBudget = UserDefaults.standard.object(forKey: AppPaths.prepareBudgetKey) as? Double ?? 3 * 3600
        let prepareBudget = storedBudget.isFinite ? storedBudget : 365 * 24 * 3600
        let engine = SystemSpeechEngine()
        let renderArbiter = RenderArbiter()
        let coordinator = PlaybackCoordinator(engine: engine, store: audioStore, player: try AudioPlayer(),
                                              playheadStore: store, timeSource: SystemTimeSource(),
                                              configuration: CoordinatorConfiguration(prepareBudgetSeconds: prepareBudget),
                                              arbiter: renderArbiter)
        return AppEnvironment(paths: paths, store: store, audioStore: audioStore, library: library,
                              coordinator: coordinator, engine: engine, renderArbiter: renderArbiter)
    }
}
