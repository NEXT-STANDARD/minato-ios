import Testing
import Foundation
@testable import bitchat

@Suite("Safety Check-in Envelope (E-2)")
struct SafetyCheckinEnvelopeTests {

    static func sampleCheckin() -> SafetyCheckin {
        SafetyCheckin(
            id: "safety-checkin-001",
            status: .needsHelp,
            content: "助けが必要です。近くの人に知らせてください。",
            battery: SafetyBatterySnapshot(
                level: 0.18,
                state: .unplugged,
                lowPowerMode: true,
                reportedAt: 1_712_800_200
            ),
            location: SafetyLocation(
                precision: .coarse,
                geohash: "xn76u",
                latitude: nil,
                longitude: nil,
                label: "渋谷区周辺"
            ),
            relay: SafetyRelayMetadata(
                delivery: .mesh,
                hops: 2,
                direct: false,
                lastSeenAt: 1_712_800_200,
                relaySeenAt: 1_712_800_260
            ),
            needs: [.water, .medical, .charging],
            expiresAt: 1_712_803_800
        )
    }

    static func sampleEnvelope() throws -> MINATOPayload {
        try MINATOPayload.safetyCheckin(
            from: "npub1alice000000000000000000000000000000000000000000000000",
            to: "npub1broadcast000000000000000000000000000000000000000000000",
            checkin: sampleCheckin(),
            timestamp: 1_712_800_200,
            nonce: "example-safety-001"
        )
    }

    @Test("builds an AGENT_MESSAGE envelope with safety.checkin intent")
    func buildsAgentMessageEnvelope() throws {
        let envelope = try Self.sampleEnvelope()
        #expect(envelope.type == MINATOMessageType.agentMessage.description)
        #expect(envelope.payload.intent == Intent.safetyCheckin.rawValue)
        #expect(envelope.payload.content == Self.sampleCheckin().content)
        #expect(envelope.isSafetyCheckin)
        #expect(envelope.payload.context?[MINATOPayload.safetyCheckinContextKey] != nil)
    }

    @Test("round-trips the check-in through the envelope JSON")
    func roundTripsThroughJSON() throws {
        let original = Self.sampleCheckin()
        let envelope = try Self.sampleEnvelope()

        let data = try JSONEncoder().encode(envelope)
        let decodedEnvelope = try JSONDecoder().decode(MINATOPayload.self, from: data)

        let decoded = try decodedEnvelope.decodedSafetyCheckin()
        #expect(decoded == original)
    }

    @Test("decodedSafetyCheckin returns nil for non-safety messages")
    func returnsNilForOtherMessages() throws {
        let content = PayloadContent(
            intent: Intent.messageChat.rawValue,
            content: "hello",
            originalLanguage: nil,
            translatedContent: nil,
            status: nil,
            requestId: nil,
            action: nil,
            context: nil,
            proposedEvent: nil,
            agentCard: nil
        )
        let envelope = MINATOPayload(
            type: MINATOMessageType.agentMessage.description,
            version: "0.1",
            from: "npub1a",
            to: "npub1b",
            timestamp: 1,
            nonce: "n",
            payload: content,
            signature: nil
        )
        #expect(envelope.isSafetyCheckin == false)
        #expect(try envelope.decodedSafetyCheckin() == nil)
    }

    @Test("signature canonical form excludes the signature and is stable")
    func signatureCanonicalFormIsStable() throws {
        let envelope = try Self.sampleEnvelope()
        let signed = envelope.withSignature(String(repeating: "c", count: 128))
        // Canonical signing bytes must ignore the signature field entirely.
        #expect(envelope.signaturePayloadData() == signed.signaturePayloadData())
        let canonical = try #require(signed.signaturePayloadData())
        #expect(!String(decoding: canonical, as: UTF8.self).contains("signature"))
    }

    @Test("safety.location.precise is high-risk, coarse is not")
    func preciseLocationIsHighRisk() {
        #expect(Capability.isHighRisk(Capability.safetyLocationPrecise.rawValue))
        #expect(Capability.isHighRisk(Capability.safetyLocationCoarse.rawValue) == false)
        #expect(Capability.highRisk.contains(.safetyLocationPrecise))
    }
}
