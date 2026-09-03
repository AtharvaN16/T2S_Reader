// App/T2SReader/System/DeviceMonitor.swift
import Foundation
import Observation
import T2SApp
import T2SCore
import UIKit

/// Reads the signals `DeviceStateMapping` needs (spec §3.4.1 guards) and republishes them whenever
/// iOS says they changed. The mapping itself is pure and tested in `T2SApp`.
@MainActor
@Observable
final class DeviceMonitor {
    private(set) var signals = DeviceSignals(batteryState: .unknown, thermal: .nominal, lowPowerMode: false, storeBytes: 0, storeCapacityBytes: 1)
    private let audioStore: FileAudioStore
    private var observers: [NSObjectProtocol] = []

    init(audioStore: FileAudioStore) { self.audioStore = audioStore }

    var deviceState: DeviceState { DeviceStateMapping.deviceState(signals) }

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let names: [Notification.Name] = [UIDevice.batteryStateDidChangeNotification, ProcessInfo.thermalStateDidChangeNotification,
                                          .NSProcessInfoPowerStateDidChange, UIApplication.didBecomeActiveNotification]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func refresh() {
        Task {
            let stats = await audioStore.stats()
            signals = DeviceSignals(batteryState: Self.battery(UIDevice.current.batteryState),
                                    thermal: Self.thermal(ProcessInfo.processInfo.thermalState),
                                    lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                    storeBytes: stats.bytes, storeCapacityBytes: stats.capacityBytes)
        }
    }

    private static func battery(_ state: UIDevice.BatteryState) -> BatteryState {
        switch state {
        case .charging: return .charging
        case .full: return .full
        case .unplugged: return .unplugged
        default: return .unknown
        }
    }

    private static func thermal(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .serious
        }
    }
}
