import CoreGraphics
import Foundation

/// Where the Dynamic Island is, and whether this phone has one.
///
/// **There is no API for this.** Apple Developer Technical Support, on the record: "We don't
/// recommend you doing this and there's no first-party API that provides support for detecting
/// whether a device has a notch or island." The two heuristics everyone used —
/// `safeAreaInsets.bottom > 0` and `safeAreaInsets.top > 20` — both stopped working in iOS 26.
/// Model identifiers did not, so that is what this uses.
///
/// The list will go stale every September. That is survivable because it fails in the safe
/// direction: an identifier this file has never heard of is treated as having no island, and
/// the capsule falls back to a plain card under the status bar. A wrong "yes" would draw a
/// black capsule through a notch; a wrong "no" draws a card that looks deliberate.
public enum IslandGeometry {
    /// The cutout, in points. **Community-measured, not published by Apple** — Apple documents
    /// only the 36 pt compact height and the 144 pt expanded maximum. Check these against a
    /// photograph of a real island phone before trusting the alignment.
    public static let cutoutWidth: CGFloat = 126
    public static let cutoutHeight: CGFloat = 37.33
    /// From the top of the screen to the top of the cutout.
    public static let cutoutTop: CGFloat = 11

    /// Every model identifier with a Dynamic Island, newest last.
    ///
    /// Note `iPhone17,5` is deliberately absent: the 16e has a notch.
    public static let islandModels: Set<String> = [
        "iPhone15,2", "iPhone15,3",              // 14 Pro, 14 Pro Max
        "iPhone15,4", "iPhone15,5",              // 15, 15 Plus
        "iPhone16,1", "iPhone16,2",              // 15 Pro, 15 Pro Max
        "iPhone17,3", "iPhone17,4",              // 16, 16 Plus
        "iPhone17,1", "iPhone17,2",              // 16 Pro, 16 Pro Max
    ]

    public static func hasIsland(machine: String) -> Bool { islandModels.contains(machine) }

    /// The identifier of the machine this is running on.
    ///
    /// **`uname` reports the host on a simulator** — "arm64" or "x86_64", never a phone's
    /// identifier — so a simulator run would always take the no-island path and the capsule
    /// could never be seen on the one device available for looking at it. The simulator
    /// publishes the device it is pretending to be in its environment instead.
    public static func currentMachine() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    public static var deviceHasIsland: Bool { hasIsland(machine: currentMachine()) }
}
