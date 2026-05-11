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

        // Non-handshake packets must have a verified envelope signature.
        // Handshake verification happens inside handleAgentHandshake (AgentCard self-sig).
        if messageType != .agentHandshake && messageType != .agentPing {
            guard let payload = decodeMINATOPayload(packet.payload),
                  let remoteCard = MINATOAgentStore.shared.remoteCard(for: senderID),
                  let ed25519PubKeyHex = remoteCard.ed25519PubKey else {
                SecureLogger.warning("MINATO \(messageType.description): no verified Ed25519 key for \(senderID.id.prefix(8)), dropping", category: .security)
                return
            }
            guard MINATOSigning.verify(payload, senderEd25519Hex: ed25519PubKeyHex) else {
                SecureLogger.warning("MINATO \(messageType.description): invalid envelope signature from \(senderID.id.prefix(8)), dropping", category: .security)
                return
            }
        }

        SecureLogger.info("MINATO \(messageType.description) from \(senderID.id.prefix(8))", category: .session)

        switch messageType {
        case .agentHandshake:
            handleAgentHandshake(packet, from: senderID)
        case .agentMessage:
            handleAgentMessage(packet, from: senderID)
        case .agentPing:
            handleAgentPing(packet, from: senderID)
        case .agentRequest:
            handleAgentRequest(packet, from: senderID)
        case .agentResponse:
            handleAgentResponse(packet, from: senderID)
        case .agentAck:
            handleAgentAck(packet, from: senderID)
        case .agentRevoke:
            handleAgentRevoke(packet, from: senderID)
        case .agentLog:
            handleAgentLog(packet, from: senderID)
        }
    }

    // MARK: - Handshake

    private func handleAgentHandshake(_ packet: BitchatPacket, from senderID: PeerID) {
        guard let payload = decodeMINATOPayload(packet.payload),
              let card = payload.payload.agentCard else {
            SecureLogger.warning("AGENT_HANDSHAKE missing or invalid Agent Card", category: .session)
            return
        }

        // Verify AgentCard self-signature before trusting the sender
        guard MINATOSigning.verify(card) else {
            SecureLogger.warning("AGENT_HANDSHAKE rejected: invalid AgentCard signature from \(senderID.id.prefix(8))", category: .security)
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
            if MINATOAgentStore.shared.localCard != nil {
                MINATOAgentStore.shared.markExchanged(senderID)
                sendAgentHandshake(to: senderID)
            } else {
                SecureLogger.info("MINATO: deferring handshake reply (local card not ready)", category: .session)
            }
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
            ownerDisplayName: localCard.displayName,
            peerDisplayName: remoteCard?.displayName ?? "Unknown",
            peerLocale: remoteCard?.ownerLocale ?? "en",
            localLocale: localCard.ownerLocale,
            intent: intent,
            trustMode: trustMode,
            capabilities: localCard.capabilities
        )

        let localLang = localCard.ownerLocale

        let engine = MINATOAgentStore.shared.aiEngine
        // Plan mode: always require approval
        // Suggest mode: auto-send for short casual messages (greetings, acks) — still require approval for substantive
        // Auto/FullAuto: auto-execute (allowsAutoExecution = true)
        let requiresApproval: Bool = {
            switch trustMode {
            case .plan:
                return true
            case .suggest:
                // Auto-send short, casual messages; require approval for substantive ones
                return !Self.isLowStakesMessage(originalContent)
            case .auto, .fullAuto:
                return false
            }
        }()

        if let engine = engine {
            SecureLogger.info("MINATO: calling AI engine (\(engine.engineId)), approval=\(requiresApproval)...", category: .session)
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    let reply = try await engine.generateResponse(to: originalContent, context: context)
                    SecureLogger.info("MINATO: AI replied (\(reply.count) chars)", category: .session)
                    let replyText = reply.isEmpty ? nil : reply

                    if requiresApproval {
                        // Plan/Suggest: send interim ack to peer (throttled: once per 5 min)
                        if MINATOAgentStore.shared.checkAndMarkInterimAck(to: peerID) {
                            let ownerName = localCard.displayName
                            let ack = localLang.hasPrefix("ja")
                                ? "\(ownerName)に確認しますね！少々お待ちください。"
                                : "Let me check with \(ownerName). Please wait a moment."
                            self.sendAgentMessage(to: peerID, content: ack, translatedContent: nil,
                                                  intent: intent ?? Intent.messageChat.rawValue, isAutoReply: true)
                        }

                        let pending = PendingReply(
                            id: UUID().uuidString,
                            peerID: peerID,
                            originalMessage: originalContent,
                            proposedReply: replyText ?? originalContent,
                            intent: intent,
                            createdAt: Date()
                        )
                        MINATOAgentStore.shared.addPendingReply(pending)
                        SecureLogger.info("MINATO: queued pending reply for owner approval", category: .session)

                        // Notify owner via delegate (ChatViewModel) and local notification
                        let peerName = remoteCard?.displayName ?? "Unknown"
                        DispatchQueue.main.async { [weak self] in
                            self?.delegate?.didReceiveAgentPendingReply(
                                for: peerID,
                                originalMessage: originalContent,
                                proposedReply: replyText,
                                peerName: peerName
                            )
                        }
                    } else {
                        // Auto/FullAuto: send immediately, with translation if languages differ
                        guard let replyText = replyText else {
                            self.sendFallbackReply(to: peerID, originalContent: originalContent, intent: intent, localLang: localLang)
                            return
                        }
                        let peerLang = remoteCard?.ownerLocale ?? "en"
                        let translated = await self.translateIfNeeded(engine: engine, text: replyText, from: localLang, to: peerLang)
                        self.sendAgentMessage(to: peerID, content: replyText, translatedContent: translated,
                                              intent: intent ?? Intent.messageChat.rawValue, isAutoReply: true)

                        // AGENT_LOG: Record autonomous action (fullAuto mode especially)
                        if trustMode == .fullAuto || trustMode == .auto {
                            let peerName = remoteCard?.displayName ?? "Unknown"
                            let logEntry = AgentActivityLog(
                                id: UUID().uuidString,
                                peerID: peerID.id,
                                peerName: peerName,
                                action: .autoReply,
                                content: replyText,
                                intent: intent,
                                timestamp: Date()
                            )
                            MINATOAgentStore.shared.appendActivityLog(logEntry)
                            self.sendAgentLog(to: peerID, entry: logEntry, trustMode: trustMode)
                        }
                    }
                } catch {
                    SecureLogger.warning("MINATO: AI error: \(error), using fallback", category: .session)
                    if requiresApproval {
                        if MINATOAgentStore.shared.checkAndMarkInterimAck(to: peerID) {
                            let ownerName = localCard.displayName
                            let ack = localLang.hasPrefix("ja")
                                ? "\(ownerName)に確認しますね！少々お待ちください。"
                                : "Let me check with \(ownerName). Please wait a moment."
                            self.sendAgentMessage(to: peerID, content: ack, translatedContent: nil,
                                                  intent: intent ?? Intent.messageChat.rawValue, isAutoReply: true)
                        }
                        // No AI proposal available — owner will reply manually
                        let peerName = remoteCard?.displayName ?? "Unknown"
                        DispatchQueue.main.async { [weak self] in
                            self?.delegate?.didReceiveAgentPendingReply(
                                for: peerID,
                                originalMessage: originalContent,
                                proposedReply: nil,
                                peerName: peerName
                            )
                        }
                    } else {
                        self.sendFallbackReply(to: peerID, originalContent: originalContent, intent: intent, localLang: localLang)
                    }
                }
            }
        } else {
            SecureLogger.info("MINATO: no AI engine, using fallback", category: .session)
            if requiresApproval {
                if MINATOAgentStore.shared.checkAndMarkInterimAck(to: peerID) {
                    let ownerName = localCard.displayName
                    let ack = localLang.hasPrefix("ja")
                        ? "\(ownerName)に確認しますね！少々お待ちください。"
                        : "Let me check with \(ownerName). Please wait a moment."
                    sendAgentMessage(to: peerID, content: ack, translatedContent: nil,
                                     intent: intent ?? Intent.messageChat.rawValue, isAutoReply: true)
                }
                let peerName = remoteCard?.displayName ?? "Unknown"
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.didReceiveAgentPendingReply(
                        for: peerID,
                        originalMessage: originalContent,
                        proposedReply: nil,
                        peerName: peerName
                    )
                }
            } else {
                sendFallbackReply(to: peerID, originalContent: originalContent, intent: intent, localLang: localLang)
            }
        }
    }

    /// Translates text if source and target locales differ. Returns nil if same language or on error.
    private func translateIfNeeded(engine: AIEngine, text: String, from source: String, to target: String) async -> String? {
        let sourceLang = String(source.prefix(2))
        let targetLang = String(target.prefix(2))
        guard sourceLang != targetLang else { return nil }
        do {
            let translated = try await engine.translateMessage(text, from: source, to: target)
            SecureLogger.info("MINATO: translated (\(sourceLang)→\(targetLang)): \(translated.prefix(30))...", category: .session)
            return translated.isEmpty ? nil : translated
        } catch {
            SecureLogger.warning("MINATO: translation failed: \(error)", category: .session)
            return nil
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

    // MARK: - Message Classification

    /// Low-stakes messages (greetings, short acks) that suggest mode can auto-send.
    /// Plan mode always requires approval; this only applies to suggest mode.
    static func isLowStakesMessage(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Very short messages (< 15 chars) are likely casual
        if trimmed.count < 15 { return true }

        let lower = trimmed.lowercased()
        let casualPatterns = [
            // Japanese greetings/acks
            "こんにちは", "おはよう", "おやすみ", "ありがとう", "了解", "わかった", "ok", "はい", "いいえ",
            "お疲れ", "よろしく", "じゃあね", "またね", "うん", "そう", "そうだね",
            // English
            "hi", "hello", "hey", "thanks", "thank you", "ok", "okay", "sure", "yes", "no",
            "sounds good", "got it", "understood", "bye", "see you", "good morning", "good night"
        ]
        return casualPatterns.contains { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasSuffix(" " + $0) }
    }

    // MARK: - Ping

    private func handleAgentPing(_ packet: BitchatPacket, from senderID: PeerID) {
        SecureLogger.debug("AGENT_PING from \(senderID.id.prefix(8))", category: .session)
    }

    // MARK: - Schedule Negotiation Handlers

    private func handleAgentRequest(_ packet: BitchatPacket, from senderID: PeerID) {
        guard let payload = decodeMINATOPayload(packet.payload) else {
            SecureLogger.warning("AGENT_REQUEST missing payload", category: .session)
            return
        }

        let requestId = payload.payload.requestId ?? UUID().uuidString
        let intent = payload.payload.intent
        let action = payload.payload.action
        let proposedEvent = payload.payload.proposedEvent
        let content = payload.payload.translatedContent ?? payload.payload.content
        let translatedContent = payload.payload.translatedContent

        SecureLogger.info("AGENT_REQUEST [\(action ?? "?")] req=\(requestId.prefix(8)) from \(senderID.id.prefix(8))", category: .session)

        // Track the negotiation
        let negotiation = ScheduleNegotiation(
            id: requestId,
            peerID: senderID,
            initiatedByLocal: false,
            proposedEvent: proposedEvent,
            state: .proposed,
            createdAt: Date(),
            updatedAt: Date()
        )
        MINATOAgentStore.shared.addNegotiation(negotiation)

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didReceiveAgentRequest(
                from: senderID,
                requestId: requestId,
                intent: intent,
                action: action,
                proposedEvent: proposedEvent,
                content: content,
                translatedContent: translatedContent,
                timestamp: Date()
            )
        }
    }

    private func handleAgentResponse(_ packet: BitchatPacket, from senderID: PeerID) {
        guard let payload = decodeMINATOPayload(packet.payload) else {
            SecureLogger.warning("AGENT_RESPONSE missing payload", category: .session)
            return
        }

        let requestId = payload.payload.requestId ?? "unknown"
        let proposedEvent = payload.payload.proposedEvent
        let content = payload.payload.translatedContent ?? payload.payload.content
        let translatedContent = payload.payload.translatedContent
        let status = payload.payload.status

        SecureLogger.info("AGENT_RESPONSE req=\(requestId.prefix(8)) from \(senderID.id.prefix(8))", category: .session)

        // Update negotiation state
        if let event = proposedEvent {
            MINATOAgentStore.shared.updateNegotiation(requestId: requestId, state: .counterOffered, event: event)
        }

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didReceiveAgentResponse(
                from: senderID,
                requestId: requestId,
                proposedEvent: proposedEvent,
                content: content,
                translatedContent: translatedContent,
                status: status,
                timestamp: Date()
            )
        }
    }

    private func handleAgentAck(_ packet: BitchatPacket, from senderID: PeerID) {
        guard let payload = decodeMINATOPayload(packet.payload) else {
            SecureLogger.warning("AGENT_ACK missing payload", category: .session)
            return
        }

        let requestId = payload.payload.requestId ?? "unknown"
        let status = payload.payload.status ?? "unknown"
        let content = payload.payload.translatedContent ?? payload.payload.content
        let translatedContent = payload.payload.translatedContent

        SecureLogger.info("AGENT_ACK req=\(requestId.prefix(8)) status=\(status) from \(senderID.id.prefix(8))", category: .session)

        // Update negotiation state
        let newState: ScheduleNegotiation.State = status == "confirmed" ? .confirmed : .rejected
        MINATOAgentStore.shared.updateNegotiation(requestId: requestId, state: newState)

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didReceiveAgentAck(
                from: senderID,
                requestId: requestId,
                status: status,
                content: content,
                translatedContent: translatedContent,
                timestamp: Date()
            )
        }
    }

    // MARK: - AGENT_REVOKE

    private func handleAgentRevoke(_ packet: BitchatPacket, from senderID: PeerID) {
        guard let payload = decodeMINATOPayload(packet.payload) else {
            SecureLogger.warning("AGENT_REVOKE missing payload", category: .session)
            return
        }

        let revokePayload = payload.payload
        guard revokePayload.intent == Intent.connectionTerminate.rawValue else {
            SecureLogger.warning("AGENT_REVOKE rejected: invalid intent from \(senderID.id.prefix(8))", category: .security)
            return
        }

        let scope = RevokeScope(rawValue: revokePayload.scope ?? RevokeScope.all.rawValue) ?? .all
        applyAgentRevoke(peerID: senderID, agentId: payload.from, scope: scope)

        let reason = revokePayload.reason ?? "no reason"
        SecureLogger.info("AGENT_REVOKE scope=\(scope.rawValue) from \(senderID.id.prefix(8)): \(reason)", category: .session)
    }

    private func applyAgentRevoke(peerID: PeerID, agentId: String, scope: RevokeScope) {
        switch scope {
        case .trust:
            MINATOAgentStore.shared.removeTrustSettings(for: agentId)
            MINATOAgentStore.shared.removePendingReply(for: peerID)
        case .agentCard:
            MINATOAgentStore.shared.removeRemoteCard(for: peerID)
            MINATOAgentStore.shared.removePendingReply(for: peerID)
        case .all:
            MINATOAgentStore.shared.removeTrustSettings(for: agentId)
            MINATOAgentStore.shared.removeRemoteCard(for: peerID)
            MINATOAgentStore.shared.removePendingReply(for: peerID)
        }
    }

    // MARK: - AGENT_LOG

    private func handleAgentLog(_ packet: BitchatPacket, from senderID: PeerID) {
        guard let payload = decodeMINATOPayload(packet.payload) else {
            SecureLogger.warning("AGENT_LOG missing payload", category: .session)
            return
        }

        let logPayload = payload.payload
        guard let logId = logPayload.logId,
              let actionRaw = logPayload.action,
              let action = AgentActivityLog.ActionType.fromProtocolValue(actionRaw),
              let content = logPayload.content,
              let trustModeRaw = logPayload.trustMode,
              let trustMode = TrustMode(rawValue: trustModeRaw),
              trustMode == .auto || trustMode == .fullAuto else {
            SecureLogger.warning("AGENT_LOG rejected: invalid payload from \(senderID.id.prefix(8))", category: .security)
            return
        }

        let remoteCard = MINATOAgentStore.shared.remoteCard(for: senderID)
        let peerName = remoteCard?.displayName ?? "Unknown"
        let entry = AgentActivityLog(
            id: logId,
            peerID: senderID.id,
            peerName: peerName,
            action: action,
            content: content,
            intent: logPayload.intent,
            timestamp: Date(timeIntervalSince1970: TimeInterval(payload.timestamp))
        )
        MINATOAgentStore.shared.appendActivityLog(entry)
        SecureLogger.info("AGENT_LOG action=\(action.protocolValue) trust=\(trustMode.rawValue) from \(senderID.id.prefix(8))", category: .session)
    }

    // MARK: - Send Schedule Messages

    /// Sends an AGENT_LOG as a post-hoc notification for an autonomous action.
    func sendAgentLog(to peerID: PeerID, entry: AgentActivityLog, trustMode: TrustMode) {
        let payloadContent = PayloadContent(
            intent: entry.intent,
            content: entry.content,
            originalLanguage: nil,
            translatedContent: nil,
            status: nil,
            requestId: nil,
            action: entry.action.protocolValue,
            logId: entry.id,
            trustMode: trustMode.rawValue,
            context: [
                "peer_id": .string(entry.peerID),
                "peer_name": .string(entry.peerName)
            ],
            proposedEvent: nil,
            agentCard: nil
        )

        guard let encoded = encodeMINATOPacket(type: .agentLog, payload: payloadContent, to: peerID) else { return }
        sendMINATOPacket(encoded, directedTo: peerID)
        SecureLogger.info("Sent AGENT_LOG id=\(entry.id.prefix(8)) action=\(entry.action.protocolValue) to \(peerID.id.prefix(8))", category: .session)
    }

    /// Sends an AGENT_REVOKE and applies the same revoke scope locally after the packet is queued.
    func sendAgentRevoke(to peerID: PeerID, scope: RevokeScope = .all, reason: String? = nil) {
        let remoteAgentId = MINATOAgentStore.shared.remoteCard(for: peerID)?.agentId
        let payloadContent = PayloadContent(
            intent: Intent.connectionTerminate.rawValue,
            content: nil,
            originalLanguage: MINATOAgentStore.shared.localCard?.ownerLocale,
            translatedContent: nil,
            status: nil, requestId: nil, action: nil,
            scope: scope.rawValue,
            reason: reason,
            context: nil,
            proposedEvent: nil,
            agentCard: nil
        )

        guard let encoded = encodeMINATOPacket(type: .agentRevoke, payload: payloadContent, to: peerID) else { return }
        sendMINATOPacket(encoded, directedTo: peerID)

        if let remoteAgentId {
            applyAgentRevoke(peerID: peerID, agentId: remoteAgentId, scope: scope)
        }
        SecureLogger.info("Sent AGENT_REVOKE scope=\(scope.rawValue) to \(peerID.id.prefix(8))", category: .session)
    }

    /// Sends an AGENT_REQUEST (e.g., schedule proposal).
    func sendAgentRequest(to peerID: PeerID, requestId: String, intent: String, action: String, proposedEvent: ProposedEvent?, content: String?, translatedContent: String?) {
        let payloadContent = PayloadContent(
            intent: intent,
            content: content,
            originalLanguage: MINATOAgentStore.shared.localCard?.ownerLocale,
            translatedContent: translatedContent,
            status: nil, requestId: requestId, action: action, context: nil,
            proposedEvent: proposedEvent, agentCard: nil
        )

        guard let encoded = encodeMINATOPacket(type: .agentRequest, payload: payloadContent, to: peerID) else { return }
        sendMINATOPacket(encoded, directedTo: peerID)
        SecureLogger.info("Sent AGENT_REQUEST [\(action)] req=\(requestId.prefix(8)) to \(peerID.id.prefix(8))", category: .session)
    }

    /// Sends an AGENT_RESPONSE (e.g., counter-proposal).
    func sendAgentResponse(to peerID: PeerID, requestId: String, proposedEvent: ProposedEvent?, content: String?, translatedContent: String?, status: String?) {
        let payloadContent = PayloadContent(
            intent: Intent.scheduleNegotiate.rawValue,
            content: content,
            originalLanguage: MINATOAgentStore.shared.localCard?.ownerLocale,
            translatedContent: translatedContent,
            status: status, requestId: requestId, action: nil, context: nil,
            proposedEvent: proposedEvent, agentCard: nil
        )

        guard let encoded = encodeMINATOPacket(type: .agentResponse, payload: payloadContent, to: peerID) else { return }
        sendMINATOPacket(encoded, directedTo: peerID)
        SecureLogger.info("Sent AGENT_RESPONSE req=\(requestId.prefix(8)) to \(peerID.id.prefix(8))", category: .session)
    }

    /// Sends an AGENT_ACK (confirm or reject).
    func sendAgentAck(to peerID: PeerID, requestId: String, status: String, content: String?, translatedContent: String?) {
        let payloadContent = PayloadContent(
            intent: status == "confirmed" ? Intent.scheduleConfirm.rawValue : Intent.scheduleCancel.rawValue,
            content: content,
            originalLanguage: MINATOAgentStore.shared.localCard?.ownerLocale,
            translatedContent: translatedContent,
            status: status, requestId: requestId, action: nil, context: nil,
            proposedEvent: nil, agentCard: nil
        )

        guard let encoded = encodeMINATOPacket(type: .agentAck, payload: payloadContent, to: peerID) else { return }
        sendMINATOPacket(encoded, directedTo: peerID)
        SecureLogger.info("Sent AGENT_ACK req=\(requestId.prefix(8)) status=\(status) to \(peerID.id.prefix(8))", category: .session)
    }

    // MARK: - Encode Helper

    func encodeMINATOPacket(type: MINATOMessageType, payload: PayloadContent, to peerID: PeerID?) -> Data? {
        guard let localCard = MINATOAgentStore.shared.localCard else { return nil }

        // Resolve recipient npub from remote card (protocol spec §10 requires non-empty `to`)
        let toNpub: String = {
            guard let pid = peerID else { return "" }
            return MINATOAgentStore.shared.remoteCard(for: pid)?.agentId ?? ""
        }()

        let unsigned = MINATOPayload(
            type: type.description,
            version: "0.1",
            from: localCard.agentId,
            to: toNpub,
            timestamp: UInt64(Date().timeIntervalSince1970),
            nonce: UUID().uuidString,
            payload: payload,
            signature: nil
        )
        let envelope = MINATOSigning.sign(unsigned, using: getNoiseService())

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
