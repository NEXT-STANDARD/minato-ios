import Foundation
import Testing
@testable import bitchat

@Suite("MINATO AGENT_REVOKE Tests")
struct AgentRevokeTests {

    @Test("Revoke payload round-trips with scope and reason")
    func revokePayloadRoundTrip() throws {
        let payload = PayloadContent(
            intent: Intent.connectionTerminate.rawValue,
            content: nil,
            originalLanguage: "ja",
            translatedContent: nil,
            status: nil,
            requestId: nil,
            action: nil,
            scope: RevokeScope.all.rawValue,
            reason: "Owner revoked this agent connection",
            context: ["initiated_by": .string("owner")],
            proposedEvent: nil,
            agentCard: nil
        )

        let envelope = MINATOPayload(
            type: MINATOMessageType.agentRevoke.description,
            version: "0.1",
            from: "npub1ds7azg0huz4lh84a7r49vhehmhkvsfgjds7azg0huz4lh84a7r49vhehmh",
            to: "npub12qrswl7u4t7qkm2rf8p5r6sfydexy6ea2qrswl7u4t7qkm2rf8p5r6sfyd",
            timestamp: 1_712_800_200,
            nonce: "revoke-001",
            payload: payload,
            signature: nil
        )

        let service = NoiseEncryptionService(keychain: MockKeychain())
        let signed = MINATOSigning.sign(envelope, using: service)
        let encoded = try JSONEncoder().encode(signed)
        let decoded = try JSONDecoder().decode(MINATOPayload.self, from: encoded)

        #expect(decoded.type == "AGENT_REVOKE")
        #expect(decoded.payload.intent == Intent.connectionTerminate.rawValue)
        #expect(decoded.payload.scope == RevokeScope.all.rawValue)
        #expect(decoded.payload.reason == "Owner revoked this agent connection")
        let initiatedBy: String?
        if case .string(let value) = decoded.payload.context?["initiated_by"] {
            initiatedBy = value
        } else {
            initiatedBy = nil
        }
        #expect(initiatedBy == "owner")
        #expect(MINATOSigning.verify(decoded, senderEd25519Hex: service.getSigningPublicKeyData().hexEncodedString()))
    }

    @Test("TrustStore removes persisted trust settings")
    @MainActor
    func trustStoreRemovesSettings() async {
        let store = TrustStore(keychain: MockKeychain())
        let npub = "npub1ds7azg0huz4lh84a7r49vhehmhkvsfgjds7azg0huz4lh84a7r49vhehmh"
        var settings = TrustSettings.defaultSettings()
        settings.mode = .fullAuto

        store.updateTrustSettings(settings, for: npub)
        let added = await TestHelpers.waitUntil({
            store.trustSettings(for: npub)?.mode == .fullAuto
        })
        #expect(added)

        store.removeTrustSettings(for: npub)
        let removed = await TestHelpers.waitUntil({
            store.trustSettings(for: npub) == nil
        })
        #expect(removed)
    }
}
