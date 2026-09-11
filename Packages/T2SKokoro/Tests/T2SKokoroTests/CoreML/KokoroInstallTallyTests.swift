import Testing
@testable import T2SKokoro

@Suite struct KokoroInstallTallyTests {
    @Test func theSummarySaysWhatWasFetchedCopiedRetriedAndCompiled() {
        let started = ContinuousClock().now
        var tally = KokoroInstallTally(startedAt: started)
        tally.downloaded(bytes: 100 * 1_048_576)
        tally.downloaded(bytes: 138 * 1_048_576)
        for _ in 0..<3 { tally.copied(bytes: 127 * 1_048_576) }
        tally.retried(); tally.retried()
        for _ in 0..<14 { tally.compiled(seconds: 10.05) }
        #expect(tally.summary(now: started.advanced(by: .milliseconds(612_040)))
                == "kokoro install finished: 2 files downloaded (238 MB), 3 copied from a staged twin (381 MB), 2 retries, 14 stages compiled in 140.7 s, 612.0 s in all")
    }

    @Test func aResumedInstallWithNothingLeftReportsZeros() {
        let started = ContinuousClock().now
        let tally = KokoroInstallTally(startedAt: started)
        #expect(tally.summary(now: started.advanced(by: .seconds(1)))
                == "kokoro install finished: 0 files downloaded (0 MB), 0 copied from a staged twin (0 MB), 0 retries, 0 stages compiled in 0.0 s, 1.0 s in all")
    }
}
