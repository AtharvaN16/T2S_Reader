// App/T2SReader/AppEnvironment.swift
import Foundation
import Observation
import T2SApp
import T2SAudio
import T2SCore
import T2SLibrary
import T2SStore
import T2SSync
import UIKit
#if KOKORO_ENGINE
import T2SKokoro
#endif

/// Builds the object graph once (spec §3): store → library → coordinator → models. Rendered audio
/// is cache, so its directory is excluded from backup (spec §3.7.3).
@MainActor
@Observable
final class AppEnvironment {
    let paths: LibraryPaths
    let store: LibraryStore
    let audioStore: any AudioStore
    let library: Library
    let coordinator: PlaybackCoordinator
    /// The one inference lease shared by the live player and Prepare.
    let renderArbiter: RenderArbiter
    let libraryModel: LibraryModel
    let player: PlayerModel
    let importModel: ImportModel
    let syncModel: SyncModel
    let preferences: ReaderPreferences
    let cloudVoiceSettings: CloudVoiceSettings
    let cloudVoiceSecrets: any SecretStoring
    let cloudRouter: RoutedEngine
    let voices: any VoiceCatalog
    /// Renders and plays one sample sentence for whichever voice a picker row previews (spec:
    /// Plan 9 voice quality) — the same model for every group, since `cloudRouter` already knows
    /// how to route any voice ID.
    let voicePreview: VoicePreviewModel
    /// The same resolver the player and Prepare use, so Preferences can show what "default" means
    /// on this device rather than guessing (spec §6).
    let voiceRouting: any VoiceRouteResolving
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
    /// The on-device engine's composition, kept for what only its build can do — the timing log's
    /// line at the fill's edges (`noteFill`); its parts are the properties above.
    let kokoro: KokoroComposition
    /// Whether the scene is active, for work iOS only allows in the foreground: the Kokoro
    /// warm-up's compute-plan builds and the model install's compiles wait on it, and `CPUBudget`
    /// paces background renders by it. `RootPager` sets it from `scenePhase`.
    let foregroundGate: ForegroundGate

    /// Whether the transport is waiting on the voice's one-time warm-up rather than routine
    /// buffering — the single definition every playback surface (Reader, its transport controls,
    /// the mini-player) reads, so they can't drift into disagreeing about which of the two states
    /// a stall is in. Lives here rather than on `PlayerModel`: `PlayerModel` is package code
    /// (`T2SApp`) and cannot depend on `KokoroStatusModel`, which belongs to this app target.
    var isWarmingUp: Bool { player.isCatchingUp && kokoroStatus.status.isWarming }

