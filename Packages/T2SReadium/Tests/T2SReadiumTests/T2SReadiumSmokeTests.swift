import ReadiumShared
import Testing
import T2SCore
@testable import T2SReadium

@Suite struct T2SReadiumSmokeTests {
    @Test func linksAgainstCoreAndReadium() {
        #expect(T2SReadium.coreSchemaVersion == Versions.schema)
        #expect(MediaType.xhtml.string == "application/xhtml+xml")
    }
}
