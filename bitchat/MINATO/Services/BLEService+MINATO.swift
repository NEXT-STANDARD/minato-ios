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
        case .agentMessage:
            handleAgentMessage(packet, from: senderID)
        case .agentPing:
            handleAgentPing(packet, from: senderID)
        case .agentRequest, .agentResponse, .agentAck, .agentRevoke, .agentLog:
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

    // MARK: - Agent Message

    private func handleAgentMessage(_ packet: BitchatPacket, from senderID: PeerID) {
        guard let payload = decodeMINATOPayload(packet.payload) else { return }

        let content = payload.payload.translatedContent ?? payload.payload.content ?? ""
        let intent = payload.payload.intent
        let originalContent = payload.payload.content
        let translatedContent = payload.payload.translatedContent

        // Check if this is an auto-reply (prevent infinite loop)
        let isAutoReply: Bool = {
            if let ctx = payload.payload.context,
               case .bool(let val) = ctx["auto_reply"] {
                return val
            }
            return false
        }()

        SecureLogger.info("AGENT_MESSAGE [\(intent ?? "chat")] from \(senderID.id.prefix(8)): \(content.prefix(50))\(isAutoReply ? " (auto-reply)" : "")", category: .session)

        // Notify delegate (ChatViewModel) to display in chat UI
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didReceiveAgentMessage(
                from: senderID,
                content: content,
                translatedContent: translatedContent,
                intent: intent,
                timestamp: Date()
            )
        }

        // Dummy agent: auto-reply only to human-originated messages (not to other auto-replies)
        if !isAutoReply {
            sendDummyAgentReply(to: senderID, originalContent: originalContent ?? content, intent: intent)
        }
    }

    // MARK: - Dummy Agent Reply

    private func sendDummyAgentReply(to peerID: PeerID, originalContent: String, intent: String?) {
        guard let localCard = MINATOAgentStore.shared.localCard else { return }
        let remoteCard = MINATOAgentStore.shared.remoteCard(for: peerID)
        let remoteLang = remoteCard?.ownerLocale ?? "en"
        let localLang = localCard.ownerLocale

        // Generate a contextual fixed response based on intent
        let (replyContent, replyTranslated) = generateDummyReply(
            intent: intent,
            originalContent: originalContent,
            localLang: localLang,
            remoteLang: remoteLang
        )

        sendAgentMessage(
            to: peerID,
            content: replyContent,
            translatedContent: replyTranslated,
            intent: intent ?? Intent.messageChat.rawValue,
            isAutoReply: true
        )
    }

    private func generateDummyReply(intent: String?, originalContent: String, localLang: String, remoteLang: String) -> (String, String?) {
        switch intent {
        case Intent.scheduleNegotiate.rawValue:
            if localLang.hasPrefix("ja") {
                return ("来週の木曜19時はいかがですか？", "How about next Thursday at 7 PM?")
            }
            return ("How about next Thursday at 7 PM?", "来週の木曜19時はいかがですか？")

        case Intent.scheduleConfirm.rawValue:
            if localLang.hasPrefix("ja") {
                return ("了解しました！カレンダーに追加しました。", "Got it! Added to calendar.")
            }
            return ("Got it! Added to calendar.", "了解しました！カレンダーに追加しました。")

        case Intent.infoExchange.rawValue:
            if localLang.hasPrefix("ja") {
                return ("はじめまして！MINATOエージェントです。よろしくお願いします。",
                        "Nice to meet you! I'm a MINATO agent. Looking forward to connecting.")
            }
            return ("Nice to meet you! I'm a MINATO agent. Looking forward to connecting.",
                    "はじめまして！MINATOエージェントです。よろしくお願いします。")

        default:
            // General chat reply
            if localLang.hasPrefix("ja") {
                return ("メッセージを受け取りました: 「\(originalContent.prefix(30))」",
                        "Message received: \"\(originalContent.prefix(30))\"")
            }
            return ("Message received: \"\(originalContent.prefix(30))\"",
                    "メッセージを受け取りました: 「\(originalContent.prefix(30))」")
        }
    }

    // MARK: - Send Agent Message

    /// Sends an AGENT_MESSAGE to a specific peer.
    func sendAgentMessage(to peerID: PeerID, content: String, translatedContent: String?, intent: String, isAutoReply: Bool = false) {
        let context: [String: AnyCodableValue]? = isAutoReply ? ["auto_reply": .bool(true)] : nil
        let payloadContent = PayloadContent(
            intent: intent,
            content: content,
            originalLanguage: MINATOAgentStore.shared.localCard?.ownerLocale,
            translatedContent: translatedContent,
            status: nil, requestId: nil, action: nil, context: context,
            proposedEvent: nil, agentCard: nil
        )

        guard let encoded = encodeMINATOPacket(
            type: .agentMessage,
            payload: payloadContent,
            to: peerID
        ) else { return }

        sendMINATOPacket(encoded, directedTo: peerID)
        SecureLogger.info("Sent AGENT_MESSAGE to \(peerID.id.prefix(8))", category: .session)
    }

    // MARK: - Send Handshake

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

    // MARK: - Ping

    private func handleAgentPing(_ packet: BitchatPacket, from senderID: PeerID) {
        SecureLogger.debug("AGENT_PING from \(senderID.id.prefix(8))", category: .session)
    }

    // MARK: - Encode Helper

    func encodeMINATOPacket(type: MINATOMessageType, payload: PayloadContent, to peerID: PeerID?) -> Data? {
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
