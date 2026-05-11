import BitLogger
import Foundation

/// Owns the audit trail of autonomous actions the AI took on the owner's behalf
/// while running in `full_auto` trust mode. Persisted to Keychain, capped at
/// `maxEntries`, newest-first.
final class ActivityLogStore {
    static let shared = ActivityLogStore()

    // MARK: - Persistence Keys (shared service with the rest of the agent store)
    private static let keychainService = AgentIdentityStore.keychainService
    private static let activityLogKey = "activity_log"
    private static let maxEntries = 200

    private let keychain: KeychainManagerProtocol
    private let queue = DispatchQueue(label: "minato.agentstore.activitylog", attributes: .concurrent)

    private var _activityLog: [AgentActivityLog] = []  // newest first

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

    /// All activity log entries (newest first).
    var activityLog: [AgentActivityLog] {
        queue.sync { _activityLog }
    }

    /// Append a new activity log entry. Persists to Keychain automatically.
    func appendActivityLog(_ entry: AgentActivityLog) {
        queue.async(flags: .barrier) {
            guard !self._activityLog.contains(where: { $0.id == entry.id }) else { return }
            self._activityLog.insert(entry, at: 0)
            if self._activityLog.count > Self.maxEntries {
                self._activityLog = Array(self._activityLog.prefix(Self.maxEntries))
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

    // MARK: - Persistence

    private func loadAll() {
        if let data = keychain.load(key: Self.activityLogKey, service: Self.keychainService),
           let log = try? Self.decoder.decode([AgentActivityLog].self, from: data) {
            _activityLog = log
            SecureLogger.info("MINATO: restored \(log.count) activity log entry/entries", category: .session)
        }
    }

    private func persistActivityLog(_ log: [AgentActivityLog]) {
        guard let data = try? Self.encoder.encode(log) else { return }
        keychain.save(key: Self.activityLogKey, data: data, service: Self.keychainService, accessible: nil)
    }
}
