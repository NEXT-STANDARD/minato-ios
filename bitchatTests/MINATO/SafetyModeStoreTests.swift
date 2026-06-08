import Testing
import Foundation
@testable import bitchat

@Suite("SafetyModeStore")
struct SafetyModeStoreTests {

    /// Deterministic battery source — returns a fixed snapshot regardless of `now`.
    private struct StubBatteryProvider: BatterySnapshotProviding {
        let snapshot: SafetyBatterySnapshot
        func currentSnapshot(now: Date) -> SafetyBatterySnapshot { snapshot }
    }

    private func makeStore(
        level: Double? = 0.8,
        state: SafetyBatteryState = .unplugged,
        lowPowerMode: Bool = false,
        epoch: TimeInterval = 1_700_000_000
    ) -> SafetyModeStore {
        let snapshot = SafetyBatterySnapshot(
            level: level,
            state: state,
            lowPowerMode: lowPowerMode,
            reportedAt: UInt64(epoch)
        )
        let provider = StubBatteryProvider(snapshot: snapshot)
        return SafetyModeStore(batteryProvider: provider, clock: { Date(timeIntervalSince1970: epoch) })
    }

    @Test("initial state is inactive, unknown status, no lastActiveAt")
    func initialState() {
        let store = makeStore()
        #expect(store.isActive == false)
        #expect(store.status == .unknown)
        #expect(store.lastActiveAt == nil)
    }

    @Test("activate turns mode on and stamps lastActiveAt")
    func activateStampsTime() {
        let store = makeStore(epoch: 1_700_000_000)
        store.activate()
        #expect(store.isActive == true)
        #expect(store.lastActiveAt == 1_700_000_000)
    }

    @Test("deactivate retains the last check-in")
    func deactivateRetainsCheckin() {
        let store = makeStore()
        store.setStatus(.needsHelp)
        store.deactivate()
        #expect(store.isActive == false)
        #expect(store.status == .needsHelp)
    }

    @Test("setStatus rebuilds the check-in with the new status and needs")
    func setStatusRebuilds() {
        let store = makeStore()

        store.setStatus(.needsHelp)
        #expect(store.status == .needsHelp)
        #expect(store.checkin.status == .needsHelp)
        #expect(store.checkin.needs == [.water, .medical, .charging])
        #expect(store.lastActiveAt != nil)

        store.setStatus(.safe)
        #expect(store.status == .safe)
        #expect(store.checkin.needs.isEmpty)
    }

    @Test("check-in carries the sampled battery snapshot and contact window")
    func checkinCarriesBattery() {
        let store = makeStore(level: 0.10, state: .unplugged)
        store.setStatus(.safe)
        #expect(store.checkin.battery.level == 0.10)
        #expect(store.checkin.battery.contactWindow == .short)
    }
}
