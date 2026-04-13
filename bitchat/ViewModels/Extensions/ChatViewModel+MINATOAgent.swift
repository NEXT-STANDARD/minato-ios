//
// ChatViewModel+MINATOAgent.swift
// bitchat
//
// MINATO agent protocol: handshake, trust mode, message handling, pending reply approval flow.
//

import Foundation

extension ChatViewModel {

    // MARK: - MINATO Trust Mode

    /// Updates the trust mode for a MINATO peer.
    func updateTrustMode(for peerID: PeerID, to mode: TrustMode) {
        guard let match = MINATOAgentStore.shared.findRemoteCard(for: peerID) else { return }
        var settings = MINATOAgentStore.shared.trustSettings(for: match.card.agentId) ?? TrustSettings.defaultSettings()
        settings.mode = mode
        settings.lastInteraction = UInt64(Date().timeIntervalSince1970)
        MINATOAgentStore.shared.updateTrustSettings(settings, for: match.card.agentId)
        objectWillChange.send()
    }

    // MARK: - Handshake Initiation

    /// Send MINATO handshake if localCard is ready; otherwise wait for the notification.
    @MainActor
    func initiateMINATOHandshakeIfReady(with peerID: PeerID) {
        guard !MINATOAgentStore.shared.hasExchangedWith(peerID),
              let bleService = meshService as? BLEService else { return }

        if MINATOAgentStore.shared.localCard != nil {
            bleService.sendAgentHandshake(to: peerID)
        } else {
            // Remove any previous deferred observer for this peer to prevent leaks
            if let existing = handshakeDeferObservers[peerID] {
                NotificationCenter.default.removeObserver(existing)
            }
            // Local card not yet ready — listen for it
            let observer = NotificationCenter.default.addObserver(
                forName: MINATOAgentStore.localCardDidSetNotification,
                object: nil, queue: .main
            ) { [weak self, weak bleService] _ in
                guard let self else { return }
                if let obs = self.handshakeDeferObservers.removeValue(forKey: peerID) {
                    NotificationCenter.default.removeObserver(obs)
                }
                guard let bleService,
                      !MINATOAgentStore.shared.hasExchangedWith(peerID) else { return }
                bleService.sendAgentHandshake(to: peerID)
            }
            handshakeDeferObservers[peerID] = observer
        }
    }

    // MARK: - MINATO Agent Message Delegate

    func didReceiveAgentMessage(from peerID: PeerID, content: String, translatedContent: String?, intent: String?, timestamp: Date) {
        Task { @MainActor in
            let card = MINATOAgentStore.shared.remoteCard(for: peerID)
            let agentName = card.map { "🤖 \($0.displayName)" } ?? "🤖 Agent-\(peerID.id.prefix(4))"

            // Display the translated content if available, original otherwise
            let displayContent = translatedContent ?? content

            let msg = BitchatMessage(
                id: UUID().uuidString,
                sender: agentName,
                content: displayContent,
                timestamp: timestamp,
                isRelay: false,
                isPrivate: true,
                recipientNickname: nickname,
                senderPeerID: peerID,
                mentions: nil,
                deliveryStatus: nil
            )

            if privateChats[peerID] == nil {
                privateChats[peerID] = []
            }
            privateChats[peerID]?.append(msg)

            if selectedPrivateChatPeer != peerID {
                unreadPrivateMessages.insert(peerID)
            }

            objectWillChange.send()
        }
    }

    // MARK: - Pending Reply Handling

    func didReceiveAgentPendingReply(for peerID: PeerID, originalMessage: String, proposedReply: String?, peerName: String) {
        Task { @MainActor in
            if let proposed = proposedReply {
                let pending = PendingReply(
                    id: UUID().uuidString,
                    peerID: peerID,
                    originalMessage: originalMessage,
                    proposedReply: proposed,
                    intent: nil,
                    createdAt: Date()
                )
                pendingReplies[peerID.id] = pending
            }
            objectWillChange.send()

            // Send local notification
            NotificationService.shared.sendAgentConfirmationNotification(
                from: peerName,
                message: originalMessage,
                peerID: peerID
            )
        }
    }

    /// Owner approves the AI-proposed reply — send it to the peer.
    @MainActor
    func approvePendingReply(for peerID: PeerID) {
        guard let pending = pendingReplies[peerID.id] else { return }
        sendAgentMessage(pending.proposedReply, to: peerID, suppressAutoReply: true)
        pendingReplies.removeValue(forKey: peerID.id)
        MINATOAgentStore.shared.removePendingReply(for: peerID)
    }

    /// Owner edits the reply and sends their own version.
    @MainActor
    func editPendingReply(for peerID: PeerID, content: String) {
        pendingReplies.removeValue(forKey: peerID.id)
        MINATOAgentStore.shared.removePendingReply(for: peerID)
        sendAgentMessage(content, to: peerID, suppressAutoReply: true)
    }

    /// Owner dismisses the pending reply without sending.
    @MainActor
    func dismissPendingReply(for peerID: PeerID) {
        pendingReplies.removeValue(forKey: peerID.id)
        MINATOAgentStore.shared.removePendingReply(for: peerID)
        objectWillChange.send()
    }

    // MARK: - Send Agent Message

    /// Send a message via the MINATO agent protocol to a peer.
    /// - Parameter suppressAutoReply: If true, the receiving agent will NOT auto-reply (used for approved/edited replies).
    @MainActor
    func sendAgentMessage(_ content: String, to peerID: PeerID, suppressAutoReply: Bool = false) {
        guard meshService as? BLEService != nil else { return }

        // Auto-dismiss any pending reply when owner sends manually
        if pendingReplies[peerID.id] != nil {
            pendingReplies.removeValue(forKey: peerID.id)
            MINATOAgentStore.shared.removePendingReply(for: peerID)
        }

        // Add our message to the chat UI
        let msg = BitchatMessage(
            id: UUID().uuidString,
            sender: nickname,
            content: content,
            timestamp: Date(),
            isRelay: false,
            isPrivate: true,
            recipientNickname: nil,
            senderPeerID: meshService.myPeerID,
            mentions: nil,
            deliveryStatus: nil
        )

        if privateChats[peerID] == nil {
            privateChats[peerID] = []
        }
        privateChats[peerID]?.append(msg)
        objectWillChange.send()

        // Translate if peer speaks a different language, then send via unified transport
        let localLang = MINATOAgentStore.shared.localCard?.ownerLocale ?? "ja"
        let peerLang = MINATOAgentStore.shared.remoteCard(for: peerID)?.ownerLocale ?? "en"

        Task { @MainActor in
            let translated = await self.translateOwnerMessage(content, from: localLang, to: peerLang)
            let context: [String: AnyCodableValue]? = suppressAutoReply ? ["auto_reply": .bool(true)] : nil
            let payload = PayloadContent(
                intent: Intent.messageChat.rawValue,
                content: content,
                originalLanguage: localLang,
                translatedContent: translated,
                status: nil, requestId: nil, action: nil, context: context,
                proposedEvent: nil, agentCard: nil
            )
            self.sendMINATO(type: .agentMessage, payload: payload, to: peerID)
        }
    }
}
