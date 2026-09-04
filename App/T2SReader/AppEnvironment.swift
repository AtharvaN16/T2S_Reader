// App/T2SReader/AppEnvironment.swift
import Foundation
import Observation
import T2SApp
import T2SAudio
import T2SCore
import T2SLibrary
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
    let cloudVoiceSettings: CloudVoiceSettings
    let cloudVoiceSecrets: any SecretStoring
    let cloudRouter: RoutedEngine
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
    /// What Preferences tells the reader about the on-device engine on this device.
    let kokoroStatus: KokoroStatusModel

    init(paths: LibraryPaths, store: LibraryStore, audioStore: FileAudioStore, library: Library,
         importModel: ImportModel, coordinator: PlaybackCoordinator, engine: any SynthesisEngine,
         renderArbiter: RenderArbiter, cloudVoiceSettings: CloudVoiceSettings,
         cloudVoiceSecrets: any SecretStoring, cloudRouter: RoutedEngine,
         kokoro: KokoroComposition) {
        self.paths = paths
        self.store = store
        self.audioStore = audioStore
        self.library = library
        self.coordinator = coordinator
        self.renderArbiter = renderArbiter
        libraryModel = LibraryModel(library: library)
        player = PlayerModel(coordinator: coordinator, library: library)
        preferences = ReaderPreferences()
        self.cloudVoiceSettings = cloudVoiceSettings
        self.cloudVoiceSecrets = cloudVoiceSecrets
        self.cloudRouter = cloudRouter
        voices = kokoro.catalog(wrapping: CloudVoiceCatalog(base: SystemVoiceCatalog(),
                                                            configurationStore: cloudVoiceSettings.configurationStore))
        kokoroStatus = kokoro.status
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
        // One resolver for both: a document's voice is decided the same way whether it is played
        // now or prepared in the background (spec §6).
        player.voiceRouting = kokoro.voiceRouting
        prepareRunner.voiceRouting = kokoro.voiceRouting
        coordinator.setRate(preferences.defaultRate)
        self.importModel = importModel
        deviceMonitor = DeviceMonitor(audioStore: audioStore)
    }

    static func live() throws -> AppEnvironment {
        let capacity = UserDefaults.standard.object(forKey: AppPaths.audioCapacityKey) as? Int ?? AppPaths.defaultAudioCapacityBytes
        let shared = try SharedLibraryFactory.make(capacityBytes: capacity)
        let storedBudget = UserDefaults.standard.object(forKey: AppPaths.prepareBudgetKey) as? Double ?? 3 * 3600
        let prepareBudget = storedBudget.isFinite ? storedBudget : 365 * 24 * 3600
        let cloudVoiceSettings = CloudVoiceSettings()
        let cloudVoiceSecrets = KeychainSecretStore()
        let configurationStore = cloudVoiceSettings.configurationStore
        let systemEngine = SystemSpeechEngine()
        let kokoro = KokoroComposition.make()
        let cloudRouter = RoutedEngine(
            system: systemEngine,
            configuration: { configurationStore.current() },
            key: { try cloudVoiceSecrets.load() },
            kokoro: kokoro.engine
        )
        let renderArbiter = RenderArbiter()
        let coordinator = PlaybackCoordinator(engine: cloudRouter, store: shared.audioStore, player: try AudioPlayer(),
                                              playheadStore: shared.store, timeSource: SystemTimeSource(),
                                              configuration: CoordinatorConfiguration(prepareBudgetSeconds: prepareBudget),
                                              arbiter: renderArbiter)
        return AppEnvironment(paths: shared.paths, store: shared.store, audioStore: shared.audioStore,
                              library: shared.library, importModel: shared.importModel, coordinator: coordinator,
                              engine: cloudRouter, renderArbiter: renderArbiter,
                              cloudVoiceSettings: cloudVoiceSettings,
                              cloudVoiceSecrets: cloudVoiceSecrets, cloudRouter: cloudRouter,
                              kokoro: kokoro)
    }
}
