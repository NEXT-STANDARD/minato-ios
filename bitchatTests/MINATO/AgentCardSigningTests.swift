import Foundation
import Testing
@testable import bitchat

// MARK: - AgentCard Signing Tests

@Suite("AgentCard Signing Tests")
struct AgentCardSigningTests {

    // MARK: - Helpers

    private func makeService() -> NoiseEncryptionService {
        NoiseEncryptionService(keychain: MockKeychain())
    }

    private func makeUnsignedCard(service: NoiseEncryptionService) -> AgentCard {
        AgentCard.create(
            agentId: "npub1testxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            displayName: "Test Agent",
            ownerLocale: "ja",
            aiEngine: "claude",
            ed25519PubKey: service.getSigningPublicKeyData().hexEncodedString()
        )
    }

    // MARK: - Sign / Verify Round-Trip

    @Test("AgentCard sign and verify round-trip succeeds")
    func signVerifyRoundTrip() throws {
        let service = makeService()
        let unsigned = makeUnsignedCard(service: service)

        let signed = MINATOSigning.sign(unsigned, using: service)

        #expect(signed.signature != nil, "Signature must be populated after signing")
        #expect(signed.ed25519PubKey != nil, "ed25519_pub_key must be set")
        #expect(MINATOSigning.verify(signed), "Freshly signed card must verify")
    }

    @Test("AgentCard verify fails when signature is nil")
    func verifyFailsWhenSignatureIsNil() {
        let service = makeService()
        let unsigned = makeUnsignedCard(service: service)

        #expect(!MINATOSigning.verify(unsigned), "Unsigned card must not verify")
    }

    @Test("AgentCard verify fails when signature is tampered")
    func verifyFailsWhenSignatureTampered() throws {
        let service = makeService()
        let unsigned = makeUnsignedCard(service: service)
        let signed = MINATOSigning.sign(unsigned, using: service)

        let originalSig = try #require(signed.signature)
        // Flip last two hex chars to corrupt the signature
        let tamperedSig = String(originalSig.dropLast(2)) + "00"
        let tampered = signed.signed(with: tamperedSig)

        #expect(!MINATOSigning.verify(tampered), "Tampered signature must not verify")
    }

    @Test("AgentCard verify fails when payload is tampered")
    func verifyFailsWhenPayloadTampered() {
        let service = makeService()
        let unsigned = makeUnsignedCard(service: service)
        let signed = MINATOSigning.sign(unsigned, using: service)

        // Preserve the signature but change the display name — breaks canonical hash
        let tampered = AgentCard(
            minatoVersion: signed.minatoVersion,
            agentId: signed.agentId,
            displayName: "Mallory",
            ownerLocale: signed.ownerLocale,
            capabilities: signed.capabilities,
            defaultTrustMode: signed.defaultTrustMode,
            supportedIntents: signed.supportedIntents,
            aiEngine: signed.aiEngine,
            createdAt: signed.createdAt,
            ed25519PubKey: signed.ed25519PubKey,
            signature: signed.signature
        )
        #expect(!MINATOSigning.verify(tampered), "Card with tampered payload must not verify")
    }

    @Test("AgentCard verify fails when ed25519PubKey is missing")
    func verifyFailsWhenPubKeyMissing() {
        // Create a card without an ed25519PubKey
        let unsigned = AgentCard.create(
            agentId: "npub1testxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            displayName: "Test Agent"
        )
        let fakeSignature = String(repeating: "ab", count: 64) // 128-char hex
        let withSig = unsigned.signed(with: fakeSignature)

        #expect(!MINATOSigning.verify(withSig), "Card without ed25519PubKey must not verify")
    }

    @Test("signaturePayloadData excludes signature field")
    func signaturePayloadDataExcludesSignature() throws {
        let service = makeService()
        let signed = MINATOSigning.sign(makeUnsignedCard(service: service), using: service)

        let canonicalData = try #require(signed.signaturePayloadData())
        let json = try #require(String(data: canonicalData, encoding: .utf8))
        #expect(!json.contains("\"signature\""), "Canonical payload must not contain signature key")
        #expect(json.contains("\"ed25519_pub_key\""), "Canonical payload must include ed25519_pub_key")
    }

    @Test("Two different NoiseEncryptionService instances cannot verify each other's cards")
    func differentServicesCannotCrossVerify() {
        let serviceA = makeService()
        let serviceB = makeService() // Independent key pair

        let cardA = MINATOSigning.sign(makeUnsignedCard(service: serviceA), using: serviceA)

        // Try to verify A's card with B's public key embedded — should fail
        let cardWithBKey = AgentCard(
            minatoVersion: cardA.minatoVersion,
            agentId: cardA.agentId,
            displayName: cardA.displayName,
            ownerLocale: cardA.ownerLocale,
            capabilities: cardA.capabilities,
            defaultTrustMode: cardA.defaultTrustMode,
            supportedIntents: cardA.supportedIntents,
            aiEngine: cardA.aiEngine,
            createdAt: cardA.createdAt,
            ed25519PubKey: serviceB.getSigningPublicKeyData().hexEncodedString(),
            signature: cardA.signature
        )
        #expect(!MINATOSigning.verify(cardWithBKey), "Signature by A must not verify against B's public key")
    }
}
