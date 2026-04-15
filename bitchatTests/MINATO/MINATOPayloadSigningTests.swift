import Foundation
import Testing
@testable import bitchat

// MARK: - MINATOPayload Signing Tests

@Suite("MINATOPayload Signing Tests")
struct MINATOPayloadSigningTests {

    // MARK: - Helpers

    private func makeService() -> NoiseEncryptionService {
        NoiseEncryptionService(keychain: MockKeychain())
    }

    private func makePayload(type: MINATOMessageType, content: String = "hello") -> MINATOPayload {
        MINATOPayload(
            type: type.description,
            version: "0.1",
            from: "npub1alicexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            to: "npub1bobxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            timestamp: 1712800000,
            nonce: UUID().uuidString,
            payload: PayloadContent(
                intent: "message.chat",
                content: content,
                originalLanguage: nil,
                translatedContent: nil,
                status: nil,
                requestId: nil,
                action: nil,
                context: nil,
                proposedEvent: nil,
                agentCard: nil
            ),
            signature: nil
        )
    }

    // MARK: - Round-Trip for All Message Types

    @Test("All MINATO message types sign and verify round-trip",
          arguments: MINATOMessageType.allCases)
    func allTypesRoundTrip(type: MINATOMessageType) throws {
        let service = makeService()
        let ed25519PubKeyHex = service.getSigningPublicKeyData().hexEncodedString()
        let unsigned = makePayload(type: type)

        let signed = MINATOSigning.sign(unsigned, using: service)

        #expect(signed.signature != nil, "Signature must be populated for \(type.description)")
        #expect(
            MINATOSigning.verify(signed, senderEd25519Hex: ed25519PubKeyHex),
            "\(type.description) round-trip verify must succeed"
        )
    }

    // MARK: - Tampering Detection

    @Test("Envelope verify fails when signature is nil")
    func verifyFailsWithNilSignature() {
        let service = makeService()
        let ed25519PubKeyHex = service.getSigningPublicKeyData().hexEncodedString()
        let unsigned = makePayload(type: .agentMessage)

        #expect(!MINATOSigning.verify(unsigned, senderEd25519Hex: ed25519PubKeyHex))
    }

    @Test("Envelope verify fails when signature is tampered")
    func verifyFailsWhenSignatureTampered() throws {
        let service = makeService()
        let ed25519PubKeyHex = service.getSigningPublicKeyData().hexEncodedString()
        let signed = MINATOSigning.sign(makePayload(type: .agentMessage), using: service)

        let originalSig = try #require(signed.signature)
        let tampered = signed.withSignature(String(originalSig.dropLast(2)) + "00")

        #expect(!MINATOSigning.verify(tampered, senderEd25519Hex: ed25519PubKeyHex))
    }

    @Test("Envelope verify fails when payload content is tampered")
    func verifyFailsWhenPayloadTampered() {
        let service = makeService()
        let ed25519PubKeyHex = service.getSigningPublicKeyData().hexEncodedString()
        let signed = MINATOSigning.sign(makePayload(type: .agentMessage, content: "hello"), using: service)

        // Preserve signature but swap content
        let tamperedContent = PayloadContent(
            intent: "message.chat",
            content: "injected",
            originalLanguage: nil,
            translatedContent: nil,
            status: nil,
            requestId: nil,
            action: nil,
            context: nil,
            proposedEvent: nil,
            agentCard: nil
        )
        let tampered = MINATOPayload(
            type: signed.type, version: signed.version,
            from: signed.from, to: signed.to,
            timestamp: signed.timestamp, nonce: signed.nonce,
            payload: tamperedContent, signature: signed.signature
        )

        #expect(!MINATOSigning.verify(tampered, senderEd25519Hex: ed25519PubKeyHex))
    }

    @Test("Envelope verify fails with wrong public key")
    func verifyFailsWithWrongPublicKey() {
        let serviceA = makeService()
        let serviceB = makeService()
        let signed = MINATOSigning.sign(makePayload(type: .agentMessage), using: serviceA)

        // Use B's public key to verify A's signature
        let bPubKeyHex = serviceB.getSigningPublicKeyData().hexEncodedString()
        #expect(!MINATOSigning.verify(signed, senderEd25519Hex: bPubKeyHex))
    }

    @Test("Envelope verify fails with invalid public key hex")
    func verifyFailsWithInvalidPublicKey() {
        let service = makeService()
        let signed = MINATOSigning.sign(makePayload(type: .agentRequest), using: service)

        #expect(!MINATOSigning.verify(signed, senderEd25519Hex: "notvalidhex"))
        #expect(!MINATOSigning.verify(signed, senderEd25519Hex: ""))
    }

    // MARK: - Canonical Form

    @Test("signaturePayloadData excludes signature field and is deterministic")
    func signaturePayloadDataIsStable() throws {
        let unsigned = makePayload(type: .agentMessage)

        let data1 = try #require(unsigned.signaturePayloadData())
        let data2 = try #require(unsigned.signaturePayloadData())

        #expect(data1 == data2, "signaturePayloadData must be deterministic")

        let json = try #require(String(data: data1, encoding: .utf8))
        #expect(!json.contains("\"signature\""), "Canonical payload must not contain signature key")
    }

    @Test("withSignature preserves all envelope fields")
    func withSignaturePreservesFields() {
        let unsigned = makePayload(type: .agentAck)
        let withSig = unsigned.withSignature("ab" + String(repeating: "cd", count: 63))

        #expect(withSig.type == unsigned.type)
        #expect(withSig.version == unsigned.version)
        #expect(withSig.from == unsigned.from)
        #expect(withSig.to == unsigned.to)
        #expect(withSig.timestamp == unsigned.timestamp)
        #expect(withSig.nonce == unsigned.nonce)
        #expect(withSig.signature != nil)
    }
}
