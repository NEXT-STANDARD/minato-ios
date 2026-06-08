import Foundation
import Combine

/// Holds safety check-ins received from peers during disaster mode.
///
/// Scope (E-3a): in-memory, deduplicated by `SafetyCheckin.id`, expired entries
/// dropped on insert and on read. Carries receive-side transport metadata
/// (`deliveredVia` / `hops`) separately from the signed check-in so the signed
/// payload stays intact. Newest-first, capped.
///
/// Threading: mutations are expected on the main actor (consumers are SwiftUI
/// views and the receive handler dispatches to main).
///
/// See: docs/MINATO-disaster-mode.md, docs/MINATO-message-shapes.md
final class SafetyCheckinStore: ObservableObject {
    static let shared = SafetyCheckinStore()

    /// A received check-in plus how this device received it.
    struct Received: Identifiable, Equatable {
        let checkin: SafetyCheckin
        let deliveredVia: SafetyRelayDelivery
        let hops: Int
        let receivedAt: UInt64
        /// Transport-observed timestamp (E-5): for `.nostr`, the relay/rumor
        /// time the gift-wrap was seen. Separate from the signed origin
        /// timestamps inside `checkin` (which stay authoritative). `nil` for mesh.
        let relaySeenAt: UInt64?

        var id: String { checkin.id }
    }

    @Published private(set) var received: [Received] = []

    private let clock: () -> Date
    private let maxEntries: Int

    init(clock: @escaping () -> Date = { Date() }, maxEntries: Int = 200) {
        self.clock = clock
        self.maxEntries = maxEntries
    }

    /// Record a received check-in. Drops it if already expired, dedupes by id
    /// (keeping the latest), prunes other expired entries, and caps the list.
    func record(
        _ checkin: SafetyCheckin,
        deliveredVia: SafetyRelayDelivery,
        hops: Int,
        receivedAt: UInt64,
        relaySeenAt: UInt64? = nil
    ) {
        let now = UInt64(clock().timeIntervalSince1970)
        guard checkin.expiresAt > now else { return }

        var list = received.filter { $0.checkin.expiresAt > now }
        let entry = Received(
            checkin: checkin,
            deliveredVia: deliveredVia,
            hops: max(0, hops),
            receivedAt: receivedAt,
            relaySeenAt: relaySeenAt
        )
        if let idx = list.firstIndex(where: { $0.id == checkin.id }) {
            list[idx] = entry
        } else {
            list.insert(entry, at: 0)
        }
        if list.count > maxEntries {
            list = Array(list.prefix(maxEntries))
        }
        received = list
    }

    /// Currently non-expired check-ins, newest-first.
    func activeCheckins() -> [Received] {
        let now = UInt64(clock().timeIntervalSince1970)
        return received.filter { $0.checkin.expiresAt > now }
    }

    /// Drop all received check-ins (e.g., when leaving disaster mode).
    func clear() {
        received = []
    }
}
