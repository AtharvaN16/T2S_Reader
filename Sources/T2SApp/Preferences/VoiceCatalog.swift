import Foundation

/// A selectable voice (spec §2.2 voice picker). Until Plan 5, the app fills this from
/// `AVSpeechSynthesisVoice`; `systemDefault` maps to the engine's language fallback.
public struct VoiceOption: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var language: String
    public var isDefault: Bool

    public init(id: String, name: String, language: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.language = language
        self.isDefault = isDefault
    }

    public static let systemDefault = VoiceOption(
        id: "default",
        name: "System default",
        language: "en",
        isDefault: true
    )
}

public protocol VoiceCatalog: Sendable {
    /// `systemDefault` first, then the device's voices.
    func voices() -> [VoiceOption]
}
