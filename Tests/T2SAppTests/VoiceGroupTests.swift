import Testing
import T2SAudio
@testable import T2SApp

@Suite struct VoiceGroupTests {
    @Test func everyOptionCarriesThePickerSectionItBelongsIn() {
        #expect(VoiceOption.systemDefault.group == .system)
        #expect(VoiceGroup.allCases.map(\.title) == ["System", "Kokoro (beta)", "Cloud"])

        let store = CloudVoiceConfigurationStore(configuration: .example)
        let voices = CloudVoiceCatalog(base: BaseCatalog(), configurationStore: store).voices()
        #expect(voices.map(\.group) == [.system, .cloud])
    }
}

private struct BaseCatalog: VoiceCatalog {
    func voices() -> [VoiceOption] { [.systemDefault] }
}
