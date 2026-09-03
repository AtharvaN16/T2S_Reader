import Foundation
import T2SApp
import T2SAudio
import T2SCore
import T2SLibrary
import T2SReadium
import T2SStore

/// The one common app-group library graph used by the host and Share Extension. Import is phase 1
/// only, so the extension creates neither an AudioPlayer nor a playback coordinator.
@MainActor
enum SharedLibraryFactory {
    static func make(capacityBytes: Int = AppPaths.defaultAudioCapacityBytes)
        throws -> (paths: LibraryPaths, store: LibraryStore, audioStore: FileAudioStore,
                   library: Library, importModel: ImportModel) {
        let paths = LibraryPaths(root: try AppPaths.sharedContainerRoot())
        try FileManager.default.createDirectory(at: paths.audioDirectory, withIntermediateDirectories: true)
        var audioDirectory = paths.audioDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try audioDirectory.setResourceValues(values)

        let store = try LibraryStore.onDisk(at: paths.databaseURL)
        let audioStore = FileAudioStore(directory: paths.audioDirectory, codec: AACCodec(), capacityBytes: capacityBytes)
        let library = Library(paths: paths, store: store, audioStore: audioStore,
                              readers: [PDFDocumentReader(), ReadiumDocumentReader()])
        let importModel = ImportModel(library: library, extractor: ArticleExtractor())
        return (paths, store, audioStore, library, importModel)
    }
}
