import Foundation
import Testing
@testable import T2SCore

@Suite struct ForegroundGateTests {
    @Test func anOpenGateReturnsAtOnce() async {
        let gate = ForegroundGate(isForeground: true)
        await gate.waitUntilForeground()
        #expect(gate.isForeground)
    }

    @Test func aClosedGateHoldsUntilOpened() async throws {
        let gate = ForegroundGate(isForeground: false)
        let passed = OSAllocatedUnfairLockBox(false)
        let waiter = Task {
            await gate.waitUntilForeground()
            passed.value = true
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(passed.value == false)
        gate.set(foreground: true)
        await waiter.value
        #expect(passed.value)
    }

    @Test func aCancelledWaiterReturnsWithoutTheForeground() async {
        let gate = ForegroundGate(isForeground: false)
        let waiter = Task {
            await gate.waitUntilForeground()
            return Task.isCancelled
        }
        waiter.cancel()
        let wasCancelled = await waiter.value
        #expect(wasCancelled)
        #expect(!gate.isForeground)
    }

    @Test func closingAgainHoldsNewWaiters() async throws {
        let gate = ForegroundGate(isForeground: true)
        gate.set(foreground: false)
        let passed = OSAllocatedUnfairLockBox(false)
        let waiter = Task {
            await gate.waitUntilForeground()
            passed.value = true
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(passed.value == false)
        gate.set(foreground: true)
        await waiter.value
        #expect(passed.value)
    }
}

/// A value the test can read from any task.
final class OSAllocatedUnfairLockBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
