import Foundation
import Observation

public enum ReaderTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// The read-along tint pair (spec 2026-09-09): which colours mark the sentence and the word.
public enum HighlightTheme: String, CaseIterable, Sendable, Identifiable {
    case amber, sky, fall, marker, mint

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .amber: return "Amber"
        case .sky: return "Sky"
        case .fall: return "Fall"
        case .marker: return "Marker"
        case .mint: return "Mint"
        }
    }
}

/// How the Collection page lays its books out (2026-09-09): the spec's cover grid, or one book per
/// row with a menu button. Remembered across launches like any other preference.
public enum CollectionLayout: String, CaseIterable, Sendable {
    case grid, list
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
        static let highlightTheme = "reader.highlightTheme"
        static let collectionLayout = "collection.layout"
        static let skipBack = "playback.skipBack"
        static let skipForward = "playback.skipForward"
        static let rate = "playback.defaultRate"
        static let autoplay = "playback.autoplayNext"
        static let voice = "voice.default"
        static let favoriteVoices = "voice.favorites"
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

    /// `amber` is the accent — the only look before there was a choice — so existing readers see no change.
    public var highlightTheme: HighlightTheme {
        didSet { defaults.set(highlightTheme.rawValue, forKey: Key.highlightTheme) }
    }

    /// The grid is the spec's Collection, so it stays the default.
    public var collectionLayout: CollectionLayout {
        didSet { defaults.set(collectionLayout.rawValue, forKey: Key.collectionLayout) }
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

    /// Voice IDs the reader has starred in the picker (spec: voice picker, Plan 9 quality). A plain
    /// set, not a ranking — the picker's "Favorites" filter is a subset, not a reorder.
    public var favoriteVoiceIDs: Set<String> {
        didSet { defaults.set(Array(favoriteVoiceIDs), forKey: Key.favoriteVoices) }
    }

    public func toggleFavoriteVoice(_ id: String) {
        if favoriteVoiceIDs.contains(id) { favoriteVoiceIDs.remove(id) } else { favoriteVoiceIDs.insert(id) }
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
        highlightTheme = HighlightTheme(rawValue: defaults.string(forKey: Key.highlightTheme) ?? "") ?? .amber
        collectionLayout = CollectionLayout(rawValue: defaults.string(forKey: Key.collectionLayout) ?? "") ?? .grid
        skipBackSeconds = defaults.object(forKey: Key.skipBack) as? Int ?? 15
        skipForwardSeconds = defaults.object(forKey: Key.skipForward) as? Int ?? 30
        defaultRate = defaults.object(forKey: Key.rate) as? Double ?? 1.0
        autoplayNext = defaults.object(forKey: Key.autoplay) as? Bool ?? true
        defaultVoiceID = defaults.string(forKey: Key.voice)
        favoriteVoiceIDs = Set(defaults.stringArray(forKey: Key.favoriteVoices) ?? [])
        prepareBudgetSeconds = defaults.object(forKey: AppPaths.prepareBudgetKey) as? Double ?? 3 * 3600
    }

    public func reset() {
        textScale = 1.0
        lineHeight = 1.5
        theme = .system
        highlightTheme = .amber
        collectionLayout = .grid
        skipBackSeconds = 15
        skipForwardSeconds = 30
        defaultRate = 1.0
        autoplayNext = true
        defaultVoiceID = nil
        favoriteVoiceIDs = []
        prepareBudgetSeconds = 3 * 3600
    }
}

private extension ClosedRange where Bound == Double {
    func clamped(_ value: Double) -> Double {
        Swift.min(upperBound, Swift.max(lowerBound, value))
    }
}
