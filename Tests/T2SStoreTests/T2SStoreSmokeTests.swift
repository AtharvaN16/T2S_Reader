import Testing
import T2SCore
@testable import T2SStore

@Suite struct T2SStoreSmokeTests {
    @Test func linksAgainstCore() {
        #expect(T2SStore.coreSchemaVersion == Versions.schema)
    }
}
