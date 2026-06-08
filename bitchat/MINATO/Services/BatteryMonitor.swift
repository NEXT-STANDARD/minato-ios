import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Battery Snapshot

/// A single reading of the device's battery, in the units the disaster
/// safety payload uses. Kept platform-neutral so the store and its tests
/// never touch UIKit.
struct BatterySnapshot: Equatable {
    /// 0...100. iOS reports in ~5% increments; `unknown` readings map to 0.
    let pct: Int
    let state: BatteryState

    /// Sentinel used when no reading is available yet (e.g. on platforms
    /// without a battery, or before monitoring is enabled).
    static let unknown = BatterySnapshot(pct: 0, state: .unknown)
}

// MARK: - Battery Monitoring

/// Abstraction over the platform battery API so `DisasterModeStore` can be
/// unit-tested with a deterministic mock and never imports UIKit itself.
protocol BatteryMonitoring {
    /// A fresh battery reading at call time.
    func currentBattery() -> BatterySnapshot
}

// MARK: - UIDevice-backed Monitor (production)

#if canImport(UIKit)
/// Reads battery level/state from `UIDevice`. Enables battery monitoring
/// lazily on first use — that global flag is required before `batteryLevel`
/// returns anything but `-1`.
final class UIDeviceBatteryMonitor: BatteryMonitoring {
    init() {
        // Safe to set repeatedly; UIKit ignores redundant assignments.
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func currentBattery() -> BatterySnapshot {
        let device = UIDevice.current
        // `batteryLevel` is 0.0...1.0, or -1.0 when monitoring is off / unknown.
        let level = device.batteryLevel
        let pct = level < 0 ? 0 : Int((level * 100).rounded())

        let state: BatteryState
        switch device.batteryState {
        case .charging:  state = .charging
        case .full:      state = .full
        case .unplugged: state = .discharging
        case .unknown:   state = .unknown
        @unknown default: state = .unknown
        }

        // An unknown level (-1) reports 0% but keeps whatever charging state
        // UIKit gave us; otherwise clamp the rounded percentage to 0...100.
        if level < 0 {
            return BatterySnapshot(pct: 0, state: state)
        }
        return BatterySnapshot(pct: max(0, min(100, pct)), state: state)
    }
}
#endif

// MARK: - Fallback Monitor (non-UIKit platforms / previews)

/// Always reports `.unknown`. Used on platforms without `UIDevice`
/// (macOS via this app's SwiftPM build) so the codebase compiles and the
/// store has a sane default. The shipping product is iOS.
struct UnknownBatteryMonitor: BatteryMonitoring {
    func currentBattery() -> BatterySnapshot { .unknown }
}

// MARK: - Platform Default

enum PlatformBatteryMonitor {
    /// The appropriate production monitor for the current platform.
    static func make() -> BatteryMonitoring {
        #if canImport(UIKit)
        return UIDeviceBatteryMonitor()
        #else
        return UnknownBatteryMonitor()
        #endif
    }
}
