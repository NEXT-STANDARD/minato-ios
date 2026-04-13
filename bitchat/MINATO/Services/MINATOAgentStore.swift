import BitLogger
import Foundation

// MARK: - Pending Reply

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

// MARK: - Schedule Negotiation

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

// MARK: - Persistence Wrappers

/// Wrapper for serializing remote cards with their peer ID association.
private struct RemoteCardEntry: Codable {
    let peerIDHex: String
    let card: AgentCard
}

// MARK: - MINATO Agent Store

/// Manages the local Agent Card and known remote Agent Cards.
/// Thread-safe singleton for agent identity and peer card storage.
/// Persists local card, remote cards, and trust settings to Keychain.
final class MINATOAgentStore {
    static let shared = MINATOAgentStore()

    // MARK: - Persistence Keys
    private static let keychainService = "minato.agentstore"
    private static let localCardKey = "local_card"
    private static let remoteCardsKey = "remote_cards"
    private static let trustSettingsKey = "trust_settings"

    private let keychain: KeychainManagerProtocol
    private let queue = DispatchQueue(label: "minato.agentstore", attributes: .concurrent)
    private var _localCard: AgentCard?
    private var _remoteCards: [String: AgentCard] = [:]  // PeerID hex → AgentCard
    private var _exchangedPeers: Set<String> = []        // PeerID hex set
    private var _trustSettings: [String: TrustSettings] = [:]  // npub → TrustSettings

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

    private init(keychain: KeychainManagerProtocol = KeychainManager()) {
        self.keychain = keychain
        loadAll()
    }

    // MARK: - Local Card

    /// The local agent's card. Must be set before any MINATO communication.
    var localCard: AgentCard? {
        queue.sync { _localCard }
    }

    /// Notification posted when the local Agent Card is first set (for deferred handshakes).
    static let localCardDidSetNotification = Notification.Name("MINATOLocalCardDidSet")

    /// Notification posted when the first-ever MINATO handshake completes (for onboarding).
    static let firstHandshakeCompletedNotification = Notification.Name("MINATOFirstHandshakeCompleted")

