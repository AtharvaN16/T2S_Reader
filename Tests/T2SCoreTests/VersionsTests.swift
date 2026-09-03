import Testing
@testable import T2SCore

@Suite struct VersionsTests {
    @Test func currentVersions() {
        #expect(Versions.schema == 1)
        #expect(Versions.segmenter == 1)
        #expect(Versions.normalizer == 2)
    }
}
