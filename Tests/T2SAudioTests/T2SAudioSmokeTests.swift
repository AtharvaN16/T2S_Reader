import Testing
import T2SCore
@testable import T2SAudio

@Suite struct T2SAudioSmokeTests {
    @Test func linksAgainstCore() {
        #expect(T2SAudio.coreSchemaVersion == Versions.schema)
    }
}
