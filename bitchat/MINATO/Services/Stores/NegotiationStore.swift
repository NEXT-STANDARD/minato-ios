import Foundation

/// Owns the in-flight state for MINATO schedule flows and AI-drafted replies
/// awaiting owner action. All state lives in memory — by design, re-proposing
/// on app restart is preferable to resurrecting stale approvals.
///
/// Covers:
/// - Individual schedule negotiations (REQUEST → RESPONSE → ACK chain)
/// - Group schedule negotiations (same request_id fanned out to N peers)
/// - Pending AI reply drafts (apprentice / partner trust modes)
/// - Pending schedule approvals (counter-proposals waiting for the owner)
final class NegotiationStore {
    static let shared = NegotiationStore()

    private let queue = DispatchQueue(label: "minato.agentstore.negotiation", attributes: .concurrent)

    private var _pendingReplies: [String: PendingReply] = [:]                             // PeerID hex → PendingReply
    private var _activeNegotiations: [String: ScheduleNegotiation] = [:]                   // requestId → negotiation
    private var _activeGroupNegotiations: [String: GroupScheduleNegotiation] = [:]         // requestId → group
    private var _pendingScheduleApprovals: [String: PendingScheduleApproval] = [:]         // requestId → approval

    init() {}

    // MARK: - Pending Replies (AI drafts awaiting owner approval)

    func addPendingReply(_ reply: PendingReply) {
        queue.async(flags: .barrier) {
            self._pendingReplies[reply.peerID.id] = reply
        }
    }

    func pendingReply(for peerID: PeerID) -> PendingReply? {
        queue.sync { _pendingReplies[peerID.id] }
    }

    func removePendingReply(for peerID: PeerID) {
        queue.async(flags: .barrier) {
            self._pendingReplies.removeValue(forKey: peerID.id)
        }
    }

    // MARK: - Schedule Negotiations (1:1)

    func addNegotiation(_ negotiation: ScheduleNegotiation) {
        queue.async(flags: .barrier) {
            self._activeNegotiations[negotiation.id] = negotiation
        }
    }

    func negotiation(for requestId: String) -> ScheduleNegotiation? {
        queue.sync { _activeNegotiations[requestId] }
    }

    func updateNegotiation(requestId: String, state: ScheduleNegotiation.State, event: ProposedEvent? = nil) {
        queue.async(flags: .barrier) {
            guard var neg = self._activeNegotiations[requestId] else { return }
            neg.state = state
            neg.updatedAt = Date()
            if let event { neg.proposedEvent = event }
            self._activeNegotiations[requestId] = neg
        }
    }

    func removeNegotiation(requestId: String) {
        queue.async(flags: .barrier) {
            self._activeNegotiations.removeValue(forKey: requestId)
        }
    }

    var allNegotiations: [String: ScheduleNegotiation] {
        queue.sync { _activeNegotiations }
    }

    // MARK: - Group Schedule Negotiations

    func addGroupNegotiation(_ group: GroupScheduleNegotiation) {
        queue.async(flags: .barrier) {
            self._activeGroupNegotiations[group.id] = group
        }
    }

    func groupNegotiation(for requestId: String) -> GroupScheduleNegotiation? {
        queue.sync { _activeGroupNegotiations[requestId] }
    }

    /// Updates a specific peer's response in a group negotiation.
    /// Returns the updated group (post-update) if it exists.
    @discardableResult
    func updateGroupResponse(requestId: String, peerID: PeerID, response: GroupScheduleNegotiation.PeerResponse) -> GroupScheduleNegotiation? {
        return queue.sync(flags: .barrier) {
            guard var group = _activeGroupNegotiations[requestId] else { return nil }
            group.responses[peerID.id] = response
            group.updatedAt = Date()
            _activeGroupNegotiations[requestId] = group
            return group
        }
    }

    func markGroupCalendarRegistered(requestId: String) {
        queue.async(flags: .barrier) {
            guard var group = self._activeGroupNegotiations[requestId] else { return }
            group.calendarRegistered = true
            self._activeGroupNegotiations[requestId] = group
        }
    }

    var allGroupNegotiations: [String: GroupScheduleNegotiation] {
        queue.sync { _activeGroupNegotiations }
    }

    func removeGroupNegotiation(requestId: String) {
        queue.async(flags: .barrier) {
            self._activeGroupNegotiations.removeValue(forKey: requestId)
        }
    }

    // MARK: - Pruning

    /// Remove negotiations older than `seconds` (called periodically).
    /// Covers both 1:1 and group negotiations in one barrier.
    func pruneStale(olderThan seconds: TimeInterval = 86400) {
        queue.async(flags: .barrier) {
            let now = Date()
            self._activeNegotiations = self._activeNegotiations.filter {
                now.timeIntervalSince($0.value.updatedAt) < seconds
            }
            self._activeGroupNegotiations = self._activeGroupNegotiations.filter {
                now.timeIntervalSince($0.value.updatedAt) < seconds
            }
        }
    }

    // MARK: - Pending Schedule Approvals

    func addPendingScheduleApproval(_ approval: PendingScheduleApproval) {
        queue.async(flags: .barrier) {
            self._pendingScheduleApprovals[approval.requestId] = approval
        }
    }

    func pendingScheduleApproval(for requestId: String) -> PendingScheduleApproval? {
        queue.sync { _pendingScheduleApprovals[requestId] }
    }

    func removePendingScheduleApproval(for requestId: String) {
        queue.async(flags: .barrier) {
            self._pendingScheduleApprovals.removeValue(forKey: requestId)
        }
    }
}
