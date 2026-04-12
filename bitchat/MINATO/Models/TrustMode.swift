import Foundation

// MARK: - Trust Mode

/// Autonomy level setting for agent interactions.
/// Users set this per-peer to control how much the agent can do automatically.
/// See: MINATO_PROTOCOL.md §7
enum TrustMode: String, Codable, CaseIterable {
    case plan      = "plan"       // Apprentice: confirm before every action
    case suggest   = "suggest"    // Partner: confirm once before execution
    case auto      = "auto"       // Lieutenant: auto for low-risk, confirm high-risk
    case fullAuto  = "full_auto"  // Alter Ego: fully autonomous, post-hoc notification

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .plan:     return "Apprentice"
        case .suggest:  return "Partner"
        case .auto:     return "Lieutenant"
        case .fullAuto: return "Alter Ego"
        }
    }

    /// Japanese display name (for UI localization).
    var displayNameJA: String {
        switch self {
        case .plan:     return "見習い"
        case .suggest:  return "相棒"
        case .auto:     return "右腕"
        case .fullAuto: return "分身"
        }
    }

    /// Whether this mode allows any automatic execution.
    var allowsAutoExecution: Bool {
        switch self {
        case .plan, .suggest: return false
        case .auto, .fullAuto: return true
        }
    }
}

// MARK: - Trust Settings

/// Per-peer trust configuration stored locally.
struct TrustSettings: Codable, Equatable {
    var mode: TrustMode
    let customPermissions: [String: Bool]   // Capability overrides
    let establishedAt: UInt64               // Unix timestamp
    var lastInteraction: UInt64             // Unix timestamp

    enum CodingKeys: String, CodingKey {
        case mode
        case customPermissions = "custom_permissions"
        case establishedAt = "established_at"
        case lastInteraction = "last_interaction"
    }

    /// Creates default trust settings for a new peer.
    static func defaultSettings() -> TrustSettings {
        let now = UInt64(Date().timeIntervalSince1970)
        return TrustSettings(
            mode: .plan,
            customPermissions: [:],
            establishedAt: now,
            lastInteraction: now
        )
    }

    /// Whether a specific capability is allowed under current trust settings.
    func isCapabilityAllowed(_ capability: String) -> Bool {
        // Custom override takes precedence
        if let override = customPermissions[capability] {
            return override
        }
        // Fall back to mode-based risk assessment
        return mode.allowsAutoExecution || !Capability.isHighRisk(capability)
    }
}
