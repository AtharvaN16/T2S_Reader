// App/T2SReader/System/KokoroModelStore.swift
import Foundation
import Observation

/// What Settings → Storage shows and does for the on-device voice model: what it occupies, a delete
/// that reclaims it, and the download that brings it back.
///
/// The model downloads itself on launch, which is the right default — a reader who taps play should
/// not then wait for 620 MB — but on an A13 the install and its compute plans run past a gigabyte,
/// so the space has to be reclaimable, and a delete has to switch the automatic download off or the
/// gigabyte silently returns on the next launch (`KokoroModelRemovalRecord`).
///
/// The work itself belongs to the composition root, which holds the installer, the availability
/// verdict, the engine and the route: this is the four closures it hands out, plus the numbers a
/// page can draw. The everyday build, which links no engine, gets ``unsupported`` and shows nothing.
@MainActor
@Observable
final class KokoroModelStore {
    /// What the model and its compute plans occupy, apart: the plans are the larger half on the CPU
    /// path (about a gigabyte against 240 MB of compiled model), and a reader deciding whether to
    /// delete deserves the honest total rather than the download's advertised size.
    struct Measurement: Equatable {
        var model: Int64 = 0
        var plans: Int64 = 0
        var total: Int64 { model + plans }
    }

    /// False in the everyday build: no engine is linked, so there is no model and no section.
    let isSupported: Bool
    private(set) var measurement = Measurement()
    /// True while a delete is running, so the pills cannot be tapped twice.
    private(set) var isDeleting = false

    private let measure: @MainActor () -> Measurement
    private let performDelete: @MainActor () async -> Void
    private let performDownload: @MainActor () -> Void

    init(isSupported: Bool,
         measure: @escaping @MainActor () -> Measurement,
         delete: @escaping @MainActor () async -> Void,
         download: @escaping @MainActor () -> Void) {
        self.isSupported = isSupported
        self.measure = measure
        self.performDelete = delete
        self.performDownload = download
    }

    /// The everyday build's: nothing on disk, nothing to do.
    static var unsupported: KokoroModelStore {
        KokoroModelStore(isSupported: false, measure: { Measurement() }, delete: {}, download: {})
    }

    /// Walks the model directory and the plan cache. A few hundred `stat`s, off no actor's critical
    /// path — Storage calls it when the page appears and after a delete or a download.
    func refresh() {
        measurement = measure()
    }

    /// Removes every downloaded revision and the compute plans, and switches the automatic download
    /// off until the reader asks for it again.
    func delete() async {
        guard isSupported, !isDeleting else { return }
        isDeleting = true
        await performDelete()
        refresh()
        isDeleting = false
    }

    /// Downloads the model now and lets launches download it again.
    func download() {
        guard isSupported else { return }
        performDownload()
    }
}
