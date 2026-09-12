import Foundation

/// Whether the reader deleted the on-device voice model, and so does not want it downloaded again
/// until they ask for it.
///
/// The app downloads the model on launch (about 620 MB, Wi-Fi only), which is the right default for
/// a read-aloud app: a reader who taps play should not then wait for a download. Settings → Storage
/// offers the other direction — the model and its compute plans run past a gigabyte on an A13, so
/// the space has to be reclaimable. The two only make sense together if a delete also switches the
/// automatic download off: otherwise the reader frees a gigabyte, relaunches, and it silently comes
/// back. So a delete records itself here, the launch path reads this before it downloads anything,
/// and the download button in Storage is what clears it.
public enum KokoroModelRemovalRecord {
    public static let key = "kokoro.autoDownloadSuppressed"

    /// True once the reader has deleted the model and has not asked for it again.
    public static func isSuppressed(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key)
    }

    /// The delete in Storage: no launch downloads the model until the reader asks.
    public static func suppress(defaults: UserDefaults) {
        defaults.set(true, forKey: key)
    }

    /// The download in Storage: launches may download it again, exactly as a fresh install does.
    public static func allow(defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}
