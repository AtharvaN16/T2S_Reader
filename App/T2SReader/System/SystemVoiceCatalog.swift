import AVFoundation
import T2SApp

/// The device's English system voices (until Plan 5 brings Kokoro's presets), best quality first.
struct SystemVoiceCatalog: VoiceCatalog {
    func voices() -> [VoiceOption] {
        let system = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
            .map { VoiceOption(id: "system:\($0.identifier)", name: "\($0.name) · \($0.language)", language: $0.language) }
        return [.systemDefault] + system
    }

    /// Speaks a short sample through the system synthesizer (the voice list's preview).
    @MainActor
    static func preview(_ option: VoiceOption, through audioSession: AudioSessionController) {
        let utterance = AVSpeechUtterance(string: "This is how I sound reading your book.")
        let identifier = option.id.hasPrefix("system:") ? String(option.id.dropFirst("system:".count)) : option.id
        utterance.voice = AVSpeechSynthesisVoice(identifier: identifier) ?? AVSpeechSynthesisVoice(language: "en-US")
        audioSession.preview(utterance)
    }
}
