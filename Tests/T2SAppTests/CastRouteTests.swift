import Foundation
import Testing
@testable import T2SApp

@Suite struct CastRouteTests {
    @Test func thePhoneItselfIsNotCasting() {
        #expect(CastRoute.castingTo([.init(kind: "Speaker", name: "Speaker")]) == nil)
        #expect(CastRoute.castingTo([.init(kind: "Receiver", name: "Receiver")]) == nil)
        #expect(CastRoute.castingTo([]) == nil)
    }

    @Test func wiredOutputsAreNotCasting() {
        #expect(CastRoute.castingTo([.init(kind: "Headphones", name: "Headphones")]) == nil)
        #expect(CastRoute.castingTo([.init(kind: "CarAudioOutput", name: "Car")]) == nil)
        #expect(CastRoute.castingTo([.init(kind: "HDMIOutput", name: "TV")]) == nil)
    }

    @Test func airPlayAndBluetoothAreCastingToTheDeviceByName() {
        #expect(CastRoute.castingTo([.init(kind: "AirPlay", name: "Living Room")]) == "Living Room")
        #expect(CastRoute.castingTo([.init(kind: "BluetoothA2DPOutput", name: "AirPods Pro")]) == "AirPods Pro")
        #expect(CastRoute.castingTo([.init(kind: "BluetoothLE", name: "Kitchen speaker")]) == "Kitchen speaker")
        #expect(CastRoute.castingTo([.init(kind: "BluetoothHFP", name: "Car kit")]) == "Car kit")
    }

    @Test func aNamelessDeviceIsNamedByItsKind() {
        #expect(CastRoute.castingTo([.init(kind: "AirPlay", name: "  ")]) == "AirPlay")
        #expect(CastRoute.castingTo([.init(kind: "BluetoothA2DPOutput", name: "")]) == "Bluetooth")
    }

    @Test func theFirstCastingOutputWins() {
        let outputs: [CastRoute.Output] = [
            .init(kind: "Speaker", name: "Speaker"),
            .init(kind: "AirPlay", name: "Apple TV"),
            .init(kind: "BluetoothA2DPOutput", name: "AirPods Pro"),
        ]
        #expect(CastRoute.castingTo(outputs) == "Apple TV")
    }
}
