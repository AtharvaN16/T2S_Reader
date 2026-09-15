import Foundation
import Observation

/// What Prepare renders while the phone is charging (owner, 2026-09-14). It replaced a budget in
/// hours, which asked the reader for a number nobody can translate into books: "3 hours" never said
/// *whose* three hours, and sat on the Storage page directly above a row of gigabyte chips that
/// meant something else entirely.
public enum PrepareMode: String, CaseIterable, Sendable {
    /// The chapter you are in, in every book you have started. The default, and the whole of what
    /// most readers want: it needs no decision and it follows the reading rather than a number.
    case keepUp
    /// Only the chapters the reader picked, book by book.
    case picked
}

/// When a pass may run (owner, 2026-09-14: "can we have it time based so night charging").
///
/// This is a *refusal*, not a schedule. `BGTaskScheduler` decides when a background task actually
/// runs — the app asks and iOS chooses — so the app cannot promise a pass at two in the morning.
/// What it can promise is the thing worth promising: outside the window, a granted pass does
/// nothing and goes back to sleep, so Prepare is never the reason the phone is warm in your hand.
public enum PrepareWindow: String, CaseIterable, Sendable {
    case anyTime
    case overnight

    /// 23:00 → 07:00, the hours a phone is usually on a charger and nobody is holding it.
    public static let overnightStartHour = 23
    public static let overnightEndHour = 7

    public var label: String {
        switch self {
        case .anyTime: return "Any time"
        case .overnight: return "Overnight"
        }
    }

    /// The window crosses midnight, so this is an `||` rather than a range test.
    public func allows(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .anyTime: return true
        case .overnight:
            let hour = calendar.component(.hour, from: date)
            return hour >= Self.overnightStartHour || hour < Self.overnightEndHour
        }
    }
}

/// Settings → Prepare on charge, persisted (owner, 2026-09-14). Its own page and its own model:
/// Prepare is about which books get made ahead, which has nothing to do with how much room the app
/// is allowed — the two lived in one screen and taught each other's numbers to be misread.
@MainActor
@Observable
public final class PrepareSettings {
    public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.enabled) }
    }

    public var mode: PrepareMode {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode) }
    }

    public var window: PrepareWindow {
        didSet { defaults.set(window.rawValue, forKey: Key.window) }
    }

    /// Document → the chapter indices picked for it. A document with one chapter — a PDF, an
    /// article — has only index 0, so "the whole file" and "chapter 0" are the same pick and the
    /// page needs no second kind of selection for it.
    public private(set) var picks: [UUID: Set<Int>] {
        didSet { write(picks) }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let enabled = "prepare.enabled"
        static let mode = "prepare.mode"
        static let window = "prepare.window"
        static let picks = "prepare.picks"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // On by default: it is what the app did before this page existed, and a reader who never
        // opens Settings should still wake up to a book that plays without spinning up.
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        mode = PrepareMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .keepUp
        window = PrepareWindow(rawValue: defaults.string(forKey: Key.window) ?? "") ?? .anyTime
        picks = Self.read(defaults: defaults)
    }

    public func chapters(for document: UUID) -> Set<Int> { picks[document] ?? [] }

    /// Replaces one document's pick. An empty set removes the row entirely rather than leaving a
    /// document behind with nothing picked in it, which the page would then have to draw.
    public func setChapters(_ chapters: Set<Int>, for document: UUID) {
        if chapters.isEmpty { picks.removeValue(forKey: document) } else { picks[document] = chapters }
    }

    public func toggleChapter(_ chapter: Int, for document: UUID) {
        var current = chapters(for: document)
        if current.contains(chapter) { current.remove(chapter) } else { current.insert(chapter) }
        setChapters(current, for: document)
    }

    /// Called when a chapter reaches the device, so the pick list is always "still to do" rather
    /// than a record of everything ever asked for. Without this the list only grows: a reader who
    /// picked ten chapters in March still reads "10 chapters" in June with all ten long since
    /// rendered, and has no way to tell the finished from the outstanding.
    public func clearPick(document: UUID, chapter: Int) {
        guard var current = picks[document], current.contains(chapter) else { return }
        current.remove(chapter)
        setChapters(current, for: document)
    }

    public func clearPicks(for document: UUID) {
        guard picks[document] != nil else { return }
        picks.removeValue(forKey: document)
    }

    /// A document that has left the library takes its pick with it.
    public func prunePicks(keeping documents: Set<UUID>) {
        let stale = picks.keys.filter { !documents.contains($0) }
        guard !stale.isEmpty else { return }
        for id in stale { picks.removeValue(forKey: id) }
    }

    public var pickedDocumentIDs: [UUID] { Array(picks.keys) }

    public var pickedChapterCount: Int { picks.values.reduce(0) { $0 + $1.count } }

    // `UUID` is not a plist key type, so the map is stored as strings → arrays.
    private func write(_ picks: [UUID: Set<Int>]) {
        let plist = Dictionary(uniqueKeysWithValues: picks.map { ($0.key.uuidString, Array($0.value).sorted()) })
        defaults.set(plist, forKey: Key.picks)
    }

    private static func read(defaults: UserDefaults) -> [UUID: Set<Int>] {
        guard let plist = defaults.dictionary(forKey: Key.picks) as? [String: [Int]] else { return [:] }
        var out: [UUID: Set<Int>] = [:]
        for (key, value) in plist {
            guard let id = UUID(uuidString: key), !value.isEmpty else { continue }
            out[id] = Set(value)
        }
        return out
    }
}
