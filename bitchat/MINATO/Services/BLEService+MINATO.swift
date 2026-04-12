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
            // These types will be implemented in Phase 3
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

        // Store the peer's Agent Card
        MINATOAgentStore.shared.saveRemoteCard(card, for: senderID)

        // Reply with our own Agent Card if we haven't already
        if !MINATOAgentStore.shared.hasExchangedWith(senderID) {
            MINATOAgentStore.shared.markExchanged(senderID)
            // TODO: Send our Agent Card back (requires wiring send path in BLEService)
            SecureLogger.info("Should reply with our Agent Card to \(senderID.id.prefix(8))", category: .session)
        }
    }

    // MARK: - Ping

    private func handleAgentPing(_ packet: BitchatPacket, from senderID: PeerID) {
        SecureLogger.debug("AGENT_PING from \(senderID.id.prefix(8))", category: .session)
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
