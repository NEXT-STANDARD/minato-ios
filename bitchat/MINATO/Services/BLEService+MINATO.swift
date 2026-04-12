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

        SecureLogger.info("Received Agent Card: \(card.displayName) [\(card.ownerLocale)] npub=\(card.agentId.prefix(12))", category: .session)

        MINATOAgentStore.shared.saveRemoteCard(card, for: senderID)

        // Bridge Agent Card npub to FavoritesPersistenceService for Nostr routing
        if let noiseKey = Data(hexString: senderID.id), !card.agentId.isEmpty {
            let agentId = card.agentId
            let displayName = card.displayName
            DispatchQueue.main.async {
                // Convert npub (bech32) to hex pubkey if needed
                let nostrPubkey: String
                if agentId.hasPrefix("npub1"), let decoded = try? Bech32.decode(agentId) {
                    nostrPubkey = decoded.data.hexEncodedString()
                } else {
                    nostrPubkey = agentId
                }
                FavoritesPersistenceService.shared.registerMINATOPeer(
                    noisePublicKey: noiseKey,
                    nostrPublicKey: nostrPubkey,
                    nickname: displayName
                )
            }
        }

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

        // Auto-reply only to human-originated messages (not to other auto-replies)
        if !isAutoReply {
            sendAIAgentReply(to: senderID, originalContent: originalContent ?? content, intent: intent)
        }
    }

    // MARK: - AI Agent Reply

    private func sendAIAgentReply(to peerID: PeerID, originalContent: String, intent: String?) {
        guard let localCard = MINATOAgentStore.shared.localCard else {
            SecureLogger.warning("MINATO: no local card, cannot reply", category: .session)
            return
        }

        // Lazy-initialize AI engine if not yet set but API key is available
        if MINATOAgentStore.shared.aiEngine == nil, let apiKey = GeminiAPIKey.default {
            MINATOAgentStore.shared.setAIEngine(GeminiEngine(apiKey: apiKey))
        }

        let hasEngine = MINATOAgentStore.shared.aiEngine != nil
        SecureLogger.info("MINATO: preparing reply (aiEngine=\(hasEngine ? "yes" : "no"))", category: .session)

        let remoteCard = MINATOAgentStore.shared.remoteCard(for: peerID)
        let trustMode = MINATOAgentStore.shared.trustSettings(for: remoteCard?.agentId ?? "")?.mode ?? .plan

        let context = AIContext(
            peerDisplayName: remoteCard?.displayName ?? "Unknown",
            peerLocale: remoteCard?.ownerLocale ?? "en",
            localLocale: localCard.ownerLocale,
            intent: intent,
            trustMode: trustMode,
            capabilities: localCard.capabilities
        )

        let localLang = localCard.ownerLocale

        // Gemini integration: temporarily disabled pending network debugging
        // Re-enable by uncommenting the line below
        // let engine = MINATOAgentStore.shared.aiEngine
        let engine: AIEngine? = nil
        if let engine = engine {
            SecureLogger.info("MINATO: calling Gemini API...", category: .session)
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    // 10-second timeout to prevent hanging
                    let reply = try await withThrowingTaskGroup(of: String.self) { group in
                        group.addTask {
                            try await engine.generateResponse(to: originalContent, context: context)
                        }
                        group.addTask {
                            try await Task.sleep(nanoseconds: 10_000_000_000)
                            throw AIEngineError.timeout
                        }
                        let result = try await group.next()!
                        group.cancelAll()
                        return result
                    }
                    SecureLogger.info("MINATO: Gemini replied (\(reply.count) chars)", category: .session)
                    guard !reply.isEmpty else {
                        self.sendFallbackReply(to: peerID, originalContent: originalContent, intent: intent, localLang: localLang)
                        return
                    }
                    self.sendAgentMessage(
                        to: peerID,
                        content: reply,
                        translatedContent: nil,
                        intent: intent ?? Intent.messageChat.rawValue,
                        isAutoReply: true
                    )
                } catch {
                    SecureLogger.warning("MINATO: AI error: \(error), using fallback", category: .session)
                    self.sendFallbackReply(to: peerID, originalContent: originalContent, intent: intent, localLang: localLang)
                }
            }
        } else {
            SecureLogger.info("MINATO: no AI engine, using fallback", category: .session)
            sendFallbackReply(to: peerID, originalContent: originalContent, intent: intent, localLang: localLang)
        }
    }

    private func sendFallbackReply(to peerID: PeerID, originalContent: String, intent: String?, localLang: String) {
        let reply: String
        if localLang.hasPrefix("ja") {
            reply = "メッセージを受け取りました: 「\(originalContent.prefix(30))」"
        } else {
            reply = "Message received: \"\(originalContent.prefix(30))\""
        }
        sendAgentMessage(to: peerID, content: reply, translatedContent: nil, intent: intent ?? Intent.messageChat.rawValue, isAutoReply: true)
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

    // MARK: - Nostr Dummy Reply

    /// Send an agent reply via Nostr path (called from ChatViewModel+Nostr).
    func sendDummyReplyViaNostr(to peerID: PeerID, originalContent: String, intent: String?) {
        // Reuse the same AI-powered reply logic
        sendAIAgentReply(to: peerID, originalContent: originalContent, intent: intent)
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
