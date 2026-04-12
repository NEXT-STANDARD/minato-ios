import Foundation

// MARK: - MINATO Agent Store

/// Manages the local Agent Card and known remote Agent Cards.
/// Thread-safe singleton for agent identity and peer card storage.
final class MINATOAgentStore {
    static let shared = MINATOAgentStore()

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

    private init() {}

    // MARK: - Local Card

    /// The local agent's card. Must be set before any MINATO communication.
    var localCard: AgentCard? {
        queue.sync { _localCard }
    }

    /// Sets the local Agent Card (typically at app launch).
    func setLocalCard(_ card: AgentCard) {
        queue.async(flags: .barrier) {
            self._localCard = card
        }
    }

    // MARK: - Remote Cards

    /// Saves a remote peer's Agent Card.
    func saveRemoteCard(_ card: AgentCard, for peerID: PeerID) {
        queue.async(flags: .barrier) {
            self._remoteCards[peerID.id] = card
            // Initialize trust settings if first encounter
            if self._trustSettings[card.agentId] == nil {
                self._trustSettings[card.agentId] = TrustSettings.defaultSettings()
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
        }
    }

    /// All known remote Agent Cards.
    var allRemoteCards: [String: AgentCard] {
        queue.sync { _remoteCards }
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
        }
    }
}
