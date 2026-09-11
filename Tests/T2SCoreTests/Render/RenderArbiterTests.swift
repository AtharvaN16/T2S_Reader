import Testing
@testable import T2SCore

@Suite struct RenderArbiterTests {
    @Test func playAheadWaiterWinsBeforePrepareAtTheNextUtteranceBoundary() async {
        let arbiter = RenderArbiter()
        await arbiter.acquire(.prepare)
        let prepareAgain = Task { await arbiter.acquire(.prepare); return "prepare" }
        let playing = Task { await arbiter.acquire(.playAhead); return "play" }
        while await arbiter.waitingCount() < 2 { await Task.yield() }
        await arbiter.release()
        #expect(await playing.value == "play")
        await arbiter.release()
        #expect(await prepareAgain.value == "prepare")
        await arbiter.release()
    }

    /// Every tier is handed the lease in declaration order — the fill tier included, which the
    /// arbiter's old literal list would have left waiting forever (Plan 18).
    @Test func everyTierIsResumedInPriorityOrder() async {
        let arbiter = RenderArbiter()
        await arbiter.acquire(.playAhead)
        let prepare = Task { await arbiter.acquire(.prepare); return "prepare" }
        let fill = Task { await arbiter.acquire(.chapterAhead); return "fill" }
        let prime = Task { await arbiter.acquire(.prime); return "prime" }
        while await arbiter.waitingCount() < 3 { await Task.yield() }
        await arbiter.release()
        #expect(await prime.value == "prime")
        #expect(await arbiter.waitingCount() == 2)
        await arbiter.release()
        #expect(await fill.value == "fill")
        #expect(await arbiter.waitingCount() == 1)
        await arbiter.release()
        #expect(await prepare.value == "prepare")
        #expect(await arbiter.waitingCount() == 0)
        await arbiter.release()
    }
}
