import Testing
import T2SCore
@testable import T2SApp

@Suite struct T2SAppSmokeTests {
    @Test func linksAgainstCore() {
        #expect(T2SApp.coreSchemaVersion == Versions.schema)
    }
}
