import Foundation
import Testing
@testable import T2SCore

@Suite struct CPUBudgetTests {
    /// A budget over a clock and a CPU meter the test moves by hand; `sleeper` advances the clock
    /// by what was asked and records it, so a wait "passes" time without passing any.
    struct Harness {
        let gate: ForegroundGate
        let clock = ManualTimeSource()
        let cpu = OSAllocatedUnfairLockBox<TimeInterval>(0)
        let sleeps = OSAllocatedUnfairLockBox<[TimeInterval]>([])
        let budget: CPUBudget

        init(foreground: Bool, window: TimeInterval = 60, budgetSeconds: TimeInterval = 36) {
            gate = ForegroundGate(isForeground: foreground)
            let clock = self.clock, cpu = self.cpu, sleeps = self.sleeps
            budget = CPUBudget(gate: gate, windowSeconds: window, budgetSeconds: budgetSeconds,
                               clock: { clock.now() }, cpuTime: { cpu.value },
                               sleeper: { seconds in sleeps.value.append(seconds); clock.advance(by: seconds) })
        }
    }

    @Test func theForegroundNeverWaits() async {
        let h = Harness(foreground: true)
        h.clock.set(50)
        h.cpu.value = 50                                            // a whole window of CPU, and then some
        let waited = await h.budget.waitForHeadroom(estimatedSeconds: 10)
        #expect(waited == 0)
        #expect(h.sleeps.value.isEmpty)
    }

    @Test func aQuietBackgroundProceeds() async {
        let h = Harness(foreground: false)
        h.clock.set(30)
        h.cpu.value = 5
        let waited = await h.budget.waitForHeadroom(estimatedSeconds: 10)
        #expect(waited == 0)
    }

    /// Forty seconds of CPU since the process started, all inside the window: the render waits
    /// until that burst has aged out of the window — the whole window, since the budget cannot
    /// know when inside it the CPU was spent — and then goes.
    @Test func aBackgroundBurstWaitsForTheWindowToClear() async {
        let h = Harness(foreground: false)
        h.clock.set(50)
        h.cpu.value = 40
        let waited = await h.budget.waitForHeadroom(estimatedSeconds: 5)
        #expect(waited > 0)
        #expect(!h.sleeps.value.isEmpty)
        // The burst (at wall 50) has left the window once the clock passes 110.
        #expect(h.clock.now() >= 110)
        #expect(h.clock.now() < 130)
        // With the window clear, the same call is free.
        let again = await h.budget.waitForHeadroom(estimatedSeconds: 5)
        #expect(again == 0)
    }

    /// The window counts what is *in* it: CPU spent before the window's horizon is not charged.
    @Test func cpuOlderThanTheWindowIsNotCharged() async {
        let h = Harness(foreground: false)
        h.cpu.value = 40
        h.clock.set(10)
        _ = h.budget.usedInWindow()                                 // a sample at wall 10, cpu 40
        h.clock.set(80)                                             // 70 s later, nothing spent since
        #expect(h.budget.usedInWindow() == 0)
        h.cpu.value = 42
        #expect(h.budget.usedInWindow() == 2)
    }

    @Test func returningToTheForegroundEndsTheWait() async {
        let h = Harness(foreground: false)
        h.clock.set(50)
        h.cpu.value = 40
        let gate = h.gate
        let opener = Task {
            try? await Task.sleep(for: .milliseconds(30))
            gate.set(foreground: true)
        }
        let waited = await h.budget.waitForHeadroom(estimatedSeconds: 5)
        await opener.value
        // It slept in slices and stopped as soon as the gate opened: well short of a full window.
        #expect(waited < 60 || h.gate.isForeground)
    }
}
