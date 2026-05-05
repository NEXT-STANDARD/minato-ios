import Foundation

/// Owns the in-memory set of remote agents whose auto-replies the local agent
/// has been asked to suppress (via `remote.mute`). Reset on app launch by
/// design — long-term suppression should go through the trust system.
final class MuteStore {
    static let shared = MuteStore()

    private let queue = DispatchQueue(label: "minato.muteStore", attributes: .concurrent)
    private var _muted: Set<String> = []  // npub of the peer we've been told to stop auto-replying to

    init() {}

    /// Suppress automatic replies addressed to the given peer.
    func mute(npub: String) {
        guard !npub.isEmpty else { return }
        queue.async(flags: .barrier) {
            self._muted.insert(npub)
        }
    }

    /// Remove the suppression. Returns true if the peer was previously muted.
    @discardableResult
    func unmute(npub: String) -> Bool {
        guard !npub.isEmpty else { return false }
        return queue.sync(flags: .barrier) {
            _muted.remove(npub) != nil
        }
    }

    /// Whether the local agent has been asked not to auto-reply to this peer.
    func isMuted(npub: String) -> Bool {
        guard !npub.isEmpty else { return false }
        return queue.sync { _muted.contains(npub) }
    }

    /// Clear all mutes. Primarily for tests.
    func clear() {
        queue.async(flags: .barrier) {
            self._muted.removeAll()
        }
    }
}
