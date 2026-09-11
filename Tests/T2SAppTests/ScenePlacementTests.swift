import Testing
@testable import T2SApp

@Suite struct ScenePlacementTests {
    /// Only `.background` places in the background. `.inactive` — a Control Center pull, a
    /// notification banner, the app switcher — must place in the foreground even though it closes
    /// the foreground gate, or a streamed head parks on the gate or renders in discarded 3 s pieces
    /// for every such interruption (2026-09-11 GPU-path review §2.3, §5 item 3 — R4).
    @Test func placesInBackgroundOnlyForBackground() {
        #expect(!ScenePlacement.placesInBackground(phase: .active))
        #expect(!ScenePlacement.placesInBackground(phase: .inactive))
        #expect(ScenePlacement.placesInBackground(phase: .background))
    }
}
