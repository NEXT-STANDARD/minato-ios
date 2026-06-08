import Foundation
import Testing
@testable import bitchat

// MARK: - Test Doubles

/// Battery monitor whose reading the test controls.
private final class MockBatteryMonitor: BatteryMonitoring {
    var snapshot: BatterySnapshot
    private(set) var readCount = 0

    init(_ snapshot: BatterySnapshot = BatterySnapshot(pct: 50, state: .discharging)) {
        self.snapshot = snapshot
    }

    func currentBattery() -> BatterySnapshot {
        readCount += 1
        return snapshot
    }
}

/// Mutable clock for deterministic `lastActiveAt` assertions.
private final class FakeClock {
    var now: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_715_000_000)) { now = start }
    func date() -> Date { now }
}

// MARK: - DisasterModeStore Tests

@MainActor
@Suite("DisasterModeStore Tests")
struct DisasterModeStoreTests {

    private func makeStore(
        battery: BatterySnapshot = BatterySnapshot(pct: 50, state: .discharging),
        clock: FakeClock = FakeClock()
    ) -> (DisasterModeStore, MockBatteryMonitor, FakeClock) {
        let monitor = MockBatteryMonitor(battery)
        let store = DisasterModeStore(batteryMonitor: monitor, clock: clock.date)
        return (store, monitor, clock)
    }

    // MARK: - Initial state

    @Test("initial state is inactive, unknown status, no activity stamp")
    func initialState() {
        let (store, monitor, _) = makeStore(battery: BatterySnapshot(pct: 80, state: .charging))
        #expect(store.isActive == false)
        #expect(store.myStatus == .unknown)
        #expect(store.locationHint == nil)
        #expect(store.lastActiveAt == nil)
        // Battery is sampled once at init.
        #expect(store.battery == BatterySnapshot(pct: 80, state: .charging))
        #expect(monitor.readCount == 1)
    }

    // MARK: - Activate / deactivate

    @Test("activate turns on, refreshes battery, and stamps activity")
    func activateRefreshesAndStamps() {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_715_000_123))
        let (store, monitor, _) = makeStore(
            battery: BatterySnapshot(pct: 40, state: .discharging),
            clock: clock
        )
        // Battery changes between init and activation.
        monitor.snapshot = BatterySnapshot(pct: 35, state: .discharging)

        store.activate()

        #expect(store.isActive == true)
        #expect(store.battery == BatterySnapshot(pct: 35, state: .discharging))
        #expect(store.lastActiveAt == 1_715_000_123)
        // init + activate's refresh = 2 reads.
        #expect(monitor.readCount == 2)
    }

    @Test("deactivate turns off but retains status and samples")
    func deactivateRetainsState() {
        let (store, _, _) = makeStore(battery: BatterySnapshot(pct: 90, state: .full))
        store.setStatus(.ok)
        store.updateLocationHint("東京駅周辺")
        store.activate()

        store.deactivate()

        #expect(store.isActive == false)
        #expect(store.myStatus == .ok)
        #expect(store.locationHint == "東京駅周辺")
        #expect(store.battery == BatterySnapshot(pct: 90, state: .full))
    }

    // MARK: - Owner input

    @Test("setStatus updates status and stamps activity from the clock")
    func setStatusStampsActivity() {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_715_000_500))
        let (store, _, _) = makeStore(clock: clock)

        store.setStatus(.needsHelp)

        #expect(store.myStatus == .needsHelp)
        #expect(store.lastActiveAt == 1_715_000_500)
    }

    @Test("each owner action advances lastActiveAt with the clock")
    func lastActiveAdvancesWithClock() {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let (store, _, _) = makeStore(clock: clock)

        store.setStatus(.ok)
        #expect(store.lastActiveAt == 1_000)

        clock.now = Date(timeIntervalSince1970: 2_000)
        store.setStatus(.injured)
        #expect(store.lastActiveAt == 2_000)
    }

    @Test("updateLocationHint sets and clears the hint")
    func updateLocationHint() {
        let (store, _, _) = makeStore()
        store.updateLocationHint("自宅")
        #expect(store.locationHint == "自宅")
        store.updateLocationHint(nil)
        #expect(store.locationHint == nil)
    }

    // MARK: - Sampling

    @Test("refresh pulls a new battery reading from the monitor")
    func refreshPullsNewReading() {
        let (store, monitor, _) = makeStore(battery: BatterySnapshot(pct: 60, state: .discharging))
        #expect(store.battery.pct == 60)

        monitor.snapshot = BatterySnapshot(pct: 55, state: .discharging)
        store.refresh()

        #expect(store.battery == BatterySnapshot(pct: 55, state: .discharging))
    }

    // MARK: - Payload assembly

    @Test("currentSafetyPayload assembles all fields from current state")
    func payloadAssembly() {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_715_000_900))
        let (store, _, _) = makeStore(
            battery: BatterySnapshot(pct: 23, state: .charging),
            clock: clock
        )
        store.setStatus(.ok)
        store.updateLocationHint("渋谷駅周辺")

        let payload = store.currentSafetyPayload()

        #expect(payload.status == .ok)
        #expect(payload.batteryPct == 23)
        #expect(payload.batteryState == .charging)
        #expect(payload.locationHint == "渋谷駅周辺")
        #expect(payload.lastActiveAt == 1_715_000_900)
    }

    @Test("currentSafetyPayload round-trips through the wire context form")
    func payloadRoundTripsThroughContext() throws {
        let (store, _, _) = makeStore(battery: BatterySnapshot(pct: 8, state: .discharging))
        store.setStatus(.needsHelp)
        store.updateLocationHint("避難所A")

        let payload = store.currentSafetyPayload()
        let decoded = try #require(DisasterSafetyPayload.from(context: payload.toContext()))
        #expect(decoded == payload)
    }

    @Test("payload before any owner input reports unknown status and no optional fields")
    func payloadDefaults() {
        let (store, _, _) = makeStore(battery: BatterySnapshot(pct: 0, state: .unknown))
        let payload = store.currentSafetyPayload()

        #expect(payload.status == .unknown)
        #expect(payload.batteryPct == 0)
        #expect(payload.batteryState == .unknown)
        #expect(payload.locationHint == nil)
        #expect(payload.lastActiveAt == nil)
    }
}
