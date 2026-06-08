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

    // Safety / Disaster mode (iOS-derived extension, not in minato-spec).
    // Off by default — owners opt in, typically per emergency contact.
    // See: docs/MINATO-disaster-mode.md, docs/MINATO-message-shapes.md
    case safetyStatusWrite     = "safety.status.write"
    case safetyLocationCoarse  = "safety.location.coarse"
    case safetyLocationPrecise = "safety.location.precise"
    case safetyRelay           = "safety.relay"
    case safetyBroadcast       = "safety.broadcast"
    case safetyPersonSearch    = "safety.person_search"

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
        .safetyLocationPrecise
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

    // Safety / Disaster mode (iOS-derived extension, not in minato-spec).
    // See: docs/MINATO-disaster-mode.md, docs/MINATO-message-shapes.md
    case safetyCheckin          = "safety.checkin"
    case safetyRequestHelp      = "safety.request_help"
    case safetyResourceOffer    = "safety.resource_offer"
    case safetyResourceRequest  = "safety.resource_request"
    case safetyLocationShare    = "safety.location_share"
    case safetyEvacuationNotice = "safety.evacuation_notice"
    case safetyPersonSearch     = "safety.person_search"

    /// Default intents supported by a new agent.
    static let defaults: [Intent] = [
        .messageChat,
        .scheduleNegotiate,
        .scheduleConfirm,
        .infoExchange
    ]
}
