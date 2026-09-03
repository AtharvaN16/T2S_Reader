import Foundation

/// The section a voice belongs to in the picker (spec §2.2). Kokoro is labelled beta while its
/// device numbers are still being taken.
public enum VoiceGroup: String, Hashable, Sendable, CaseIterable {
    case system, kokoro, cloud

    public var title: String {
        switch self {
        case .system: return "System"
        case .kokoro: return "Kokoro (beta)"
        case .cloud: return "Cloud"
        }
    }
}

/// A selectable voice (spec §2.2 voice picker). Until Plan 5, the app fills this from
/// `AVSpeechSynthesisVoice`; `systemDefault` maps to the engine's language fallback.
public struct VoiceOption: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var language: String
    public var isDefault: Bool
    public var group: VoiceGroup

    public init(id: String, name: String, language: String, isDefault: Bool = false,
                group: VoiceGroup = .system) {
        self.id = id
        self.name = name
        self.language = language
        self.isDefault = isDefault
        self.group = group
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
