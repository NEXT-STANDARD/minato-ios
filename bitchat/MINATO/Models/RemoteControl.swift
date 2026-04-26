import Foundation

// MARK: - Remote Control Action

/// Allowlisted remote-control commands carried over `AGENT_REQUEST` (0x32)
/// using the `remote.*` action namespace. Responses come back on `AGENT_RESPONSE`
/// (0x33) with `status` set to one of `RemoteControlStatus`.
///
/// The set is intentionally narrow: every command here is either read-only or
/// reversible. New commands MUST go through capability gating in
/// `Capability.highRisk` before being added.
enum RemoteControlAction: String, CaseIterable {
    /// Read the peer agent's runtime state (online flag, trust mode, AI engine).
    /// Requires `remote.control.read`.
    case status = "remote.status"

    /// Round-trip liveness probe with response. Distinct from fire-and-forget
    /// `AGENT_PING` (0x36) in that the requester gets back an `AGENT_RESPONSE`
    /// with `latency_ms` measured by the receiver.
    /// Requires `remote.control.read`.
    case ping = "remote.ping"

    /// Cancel an in-flight schedule negotiation by `request_id`. The peer must
    /// be the one that initiated the negotiation (or the canceller must be a
    /// participant); otherwise the receiver replies with `denied`.
    /// Requires `remote.control.write`.
    case cancel = "remote.cancel"

    /// Temporarily suppress automatic AI replies from the receiver to the
    /// requester. Reversed by `remote.unmute`.
    /// Requires `remote.control.write`.
    case mute = "remote.mute"

    /// Reverse a previous `remote.mute`. No-op if not currently muted.
    /// Requires `remote.control.write`.
    case unmute = "remote.unmute"

    /// Capability that gates execution of this command on the receiver side.
    var requiredCapability: Capability {
        switch self {
        case .status, .ping:
            return .remoteControlRead
        case .cancel, .mute, .unmute:
            return .remoteControlWrite
        }
    }

    /// Whether the command mutates state on the receiver.
    var mutatesState: Bool {
        switch self {
        case .status, .ping:
            return false
        case .cancel, .mute, .unmute:
            return true
        }
    }

    /// Parses a payload `action` string. Returns nil if the string is not a
    /// recognised remote-control command (including non-`remote.*` actions).
    static func parse(_ action: String?) -> RemoteControlAction? {
        guard let action = action else { return nil }
        return RemoteControlAction(rawValue: action)
    }
}

// MARK: - Remote Control Status

/// Status field used in the `AGENT_RESPONSE` for a remote-control reply.
enum RemoteControlStatus: String {
    case ok        = "ok"          // Command succeeded
    case denied    = "denied"      // Capability or trust check rejected the command
    case notFound  = "not_found"   // E.g. cancel referenced an unknown request_id
    case unknown   = "unknown"     // Receiver does not recognise the action
    case error     = "error"       // Internal failure on the receiver
}
