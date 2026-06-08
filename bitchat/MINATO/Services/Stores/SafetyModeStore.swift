import Foundation
import Combine

/// Owns the local device's disaster-mode state for the Safety* track:
/// whether disaster mode is active, the owner's current safety check-in
/// (status + battery + needs), and the timestamp of the last owner-driven
/// interaction.
///
/// Scope (D-3): pure, observable state plus battery sampling through an
/// injected `BatterySnapshotProviding`. Deliberately excludes the periodic
/// broadcast timer, transport wiring, and CoreLocation coupling — keeping
/// timers/UIKit singletons out keeps this fully unit-testable and free of
/// the CI hangs that timer-bound singletons have caused before. MINATO
/// payload encoding and the mesh send path land in Phase 2 (E-2/E-3).
///
/// Threading: mutations are expected on the main actor (consumers are
/// SwiftUI views and app-lifecycle hooks). `@Published` keeps views in sync.
///
/// See: docs/MINATO-disaster-mode.md
final class SafetyModeStore: ObservableObject {
    /// Production singleton. Tests construct their own instance with a mock
    /// provider and an injected clock instead of touching this.
    static let shared = SafetyModeStore(
        batteryProvider: BatterySnapshotProvider(),
        locationProvider: SafetyLocationProvider()
    )

    // MARK: - Published State

    /// Whether disaster mode is currently active on this device.
    @Published private(set) var isActive: Bool = false

    /// The current local safety check-in (status, battery, needs, …).
    /// Rebuilt whenever the owner changes status or a refresh is requested.
    @Published private(set) var checkin: SafetyCheckin

    /// Unix timestamp of the last owner-driven interaction (status change /
    /// explicit activation). Lets receivers tell "owner is actively using
    /// the phone" from "agent auto-broadcasting unattended".
    @Published private(set) var lastActiveAt: UInt64?

    // MARK: - Dependencies

    private let batteryProvider: BatterySnapshotProviding
    private let locationProvider: SafetyLocationProviding?
    private let clock: () -> Date

    // MARK: - Init

    /// - Parameters:
    ///   - batteryProvider: source of battery readings (mock in tests).
    ///   - locationProvider: source of coarse location (nil = no location;
    ///     tests omit it, production injects `SafetyLocationProvider`).
    ///   - clock: time source (injectable for deterministic tests).
    init(
        batteryProvider: BatterySnapshotProviding,
        locationProvider: SafetyLocationProviding? = nil,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.batteryProvider = batteryProvider
        self.locationProvider = locationProvider
        self.clock = clock
        let now = clock()
        let snapshot = batteryProvider.currentSnapshot(now: now)
        let location = locationProvider?.coarseLocation(now: now) ?? .undisclosed
        self.checkin = SafetyCheckin.makeLocalPreview(status: .unknown, battery: snapshot, location: location, now: now)
    }

    // MARK: - Derived

    /// The owner's currently selected safety status.
    var status: SafetyStatus { checkin.status }

    // MARK: - Mode Lifecycle

    /// Turn disaster mode on. Counts as owner activity and pulls a fresh
    /// battery sample so the first preview carries current data.
    func activate() {
        isActive = true
        refresh()
        markActive()
    }

    /// Turn disaster mode off. The check-in is retained so a later
    /// re-activation starts from the last known state.
    func deactivate() {
        isActive = false
    }

    // MARK: - Owner Input

    /// Record the owner's chosen safety status and rebuild the check-in.
    /// Counts as owner activity.
    func setStatus(_ status: SafetyStatus) {
        rebuild(status: status)
        markActive()
    }

    // MARK: - Sampling

    /// Re-sample battery and rebuild the local check-in for the current status.
    func refresh() {
        rebuild(status: checkin.status)
    }

    /// Stamp `lastActiveAt` with the current time. Exposed so app-lifecycle
    /// hooks (foreground, manual refresh) can mark activity too.
    func markActive() {
        lastActiveAt = UInt64(clock().timeIntervalSince1970)
    }

    // MARK: - Private

    private func rebuild(status: SafetyStatus) {
        let now = clock()
        let snapshot = batteryProvider.currentSnapshot(now: now)
        // Coarse (city-level) location only — precise location is attached per
        // recipient at send time, never on the broadcast check-in (E-4b).
        let location = locationProvider?.coarseLocation(now: now) ?? .undisclosed
        checkin = SafetyCheckin.makeLocalPreview(status: status, battery: snapshot, location: location, now: now)
    }
}
