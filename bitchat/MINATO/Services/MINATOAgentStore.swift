import BitLogger
import Foundation

// MARK: - Shared Model Types
//
// These types are referenced by the sub-stores under `Stores/` as well as
// by ViewModels/Views. They stay at file scope here so the public MINATO
// surface keeps a single home for protocol-level value types.

/// A reply proposed by the AI engine that awaits owner approval.
/// Used in Apprentice (plan) and Partner (suggest) trust modes.
struct PendingReply {
    let id: String
    let peerID: PeerID
    let originalMessage: String
    let proposedReply: String
    let intent: String?
    let createdAt: Date
}

/// Tracks the lifecycle of a schedule negotiation (REQUEST → RESPONSE → ACK chain).
struct ScheduleNegotiation {
    let id: String                  // Matches request_id in payload
    let peerID: PeerID
    let initiatedByLocal: Bool      // true if we sent the initial REQUEST
    var proposedEvent: ProposedEvent?
    var state: State
    let createdAt: Date
    var updatedAt: Date

    enum State: String {
        case proposed           // REQUEST sent, awaiting RESPONSE
        case counterOffered     // Received RESPONSE with counter-proposal
        case confirmed          // ACK with status "confirmed"
        case rejected           // ACK with status "rejected"
        case cancelled          // schedule.cancel intent received
    }
}

/// Activity log entry — records autonomous actions taken by the AI (full_auto mode).
struct AgentActivityLog: Codable, Identifiable {
    let id: String               // UUID
    let peerID: String           // peerID.id hex (who we acted toward)
    let peerName: String         // display name at time of action
    let action: ActionType
    let content: String          // the message/event content
    let intent: String?
    let timestamp: Date

    enum ActionType: String, Codable {
        case autoReply           // full_auto sent a reply
        case autoScheduleAck     // full_auto confirmed a schedule
        case autoScheduleReject  // full_auto rejected a schedule

        var protocolValue: String {
            switch self {
            case .autoReply: return "auto_reply"
            case .autoScheduleAck: return "auto_schedule_ack"
            case .autoScheduleReject: return "auto_schedule_reject"
            }
        }

        static func fromProtocolValue(_ value: String) -> ActionType? {
            switch value {
            case "auto_reply": return .autoReply
            case "auto_schedule_ack": return .autoScheduleAck
            case "auto_schedule_reject": return .autoScheduleReject
            default: return nil
            }
        }
    }
}

/// Tracks a group schedule proposal sent to multiple peers with a shared request_id.
struct GroupScheduleNegotiation {
    let id: String                              // shared request_id
    let peerIDs: [PeerID]                       // all invited peers
    let peerNames: [String: String]             // peerID.id → display name
    let proposedEvent: ProposedEvent
    var responses: [String: PeerResponse]       // peerID.id → response
    let createdAt: Date
    var updatedAt: Date
    var calendarRegistered: Bool = false        // prevents double-registration

    enum PeerResponse: String {
        case pending
        case confirmed
        case rejected
    }

    var isComplete: Bool {
        !responses.isEmpty && responses.values.allSatisfy { $0 != .pending }
    }

    var allConfirmed: Bool {
        !responses.isEmpty && responses.values.allSatisfy { $0 == .confirmed }
    }

    var confirmedCount: Int {
        responses.values.filter { $0 == .confirmed }.count
    }
}

/// Pending schedule approval awaiting owner action.
struct PendingScheduleApproval {
    let requestId: String
    let peerID: PeerID
    let proposedEvent: ProposedEvent
    let content: String?
    let translatedContent: String?
    let peerName: String
    let createdAt: Date
    var hasConflict: Bool = false
}

// MARK: - MINATO Agent Store (facade)

/// Public entry point for the MINATO agent state layer.
///
/// Under the hood, responsibilities are split across four focused stores
/// (see `Stores/`):
///
/// - ``AgentIdentityStore`` — local & remote Agent Cards, handshake tracking
/// - ``TrustStore``         — per-npub trust settings, interim ACK throttle
/// - ``NegotiationStore``   — in-flight schedule negotiations & pending approvals
/// - ``ActivityLogStore``   — full_auto audit trail
///
/// This class remains as a stable thin facade so existing call sites
/// (`MINATOAgentStore.shared.localCard`, etc.) keep working unchanged.
/// New code is free to call the sub-stores directly where the coupling is
/// already clear.
final class MINATOAgentStore {
    static let shared = MINATOAgentStore()

    // MARK: - Sub-stores

    let identity: AgentIdentityStore
    let trust: TrustStore
    let negotiation: NegotiationStore
    let log: ActivityLogStore

    // MARK: - Notifications (re-exported from AgentIdentityStore)

    static var localCardDidSetNotification: Notification.Name {
        AgentIdentityStore.localCardDidSetNotification
    }
    static var firstHandshakeCompletedNotification: Notification.Name {
        AgentIdentityStore.firstHandshakeCompletedNotification
    }

    // MARK: - App-level dependencies

    /// The AI engine for generating responses. Set at app launch.
    private(set) var aiEngine: AIEngine?

    /// Configures the AI engine (call once at startup).
    func setAIEngine(_ engine: AIEngine) {
        aiEngine = engine
    }

    /// The calendar adapter for EventKit integration. Set at app launch.
    private(set) var calendarAdapter: CalendarAdapterProtocol?

    /// Configures the calendar adapter (call once at startup).
    func setCalendarAdapter(_ adapter: CalendarAdapterProtocol) {
        calendarAdapter = adapter
    }

