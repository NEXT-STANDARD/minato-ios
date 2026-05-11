import Foundation
import Testing
@testable import bitchat

@Suite("MINATO AGENT_LOG Tests")
struct AgentLogTests {

    @Test("Action types map to protocol snake_case values")
    func actionProtocolValues() {
        #expect(AgentActivityLog.ActionType.autoReply.protocolValue == "auto_reply")
        #expect(AgentActivityLog.ActionType.autoScheduleAck.protocolValue == "auto_schedule_ack")
        #expect(AgentActivityLog.ActionType.autoScheduleReject.protocolValue == "auto_schedule_reject")
        #expect(AgentActivityLog.ActionType.fromProtocolValue("auto_reply") == .autoReply)
        #expect(AgentActivityLog.ActionType.fromProtocolValue("auto_schedule_ack") == .autoScheduleAck)
        #expect(AgentActivityLog.ActionType.fromProtocolValue("auto_schedule_reject") == .autoScheduleReject)
        #expect(AgentActivityLog.ActionType.fromProtocolValue("autoReply") == nil)
    }

    @Test("Log payload round-trips with idempotency key and trust mode")
    func logPayloadRoundTrip() throws {
        let payload = PayloadContent(
            intent: Intent.messageChat.rawValue,
            content: "メッセージを受け取り、自動返信しました。",
            originalLanguage: nil,
            translatedContent: nil,
            status: nil,
            requestId: nil,
            action: AgentActivityLog.ActionType.autoReply.protocolValue,
            logId: "log-20260413-0001",
            trustMode: TrustMode.fullAuto.rawValue,
            context: ["source_transport": .string("ble")],
            proposedEvent: nil,
            agentCard: nil
        )

        let envelope = MINATOPayload(
            type: MINATOMessageType.agentLog.description,
            version: "0.1",
            from: "npub1ds7azg0huz4lh84a7r49vhehmhkvsfgjds7azg0huz4lh84a7r49vhehmh",
            to: "npub12qrswl7u4t7qkm2rf8p5r6sfydexy6ea2qrswl7u4t7qkm2rf8p5r6sfyd",
            timestamp: 1_712_800_300,
            nonce: "agent-log-001",
            payload: payload,
            signature: nil
        )

        let service = NoiseEncryptionService(keychain: MockKeychain())
        let signed = MINATOSigning.sign(envelope, using: service)
        let encoded = try JSONEncoder().encode(signed)
        let decoded = try JSONDecoder().decode(MINATOPayload.self, from: encoded)

        #expect(decoded.type == "AGENT_LOG")
        #expect(decoded.payload.logId == "log-20260413-0001")
        #expect(decoded.payload.action == "auto_reply")
        #expect(decoded.payload.trustMode == "full_auto")
        #expect(decoded.payload.intent == Intent.messageChat.rawValue)
        #expect(MINATOSigning.verify(decoded, senderEd25519Hex: service.getSigningPublicKeyData().hexEncodedString()))
    }

    @Test("ActivityLogStore deduplicates by log id")
    @MainActor
    func activityLogDeduplicatesById() async {
        let store = ActivityLogStore(keychain: MockKeychain())
        let entry = AgentActivityLog(
            id: "log-duplicate",
            peerID: "0123456789abcdef",
            peerName: "Alice",
            action: .autoReply,
            content: "hello",
            intent: Intent.messageChat.rawValue,
            timestamp: Date()
        )

        store.appendActivityLog(entry)
        store.appendActivityLog(entry)

        let deduped = await TestHelpers.waitUntil({
            store.activityLog(for: PeerID(str: "0123456789abcdef")).count == 1
        })
        #expect(deduped)
    }
}
