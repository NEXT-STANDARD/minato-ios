import Foundation

/// A time-boxed, per-contact grant that unlocks high-risk safety capabilities
/// (e.g. precise location) for a specific emergency contact during disaster
/// mode. Off by default; scoped to `safety.*` capabilities only; auto-expires.
///
/// Scope (E-4a). See: docs/MINATO-disaster-mode.md
struct EmergencyOverride: Codable, Equatable {
    let grantedAt: UInt64
    /// Absolute Unix expiry, or `nil` for "active until manually revoked /
    /// disaster mode ends".
    let expiresAt: UInt64?
    /// Granted `safety.*` capability rawValues (e.g. "safety.location.precise").
    let capabilities: [String]

    enum CodingKeys: String, CodingKey {
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case capabilities
    }

    /// Whether the override is currently in effect.
    func isActive(now: UInt64) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt > now
    }

    /// Whether the override currently grants the given capability.
    func grants(_ capability: String, now: UInt64) -> Bool {
        isActive(now: now) && capabilities.contains(capability)
    }
}

/// Duration options offered when granting an emergency override.
enum EmergencyOverrideDuration: String, CaseIterable, Identifiable {
    case sixHours
    case twelveHours
    case twentyFourHours
    case manual

    /// Conservative default — short windows limit accidental long-lived sharing.
    static let `default`: EmergencyOverrideDuration = .sixHours

    var id: String { rawValue }

    /// Seconds the override lasts, or `nil` for "until manually revoked".
    var seconds: UInt64? {
        switch self {
        case .sixHours: return 6 * 3600
        case .twelveHours: return 12 * 3600
        case .twentyFourHours: return 24 * 3600
        case .manual: return nil
        }
    }

    var displayNameJA: String {
        switch self {
        case .sixHours: return "6時間"
        case .twelveHours: return "12時間"
        case .twentyFourHours: return "24時間"
        case .manual: return "手動で解除するまで"
        }
    }

    /// Absolute expiry for a grant starting at `now` (nil for `.manual`).
    func expiry(from now: UInt64) -> UInt64? {
        seconds.map { now + $0 }
    }
}
