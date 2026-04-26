import Foundation

// MARK: - Capability

/// Operations that an agent can be permitted to perform.
/// Declared in the Agent Card and toggled by the user.
/// See: MINATO_PROTOCOL.md §8
enum Capability: String, Codable, CaseIterable {
    // Calendar
    case scheduleRead   = "schedule.read"
    case scheduleWrite  = "schedule.write"
    case scheduleDelete = "schedule.delete"

    // Messaging
    case messageReply    = "message.reply"
    case messageInitiate = "message.initiate"

    // Information
    case infoExchange      = "info.exchange"
    case languageTranslate = "language.translate"
    case locationArea      = "location.area"
    case locationPrecise   = "location.precise"

    // Remote control (Phase 4) — read-only commands a peer can issue against us.
    // `read` covers introspection (status, ping). `write` covers state-changing
    // commands (cancel a pending negotiation, mute auto-replies). Neither
    // capability is granted by default; users opt in per-peer.
    case remoteControlRead  = "remote.control.read"
    case remoteControlWrite = "remote.control.write"

    /// Default capabilities for a new agent.
    static let defaults: [Capability] = [
        .scheduleRead,
        .messageReply,
        .infoExchange,
        .languageTranslate
    ]

    /// High-risk capabilities that require explicit confirmation in `auto` mode.
    static let highRisk: Set<Capability> = [
        .scheduleWrite,
        .scheduleDelete,
        .locationPrecise,
        .remoteControlWrite
    ]

    /// Returns true if the given capability string is considered high-risk.
    static func isHighRisk(_ rawValue: String) -> Bool {
        guard let cap = Capability(rawValue: rawValue) else { return true }
        return highRisk.contains(cap)
    }
}

// MARK: - Intent

/// The purpose conveyed by a message payload.
/// See: MINATO_PROTOCOL.md §9
enum Intent: String, Codable, CaseIterable {
    case messageChat         = "message.chat"
    case scheduleNegotiate   = "schedule.negotiate"
    case scheduleConfirm     = "schedule.confirm"
    case scheduleCancel      = "schedule.cancel"
    case infoExchange        = "info.exchange"
    case trustUpgrade        = "trust.upgrade"
    case trustDowngrade      = "trust.downgrade"
    case connectionEstablish = "connection.establish"
    case connectionTerminate = "connection.terminate"

    /// Default intents supported by a new agent.
    static let defaults: [Intent] = [
        .messageChat,
        .scheduleNegotiate,
        .scheduleConfirm,
        .infoExchange
    ]
}
