import Foundation

protocol SafetyBroadcastTimerProtocol: AnyObject {
    var isValid: Bool { get }
    func invalidate()
}

private final class SafetyBroadcastTimerAdapter: SafetyBroadcastTimerProtocol {
    private let base: Timer
    init(base: Timer) { self.base = base }
    var isValid: Bool { base.isValid }
    func invalidate() { base.invalidate() }
}

/// Re-broadcasts the local safety check-in on a battery-throttled interval while
/// disaster mode is active (E-3b). The interval decision (`SafetyBroadcastPolicy`),
/// battery sampling, check-in source, the actual send, and the timer are all
/// injected, so the scheduling behavior is fully unit-testable; only the live
/// `Timer` wiring requires a device.
///
/// Expected to be driven on the main thread (the production timer fires on the
/// main run loop and consumers are UI-bound).
///
/// See: docs/MINATO-disaster-mode.md
final class SafetyBroadcastScheduler {
    private let batteryProvider: BatterySnapshotProviding
    private let currentCheckin: () -> SafetyCheckin?
    private let broadcast: (SafetyCheckin) -> Void
    private let scheduleTimer: (TimeInterval, @escaping () -> Void) -> SafetyBroadcastTimerProtocol
    private let clock: () -> Date

    private var timer: SafetyBroadcastTimerProtocol?
    private(set) var isRunning = false

    init(
        batteryProvider: BatterySnapshotProviding = BatterySnapshotProvider(),
        currentCheckin: @escaping () -> SafetyCheckin?,
        broadcast: @escaping (SafetyCheckin) -> Void,
        scheduleTimer: ((TimeInterval, @escaping () -> Void) -> SafetyBroadcastTimerProtocol)? = nil,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.batteryProvider = batteryProvider
        self.currentCheckin = currentCheckin
        self.broadcast = broadcast
        self.clock = clock
        self.scheduleTimer = scheduleTimer ?? { interval, handler in
            let base = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in handler() }
            return SafetyBroadcastTimerAdapter(base: base)
        }
    }

    /// Begin the throttled re-broadcast loop. Idempotent. Does not broadcast
    /// immediately — activation already sends the first check-in (E-3a); this
    /// schedules the next one.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleNext()
    }

    /// Stop the loop and invalidate the pending timer.
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func scheduleNext() {
        guard isRunning else { return }
        let battery = batteryProvider.currentSnapshot(now: clock())
        let interval = SafetyBroadcastPolicy.interval(for: battery)
        timer = scheduleTimer(interval) { [weak self] in
            self?.tick()
        }
    }

    private func tick() {
        guard isRunning else { return }
        // Stop quietly if disaster mode was turned off out from under us.
        guard let checkin = currentCheckin() else {
            stop()
            return
        }
        broadcast(checkin)
        scheduleNext()
    }
}
