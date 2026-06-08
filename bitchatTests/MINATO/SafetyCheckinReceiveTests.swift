import Testing
import Foundation
@testable import bitchat

@Suite("Safety Check-in Receive / TOFU (E-3a)")
struct SafetyCheckinReceiveTests {

    private let agentId = "npub1testxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

    private func makeService() -> NoiseEncryptionService {
        NoiseEncryptionService(keychain: MockKeychain())
    }

    private func signedCard(service: NoiseEncryptionService, agentId: String) -> AgentCard {
        let unsigned = AgentCard.create(
            agentId: agentId,
            displayName: "Tester",
            ownerLocale: "ja",
            aiEngine: "claude",
            ed25519PubKey: service.getSigningPublicKeyData().hexEncodedString()
        )
        return MINATOSigning.sign(unsigned, using: service)
    }

    private func sampleCheckin() -> SafetyCheckin {
        SafetyCheckin.makeLocalPreview(
            status: .safe,
            battery: SafetyBatterySnapshot(level: 0.5, state: .unplugged, lowPowerMode: false, reportedAt: 1000)
        )
    }

    /// Builds a signed safety check-in envelope with the Agent Card embedded
    /// (mirrors BLEService.sendSafetyCheckin).
    private func makeEnvelope(service: NoiseEncryptionService, card: AgentCard, from: String) throws -> MINATOPayload {
        let content = PayloadContent(
            intent: Intent.safetyCheckin.rawValue,
            content: "無事です。",
            originalLanguage: nil, translatedContent: nil,
            status: nil, requestId: nil, action: nil,
            context: [MINATOPayload.safetyCheckinContextKey: try sampleCheckin().asContextValue()],
            proposedEvent: nil,
            agentCard: card
        )
        let unsigned = MINATOPayload(
            type: MINATOMessageType.agentMessage.description,
            version: "0.1", from: from, to: "",
            timestamp: 1, nonce: "n", payload: content, signature: nil
        )
        return MINATOSigning.sign(unsigned, using: service)
    }

    @Test("verifies a self-attested safety envelope on first contact")
    func verifiesFirstContact() throws {
        let service = makeService()
        let card = signedCard(service: service, agentId: agentId)
        let envelope = try makeEnvelope(service: service, card: card, from: agentId)

        let verified = envelope.verifiedSafetyCard(cachedKey: nil)
        #expect(verified != nil)
        #expect(verified?.agentId == agentId)
    }

    @Test("rejects when envelope from does not match the card identity")
    func rejectsFromMismatch() throws {
        let service = makeService()
        let card = signedCard(service: service, agentId: agentId)
        let envelope = try makeEnvelope(service: service, card: card, from: "npub1someoneelse")
        #expect(envelope.verifiedSafetyCard(cachedKey: nil) == nil)
    }

    @Test("rejects a tampered envelope signature")
    func rejectsTamperedEnvelope() throws {
        let service = makeService()
        let card = signedCard(service: service, agentId: agentId)
        let envelope = try makeEnvelope(service: service, card: card, from: agentId)
        let sig = try #require(envelope.signature)
        let tampered = envelope.withSignature(String(sig.dropLast(2)) + (sig.hasSuffix("00") ? "ff" : "00"))
        #expect(tampered.verifiedSafetyCard(cachedKey: nil) == nil)
    }

    @Test("rejects when a cached key for the sender differs (no identity swap)")
    func rejectsCachedKeyMismatch() throws {
        let service = makeService()
        let card = signedCard(service: service, agentId: agentId)
        let envelope = try makeEnvelope(service: service, card: card, from: agentId)
        #expect(envelope.verifiedSafetyCard(cachedKey: String(repeating: "ab", count: 32)) == nil)
    }

    @Test("accepts when the cached key matches the embedded card")
    func acceptsCachedKeyMatch() throws {
        let service = makeService()
        let card = signedCard(service: service, agentId: agentId)
        let envelope = try makeEnvelope(service: service, card: card, from: agentId)
        let key = try #require(card.ed25519PubKey)
        #expect(envelope.verifiedSafetyCard(cachedKey: key) != nil)
    }

    @Test("a non-safety message is not treated as a safety card")
    func nonSafetyReturnsNil() {
        let content = PayloadContent(
            intent: Intent.messageChat.rawValue, content: "hi",
            originalLanguage: nil, translatedContent: nil,
            status: nil, requestId: nil, action: nil, context: nil,
            proposedEvent: nil, agentCard: nil
        )
        let envelope = MINATOPayload(
            type: MINATOMessageType.agentMessage.description,
            version: "0.1", from: "a", to: "b", timestamp: 1, nonce: "n",
            payload: content, signature: nil
        )
        #expect(envelope.verifiedSafetyCard(cachedKey: nil) == nil)
    }

    @Test("delivery metadata derives direct vs relayed from packet TTL")
    func deliveryMetadataFromTTL() {
        #expect(MINATOPayload.deliveryMetadata(forPacketTTL: 5).delivery == .direct)
        #expect(MINATOPayload.deliveryMetadata(forPacketTTL: 5).hops == 0)
        #expect(MINATOPayload.deliveryMetadata(forPacketTTL: 4).delivery == .mesh)
        #expect(MINATOPayload.deliveryMetadata(forPacketTTL: 4).hops == 1)
        #expect(MINATOPayload.deliveryMetadata(forPacketTTL: 1).hops == 4)
        // Clamp when a packet somehow reports a higher TTL than our safety TTL.
        #expect(MINATOPayload.deliveryMetadata(forPacketTTL: 6).delivery == .direct)
        #expect(MINATOPayload.deliveryMetadata(forPacketTTL: 6).hops == 0)
    }
}
