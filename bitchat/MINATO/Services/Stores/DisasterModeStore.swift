import Foundation
import Combine

/// Owns the local device's disaster-mode state: whether disaster mode is
/// active, the owner's chosen safety status, and the most recent battery /
/// location samples used to assemble an outbound `disaster.safety` payload.
///
/// Scope (D-2): pure, observable state plus battery sampling through an
/// injected `BatteryMonitoring`. Deliberately excludes:
/// - the periodic broadcast timer and transport wiring (added when the
///   send path is connected) — keeping timers out keeps this fully unit-
///   testable and free of the CI hangs that timer/UIKit-bound singletons
///   have caused before, and
/// - CoreLocation coupling: callers push a resolved `locationHint` in via
///   `updateLocationHint(_:)` rather than the store reaching into
///   `LocationStateManager` itself.
///
/// Threading: mutations are expected on the main actor (the consumers are
/// SwiftUI views and app-lifecycle hooks). `@Published` keeps those views
/// in sync.
///
/// See: docs/disaster-mode.md
final class DisasterModeStore: ObservableObject {
    /// Production singleton. Tests construct their own instance with a mock
    /// monitor and an injected clock instead of touching this.
    static let shared = DisasterModeStore(batteryMonitor: PlatformBatteryMonitor.make())

    // MARK: - Published State

    /// Whether disaster mode is currently active on this device.
    @Published private(set) var isActive: Bool = false

    /// The owner's safety status. Defaults to `.unknown` until they set it.
    @Published private(set) var myStatus: DisasterStatus = .unknown

    /// Most recent battery reading. Refreshed on `activate()` and `refresh()`.
    @Published private(set) var battery: BatterySnapshot

    /// Rounded place name (peacetime) or GPS-derived hint (disaster). `nil`
    /// when location is unavailable or not yet resolved.
    @Published private(set) var locationHint: String?

    /// Unix timestamp of the last owner-driven interaction (status change /
    /// explicit activation). Lets receivers tell "owner is actively using
    /// the phone" from "agent auto-broadcasting unattended".
    @Published private(set) var lastActiveAt: UInt64?

    // MARK: - Dependencies

    private let batteryMonitor: BatteryMonitoring
    private let clock: () -> Date

    // MARK: - Init

    /// - Parameters:
    ///   - batteryMonitor: source of battery readings (mock in tests).
    ///   - clock: time source for `lastActiveAt` (injectable for tests).
    init(batteryMonitor: BatteryMonitoring, clock: @escaping () -> Date = { Date() }) {
        self.batteryMonitor = batteryMonitor
        self.clock = clock
        self.battery = batteryMonitor.currentBattery()
    }

    // MARK: - Mode Lifecycle

    /// Turn disaster mode on. Counts as owner activity and pulls a fresh
    /// battery sample so the first broadcast carries current data.
    func activate() {
        isActive = true
        refresh()
        markActive()
    }

    /// Turn disaster mode off. Status and samples are retained so a later
    /// re-activation starts from the last known state.
    func deactivate() {
        isActive = false
    }

    // MARK: - Owner Input

    /// Record the owner's chosen safety status. Counts as owner activity.
    func setStatus(_ status: DisasterStatus) {
        myStatus = status
        markActive()
    }

    /// Push a freshly resolved location hint (or `nil` to clear it).
    func updateLocationHint(_ hint: String?) {
        locationHint = hint
    }

    // MARK: - Sampling

    /// Pull a fresh battery reading from the monitor.
    func refresh() {
        battery = batteryMonitor.currentBattery()
    }

    /// Stamp `lastActiveAt` with the current time. Called on owner-driven
    /// actions; exposed so app-lifecycle hooks (foreground, manual refresh)
    /// can mark activity too.
    func markActive() {
        lastActiveAt = UInt64(clock().timeIntervalSince1970)
    }

    // MARK: - Payload Assembly

    /// Build the outbound safety payload from the current state. Reads the
    /// latest cached samples; call `refresh()` first if a fresh battery
    /// reading is required.
    func currentSafetyPayload() -> DisasterSafetyPayload {
        DisasterSafetyPayload(
            status: myStatus,
            batteryPct: battery.pct,
            batteryState: battery.state,
            locationHint: locationHint,
            lastActiveAt: lastActiveAt
        )
    }
}
