import Testing
@testable import T2SKokoro

@Suite struct KokoroLoadTallyTests {
    /// The 11 Pro on 2026-09-11: four stages from the cache, three plans built.
    @Test func theSummaryLandsWithTheLastStageAndCountsThePlansBuilt() {
        let clock = ContinuousClock()
        let started = clock.now
        var tally = KokoroLoadTally(label: "main set", total: 7, startedAt: started)
        for (name, seconds) in [("f0ntrain_t600", 0.47), ("f0ntrain_t120", 0.75), ("decoder_pre_3s", 0.73),
                                ("decoder_pre_15s", 1.03), ("duration_t128", 59.46), ("decoder_har_post_3s", 59.63)] {
            #expect(tally.record(name, seconds: seconds, now: started.advanced(by: .seconds(60))) == nil)
        }
        let line = tally.record("decoder_har_post_15s", seconds: 228.35, now: started.advanced(by: .milliseconds(231_400)))
        #expect(line == "kokoro main set loaded: 7 stages in 231.4 s, 3 rebuilt (a plan built, ≥ 5 s), slowest decoder_har_post_15s 228.35 s")
    }

    @Test func aWarmLaunchReportsNothingRebuilt() {
        let started = ContinuousClock().now
        var tally = KokoroLoadTally(label: "background set on cpu", total: 2, startedAt: started)
        _ = tally.record("decoder_pre_3s", seconds: 0.5, now: started.advanced(by: .seconds(1)))
        let line = tally.record("decoder_har_post_3s", seconds: 0.9, now: started.advanced(by: .seconds(2)))
        #expect(line == "kokoro background set on cpu loaded: 2 stages in 2.0 s, 0 rebuilt (a plan built, ≥ 5 s), slowest decoder_har_post_3s 0.90 s")
    }
}
