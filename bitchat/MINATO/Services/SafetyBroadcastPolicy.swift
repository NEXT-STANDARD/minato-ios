import Foundation

/// Decides how often a disaster-mode safety check-in is re-broadcast, based on
/// battery state. Re-broadcasting keeps a check-in fresh across the mesh, but
/// must back off as the battery drains (and when Low Power Mode is on) so the
/// device survives longer in a disaster. Pure and deterministic for testing.
///
/// Scope (E-3b). See: docs/MINATO-disaster-mode.md
enum SafetyBroadcastPolicy {
    /// Re-broadcast interval at healthy battery (seconds).
    static let baseInterval: TimeInterval = 300   // 5 min
    /// Upper bound regardless of battery state (seconds).
    static let maxInterval: TimeInterval = 1800   // 30 min

    /// Re-broadcast interval for the given battery snapshot. Never stops
    /// entirely — a dying phone's safety status is the most important to keep
    /// fresh — but slows down as the contact window shrinks and under Low
    /// Power Mode, capped at `maximum`.
    static func interval(
        for battery: SafetyBatterySnapshot,
        base: TimeInterval = baseInterval,
        maximum: TimeInterval = maxInterval
    ) -> TimeInterval {
        let windowFactor: Double
        switch battery.contactWindow {
        case .long:    windowFactor = 1   // charging/full or >= 40%
        case .medium:  windowFactor = 2   // < 40%
        case .short:   windowFactor = 4   // < 15%
        case .unknown: windowFactor = 2   // be conservative
        }
        let lowPowerFactor: Double = battery.lowPowerMode ? 2 : 1
        return min(base * windowFactor * lowPowerFactor, maximum)
    }
}
