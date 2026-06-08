import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

/// Produces a `SafetyLocation` from the device's current coordinate (E-4b).
/// Protocol form keeps it free of CoreLocation so it can be mocked in tests,
/// mirroring `BatterySnapshotProviding`.
protocol SafetyLocationProviding {
    /// City-level geohash only (safe for the open BLE broadcast). `nil` when
    /// location is unavailable or permission is not granted.
    func coarseLocation(now: Date) -> SafetyLocation?
    /// Precise lat/long + geohash. Only ever attached to encrypted, directed
    /// sends to emergency-override contacts — never the open broadcast. `nil`
    /// when unavailable / not permitted.
    func preciseLocation(now: Date) -> SafetyLocation?
}

#if canImport(CoreLocation)
struct SafetyLocationProvider: SafetyLocationProviding {
    /// City-level geohash (~few km) — matches the app's existing public
    /// geohash-presence privacy bar (`GeohashChannelLevel.city`).
    static let coarsePrecision = 5
    /// Building-level geohash (~tens of m) for precise directed sharing.
    static let precisePrecision = 8

    private let manager: LocationStateManager

    init(manager: LocationStateManager = .shared) {
        self.manager = manager
    }

    func coarseLocation(now: Date) -> SafetyLocation? {
        guard let coord = authorizedCoordinate else { return nil }
        let geohash = Geohash.encode(
            latitude: coord.latitude,
            longitude: coord.longitude,
            precision: Self.coarsePrecision
        )
        guard !geohash.isEmpty else { return nil }
        return SafetyLocation(precision: .coarse, geohash: geohash, latitude: nil, longitude: nil, label: nil)
    }

    func preciseLocation(now: Date) -> SafetyLocation? {
        guard let coord = authorizedCoordinate else { return nil }
        let geohash = Geohash.encode(
            latitude: coord.latitude,
            longitude: coord.longitude,
            precision: Self.precisePrecision
        )
        return SafetyLocation(
            precision: .precise,
            geohash: geohash.isEmpty ? nil : geohash,
            latitude: coord.latitude,
            longitude: coord.longitude,
            label: nil
        )
    }

    /// Current coordinate only when location permission is authorized.
    private var authorizedCoordinate: CLLocationCoordinate2D? {
        guard manager.permissionState == .authorized else { return nil }
        return manager.currentCoordinate
    }
}
#endif
