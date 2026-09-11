import Testing
@testable import T2SKokoro

@Suite struct KokoroComputeUnitsTests {
    /// The split is by chip generation, from the two phones measured (see `defaultPolicy`): the A13
    /// on the CPU, the A19 on the GPU, and the unmeasured generations between them on the measured
    /// path. Anything that is not an iPhone — an iPad, the simulator's "arm64", a Mac — gets the CPU.
    @Test(arguments: [
        ("iPhone12,3", KokoroComputeUnits.cpu),   // iPhone 11 Pro, A13: plans in 206 s, RTF 0.18
        ("iPhone13,2", KokoroComputeUnits.cpu),   // iPhone 12, A14: unmeasured
        ("iPhone17,1", KokoroComputeUnits.cpu),   // iPhone 16 Pro, A18 Pro: unmeasured
        ("iPhone18,1", KokoroComputeUnits.cpuAndGPU),   // iPhone 17 Pro, A19 Pro: the CPU never builds the 15 s generator
        ("iPhone19,4", KokoroComputeUnits.cpuAndGPU),   // whatever follows the A19
        ("iPad8,9", KokoroComputeUnits.cpu),
        ("arm64", KokoroComputeUnits.cpu),
        ("", KokoroComputeUnits.cpu),
    ])
    func thePolicyFollowsTheChipGeneration(machine: String, expected: KokoroComputeUnits) {
        #expect(KokoroComputeUnits.defaultPolicy(machine: machine) == expected)
    }

    /// The GPU path compiles its plans through MPSGraph, which ran a 4 GB phone out of memory
    /// (`std::bad_alloc`, the 11 Pro on 2026-09-10): a phone under the floor keeps the CPU whatever
    /// was asked — the chip policy and the `kokoro.computeUnits` override alike.
    @Test(arguments: [
        (KokoroComputeUnits.cpuAndGPU, UInt64(3_900_000_000), KokoroComputeUnits.cpu),    // 4 GB phone: no
        (KokoroComputeUnits.all, UInt64(3_900_000_000), KokoroComputeUnits.cpu),
        (KokoroComputeUnits.cpuAndGPU, UInt64(5_700_000_000), KokoroComputeUnits.cpuAndGPU),   // 6 GB phone: yes
        (KokoroComputeUnits.cpuAndGPU, UInt64(11_800_000_000), KokoroComputeUnits.cpuAndGPU),  // 12 GB: yes
        (KokoroComputeUnits.cpu, UInt64(3_900_000_000), KokoroComputeUnits.cpu),
    ])
    func theGPUNeedsMemory(requested: KokoroComputeUnits, physicalMemory: UInt64, expected: KokoroComputeUnits) {
        #expect(KokoroComputeUnits.permitted(requested, physicalMemory: physicalMemory) == expected)
    }

    @Test func theChipPolicyRespectsTheMemoryFloor() {
        #expect(KokoroComputeUnits.defaultPolicy(machine: "iPhone18,1", physicalMemory: 3_900_000_000) == .cpu)
        #expect(KokoroComputeUnits.defaultPolicy(machine: "iPhone18,1", physicalMemory: 11_800_000_000) == .cpuAndGPU)
    }

    @Test func thisMachineReportsAModelName() {
        #expect(!KokoroComputeUnits.hardwareModel().isEmpty)
    }
}
