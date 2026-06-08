import Testing
import Foundation
@testable import bitchat

@Suite("SafetyCheckinStore (E-3a)")
struct SafetyCheckinStoreTests {

    /// Mutable time source so tests can advance the clock.
    private final class TestClock {
        var now: Date
        init(_ epoch: TimeInterval) { now = Date(timeIntervalSince1970: epoch) }
    }

    private func makeCheckin(id: String, expiresAt: UInt64, status: SafetyStatus = .safe) -> SafetyCheckin {
        SafetyCheckin(
            id: id,
            status: status,
            content: "status",
            battery: SafetyBatterySnapshot(level: 0.5, state: .unplugged, lowPowerMode: false, reportedAt: 1000),
            location: .undisclosed,
            relay: SafetyRelayMetadata(delivery: .direct, hops: nil, direct: true, lastSeenAt: 1000, relaySeenAt: nil),
            needs: [],
            expiresAt: expiresAt
        )
    }

    @Test("records an active check-in with delivery metadata")
    func recordsActive() {
        let clock = TestClock(1000)
        let store = SafetyCheckinStore(clock: { clock.now })
        store.record(makeCheckin(id: "a", expiresAt: 2000), deliveredVia: .mesh, hops: 2, receivedAt: 1000)

        let active = store.activeCheckins()
        #expect(active.count == 1)
        #expect(active.first?.deliveredVia == .mesh)
        #expect(active.first?.hops == 2)
    }

    @Test("drops an already-expired check-in")
    func dropsExpired() {
        let clock = TestClock(1000)
        let store = SafetyCheckinStore(clock: { clock.now })
        store.record(makeCheckin(id: "old", expiresAt: 500), deliveredVia: .direct, hops: 0, receivedAt: 1000)
        #expect(store.received.isEmpty)
    }

    @Test("dedupes by id, keeping the latest entry")
    func dedupesById() {
        let clock = TestClock(1000)
        let store = SafetyCheckinStore(clock: { clock.now })
        store.record(makeCheckin(id: "a", expiresAt: 2000), deliveredVia: .direct, hops: 0, receivedAt: 1000)
        store.record(makeCheckin(id: "a", expiresAt: 2000), deliveredVia: .mesh, hops: 3, receivedAt: 1100)

        #expect(store.received.count == 1)
        #expect(store.received.first?.hops == 3)
        #expect(store.received.first?.deliveredVia == .mesh)
    }

    @Test("orders newest first")
    func newestFirst() {
        let clock = TestClock(1000)
        let store = SafetyCheckinStore(clock: { clock.now })
        store.record(makeCheckin(id: "a", expiresAt: 2000), deliveredVia: .direct, hops: 0, receivedAt: 1000)
        store.record(makeCheckin(id: "b", expiresAt: 2000), deliveredVia: .direct, hops: 0, receivedAt: 1001)
        #expect(store.received.map(\.id) == ["b", "a"])
    }

    @Test("prunes entries that expire as the clock advances")
    func prunesExpiredOnInsert() {
        let clock = TestClock(1000)
        let store = SafetyCheckinStore(clock: { clock.now })
        store.record(makeCheckin(id: "short", expiresAt: 1500), deliveredVia: .direct, hops: 0, receivedAt: 1000)
        clock.now = Date(timeIntervalSince1970: 1600) // "short" now expired
        store.record(makeCheckin(id: "fresh", expiresAt: 3000), deliveredVia: .direct, hops: 0, receivedAt: 1600)

        #expect(store.received.map(\.id) == ["fresh"])
        #expect(store.activeCheckins().map(\.id) == ["fresh"])
    }

    @Test("caps the number of retained entries")
    func capsEntries() {
        let clock = TestClock(1000)
        let store = SafetyCheckinStore(clock: { clock.now }, maxEntries: 2)
        store.record(makeCheckin(id: "a", expiresAt: 2000), deliveredVia: .direct, hops: 0, receivedAt: 1000)
        store.record(makeCheckin(id: "b", expiresAt: 2000), deliveredVia: .direct, hops: 0, receivedAt: 1001)
        store.record(makeCheckin(id: "c", expiresAt: 2000), deliveredVia: .direct, hops: 0, receivedAt: 1002)
        #expect(store.received.count == 2)
        #expect(store.received.map(\.id) == ["c", "b"])
    }

    @Test("clear removes all entries")
    func clearRemovesAll() {
        let clock = TestClock(1000)
        let store = SafetyCheckinStore(clock: { clock.now })
        store.record(makeCheckin(id: "a", expiresAt: 2000), deliveredVia: .direct, hops: 0, receivedAt: 1000)
        store.clear()
        #expect(store.received.isEmpty)
    }
}
