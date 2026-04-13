import BitLogger
import Foundation

// MARK: - Persistence Wrapper

/// Wrapper for serializing remote cards with their peer ID association.
private struct RemoteCardEntry: Codable {
    let peerIDHex: String
    let card: AgentCard
}

// MARK: - Agent Identity Store

/// Owns the local Agent Card, the remote Agent Cards we've handshaked with,
/// and the set of peers we've already completed a card exchange with.
///
/// Persists local card and remote cards to Keychain. Emits notifications
/// when the local card is first set and when the first-ever remote handshake
/// completes (used by onboarding).
final class AgentIdentityStore {
    static let shared = AgentIdentityStore()

    // MARK: - Notifications

    /// Posted when the local Agent Card is first set (for deferred handshakes).
    static let localCardDidSetNotification = Notification.Name("MINATOLocalCardDidSet")

    /// Posted when the first-ever MINATO handshake completes (for onboarding).
    static let firstHandshakeCompletedNotification = Notification.Name("MINATOFirstHandshakeCompleted")

    // MARK: - Persistence Keys (kept compatible with legacy MINATOAgentStore)
    static let keychainService = "minato.agentstore"
    private static let localCardKey = "local_card"
    private static let remoteCardsKey = "remote_cards"

    private let keychain: KeychainManagerProtocol
    private let queue = DispatchQueue(label: "minato.agentstore.identity", attributes: .concurrent)

    private var _localCard: AgentCard?
    private var _remoteCards: [String: AgentCard] = [:]  // PeerID hex → AgentCard
    private var _exchangedPeers: Set<String> = []        // PeerID hex set

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    /// Called after a new remote card is saved for an agentId we haven't seen.
    /// Used by the facade to seed default trust settings in `TrustStore`.
    var onNewAgentIdObserved: ((_ agentId: String) -> Void)?

    init(keychain: KeychainManagerProtocol = KeychainManager()) {
        self.keychain = keychain
        loadAll()
    }

    // MARK: - Local Card

    var localCard: AgentCard? {
        queue.sync { _localCard }
    }

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

    func saveRemoteCard(_ card: AgentCard, for peerID: PeerID) {
        var isFirstEverRemoteCard = false
        var isNewAgentId = false
        queue.sync(flags: .barrier) {
            isFirstEverRemoteCard = self._remoteCards.isEmpty
            // Is this agentId already associated with any stored remote card?
            isNewAgentId = !self._remoteCards.values.contains(where: { $0.agentId == card.agentId })
            self._remoteCards[peerID.id] = card
            self.persistRemoteCards(self._remoteCards)
        }
        if isNewAgentId {
            onNewAgentIdObserved?(card.agentId)
        }
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

    func remoteCard(for peerID: PeerID) -> AgentCard? {
        queue.sync { _remoteCards[peerID.id] }
    }

    func removeRemoteCard(for peerID: PeerID) {
        queue.async(flags: .barrier) {
            self._remoteCards.removeValue(forKey: peerID.id)
            self._exchangedPeers.remove(peerID.id)
            self.persistRemoteCards(self._remoteCards)
        }
    }

    var allRemoteCards: [String: AgentCard] {
        queue.sync { _remoteCards }
    }

    /// Finds a remote card by any peerID format (short 16-hex or full 64-hex Noise key).
    /// Falls back to prefix matching if the provided ID is longer than stored keys.
    func findRemoteCard(for peerID: PeerID) -> (peerID: PeerID, card: AgentCard)? {
        return queue.sync {
            if let card = _remoteCards[peerID.id] {
                return (peerID, card)
            }
            if peerID.id.count == 64 {
                let shortPrefix = String(peerID.id.prefix(16))
                if let card = _remoteCards[shortPrefix] {
                    return (PeerID(str: shortPrefix), card)
                }
            }
            if peerID.id.count == 16 {
                for (key, card) in _remoteCards where key.hasPrefix(peerID.id) || peerID.id.hasPrefix(key) {
                    return (PeerID(str: key), card)
                }
            }
            return nil
        }
    }

    // MARK: - Handshake Tracking

    func hasExchangedWith(_ peerID: PeerID) -> Bool {
        queue.sync { _exchangedPeers.contains(peerID.id) }
    }

    func markExchanged(_ peerID: PeerID) {
        queue.async(flags: .barrier) {
            self._exchangedPeers.insert(peerID.id)
        }
    }

    // MARK: - Persistence

    private func loadAll() {
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
    }

    private func persistLocalCard(_ card: AgentCard) {
        guard let data = try? Self.encoder.encode(card) else { return }
        keychain.save(key: Self.localCardKey, data: data, service: Self.keychainService, accessible: nil)
    }

    private func persistRemoteCards(_ cards: [String: AgentCard]) {
        let entries = cards.map { RemoteCardEntry(peerIDHex: $0.key, card: $0.value) }
        guard let data = try? Self.encoder.encode(entries) else { return }
        keychain.save(key: Self.remoteCardsKey, data: data, service: Self.keychainService, accessible: nil)
    }
}