    init(paths: LibraryPaths, store: LibraryStore, audioStore: any AudioStore, library: Library,
         importModel: ImportModel, coordinator: PlaybackCoordinator, engine: any SynthesisEngine,
         renderArbiter: RenderArbiter, cloudVoiceSettings: CloudVoiceSettings,
         cloudVoiceSecrets: any SecretStoring, cloudRouter: RoutedEngine,
         kokoro: KokoroComposition, foregroundGate: ForegroundGate, cpuBudget: CPUBudget?, syncModel: SyncModel) {
        self.paths = paths
        self.syncModel = syncModel
        self.foregroundGate = foregroundGate
        self.store = store
        self.audioStore = audioStore
        self.library = library
        self.coordinator = coordinator
        self.renderArbiter = renderArbiter
        self.kokoro = kokoro
        libraryModel = LibraryModel(library: library)
        player = PlayerModel(coordinator: coordinator, library: library)
        preferences = ReaderPreferences()
        self.cloudVoiceSettings = cloudVoiceSettings
        self.cloudVoiceSecrets = cloudVoiceSecrets
        self.cloudRouter = cloudRouter
        voices = kokoro.catalog(wrapping: CloudVoiceCatalog(base: SystemVoiceCatalog(),
                                                            configurationStore: cloudVoiceSettings.configurationStore))
        kokoroStatus = kokoro.status
        voiceRouting = kokoro.voiceRouting
        pronunciation = PronunciationModel(store: store)
        storage = StorageModel(library: library, audioStore: audioStore, player: player, libraryModel: libraryModel)
        prepareRunner = PrepareRunner(library: library, store: store, audioStore: audioStore,
                                      engine: engine, arbiter: renderArbiter, budget: cpuBudget)
        voiceChange = VoiceChangeModel(library: library, player: player, libraryModel: libraryModel)
        readerModel = ReaderModel(player: player)
        sleepTimer = SleepTimer(player: player)
        continuation = QueueContinuation(player: player, library: libraryModel, preferences: preferences)
        nowPlaying = NowPlayingController(player: player, libraryModel: libraryModel, preferences: preferences, paths: paths)
        player.defaultVoiceID = preferences.defaultVoiceID
        prepareRunner.defaultVoiceID = preferences.defaultVoiceID
        // One resolver for all three: a document's voice is decided the same way whether it is
        // played now, prepared in the background, or described in Preferences (spec §6).
        player.voiceRouting = voiceRouting
        prepareRunner.voiceRouting = voiceRouting
        // Spec §3.4.1 tier 2: a new document's first 30 s render now, on any power state, so its
        // first tap plays with no spin-up. One at a time, behind whatever the player is rendering —
        // the arbiter gives play-ahead the next utterance.
        // The lists read the store only on a refresh, so the new documents are read in first: the
        // Import page now stays open on them (Play or Done) and both pages must already show them
        // behind it (owner, 2026-09-10: an import showed nowhere until the app was reopened).
        importModel.afterImport = { [prepareRunner, libraryModel] documents in
            Task {
                await libraryModel.refresh()
                for document in documents { _ = await prepareRunner.prime(document.id) }
            }
        }
        coordinator.setRate(preferences.defaultRate)
        self.importModel = importModel
        deviceMonitor = DeviceMonitor(audioStore: audioStore)
        // Last: capturing `player` in `beforePreview` is only safe once every stored property has
        // a value, which is what makes `self` usable inside an escaping closure at all.
        voicePreview = VoicePreviewModel(
            engine: cloudRouter,
            makePlayer: { rate -> any AudioPlaying in
                if let player = try? AudioPlayer(sampleRate: rate) { return player }
                return NullAudioPlaying()
            },
            beforePreview: { [player] in
                // A preview is never heard over the book: pause it first, exactly as a listener's
                // own pause would, so resuming afterward is the listener's call, not this one's.
                if player.isPlaying { await player.togglePlay() }
            }
        )
        // A cycle that pulled something has already written it to the store; the lists still show
        // what was there before, until they are read again (sync spec §7).
        syncModel.onPulled = { [libraryModel] in await libraryModel.refresh() }
        // A deletion pulled from another device removes the book, its audio and its rows: the
        // player lets go of it first, exactly as a delete made here does (`deleteDocument`).
        Task { [syncModel, player] in
            await syncModel.setOnRemove { id in
                await MainActor.run { if player.current?.id == id { player.unload() } }
            }
        }
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
        // Closed until the scene reports itself active; a process launched for a background task
        // never opens it, so nothing that needs the foreground ever starts there.
        let foregroundGate = ForegroundGate(isForeground: false)
        let cpuBudget = CPUBudget(gate: foregroundGate)
        // The budget's pacing decisions otherwise live only in `os_log`, which the phone does not
        // hand over; the timing log is what a crash report can actually be read against.
        #if KOKORO_ENGINE
        cpuBudget.report = { KokoroCoreMLEngine.timing("kokoro budget: " + $0) }
        #endif
        let kokoro = KokoroComposition.make(gate: foregroundGate)
        let cloudRouter = RoutedEngine(
            system: systemEngine,
            // Both on-device runtimes, keyed by identity: a `kokoro:` voice ID names which one
            // rendered it, so the two never share a render key (spec §5).
            kokoro: kokoro.engines,
            configuration: { configurationStore.current() },
            key: { try cloudVoiceSecrets.load() }
        )
        let renderArbiter = RenderArbiter()
        // The Kokoro route's own play-ahead — ten minutes on a GPU phone, three on the CPU path — in
        // every state; the window has no foreground/background split (`KokoroComposition.playAheadWindowSeconds`).
        // The fill past it — the rest of the chapter — runs only while frontmost and listening
        // (`foregroundFillSeconds`, Plan 18); nil in the everyday build leaves the coordinator as it was.
        var configuration = CoordinatorConfiguration(prepareBudgetSeconds: prepareBudget)
        if let window = kokoro.playAheadWindowSeconds { configuration.windowSeconds = window }
        configuration.foregroundFill = kokoro.foregroundFillSeconds
        let coordinator = PlaybackCoordinator(engine: cloudRouter, store: shared.audioStore, player: try AudioPlayer(),
                                              playheadStore: shared.store, timeSource: SystemTimeSource(),
                                              configuration: configuration,
                                              arbiter: renderArbiter, budget: cpuBudget)
        // The provider (sync spec §8): CloudKit when the build carries a container, the fake under
        // `-t2s.sync fake` for a simulator run, else none — the toggle stays off with its reason.
        let container = ((Bundle.main.infoDictionary?["T2SICloudContainer"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let provider: (any SyncProvider)? = UserDefaults.standard.string(forKey: "t2s.sync") == "fake" ? FakeSyncProvider()
            : (container.isEmpty || container.hasPrefix("$(")) ? nil : CloudKitSyncProvider(containerIdentifier: container)
        let syncModel = SyncModel(provider: provider, library: shared.library, deviceName: UIDevice.current.name)
        return AppEnvironment(paths: shared.paths, store: shared.store, audioStore: shared.audioStore,
                              library: shared.library, importModel: shared.importModel, coordinator: coordinator,
                              engine: cloudRouter, renderArbiter: renderArbiter,
                              cloudVoiceSettings: cloudVoiceSettings,
                              cloudVoiceSecrets: cloudVoiceSecrets, cloudRouter: cloudRouter,
                              kokoro: kokoro, foregroundGate: foregroundGate, cpuBudget: cpuBudget, syncModel: syncModel)
    }
}

extension AppEnvironment {
    /// Delete removes a document from Queue and Collection both (spec §2.3). The player lets go of
    /// it first, so nothing keeps sounding from — or tries to save into — a document the library
    /// no longer has. Every delete in the app goes through here.
    func deleteDocument(_ id: UUID, everywhere: Bool = false) async {
        if player.current?.id == id { player.unload() }
        await libraryModel.delete(id, everywhere: everywhere)
    }

    /// The confirmation's one line, wherever a delete is offered.
    static let deleteMessage = "Removes it, its audio and its progress from this device."

    /// The confirmation's line once sync is on and a delete has two meanings (sync spec §5).
    static let deleteMessageWithSync = "This device: removes it, its audio and its progress here; it stays on your other devices. Everywhere: removes it from every device signed into your iCloud."
}

/// `AudioPlayer`'s init can throw — a real `AVAudioEngine` failing to start, not something a preview
/// button tap should crash over. This plays nothing and reports every segment finished the moment
/// `play()` is called, so the preview button returns to "play" at once rather than sitting on "stop"
/// for audio that will never come — the honest outcome when the device's audio engine itself would
/// not come up.
@MainActor
private final class NullAudioPlaying: AudioPlaying {
    var rate: Double = 1
    let isPlaying = false
    let consumedSeconds: TimeInterval = 0
    let queuedSeconds: TimeInterval = 0
    var onSegmentFinished: ((Int) -> Void)?
    private var queued: [Int] = []
    func enqueue(_ audio: PCMAudio, tag: Int, isFinal: Bool) { if isFinal { queued.append(tag) } }
    func play() {
        let tags = queued
        queued.removeAll()
        for tag in tags { onSegmentFinished?(tag) }
    }
    func pause() {}
    func reset() { queued.removeAll() }
    func rebuildAfterMediaServicesReset() {}
}
