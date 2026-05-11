import Foundation

// MARK: - MINATO Message Types

/// MINATO Agent Protocol message types (0x30–0x37).
/// These extend Bitchat's MessageType enum with agent-specific semantics.
/// See: MINATO_PROTOCOL.md §5
enum MINATOMessageType: UInt8, CaseIterable {
    case agentHandshake = 0x30   // Initial connection and Agent Card exchange
    case agentMessage   = 0x31   // General conversation and information sharing
    case agentRequest   = 0x32   // Action request (e.g., add a calendar event)
    case agentResponse  = 0x33   // Response or proposal to a request
    case agentAck       = 0x34   // Confirmation or rejection
    case agentRevoke    = 0x35   // Permission revocation or disconnection
    case agentPing      = 0x36   // Liveness check and latency measurement
    case agentLog       = 0x37   // Post-hoc notification (Full Auto activity log)

    var description: String {
        switch self {
        case .agentHandshake: return "AGENT_HANDSHAKE"
        case .agentMessage:   return "AGENT_MESSAGE"
        case .agentRequest:   return "AGENT_REQUEST"
        case .agentResponse:  return "AGENT_RESPONSE"
        case .agentAck:       return "AGENT_ACK"
        case .agentRevoke:    return "AGENT_REVOKE"
        case .agentPing:      return "AGENT_PING"
        case .agentLog:       return "AGENT_LOG"
        }
    }

    /// Whether this message type requires Noise encryption for transport.
    /// Handshake and ping are cleartext; all others are encrypted.
    var requiresEncryption: Bool {
        switch self {
        case .agentHandshake, .agentPing:
            return false
        default:
            return true
        }
    }
}

// MARK: - MINATO Payload Envelope

/// Top-level envelope for all MINATO message payloads.
/// Serialized as JSON inside a BitchatPacket's payload field.
struct MINATOPayload: Codable {
    let type: String              // MINATOMessageType description (e.g., "AGENT_MESSAGE")
    let version: String           // Protocol version (e.g., "0.1")
    let from: String              // Sender's npub
    let to: String                // Recipient's npub
    let timestamp: UInt64         // Unix timestamp
    let nonce: String             // Random nonce for replay protection
    let payload: PayloadContent   // Type-specific content
    let signature: String?        // Ed25519 signature

    enum CodingKeys: String, CodingKey {
        case type, version, from, to, timestamp, nonce, payload, signature
    }

    /// Returns the canonical bytes to sign or verify: sorted-keys JSON with `signature` excluded.
    /// See MINATO_PROTOCOL.md §4 — Signature Canonical Form.
    func signaturePayloadData() -> Data? {
        let unsigned = MINATOPayload(
            type: type, version: version,
            from: from, to: to,
            timestamp: timestamp, nonce: nonce,
            payload: payload, signature: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(unsigned)
    }

    /// Returns a new MINATOPayload with the given Ed25519 signature applied.
    func withSignature(_ signatureHex: String) -> MINATOPayload {
        MINATOPayload(
            type: type, version: version,
            from: from, to: to,
            timestamp: timestamp, nonce: nonce,
            payload: payload, signature: signatureHex
        )
    }
}

/// Type-specific payload content, determined by the message type.
struct PayloadContent: Codable {
    let intent: String?
    let content: String?
    let originalLanguage: String?
    let translatedContent: String?
    let status: String?           // For AGENT_ACK: "confirmed" / "rejected"
    let requestId: String?        // For AGENT_REQUEST / AGENT_ACK
    let action: String?           // For AGENT_REQUEST: capability being invoked
    let scope: String?            // For AGENT_REVOKE: trust / agent_card / all
    let reason: String?           // For AGENT_REVOKE: human-readable reason
    let logId: String?            // For AGENT_LOG: idempotency key
    let trustMode: String?        // For AGENT_LOG: auto / full_auto
    let context: [String: AnyCodableValue]?
    let proposedEvent: ProposedEvent?
    let agentCard: AgentCard?     // For AGENT_HANDSHAKE

    enum CodingKeys: String, CodingKey {
        case intent, content, status, action, scope, reason, context
        case originalLanguage = "original_language"
        case translatedContent = "translated_content"
        case requestId = "request_id"
        case logId = "log_id"
        case trustMode = "trust_mode"
        case proposedEvent = "proposed_event"
        case agentCard = "agent_card"
    }

    init(
        intent: String?,
        content: String?,
        originalLanguage: String?,
        translatedContent: String?,
        status: String?,
        requestId: String?,
        action: String?,
        scope: String? = nil,
        reason: String? = nil,
        logId: String? = nil,
        trustMode: String? = nil,
        context: [String: AnyCodableValue]?,
        proposedEvent: ProposedEvent?,
        agentCard: AgentCard?
    ) {
        self.intent = intent
        self.content = content
        self.originalLanguage = originalLanguage
        self.translatedContent = translatedContent
        self.status = status
        self.requestId = requestId
        self.action = action
        self.scope = scope
        self.reason = reason
        self.logId = logId
        self.trustMode = trustMode
        self.context = context
        self.proposedEvent = proposedEvent
        self.agentCard = agentCard
    }
}

/// Scope affected by AGENT_REVOKE.
/// See MINATO_PROTOCOL.md §10 — AGENT_REVOKE.
enum RevokeScope: String, Codable, CaseIterable {
    case trust
    case agentCard = "agent_card"
    case all
}

/// Event proposal for schedule negotiation.
struct ProposedEvent: Codable {
    let title: String
    let start: String   // ISO 8601
    let end: String     // ISO 8601
    let location: String?
}

// MARK: - AnyCodableValue

/// Type-erased Codable value for flexible context dictionaries.
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode([AnyCodableValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: AnyCodableValue].self) { self = .dictionary(v); return }
        if container.decodeNil() { self = .null; return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}
