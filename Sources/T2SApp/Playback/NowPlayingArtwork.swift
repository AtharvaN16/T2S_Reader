import Foundation
import MediaPlayer
#if canImport(UIKit)
import UIKit
public typealias NowPlayingImage = UIImage
#else
import AppKit
public typealias NowPlayingImage = NSImage
#endif

/// Builds Lock Screen / Control Center artwork for the MediaPlayer boundary.
///
/// MediaPlayer resolves the request handler on its own serial queue when it serialises the Now
/// Playing dictionary for MediaRemote (`-[MPMediaItemArtwork jpegDataWithSize:]`), never on the
/// main actor. A handler formed inside a `@MainActor` context inherits that isolation and traps
/// under Swift 6's executor check the moment playback starts, so the handler is formed here, in a
/// nonisolated context, and captures nothing but the already-decoded image.
public enum NowPlayingArtwork {
    public static func make(_ image: NowPlayingImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
