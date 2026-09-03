import Foundation
import MediaPlayer
import Testing
@testable import T2SApp
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@Suite struct NowPlayingArtworkTests {
    /// MediaPlayer resolves artwork on its own serial queue (`-[MPMediaItemArtwork jpegDataWithSize:]`
    /// inside `MPNowPlayingInfoCenter`'s push), never on the main actor. A handler that inherited
    /// main-actor isolation trapped there under Swift 6's executor check the moment playback
    /// started, so the handler must be callable from any queue.
    @Test func requestHandlerIsCallableOffTheMainQueue() {
        let image = Self.image(width: 12, height: 8)
        let artwork = NowPlayingArtwork.make(image)
        let returned = DispatchQueue.global(qos: .userInitiated).sync {
            artwork.image(at: CGSize(width: 4, height: 4))
        }
        #expect(returned === image)                                   // the decoded image, at any requested size
        #expect(artwork.bounds.size == image.size)
    }

    private static func image(width: Int, height: Int) -> NowPlayingImage {
        #if canImport(UIKit)
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in }
        #else
        return NSImage(size: CGSize(width: width, height: height))
        #endif
    }
}
