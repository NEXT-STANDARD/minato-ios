import Testing
import Foundation
@testable import bitchat

@Suite("Safety Broadcast Throttling (E-3b)")
struct SafetyBroadcastSchedulerTests {

    // MARK: - Helpers

    private func battery(_ window: SafetyContactWindow, lowPower: Bool = false) -> SafetyBatterySnapshot {
        SafetyBatterySnapshot(
            level: nil,
            state: .unknown,
            lowPowerMode: lowPower,
            reportedAt: 0,
            contactWindow: window
        )
    }

    private func sampleCheckin() -> SafetyCheckin {
        SafetyCheckin.makeLocalPreview(
            status: .safe,
            battery: SafetyBatterySnapshot(level: 0.9, state: .charging, lowPowerMode: false, reportedAt: 0)
        )
    }

    private final class StubBatteryProvider: BatterySnapshotProviding {
        var snapshot: SafetyBatterySnapshot
        init(_ snapshot: SafetyBatterySnapshot) { self.snapshot = snapshot }
        func currentSnapshot(now: Date) -> SafetyBatterySnapshot { snapshot }
    }

    private final class MockTimer: SafetyBroadcastTimerProtocol {
        let handler: () -> Void
        private(set) var isValid = true
        private(set) var invalidateCount = 0
        init(handler: @escaping () -> Void) { self.handler = handler }
        func invalidate() { invalidateCount += 1; isValid = false }
        func fire() { handler() }
    }

    private final class MockScheduler {
        private(set) var intervals: [TimeInterval] = []
        private(set) var timers: [MockTimer] = []
        func schedule(interval: TimeInterval, handler: @escaping () -> Void) -> SafetyBroadcastTimerProtocol {
            intervals.append(interval)
            let timer = MockTimer(handler: handler)
            timers.append(timer)
            return timer
        }
    }

    // MARK: - Policy

    @Test("interval backs off with contact window and low power mode")
    func policyIntervals() {
        #expect(SafetyBroadcastPolicy.interval(for: battery(.long)) == 300)
        #expect(SafetyBroadcastPolicy.interval(for: battery(.medium)) == 600)
        #expect(SafetyBroadcastPolicy.interval(for: battery(.short)) == 1200)
        #expect(SafetyBroadcastPolicy.interval(for: battery(.unknown)) == 600)
        #expect(SafetyBroadcastPolicy.interval(for: battery(.long, lowPower: true)) == 600)
        #expect(SafetyBroadcastPolicy.interval(for: battery(.medium, lowPower: true)) == 1200)
        // short + low power would be 2400 but is capped at the 1800 maximum.
        #expect(SafetyBroadcastPolicy.interval(for: battery(.short, lowPower: true)) == 1800)
    }

    // MARK: - Scheduler

    @Test("start schedules the next broadcast at the throttled interval (no immediate send)")
    func startSchedulesNext() {
        let mock = MockScheduler()
        var sendCount = 0
        let scheduler = SafetyBroadcastScheduler(
            batteryProvider: StubBatteryProvider(battery(.medium)),
            currentCheckin: { self.sampleCheckin() },
            broadcast: { _ in sendCount += 1 },
            scheduleTimer: mock.schedule
        )

        scheduler.start()

        #expect(scheduler.isRunning)
        #expect(mock.intervals == [600])
        #expect(sendCount == 0)
    }

    @Test("each tick broadcasts and reschedules")
    func tickBroadcastsAndReschedules() {
        let mock = MockScheduler()
        var sendCount = 0
        var lastID: String?
        let checkin = sampleCheckin()
        let scheduler = SafetyBroadcastScheduler(
            batteryProvider: StubBatteryProvider(battery(.long)),
            currentCheckin: { checkin },
            broadcast: { sendCount += 1; lastID = $0.id },
            scheduleTimer: mock.schedule
        )

        scheduler.start()
        mock.timers[0].fire()

        #expect(sendCount == 1)
        #expect(lastID == checkin.id)
        #expect(mock.intervals == [300, 300])
    }

    @Test("interval adapts when battery state changes between ticks")
    func intervalAdaptsToBattery() {
        let mock = MockScheduler()
        let stub = StubBatteryProvider(battery(.long))
        let scheduler = SafetyBroadcastScheduler(
            batteryProvider: stub,
            currentCheckin: { self.sampleCheckin() },
            broadcast: { _ in },
            scheduleTimer: mock.schedule
        )

        scheduler.start()
        #expect(mock.intervals == [300])

        stub.snapshot = battery(.short) // battery drained
        mock.timers[0].fire()
        #expect(mock.intervals == [300, 1200])
    }

    @Test("stop invalidates the pending timer and halts the loop")
    func stopHalts() {
        let mock = MockScheduler()
        let scheduler = SafetyBroadcastScheduler(
            batteryProvider: StubBatteryProvider(battery(.medium)),
            currentCheckin: { self.sampleCheckin() },
            broadcast: { _ in },
            scheduleTimer: mock.schedule
        )

        scheduler.start()
        scheduler.stop()

        #expect(scheduler.isRunning == false)
        #expect(mock.timers[0].invalidateCount == 1)
    }

    @Test("start is idempotent")
    func startIdempotent() {
        let mock = MockScheduler()
        let scheduler = SafetyBroadcastScheduler(
            batteryProvider: StubBatteryProvider(battery(.medium)),
            currentCheckin: { self.sampleCheckin() },
            broadcast: { _ in },
            scheduleTimer: mock.schedule
        )
        scheduler.start()
        scheduler.start()
        #expect(mock.intervals.count == 1)
    }

    @Test("a tick with no active check-in stops the loop quietly")
    func tickWithoutCheckinStops() {
        let mock = MockScheduler()
        var sendCount = 0
        let scheduler = SafetyBroadcastScheduler(
            batteryProvider: StubBatteryProvider(battery(.medium)),
            currentCheckin: { nil },
            broadcast: { _ in sendCount += 1 },
            scheduleTimer: mock.schedule
        )

        scheduler.start()
        mock.timers[0].fire()

        #expect(sendCount == 0)
        #expect(scheduler.isRunning == false)
        #expect(mock.intervals == [600]) // no reschedule
    }
}
