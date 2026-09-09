import Foundation

/// The section a voice belongs to in the picker (spec §2.2). Kokoro is the only on-device engine
/// the phone build ships, so its section reads as what it is rather than as a beta label.
public enum VoiceGroup: String, Hashable, Sendable, CaseIterable {
    case system, kokoro, cloud

    public var title: String {
        switch self {
        case .system: return "System"
        case .kokoro: return "On-device voices"
        case .cloud: return "Cloud"
        }
    }
}

/// The voice's gender, for the picker's tinted avatar (pink for a female voice, blue for a male one).
/// `nil` for a row that has none to show: the "Default" pointer row, a system voice, a cloud voice.
public enum VoiceGender: String, Hashable, Sendable {
    case female, male
}

/// A selectable voice (spec §2.2 voice picker). Until Plan 5, the app fills this from
/// `AVSpeechSynthesisVoice`; `systemDefault` maps to the engine's language fallback.
public struct VoiceOption: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// A second row line — the voice's character for Kokoro ("Warm and intimate"), the OS language
    /// for a system voice, nil for a row with nothing more to say. `name` alone is the display name;
    /// this is never folded into it. Accent and gender are not repeated here: the accent is the
    /// sub-section the row sits in, the gender is the avatar's tint.
    public var detail: String?
    public var language: String
    public var isDefault: Bool
    public var group: VoiceGroup
    public var gender: VoiceGender?

    public init(id: String, name: String, detail: String? = nil, language: String, isDefault: Bool = false,
                group: VoiceGroup = .system, gender: VoiceGender? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
        self.language = language
        self.isDefault = isDefault
        self.group = group
        self.gender = gender
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
