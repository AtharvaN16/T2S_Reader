import Testing
@testable import T2SCore

@Suite struct VersionsTests {
    @Test func versionsStartAtOne() {
        #expect(Versions.schema == 1)
        #expect(Versions.segmenter == 1)
        #expect(Versions.normalizer == 1)
    }
}
