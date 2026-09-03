import T2SAudio

/// Adds the one active BYO cloud route to the platform voice catalog. A stored endpoint alone is
/// not enough: invalid/unsaved edits never become a selectable route.
public struct CloudVoiceCatalog: VoiceCatalog {
    private let base: any VoiceCatalog
    private let configurationStore: CloudVoiceConfigurationStore

    public init(base: any VoiceCatalog, configurationStore: CloudVoiceConfigurationStore) {
        self.base = base
        self.configurationStore = configurationStore
    }

    public func voices() -> [VoiceOption] {
        var voices = base.voices()
        guard let configuration = configurationStore.current() else { return voices }
        let id = CloudVoiceID(configuration: configuration, voice: configuration.voice).rawValue
        voices.append(VoiceOption(id: id, name: "\(configuration.voice) · Cloud", language: "Cloud"))
        return voices
    }
}
