import Foundation

/// Whether the audio session's current route is a cast — the book playing on a speaker or a TV
/// the listener chose from the AirPlay picker — and what to call that device. Pure, so it is
/// tested here; the app hands it the session's outputs.
///
/// Wired headphones, CarPlay and HDMI are outputs too, but nobody "casts" to them: the header
/// keeps the book's title for those, and only AirPlay and Bluetooth turn it into the casting pill.
public enum CastRoute {
    /// One output of the session's current route: `AVAudioSession.Port`'s raw value, and the
    /// device's own name. Strings rather than the port type itself because `AVAudioSession` does
    /// not exist on macOS, where this package's tests run.
    public struct Output: Hashable, Sendable {
        public var kind: String
        public var name: String

        public init(kind: String, name: String) {
            self.kind = kind
            self.name = name
        }
    }

    private static let airPlay = "AirPlay"
    private static let bluetooth: Set<String> = ["BluetoothA2DPOutput", "BluetoothLE", "BluetoothHFP"]

    /// The device to say the book is casting to, or nil when it is not casting.
    public static func castingTo(_ outputs: [Output]) -> String? {
        for output in outputs {
            let fallback: String
            if output.kind == airPlay {
                fallback = "AirPlay"
            } else if bluetooth.contains(output.kind) {
                fallback = "Bluetooth"
            } else {
                continue
            }
            let name = output.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? fallback : name
        }
        return nil
    }
}
