import Foundation

// MARK: - Agent Card

/// An agent's "business card" exchanged during handshake.
/// Declares the agent's capabilities, trust settings, and identity.
/// See: MINATO_PROTOCOL.md §4
struct AgentCard: Codable, Equatable {
    let minatoVersion: String         // Protocol version (e.g., "0.1")
    let agentId: String               // Nostr public key (npub format)
    let displayName: String           // User-configured agent name
    let ownerLocale: String           // Owner's primary language (BCP 47)
    let capabilities: [String]        // Permitted operations
    let defaultTrustMode: String      // Default trust mode for new connections
    let supportedIntents: [String]    // Supported intents
    let aiEngine: String              // AI engine in use (informational)
    let createdAt: UInt64             // Unix timestamp
    let signature: String?            // Ed25519 signature

    enum CodingKeys: String, CodingKey {
        case capabilities, signature
        case minatoVersion = "minato_version"
        case agentId = "agent_id"
        case displayName = "display_name"
        case ownerLocale = "owner_locale"
        case defaultTrustMode = "default_trust_mode"
        case supportedIntents = "supported_intents"
        case aiEngine = "ai_engine"
        case createdAt = "created_at"
    }
}

// MARK: - Agent Card Builder

extension AgentCard {
    /// Creates an unsigned Agent Card with the given parameters.
    /// Call `signed(with:)` to add an Ed25519 signature.
    static func create(
        agentId: String,
        displayName: String,
        ownerLocale: String = Locale.current.language.languageCode?.identifier ?? "en",
        capabilities: [Capability] = Capability.defaults,
        defaultTrustMode: TrustMode = .suggest,
        supportedIntents: [Intent] = Intent.defaults,
        aiEngine: String = "claude"
    ) -> AgentCard {
        AgentCard(
            minatoVersion: "0.1",
            agentId: agentId,
            displayName: displayName,
            ownerLocale: ownerLocale,
            capabilities: capabilities.map(\.rawValue),
            defaultTrustMode: defaultTrustMode.rawValue,
            supportedIntents: supportedIntents.map(\.rawValue),
            aiEngine: aiEngine,
            createdAt: UInt64(Date().timeIntervalSince1970),
            signature: nil
        )
    }

    /// Returns a new AgentCard with the Ed25519 signature populated.
    func signed(with signatureHex: String) -> AgentCard {
        AgentCard(
            minatoVersion: minatoVersion,
            agentId: agentId,
            displayName: displayName,
            ownerLocale: ownerLocale,
            capabilities: capabilities,
            defaultTrustMode: defaultTrustMode,
            supportedIntents: supportedIntents,
            aiEngine: aiEngine,
            createdAt: createdAt,
            signature: signatureHex
        )
    }

    /// Serializes the Agent Card to JSON Data (for signing and transport).
    func toJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }
}