    /// Sets the local Agent Card (typically at app launch).
    func setLocalCard(_ card: AgentCard) {
        queue.async(flags: .barrier) {
            let wasNil = self._localCard == nil
            self._localCard = card
            self.persistLocalCard(card)
            if wasNil {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.localCardDidSetNotification, object: nil)
                }
            }
        }
    }

    // MARK: - Remote Cards

    /// Saves a remote peer's Agent Card.
    func saveRemoteCard(_ card: AgentCard, for peerID: PeerID) {
        var isFirstEverRemoteCard = false
        queue.sync(flags: .barrier) {
            isFirstEverRemoteCard = self._remoteCards.isEmpty
            self._remoteCards[peerID.id] = card
            // Initialize trust settings if first encounter
            if self._trustSettings[card.agentId] == nil {
                self._trustSettings[card.agentId] = TrustSettings.defaultSettings()
                self.persistTrustSettings(self._trustSettings)
            }
            self.persistRemoteCards(self._remoteCards)
        }
        // Post first-handshake notification (for onboarding) outside the barrier
        if isFirstEverRemoteCard {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.firstHandshakeCompletedNotification,
                    object: nil,
                    userInfo: ["peerName": card.displayName, "peerID": peerID.id]
                )
            }
        }
    }

    /// Retrieves the Agent Card for a known peer.
    func remoteCard(for peerID: PeerID) -> AgentCard? {
        queue.sync { _remoteCards[peerID.id] }
    }

    /// Removes a remote peer's Agent Card (on revoke or disconnect).
    func removeRemoteCard(for peerID: PeerID) {
        queue.async(flags: .barrier) {
            self._remoteCards.removeValue(forKey: peerID.id)
            self._exchangedPeers.remove(peerID.id)
            self.persistRemoteCards(self._remoteCards)
        }
    }

    /// All known remote Agent Cards.
    var allRemoteCards: [String: AgentCard] {
        queue.sync { _remoteCards }
    }

    /// Finds a remote card by any peerID format (short 16-hex or full 64-hex Noise key).
    /// Falls back to prefix matching if the provided ID is longer than stored keys.
    func findRemoteCard(for peerID: PeerID) -> (peerID: PeerID, card: AgentCard)? {
        return queue.sync {
            // Direct match
            if let card = _remoteCards[peerID.id] {
                return (peerID, card)
            }
            // If the lookup key is a full 64-hex Noise key, try prefix match (first 16 hex)
            if peerID.id.count == 64 {
                let shortPrefix = String(peerID.id.prefix(16))
                if let card = _remoteCards[shortPrefix] {
                    return (PeerID(str: shortPrefix), card)
                }
            }
            // If the lookup key is short, try finding a full key that starts with it
            if peerID.id.count == 16 {
                for (key, card) in _remoteCards where key.hasPrefix(peerID.id) || peerID.id.hasPrefix(key) {
                    return (PeerID(str: key), card)
                }
            }
            return nil
        }
    }

    // MARK: - Handshake Tracking

    /// Whether we've already exchanged Agent Cards with this peer.
    func hasExchangedWith(_ peerID: PeerID) -> Bool {
        queue.sync { _exchangedPeers.contains(peerID.id) }
    }

    /// Mark a peer as having completed the Agent Card exchange.
    func markExchanged(_ peerID: PeerID) {
        queue.async(flags: .barrier) {
            self._exchangedPeers.insert(peerID.id)
        }
    }

    // MARK: - Trust Settings

    /// Gets trust settings for a peer by their npub.
    func trustSettings(for npub: String) -> TrustSettings? {
        queue.sync { _trustSettings[npub] }
    }

    /// Updates trust settings for a peer.
    func updateTrustSettings(_ settings: TrustSettings, for npub: String) {
        queue.async(flags: .barrier) {
            self._trustSettings[npub] = settings
            self.persistTrustSettings(self._trustSettings)
        }
    }

    // MARK: - Pending Replies

    private var _pendingReplies: [String: PendingReply] = [:]  // PeerID hex → PendingReply

    /// Stores a pending reply for owner approval.
    func addPendingReply(_ reply: PendingReply) {
        queue.async(flags: .barrier) {
            self._pendingReplies[reply.peerID.id] = reply
        }
    }

    /// Retrieves the pending reply for a peer, if any.
    func pendingReply(for peerID: PeerID) -> PendingReply? {
        queue.sync { _pendingReplies[peerID.id] }
    }

    /// Removes the pending reply for a peer.
    func removePendingReply(for peerID: PeerID) {
        queue.async(flags: .barrier) {
            self._pendingReplies.removeValue(forKey: peerID.id)
        }
    }

    // MARK: - Interim ACK Throttling

    private var _recentAckPeers: [String: Date] = [:]  // peerID hex → last ACK time

    /// Atomically checks whether an interim ACK should be sent AND marks it as sent if so.
    /// Prevents TOCTOU race where concurrent callers both pass the check before either marks.
    func checkAndMarkInterimAck(to peerID: PeerID) -> Bool {
        return queue.sync(flags: .barrier) {
            // Prune stale entries (older than 5 min) while we're here
            let now = Date()
            _recentAckPeers = _recentAckPeers.filter { now.timeIntervalSince($0.value) < 300 }

            if let lastAck = _recentAckPeers[peerID.id],
               now.timeIntervalSince(lastAck) < 300 {
                return false
            }
            _recentAckPeers[peerID.id] = now
            return true
        }
    }

    /// Legacy: checks without marking. Prefer `checkAndMarkInterimAck` to avoid TOCTOU race.
    func shouldSendInterimAck(to peerID: PeerID) -> Bool {
        return queue.sync {
            if let lastAck = _recentAckPeers[peerID.id],
               Date().timeIntervalSince(lastAck) < 300 {
                return false
            }
            return true
        }
    }

    /// Record that an interim ACK was sent to this peer.
    func markInterimAckSent(to peerID: PeerID) {
        queue.async(flags: .barrier) {
            self._recentAckPeers[peerID.id] = Date()
        }
    }

    // MARK: - Schedule Negotiations

    private var _activeNegotiations: [String: ScheduleNegotiation] = [:]  // requestId → negotiation

    /// Starts tracking a new schedule negotiation.
    func addNegotiation(_ negotiation: ScheduleNegotiation) {
        queue.async(flags: .barrier) {
            self._activeNegotiations[negotiation.id] = negotiation
        }
    }

    /// Retrieves an active negotiation by request ID.
    func negotiation(for requestId: String) -> ScheduleNegotiation? {
        queue.sync { _activeNegotiations[requestId] }
    }

    /// Updates the state and optionally the proposed event of a negotiation.
    func updateNegotiation(requestId: String, state: ScheduleNegotiation.State, event: ProposedEvent? = nil) {
        queue.async(flags: .barrier) {
            guard var neg = self._activeNegotiations[requestId] else { return }
            neg.state = state
            neg.updatedAt = Date()
            if let event { neg.proposedEvent = event }
            self._activeNegotiations[requestId] = neg
        }
    }

    /// Removes a completed or cancelled negotiation.
    func removeNegotiation(requestId: String) {
        queue.async(flags: .barrier) {
            self._activeNegotiations.removeValue(forKey: requestId)
        }
    }

    /// All active negotiations.
    var allNegotiations: [String: ScheduleNegotiation] {
        queue.sync { _activeNegotiations }
    }

    /// Remove negotiations older than 24 hours (called periodically).
    func pruneStaleNegotiations(olderThan seconds: TimeInterval = 86400) {
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

    // MARK: - Group Schedule Negotiations

    private var _activeGroupNegotiations: [String: GroupScheduleNegotiation] = [:]  // requestId → group

    /// Starts tracking a new group schedule negotiation.
    func addGroupNegotiation(_ group: GroupScheduleNegotiation) {
        queue.async(flags: .barrier) {
            self._activeGroupNegotiations[group.id] = group
        }
    }

    /// Retrieves an active group negotiation by request ID.
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

    /// Mark calendar as registered to prevent double-registration.
    func markGroupCalendarRegistered(requestId: String) {
        queue.async(flags: .barrier) {
            guard var group = self._activeGroupNegotiations[requestId] else { return }
            group.calendarRegistered = true
            self._activeGroupNegotiations[requestId] = group
        }
    }

    /// All active group negotiations.
    var allGroupNegotiations: [String: GroupScheduleNegotiation] {
        queue.sync { _activeGroupNegotiations }
    }

    func removeGroupNegotiation(requestId: String) {
        queue.async(flags: .barrier) {
            self._activeGroupNegotiations.removeValue(forKey: requestId)
        }
    }

    // MARK: - Activity Log (full_auto mode audit trail)

    private static let activityLogKey = "activity_log"
    private static let activityLogMaxEntries = 200

    private var _activityLog: [AgentActivityLog] = []  // newest first

    /// All activity log entries (newest first).
    var activityLog: [AgentActivityLog] {
        queue.sync { _activityLog }
    }

    /// Append a new activity log entry. Persists to Keychain automatically.
    func appendActivityLog(_ entry: AgentActivityLog) {
        queue.async(flags: .barrier) {
            self._activityLog.insert(entry, at: 0)
            if self._activityLog.count > Self.activityLogMaxEntries {
                self._activityLog = Array(self._activityLog.prefix(Self.activityLogMaxEntries))
            }
            self.persistActivityLog(self._activityLog)
        }
    }

    /// Activity log entries for a specific peer (newest first).
    func activityLog(for peerID: PeerID) -> [AgentActivityLog] {
        queue.sync { _activityLog.filter { $0.peerID == peerID.id } }
    }

    /// Clear the activity log.
    func clearActivityLog() {
        queue.async(flags: .barrier) {
            self._activityLog = []
            self.persistActivityLog([])
        }
    }

    private func persistActivityLog(_ log: [AgentActivityLog]) {
        guard let data = try? Self.encoder.encode(log) else { return }
        keychain.save(key: Self.activityLogKey, data: data, service: Self.keychainService, accessible: nil)
    }

    // MARK: - Pending Schedule Approvals

    private var _pendingScheduleApprovals: [String: PendingScheduleApproval] = [:]  // requestId → approval

    /// Stores a schedule proposal awaiting owner action.
    func addPendingScheduleApproval(_ approval: PendingScheduleApproval) {
        queue.async(flags: .barrier) {
            self._pendingScheduleApprovals[approval.requestId] = approval
        }
    }

    /// Retrieves pending schedule approval by request ID.
    func pendingScheduleApproval(for requestId: String) -> PendingScheduleApproval? {
        queue.sync { _pendingScheduleApprovals[requestId] }
    }

    /// Removes a pending schedule approval.
    func removePendingScheduleApproval(for requestId: String) {
        queue.async(flags: .barrier) {
            self._pendingScheduleApprovals.removeValue(forKey: requestId)
        }
    }

    // MARK: - Persistence

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    /// Load all persisted data from Keychain on init.
    private func loadAll() {
        // Local card
        if let data = keychain.load(key: Self.localCardKey, service: Self.keychainService),
           let card = try? Self.decoder.decode(AgentCard.self, from: data) {
            _localCard = card
            SecureLogger.info("MINATO: restored local Agent Card (\(card.displayName))", category: .session)
        }

        // Remote cards (restore cards but NOT exchangedPeers — always re-handshake on reconnect)
        if let data = keychain.load(key: Self.remoteCardsKey, service: Self.keychainService),
           let entries = try? Self.decoder.decode([RemoteCardEntry].self, from: data) {
            for entry in entries {
                _remoteCards[entry.peerIDHex] = entry.card
            }
            SecureLogger.info("MINATO: restored \(entries.count) remote Agent Card(s)", category: .session)
        }

        // Trust settings
        if let data = keychain.load(key: Self.trustSettingsKey, service: Self.keychainService),
           let settings = try? Self.decoder.decode([String: TrustSettings].self, from: data) {
            _trustSettings = settings
            SecureLogger.info("MINATO: restored \(settings.count) trust setting(s)", category: .session)
        }

        // Activity log
        if let data = keychain.load(key: Self.activityLogKey, service: Self.keychainService),
           let log = try? Self.decoder.decode([AgentActivityLog].self, from: data) {
            _activityLog = log
            SecureLogger.info("MINATO: restored \(log.count) activity log entry/entries", category: .session)
        }
    }

    /// Persist the local Agent Card.
    private func persistLocalCard(_ card: AgentCard) {
        guard let data = try? Self.encoder.encode(card) else { return }
        keychain.save(key: Self.localCardKey, data: data, service: Self.keychainService, accessible: nil)
    }

    /// Persist all remote Agent Cards.
    private func persistRemoteCards(_ cards: [String: AgentCard]) {
        let entries = cards.map { RemoteCardEntry(peerIDHex: $0.key, card: $0.value) }
        guard let data = try? Self.encoder.encode(entries) else { return }
        keychain.save(key: Self.remoteCardsKey, data: data, service: Self.keychainService, accessible: nil)
    }

    /// Persist all trust settings.
    private func persistTrustSettings(_ settings: [String: TrustSettings]) {
        guard let data = try? Self.encoder.encode(settings) else { return }
        keychain.save(key: Self.trustSettingsKey, data: data, service: Self.keychainService, accessible: nil)
    }
}
