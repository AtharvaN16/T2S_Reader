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
    let libraryModel: LibraryModel
    let player: PlayerModel
    let importModel: ImportModel
    let audioSession = AudioSessionController()
    let deviceMonitor: DeviceMonitor

    init(paths: LibraryPaths, store: LibraryStore, audioStore: FileAudioStore, library: Library, coordinator: PlaybackCoordinator) {
        self.paths = paths
        self.store = store
        self.audioStore = audioStore
        self.library = library
        self.coordinator = coordinator
        libraryModel = LibraryModel(library: library)
        player = PlayerModel(coordinator: coordinator, library: library)
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
        let coordinator = PlaybackCoordinator(engine: SystemSpeechEngine(), store: audioStore, player: try AudioPlayer(),
                                              playheadStore: store, timeSource: SystemTimeSource())
        return AppEnvironment(paths: paths, store: store, audioStore: audioStore, library: library, coordinator: coordinator)
    }
}
