import Testing
import T2SCore
@testable import T2SLibrary

@Suite struct T2SLibrarySmokeTests {
    @Test func linksAgainstCore() {
        #expect(T2SLibrary.coreSchemaVersion == Versions.schema)
    }
}
