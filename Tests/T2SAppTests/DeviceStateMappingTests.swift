import Testing
import T2SCore
@testable import T2SApp

@Suite struct DeviceStateMappingTests {
    func signals(battery: BatteryState = .unplugged, thermal: ThermalLevel = .nominal, lowPower: Bool = false,
                 bytes: Int = 0, capacity: Int = 1_000_000_000) -> DeviceSignals {
        DeviceSignals(batteryState: battery, thermal: thermal, lowPowerMode: lowPower, storeBytes: bytes, storeCapacityBytes: capacity)
    }

    @Test func chargingAndFullCountAsCharging() {
        #expect(DeviceStateMapping.deviceState(signals(battery: .charging)).charging)
        #expect(DeviceStateMapping.deviceState(signals(battery: .full)).charging)
        #expect(!DeviceStateMapping.deviceState(signals(battery: .unplugged)).charging)
        #expect(!DeviceStateMapping.deviceState(signals(battery: .unknown)).charging)
    }

    @Test func thermalSeriousAndAbove() {
        #expect(!DeviceStateMapping.deviceState(signals(thermal: .fair)).thermalSerious)
        #expect(DeviceStateMapping.deviceState(signals(thermal: .serious)).thermalSerious)
        #expect(DeviceStateMapping.deviceState(signals(thermal: .critical)).thermalSerious)
    }

    @Test func lowPowerAndStoreHeadroom() {
        #expect(DeviceStateMapping.deviceState(signals(lowPower: true)).lowPowerMode)
        let headroom = DeviceStateMapping.storeFullHeadroomBytes
        #expect(!DeviceStateMapping.deviceState(signals(bytes: 1_000_000_000 - headroom - 1)).storeFull)
        #expect(DeviceStateMapping.deviceState(signals(bytes: 1_000_000_000 - headroom + 1)).storeFull)
        #expect(DeviceStateMapping.deviceState(signals(bytes: 5, capacity: 0)).storeFull)
        #expect(DeviceStateMapping.deviceState(signals()) == DeviceState.unplugged)
    }
}
