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
}
