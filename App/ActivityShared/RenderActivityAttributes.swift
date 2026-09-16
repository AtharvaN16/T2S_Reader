import ActivityKit
import Foundation

/// The render card's wire format — the only type the app and the widget extension both hold.
///
/// It lives under `App/` and not in the package because the package builds for macOS, where
/// `ActivityKit` does not exist; one import here would break `swift test` for every target.
/// `App/ActivityShared` is listed by both the app target and the extension, the same way
/// `T2SReader/Shared` is already shared with `T2SReaderShare`.
///
/// The fields are primitives rather than a `RenderCardReading`, so this file compiles with no
/// dependency on the package at all.
struct RenderActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var headline: String
        var detail: String
        var ready: Int
        var total: Int
        var fraction: Double
    }

    /// Fixed for the life of the activity — a batch is one book.
    var bookTitle: String
    /// Library-relative path to the cover, or nil. The extension resolves it through the shared
    /// app group; a cover it cannot find simply is not drawn.
    var coverPath: String?
}
