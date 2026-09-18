import AVFoundation
import T2SApp

/// The device's English system voices, best quality first. Its rows used to preview through a
/// dedicated `AVSpeechSynthesizer` in `AudioSessionController`; `VoicePreviewModel` now previews
/// every group the same way, this one included, through `RoutedEngine`'s `system:` route — the same
/// offline `AVSpeechSynthesizer.write` path `SystemSpeechEngine` renders a book with.
struct SystemVoiceCatalog: VoiceCatalog {
    func voices() -> [VoiceOption] { [.systemDefault] + SystemVoices.shared.english }
}

/// The device's English voices, asked of the speech daemon once. `AVSpeechSynthesisVoice.speechVoices()`
/// is a call out of the process, tens of milliseconds, and `voices()` is read from view bodies —
/// the voice page's on every tap of a row, the Reader's when its chip resolves a name — so it was
/// paid over and over for a list that does not change while the app runs. The one thing that
/// changes it, a voice downloaded in the system's Settings meanwhile, is announced, and the cache
/// is dropped on that notice.
private final class SystemVoices: @unchecked Sendable {
    static let shared = SystemVoices()

    private let lock = NSLock()
    private var cached: [VoiceOption]?

    private init() {
        NotificationCenter.default.addObserver(forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                                               object: nil, queue: nil) { [weak self] _ in
            self?.invalidate()
        }
    }

    var english: [VoiceOption] {
        lock.withLock {
            if let cached { return cached }
            let voices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix("en") }
                .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
                .map { VoiceOption(id: "system:\($0.identifier)", name: $0.name, detail: $0.language, language: $0.language) }
            cached = voices
            return voices
        }
    }

    private func invalidate() {
        lock.withLock { cached = nil }
    }
}
