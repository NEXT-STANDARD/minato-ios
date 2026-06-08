import Foundation

#if canImport(UIKit)
import UIKit
#endif

protocol BatterySnapshotProviding {
    func currentSnapshot(now: Date) -> SafetyBatterySnapshot
}

struct BatterySnapshotProvider: BatterySnapshotProviding {
    func currentSnapshot(now: Date = Date()) -> SafetyBatterySnapshot {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        let level = rawLevel >= 0 ? Double(rawLevel) : nil
        let state: SafetyBatteryState
        switch UIDevice.current.batteryState {
        case .charging:
            state = .charging
        case .full:
            state = .full
        case .unplugged:
            state = .unplugged
        case .unknown:
            fallthrough
        @unknown default:
            state = .unknown
        }
        #else
        let level: Double? = nil
        let state: SafetyBatteryState = .unknown
        #endif

        return SafetyBatterySnapshot(
            level: level,
            state: state,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            reportedAt: UInt64(now.timeIntervalSince1970)
        )
    }
}
