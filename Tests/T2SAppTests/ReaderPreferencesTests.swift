import Foundation
import Testing
@testable import T2SApp

@MainActor
@Suite struct ReaderPreferencesTests {
    func fresh() -> UserDefaults {
        let suite = "t2s-prefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// The scrubber's scope (2026-09-13) is global and remembered: it is a way of reading rather
    /// than a fact about one book, and closing the Reader must not put the bar back.
    @Test func scrubberScopeDefaultsToTheBookAndPersists() {
        let defaults = fresh()
        #expect(ReaderPreferences(defaults: defaults).scrubberScope == .book)
        let preferences = ReaderPreferences(defaults: defaults)
        preferences.scrubberScope = .chapter
        #expect(ReaderPreferences(defaults: defaults).scrubberScope == .chapter)
        preferences.reset()
        #expect(ReaderPreferences(defaults: defaults).scrubberScope == .book)
    }

    /// The sleep sheet opens on what was chosen last time (2026-09-18): a sleep timer is a habit.
    /// A stale or hand-edited value lands on a stop of the ruler rather than between two.
    @Test func sleepChoiceIsRememberedAndSnapsToTheRuler() {
        let defaults = fresh()
        let fresh = ReaderPreferences(defaults: defaults)
        #expect(fresh.sleepMinutes == 30 && !fresh.sleepsAtChapterEnd)
        fresh.sleepMinutes = 45
        fresh.sleepsAtChapterEnd = true
        let again = ReaderPreferences(defaults: defaults)
        #expect(again.sleepMinutes == 45 && again.sleepsAtChapterEnd)
        again.sleepMinutes = 7
        #expect(again.sleepMinutes == 5)
        again.sleepMinutes = 999
        #expect(ReaderPreferences(defaults: defaults).sleepMinutes == 120)
        again.reset()
        #expect(ReaderPreferences(defaults: defaults).sleepMinutes == 30)
        #expect(!ReaderPreferences(defaults: defaults).sleepsAtChapterEnd)
    }

    /// The Reader-wide soundscape (soundscape design §4.2): off until chosen, 0.4 on the slider.
    @Test func theSoundscapeIsRememberedAndTheVolumeClamps() {
        let defaults = fresh()
        let first = ReaderPreferences(defaults: defaults)
        #expect(first.soundscapeID == nil && first.soundscapeVolume == 0.4)
        first.soundscapeID = "rain"
        first.soundscapeVolume = 0.7
        let again = ReaderPreferences(defaults: defaults)
        #expect(again.soundscapeID == "rain" && again.soundscapeVolume == 0.7)
        again.soundscapeVolume = 3
        #expect(again.soundscapeVolume == 1)
        again.soundscapeID = nil
        #expect(ReaderPreferences(defaults: defaults).soundscapeID == nil)
        again.reset()
        #expect(ReaderPreferences(defaults: defaults).soundscapeVolume == 0.4)
    }

    @Test func scopeFlipsToTheOther() {
        #expect(ScrubberScope.book.other == .chapter)
        #expect(ScrubberScope.chapter.other == .book)
    }

    @Test func defaultsMatchTheSpec() {
        let preferences = ReaderPreferences(defaults: fresh())
        #expect(preferences.textScale == 1.0 && preferences.lineHeight == 1.5 && preferences.theme == .system)
        #expect(preferences.skipBackSeconds == 15 && preferences.skipForwardSeconds == 30)
        #expect(preferences.defaultRate == 1.0 && preferences.autoplayNext)
        #expect(preferences.defaultVoiceID == nil)
        #expect(preferences.prepareBudgetSeconds == 3 * 3600)
        let expected: [TimeInterval] = [3600, 3 * 3600, 8 * 3600, .infinity]
        #expect(ReaderPreferences.prepareBudgetOptions.map(\.seconds) == expected)
    }

    @Test func valuesPersistAndClamp() {
        let defaults = fresh()
        let preferences = ReaderPreferences(defaults: defaults)
        preferences.textScale = 9
        preferences.lineHeight = 0.1
        preferences.theme = .dark
        preferences.skipBackSeconds = 30
        preferences.skipForwardSeconds = 45
        preferences.defaultRate = 1.5
        preferences.autoplayNext = false
        preferences.defaultVoiceID = "com.apple.voice.compact.en-US.Samantha"
        preferences.prepareBudgetSeconds = .infinity
        #expect(preferences.textScale == ReaderPreferences.textScaleRange.upperBound)
        #expect(preferences.lineHeight == ReaderPreferences.lineHeightRange.lowerBound)
        let again = ReaderPreferences(defaults: defaults)
        #expect(again.textScale == ReaderPreferences.textScaleRange.upperBound && again.lineHeight == ReaderPreferences.lineHeightRange.lowerBound)
        #expect(again.theme == .dark && again.skipBackSeconds == 30 && again.skipForwardSeconds == 45)
        #expect(again.defaultRate == 1.5 && !again.autoplayNext)
        #expect(again.defaultVoiceID == "com.apple.voice.compact.en-US.Samantha")
        #expect(again.prepareBudgetSeconds == .infinity)
        again.reset()
        #expect(again.textScale == 1.0 && again.theme == .system && again.defaultVoiceID == nil && again.prepareBudgetSeconds == 3 * 3600)
    }

    @Test func highlightThemeDefaultsPersistsAndResets() {
        let defaults = fresh()
        let preferences = ReaderPreferences(defaults: defaults)
        #expect(preferences.highlightTheme == .amber)
        preferences.highlightTheme = .sky
        let again = ReaderPreferences(defaults: defaults)
        #expect(again.highlightTheme == .sky)
        again.reset()
        #expect(again.highlightTheme == .amber && ReaderPreferences(defaults: defaults).highlightTheme == .amber)
    }

    @Test func collectionLayoutDefaultsPersistsAndResets() {
        let defaults = fresh()
        let preferences = ReaderPreferences(defaults: defaults)
        #expect(preferences.collectionLayout == .grid)
        preferences.collectionLayout = .list
        let again = ReaderPreferences(defaults: defaults)
        #expect(again.collectionLayout == .list)
        again.reset()
        #expect(again.collectionLayout == .grid && ReaderPreferences(defaults: defaults).collectionLayout == .grid)
    }

    @Test func voiceOptionDefault() {
        #expect(VoiceOption.systemDefault.id == "default" && VoiceOption.systemDefault.isDefault)
    }
}
