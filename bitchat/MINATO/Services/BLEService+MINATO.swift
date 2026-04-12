import BitLogger
import Foundation

// MARK: - BLEService MINATO Extension

extension BLEService {

    /// Routes incoming MINATO packets (0x30–0x37) to the appropriate handler.
    func handleMINATOPacket(_ packet: BitchatPacket, from senderID: PeerID) {
        guard let messageType = MINATOMessageType(rawValue: packet.type) else {
            SecureLogger.warning("Unknown MINATO type: \(packet.type)", category: .session)
            return
        }

        SecureLogger.info("MINATO \(messageType.description) from \(senderID.id.prefix(8))", category: .session)

        switch messageType {
        case .agentHandshake:
            handleAgentHandshake(packet, from: senderID)
        case .agentPing:
            handleAgentPing(packet, from: senderID)
        case .agentMessage, .agentRequest, .agentResponse, .agentAck,
             .agentRevoke, .agentLog:
            SecureLogger.debug("MINATO \(messageType.description) received (handler pending)", category: .session)
        }
    }

    // MARK: - Handshake

    private func handleAgentHandshake(_ packet: BitchatPacket, from senderID: PeerID) {
        guard let payload = decodeMINATOPayload(packet.payload),
              let card = payload.payload.agentCard else {
            SecureLogger.warning("AGENT_HANDSHAKE missing or invalid Agent Card", category: .session)
            return
        }

        SecureLogger.info("Received Agent Card: \(card.displayName) [\(card.ownerLocale)]", category: .session)

        MINATOAgentStore.shared.saveRemoteCard(card, for: senderID)

        if !MINATOAgentStore.shared.hasExchangedWith(senderID) {
            MINATOAgentStore.shared.markExchanged(senderID)
            sendAgentHandshake(to: senderID)
        }
    }

    // MARK: - Ping

    private func handleAgentPing(_ packet: BitchatPacket, from senderID: PeerID) {
        SecureLogger.debug("AGENT_PING from \(senderID.id.prefix(8))", category: .session)
    }

    // MARK: - Send

    /// Sends our Agent Card as a handshake to the specified peer.
    func sendAgentHandshake(to peerID: PeerID) {
        guard let localCard = MINATOAgentStore.shared.localCard else {
            SecureLogger.warning("Cannot send handshake: no local Agent Card", category: .session)
            return
        }

        let payloadContent = PayloadContent(
            intent: Intent.connectionEstablish.rawValue,
            content: nil, originalLanguage: nil, translatedContent: nil,
            status: nil, requestId: nil, action: nil, context: nil,
            proposedEvent: nil, agentCard: localCard
        )

        guard let encoded = encodeMINATOPacket(
            type: .agentHandshake,
            payload: payloadContent,
            to: peerID
        ) else { return }

        sendMINATOPacket(encoded, directedTo: peerID)
        SecureLogger.info("Sent Agent Card to \(peerID.id.prefix(8))", category: .session)
    }

    // MARK: - Encode Helper

    private func encodeMINATOPacket(type: MINATOMessageType, payload: PayloadContent, to peerID: PeerID?) -> Data? {
        guard let localCard = MINATOAgentStore.shared.localCard else { return nil }

        let envelope = MINATOPayload(
            type: type.description,
            version: "0.1",
            from: localCard.agentId,
            to: peerID.map { _ in "" } ?? "",
            timestamp: UInt64(Date().timeIntervalSince1970),
            nonce: UUID().uuidString,
            payload: payload,
            signature: nil
        )

        guard let jsonData = try? JSONEncoder().encode(envelope) else {
            SecureLogger.warning("Failed to encode MINATO payload", category: .session)
            return nil
        }

        let packet = BitchatPacket(
            type: type.rawValue,
            senderID: Data(hexString: myPeerID.id) ?? Data(),
            recipientID: peerID.flatMap { Data(hexString: $0.id) },
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: jsonData,
            signature: nil,
            ttl: 3
        )

        return BinaryProtocol.encode(packet)
    }

    // MARK: - Decode Helper

    private func decodeMINATOPayload(_ data: Data) -> MINATOPayload? {
        do {
            return try JSONDecoder().decode(MINATOPayload.self, from: data)
        } catch {
            SecureLogger.warning("Failed to decode MINATO payload: \(error.localizedDescription)", category: .session)
            return nil
        }
    }
}
