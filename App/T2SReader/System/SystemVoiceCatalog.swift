import AVFoundation
import T2SApp

/// The device's English system voices (until Plan 5 brings Kokoro's presets), best quality first.
struct SystemVoiceCatalog: VoiceCatalog {
    func voices() -> [VoiceOption] {
        let system = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
            .map { VoiceOption(id: $0.identifier, name: "\($0.name) · \($0.language)", language: $0.language) }
        return [.systemDefault] + system
    }

    /// Speaks a short sample through the system synthesizer (the voice list's preview).
    @MainActor
    static func preview(_ option: VoiceOption, synthesizer: AVSpeechSynthesizer) {
        let utterance = AVSpeechUtterance(string: "This is how I sound reading your book.")
        utterance.voice = AVSpeechSynthesisVoice(identifier: option.id) ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}
