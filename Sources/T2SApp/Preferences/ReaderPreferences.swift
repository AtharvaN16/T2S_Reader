import Foundation
import Observation

public enum ReaderTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// User preferences behind the Preferences page (spec §2.4.5) and the Reader's appearance, stored in
/// `UserDefaults`. Reader body size and line height are independent of the system text size
/// (spec §2.4.1), hence a scale over the 18pt base rather than a Dynamic Type category.
@MainActor
@Observable
public final class ReaderPreferences {
    public static let textScaleRange: ClosedRange<Double> = 0.8...1.6
    public static let lineHeightRange: ClosedRange<Double> = 1.3...1.8
    public static let skipBackOptions = [10, 15, 30]
    public static let skipForwardOptions = [15, 30, 45]

    public struct BudgetOption: Hashable, Sendable {
        public var label: String
        public var seconds: TimeInterval

        public init(label: String, seconds: TimeInterval) {
            self.label = label
            self.seconds = seconds
        }
    }

    /// Spec §3.4.1: 1 h · 3 h · 8 h · Everything.
    public static let prepareBudgetOptions = [
        BudgetOption(label: "1 hour", seconds: 3600),
        BudgetOption(label: "3 hours", seconds: 3 * 3600),
        BudgetOption(label: "8 hours", seconds: 8 * 3600),
        BudgetOption(label: "Everything", seconds: .infinity),
    ]

    private let defaults: UserDefaults

    private enum Key {
        static let textScale = "reader.textScale"
        static let lineHeight = "reader.lineHeight"
        static let theme = "reader.theme"
        static let skipBack = "playback.skipBack"
        static let skipForward = "playback.skipForward"
        static let rate = "playback.defaultRate"
        static let autoplay = "playback.autoplayNext"
        static let voice = "voice.default"
    }

    public var textScale: Double {
        didSet {
            let clamped = Self.textScaleRange.clamped(textScale)
            if textScale != clamped { textScale = clamped }
            defaults.set(textScale, forKey: Key.textScale)
        }
    }

    public var lineHeight: Double {
        didSet {
            let clamped = Self.lineHeightRange.clamped(lineHeight)
            if lineHeight != clamped { lineHeight = clamped }
            defaults.set(lineHeight, forKey: Key.lineHeight)
        }
    }

    public var theme: ReaderTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    public var skipBackSeconds: Int {
        didSet { defaults.set(skipBackSeconds, forKey: Key.skipBack) }
    }

    public var skipForwardSeconds: Int {
        didSet { defaults.set(skipForwardSeconds, forKey: Key.skipForward) }
    }

    public var defaultRate: Double {
        didSet { defaults.set(defaultRate, forKey: Key.rate) }
    }

    public var autoplayNext: Bool {
        didSet { defaults.set(autoplayNext, forKey: Key.autoplay) }
    }

    /// nil = the engine's language default ("default" in render keys).
    public var defaultVoiceID: String? {
        didSet { defaults.set(defaultVoiceID, forKey: Key.voice) }
    }

    /// `.infinity` = Everything. Stored as a Double; `AppPaths.prepareBudgetKey` is shared with
    /// the coordinator wiring.
    public var prepareBudgetSeconds: TimeInterval {
        didSet { defaults.set(prepareBudgetSeconds, forKey: AppPaths.prepareBudgetKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        textScale = Self.textScaleRange.clamped(defaults.object(forKey: Key.textScale) as? Double ?? 1.0)
        lineHeight = Self.lineHeightRange.clamped(defaults.object(forKey: Key.lineHeight) as? Double ?? 1.5)
        theme = ReaderTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        skipBackSeconds = defaults.object(forKey: Key.skipBack) as? Int ?? 15
        skipForwardSeconds = defaults.object(forKey: Key.skipForward) as? Int ?? 30
        defaultRate = defaults.object(forKey: Key.rate) as? Double ?? 1.0
        autoplayNext = defaults.object(forKey: Key.autoplay) as? Bool ?? true
        defaultVoiceID = defaults.string(forKey: Key.voice)
        prepareBudgetSeconds = defaults.object(forKey: AppPaths.prepareBudgetKey) as? Double ?? 3 * 3600
    }

    public func reset() {
        textScale = 1.0
        lineHeight = 1.5
        theme = .system
        skipBackSeconds = 15
        skipForwardSeconds = 30
        defaultRate = 1.0
        autoplayNext = true
        defaultVoiceID = nil
        prepareBudgetSeconds = 3 * 3600
    }
}

private extension ClosedRange where Bound == Double {
    func clamped(_ value: Double) -> Double {
        Swift.min(upperBound, Swift.max(lowerBound, value))
    }
}
