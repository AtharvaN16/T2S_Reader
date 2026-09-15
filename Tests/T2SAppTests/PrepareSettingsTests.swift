import Foundation
import Testing
@testable import T2SApp

/// Settings → Prepare on charge (owner, 2026-09-14): the switch, the window and the picks, and the
/// rule that keeps the pick list meaning "still to do".
@MainActor
@Suite struct PrepareSettingsTests {
    private func fresh() -> UserDefaults {
        let suite = "t2s-prepare-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// On, keeping up, any time: what a reader who never opens this page gets, which is what the
    /// app did before the page existed.
    @Test func defaultsAreOnAndKeepingUp() {
        let settings = PrepareSettings(defaults: fresh())
        #expect(settings.isEnabled)
        #expect(settings.mode == .keepUp)
        #expect(settings.window == .anyTime)
        #expect(settings.picks.isEmpty)
    }

    @Test func picksSurviveALaunch() {
        let defaults = fresh()
        let first = PrepareSettings(defaults: defaults)
        let book = UUID()
        first.setChapters([3, 1, 9], for: book)
        first.mode = .picked
        first.window = .overnight
        first.isEnabled = false

        let second = PrepareSettings(defaults: defaults)
        #expect(second.chapters(for: book) == [1, 3, 9])
        #expect(second.mode == .picked)
        #expect(second.window == .overnight)
        #expect(!second.isEnabled)
        #expect(second.pickedChapterCount == 3)
    }

    /// An empty pick is a row the page would have to draw with nothing in it, so the document
    /// leaves the map entirely rather than staying behind holding an empty set.
    @Test func emptyingAPickRemovesTheDocument() {
        let settings = PrepareSettings(defaults: fresh())
        let book = UUID()
        settings.toggleChapter(2, for: book)
        #expect(settings.picks[book] == [2])
        settings.toggleChapter(2, for: book)
        #expect(settings.picks[book] == nil)
        #expect(settings.pickedDocumentIDs.isEmpty)
    }

    @Test func clearingOneChapterLeavesTheRest() {
        let settings = PrepareSettings(defaults: fresh())
        let book = UUID()
        settings.setChapters([1, 2, 3], for: book)
        settings.clearPick(document: book, chapter: 2)
        #expect(settings.chapters(for: book) == [1, 3])
        settings.clearPicks(for: book)
        #expect(settings.chapters(for: book).isEmpty)
    }

    /// A book deleted from the library takes its pick with it, or the page draws a row with no book
    /// behind it.
    @Test func prunedPicksFollowTheLibrary() {
        let settings = PrepareSettings(defaults: fresh())
        let kept = UUID(), gone = UUID()
        settings.setChapters([0], for: kept)
        settings.setChapters([0], for: gone)
        settings.prunePicks(keeping: [kept])
        #expect(settings.pickedDocumentIDs == [kept])
    }

    /// The window crosses midnight, so 11 PM and 2 AM are both inside it and 8 PM is not.
    @Test func overnightSpansMidnight() {
        let calendar = Calendar(identifier: .gregorian)
        func at(_ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: hour)) ?? Date()
        }
        #expect(PrepareWindow.overnight.allows(at(23), calendar: calendar))
        #expect(PrepareWindow.overnight.allows(at(2), calendar: calendar))
        #expect(PrepareWindow.overnight.allows(at(6), calendar: calendar))
        #expect(!PrepareWindow.overnight.allows(at(7), calendar: calendar))
        #expect(!PrepareWindow.overnight.allows(at(20), calendar: calendar))
        // Any time means any time, including the hours the other one refuses.
        #expect(PrepareWindow.anyTime.allows(at(20), calendar: calendar))
    }
}
