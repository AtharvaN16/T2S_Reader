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

    @Test func voiceOptionDefault() {
        #expect(VoiceOption.systemDefault.id == "default" && VoiceOption.systemDefault.isDefault)
    }
}
