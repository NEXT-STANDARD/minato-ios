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
}
