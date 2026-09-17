import Foundation
import Testing
@testable import T2SApp

@Suite struct IslandGeometryTests {
    @Test func knownIslandDevicesAreRecognised() {
        // Every identifier in `islandModels`, in its order: 14 Pro / Pro Max, 15 / Plus,
        // 15 Pro / Pro Max, 16 / Plus, 16 Pro / Pro Max, 17 Pro / Pro Max, 17, Air,
        // 18 Pro / Pro Max.
        for machine in ["iPhone15,2", "iPhone15,3", "iPhone15,4", "iPhone15,5",
                        "iPhone16,1", "iPhone16,2",
                        "iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2",
                        "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4",
                        "iPhone19,2", "iPhone19,3"] {
            #expect(IslandGeometry.hasIsland(machine: machine), "\(machine) has an island")
        }
    }

    @Test func notchAndOlderDevicesAreNot() {
        // 11 Pro (the owner's test phone), SE 3, and the 16e/17e — which have notches, not islands.
        for machine in ["iPhone12,3", "iPhone14,6", "iPhone17,5", "iPhone18,5"] {
            #expect(!IslandGeometry.hasIsland(machine: machine), "\(machine) has no island")
        }
    }

    /// The fail-safe, and the whole reason the list is allowed to be incomplete: a phone that
    /// ships after this list was written gets the plain card, not a capsule through its notch.
    @Test func unknownIdentifiersFallBackToNoIsland() {
        #expect(!IslandGeometry.hasIsland(machine: "iPhone99,1"))
        #expect(!IslandGeometry.hasIsland(machine: ""))
        #expect(!IslandGeometry.hasIsland(machine: "arm64"))
    }
}
