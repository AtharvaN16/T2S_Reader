import AVFoundation
import T2SApp

/// The device's English system voices, best quality first. Its rows used to preview through a
/// dedicated `AVSpeechSynthesizer` in `AudioSessionController`; `VoicePreviewModel` now previews
/// every group the same way, this one included, through `RoutedEngine`'s `system:` route — the same
/// offline `AVSpeechSynthesizer.write` path `SystemSpeechEngine` renders a book with.
struct SystemVoiceCatalog: VoiceCatalog {
    func voices() -> [VoiceOption] {
        let system = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
            .map { VoiceOption(id: "system:\($0.identifier)", name: $0.name, detail: $0.language, language: $0.language) }
        return [.systemDefault] + system
    }
}
