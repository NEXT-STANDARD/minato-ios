import Foundation

// MARK: - Safety check-in ⇄ MINATO envelope (E-2)
//
// A safety check-in is an iOS-derived shape that rides on the existing
// `AGENT_MESSAGE` (0x31) message type rather than introducing a new wire type:
//   - `payload.intent`  = "safety.checkin" (`Intent.safetyCheckin`)
//   - `payload.content` = the human-readable status line
//   - `payload.context["safety_checkin"]` = the encoded `SafetyCheckin`
//
// Keeping the structured data under `payload.context` lets the existing
// envelope, canonical-signing, and transport paths carry it unchanged.
// See: docs/MINATO-message-shapes.md, docs/MINATO-disaster-mode.md

extension SafetyCheckin {
    /// Encode this check-in as a type-erased value for `payload.context`.
    func asContextValue() throws -> AnyCodableValue {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(AnyCodableValue.self, from: data)
    }

    /// Decode a check-in previously stored under `payload.context["safety_checkin"]`.
    init(contextValue: AnyCodableValue) throws {
        let data = try JSONEncoder().encode(contextValue)
        self = try JSONDecoder().decode(SafetyCheckin.self, from: data)
    }
}

extension MINATOPayload {
    /// Context key under which the encoded `SafetyCheckin` is carried.
    static let safetyCheckinContextKey = "safety_checkin"

    /// Mesh TTL used when broadcasting a safety check-in. Higher than the
    /// default agent-message TTL so check-ins reach further across the mesh
    /// during a disaster.
    static let safetyTTL: UInt8 = 5

    /// Best-effort delivery metadata derived from a received packet's TTL.
    /// `hops` = `safetyTTL - packetTTL` (0 when received directly). Approximate:
    /// assumes the sender used `safetyTTL`.
    static func deliveryMetadata(forPacketTTL packetTTL: UInt8) -> (delivery: SafetyRelayDelivery, hops: Int) {
        let hops = max(0, Int(safetyTTL) - Int(packetTTL))
        return (hops == 0 ? .direct : .mesh, hops)
    }

    /// Build an unsigned `AGENT_MESSAGE` envelope carrying a safety check-in.
    /// Sign it via `signaturePayloadData()` + `withSignature(_:)` before sending.
    static func safetyCheckin(
        from: String,
        to: String,
        checkin: SafetyCheckin,
        timestamp: UInt64,
        nonce: String,
        version: String = "0.1"
    ) throws -> MINATOPayload {
        let content = PayloadContent(
            intent: Intent.safetyCheckin.rawValue,
            content: checkin.content,
            originalLanguage: nil,
            translatedContent: nil,
            status: nil,
            requestId: nil,
            action: nil,
            context: [safetyCheckinContextKey: try checkin.asContextValue()],
            proposedEvent: nil,
            agentCard: nil
        )
        return MINATOPayload(
            type: MINATOMessageType.agentMessage.description,
            version: version,
            from: from,
            to: to,
            timestamp: timestamp,
            nonce: nonce,
            payload: content,
            signature: nil
        )
    }

    /// True when this envelope is an `AGENT_MESSAGE` carrying a safety check-in.
    var isSafetyCheckin: Bool {
        type == MINATOMessageType.agentMessage.description
            && payload.intent == Intent.safetyCheckin.rawValue
    }

    /// Extract the safety check-in from this envelope, if one is present.
    /// Returns `nil` when the envelope is not a safety check-in.
    func decodedSafetyCheckin() throws -> SafetyCheckin? {
        guard isSafetyCheckin,
              let value = payload.context?[Self.safetyCheckinContextKey] else {
            return nil
        }
        return try SafetyCheckin(contextValue: value)
    }

    /// Pure TOFU verification for a safety check-in that carries its own Agent
    /// Card. Verifies the card self-signature, that the envelope `from` matches
    /// the card identity, and the envelope signature against the card's key.
    ///
    /// - Parameter cachedKey: the Ed25519 key already cached for the sender, or
    ///   `nil` on first contact. A mismatch is rejected (no identity swap).
    /// - Returns: the verified Agent Card (to cache on first contact), or `nil`
    ///   if verification fails. The caller performs the cache side-effect.
    func verifiedSafetyCard(cachedKey: String?) -> AgentCard? {
        guard isSafetyCheckin,
              let card = payload.agentCard,
              let cardKey = card.ed25519PubKey,
              MINATOSigning.verify(card),
              from == card.agentId,
              MINATOSigning.verify(self, senderEd25519Hex: cardKey) else {
            return nil
        }
        if let cachedKey, cachedKey != cardKey {
            return nil
        }
        return card
    }
}