    private init(
        identity: AgentIdentityStore = .shared,
        trust: TrustStore = .shared,
        negotiation: NegotiationStore = .shared,
        log: ActivityLogStore = .shared
    ) {
        self.identity = identity
        self.trust = trust
        self.negotiation = negotiation
        self.log = log

        // Wire identity → trust so that whenever a new remote Agent Card
        // introduces an agentId we've never seen, TrustStore seeds default
        // settings for it. (Previously both updates lived under a single
        // barrier inside the monolithic store.)
        identity.onNewAgentIdObserved = { [weak trust] agentId in
            trust?.ensureDefaultSettings(for: agentId)
        }
    }

    // MARK: - Identity facade

    var localCard: AgentCard? { identity.localCard }

    func setLocalCard(_ card: AgentCard) { identity.setLocalCard(card) }

    func saveRemoteCard(_ card: AgentCard, for peerID: PeerID) {
        identity.saveRemoteCard(card, for: peerID)
    }

    func remoteCard(for peerID: PeerID) -> AgentCard? { identity.remoteCard(for: peerID) }

    func removeRemoteCard(for peerID: PeerID) { identity.removeRemoteCard(for: peerID) }

    var allRemoteCards: [String: AgentCard] { identity.allRemoteCards }

    func findRemoteCard(for peerID: PeerID) -> (peerID: PeerID, card: AgentCard)? {
        identity.findRemoteCard(for: peerID)
    }

    func hasExchangedWith(_ peerID: PeerID) -> Bool { identity.hasExchangedWith(peerID) }

    func markExchanged(_ peerID: PeerID) { identity.markExchanged(peerID) }

    // MARK: - Trust facade

    func trustSettings(for npub: String) -> TrustSettings? { trust.trustSettings(for: npub) }

    func updateTrustSettings(_ settings: TrustSettings, for npub: String) {
        trust.updateTrustSettings(settings, for: npub)
    }

    func removeTrustSettings(for npub: String) {
        trust.removeTrustSettings(for: npub)
    }

    func checkAndMarkInterimAck(to peerID: PeerID) -> Bool {
        trust.checkAndMarkInterimAck(to: peerID)
    }

    func shouldSendInterimAck(to peerID: PeerID) -> Bool {
        trust.shouldSendInterimAck(to: peerID)
    }

    func markInterimAckSent(to peerID: PeerID) { trust.markInterimAckSent(to: peerID) }

    // MARK: - Negotiation facade (pending replies)

    func addPendingReply(_ reply: PendingReply) { negotiation.addPendingReply(reply) }

    func pendingReply(for peerID: PeerID) -> PendingReply? {
        negotiation.pendingReply(for: peerID)
    }

    func removePendingReply(for peerID: PeerID) { negotiation.removePendingReply(for: peerID) }

    // MARK: - Negotiation facade (1:1)

    func addNegotiation(_ n: ScheduleNegotiation) { negotiation.addNegotiation(n) }

    func negotiation(for requestId: String) -> ScheduleNegotiation? {
        negotiation.negotiation(for: requestId)
    }

    func updateNegotiation(requestId: String, state: ScheduleNegotiation.State, event: ProposedEvent? = nil) {
        negotiation.updateNegotiation(requestId: requestId, state: state, event: event)
    }

    func removeNegotiation(requestId: String) { negotiation.removeNegotiation(requestId: requestId) }

    var allNegotiations: [String: ScheduleNegotiation] { negotiation.allNegotiations }

    func pruneStaleNegotiations(olderThan seconds: TimeInterval = 86400) {
        negotiation.pruneStale(olderThan: seconds)
    }

    // MARK: - Negotiation facade (group)

    func addGroupNegotiation(_ group: GroupScheduleNegotiation) {
        negotiation.addGroupNegotiation(group)
    }

    func groupNegotiation(for requestId: String) -> GroupScheduleNegotiation? {
        negotiation.groupNegotiation(for: requestId)
    }

    @discardableResult
    func updateGroupResponse(requestId: String, peerID: PeerID, response: GroupScheduleNegotiation.PeerResponse) -> GroupScheduleNegotiation? {
        negotiation.updateGroupResponse(requestId: requestId, peerID: peerID, response: response)
    }

    func markGroupCalendarRegistered(requestId: String) {
        negotiation.markGroupCalendarRegistered(requestId: requestId)
    }

    var allGroupNegotiations: [String: GroupScheduleNegotiation] {
        negotiation.allGroupNegotiations
    }

    func removeGroupNegotiation(requestId: String) {
        negotiation.removeGroupNegotiation(requestId: requestId)
    }

    // MARK: - Negotiation facade (pending schedule approvals)

    func addPendingScheduleApproval(_ approval: PendingScheduleApproval) {
        negotiation.addPendingScheduleApproval(approval)
    }

    func pendingScheduleApproval(for requestId: String) -> PendingScheduleApproval? {
        negotiation.pendingScheduleApproval(for: requestId)
    }

    func removePendingScheduleApproval(for requestId: String) {
        negotiation.removePendingScheduleApproval(for: requestId)
    }

    // MARK: - Activity Log facade

    var activityLog: [AgentActivityLog] { log.activityLog }

    func appendActivityLog(_ entry: AgentActivityLog) { log.appendActivityLog(entry) }

    func activityLog(for peerID: PeerID) -> [AgentActivityLog] { log.activityLog(for: peerID) }

    func clearActivityLog() { log.clearActivityLog() }
}
