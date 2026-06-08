import Testing
import Foundation
@testable import bitchat

@Suite("Safety Location (E-4b)")
struct SafetyLocationTests {

    private struct StubLocationProvider: SafetyLocationProviding {
        let coarse: SafetyLocation?
        let precise: SafetyLocation?
        func coarseLocation(now: Date) -> SafetyLocation? { coarse }
        func preciseLocation(now: Date) -> SafetyLocation? { precise }
    }

    private struct StubBattery: BatterySnapshotProviding {
        func currentSnapshot(now: Date) -> SafetyBatterySnapshot {
            SafetyBatterySnapshot(level: 0.9, state: .charging, lowPowerMode: false, reportedAt: 0)
        }
    }

    private func battery() -> SafetyBatterySnapshot { StubBattery().currentSnapshot(now: Date()) }

    @Test("makeLocalPreview carries the provided location")
    func makeLocalPreviewLocation() {
        let loc = SafetyLocation(precision: .coarse, geohash: "xn76u", latitude: nil, longitude: nil, label: nil)
        let c = SafetyCheckin.makeLocalPreview(status: .safe, battery: battery(), location: loc)
        #expect(c.location.precision == .coarse)
        let ghOK = c.location.geohash == "xn76u"   // precompute (CI SILGen)
        #expect(ghOK)
    }

    @Test("makeLocalPreview defaults to undisclosed")
    func makeLocalPreviewDefault() {
        let c = SafetyCheckin.makeLocalPreview(status: .safe, battery: battery())
        #expect(c.location.precision == SafetyLocationPrecision.none)
    }

    @Test("withLocation swaps location, preserves identity")
    func withLocationPreservesIdentity() {
        let base = SafetyCheckin.makeLocalPreview(status: .needsHelp, battery: battery())
        let precise = SafetyLocation(precision: .precise, geohash: "xn76uz8w", latitude: 35.0, longitude: 139.0, label: nil)
        let updated = base.withLocation(precise)
        #expect(updated.id == base.id)
        #expect(updated.status == base.status)
        #expect(updated.needs == base.needs)
        #expect(updated.location.precision == .precise)
        let latOK = updated.location.latitude == 35.0
        let lonOK = updated.location.longitude == 139.0
        #expect(latOK)
        #expect(lonOK)
    }

    @Test("store injects coarse location into the check-in")
    func storeInjectsCoarse() {
        let coarse = SafetyLocation(precision: .coarse, geohash: "xn76u", latitude: nil, longitude: nil, label: nil)
        let store = SafetyModeStore(
            batteryProvider: StubBattery(),
            locationProvider: StubLocationProvider(coarse: coarse, precise: nil),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        store.setStatus(.safe)
        #expect(store.checkin.location.precision == .coarse)
        let ghOK = store.checkin.location.geohash == "xn76u"
        #expect(ghOK)
        // The broadcast check-in must never carry raw coordinates.
        let latNil = store.checkin.location.latitude == nil
        #expect(latNil)
    }

    @Test("store falls back to undisclosed when no location available")
    func storeFallsBackUndisclosed() {
        let store = SafetyModeStore(
            batteryProvider: StubBattery(),
            locationProvider: StubLocationProvider(coarse: nil, precise: nil),
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        store.setStatus(.safe)
        #expect(store.checkin.location.precision == SafetyLocationPrecision.none)
    }
}
