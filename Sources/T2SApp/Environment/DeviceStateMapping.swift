import Foundation
import T2SCore

public enum BatteryState: Hashable, Sendable { case unknown, unplugged, charging, full }
public enum ThermalLevel: Hashable, Sendable { case nominal, fair, serious, critical }

/// Raw signals the app target reads from UIKit and ProcessInfo; kept UIKit-free so the mapping is testable.
public struct DeviceSignals: Hashable, Sendable {
    public var batteryState: BatteryState
    public var thermal: ThermalLevel
    public var lowPowerMode: Bool
    public var storeBytes: Int
    public var storeCapacityBytes: Int

    public init(batteryState: BatteryState, thermal: ThermalLevel, lowPowerMode: Bool, storeBytes: Int, storeCapacityBytes: Int) {
        self.batteryState = batteryState
        self.thermal = thermal
        self.lowPowerMode = lowPowerMode
        self.storeBytes = storeBytes
        self.storeCapacityBytes = storeCapacityBytes
    }
}

/// Spec §3.4.1 guards: Prepare stops on unplug, at thermal `.serious` or above, in Low Power Mode,
/// and at the cache cap. "At the cap" means less than one hour of AAC headroom left.
public enum DeviceStateMapping {
    /// 32 kbps × 3600 s ≈ 14 MB; twice that is the headroom Prepare needs to be worth starting.
    public static let storeFullHeadroomBytes = 32 * 1024 * 1024

    public static func deviceState(_ s: DeviceSignals) -> DeviceState {
        DeviceState(charging: s.batteryState == .charging || s.batteryState == .full,
                    thermalSerious: s.thermal == .serious || s.thermal == .critical,
                    lowPowerMode: s.lowPowerMode,
                    storeFull: s.storeCapacityBytes - s.storeBytes < storeFullHeadroomBytes)
    }
}
