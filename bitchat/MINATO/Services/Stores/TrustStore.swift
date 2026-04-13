import BitLogger
import Foundation

/// Owns per-npub Trust Settings and the short-lived throttle that prevents
/// spamming interim ACKs to the same peer during a burst of incoming messages.
///
/// Persists trust settings to Keychain (interim ACK state is in-memory only —
/// re-throttling on restart is harmless).
final class TrustStore {
    static let shared = TrustStore()

    // MARK: - Persistence Keys (shared service with the rest of the agent store)
    private static let keychainService = AgentIdentityStore.keychainService
    private static let trustSettingsKey = "trust_settings"

    /// Interim ACK throttle window. One ACK per peer per window.
    private static let interimAckWindowSeconds: TimeInterval = 300

    private let keychain: KeychainManagerProtocol
    private let queue = DispatchQueue(label: "minato.agentstore.trust", attributes: .concurrent)

    private var _trustSettings: [String: TrustSettings] = [:]  // npub → TrustSettings
    private var _recentAckPeers: [String: Date] = [:]          // PeerID hex → last ACK time

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    init(keychain: KeychainManagerProtocol = KeychainManager()) {
        self.keychain = keychain
        loadAll()
    }

    // MARK: - Trust Settings

    func trustSettings(for npub: String) -> TrustSettings? {
        queue.sync { _trustSettings[npub] }
    }

    func updateTrustSettings(_ settings: TrustSettings, for npub: String) {
        queue.async(flags: .barrier) {
            self._trustSettings[npub] = settings
            self.persistTrustSettings(self._trustSettings)
        }
    }

    /// Ensures a default TrustSettings entry exists for the given npub. No-op if already present.
    /// Called by the facade after a new remote Agent Card is saved.
    func ensureDefaultSettings(for npub: String) {
        queue.async(flags: .barrier) {
            guard self._trustSettings[npub] == nil else { return }
            self._trustSettings[npub] = TrustSettings.defaultSettings()
            self.persistTrustSettings(self._trustSettings)
        }
    }

    // MARK: - Interim ACK Throttling

    /// Atomically checks whether an interim ACK should be sent AND marks it as sent if so.
    /// Prevents TOCTOU race where concurrent callers both pass the check before either marks.
    func checkAndMarkInterimAck(to peerID: PeerID) -> Bool {
        return queue.sync(flags: .barrier) {
            // Prune stale entries while we're here
            let now = Date()
            _recentAckPeers = _recentAckPeers.filter { now.timeIntervalSince($0.value) < Self.interimAckWindowSeconds }

            if let lastAck = _recentAckPeers[peerID.id],
               now.timeIntervalSince(lastAck) < Self.interimAckWindowSeconds {
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
               Date().timeIntervalSince(lastAck) < Self.interimAckWindowSeconds {
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

    // MARK: - Persistence

    private func loadAll() {
        if let data = keychain.load(key: Self.trustSettingsKey, service: Self.keychainService),
           let settings = try? Self.decoder.decode([String: TrustSettings].self, from: data) {
            _trustSettings = settings
            SecureLogger.info("MINATO: restored \(settings.count) trust setting(s)", category: .session)
        }
    }

    private func persistTrustSettings(_ settings: [String: TrustSettings]) {
        guard let data = try? Self.encoder.encode(settings) else { return }
        keychain.save(key: Self.trustSettingsKey, data: data, service: Self.keychainService, accessible: nil)
    }
}
