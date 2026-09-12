import Testing
import T2SApp

@Suite struct CloudVoiceKeySeederTests {
    @Test func seedsAnEmptyStore() throws {
        let store = InMemorySecretStore()
        #expect(try CloudVoiceKeySeeder.seed(infoValue: "built-key", into: store) == true)
        #expect(try store.load() == "built-key")
    }

    @Test func leavesAStoredKeyAlone() throws {
        let store = InMemorySecretStore(value: "typed-key")
        #expect(try CloudVoiceKeySeeder.seed(infoValue: "built-key", into: store) == false)
        #expect(try store.load() == "typed-key")
    }

    /// An unset build setting reaches the plist as its own name.
    @Test func ignoresAnEmptyValueAndAnUnsetBuildSetting() throws {
        let values: [String?] = [nil, "", "  ", "$(T2S_CLOUD_VOICE_KEY)"]
        for value in values {
            let store = InMemorySecretStore()
            #expect(try CloudVoiceKeySeeder.seed(infoValue: value, into: store) == false)
            #expect(try store.load() == nil)
        }
    }
}
