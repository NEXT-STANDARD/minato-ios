//
// ChatViewModel+MINATOAgent.swift
// bitchat
//
// MINATO agent protocol: handshake, trust mode, message handling, pending reply approval flow.
//

import Foundation
import BitLogger

/// A known MINATO contact eligible for an emergency override (E-4a).
struct EmergencyContact: Identifiable {
    let npub: String
    let displayName: String
    let override: EmergencyOverride?
    var id: String { npub }
}

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

    // MARK: - Disaster Mode (E-3a)

    /// Broadcasts the given safety check-in. Dual-path (E-5): always BLE mesh
    /// broadcast (coarse, to everyone nearby) plus directed Nostr gift-wrap to
    /// emergency-override contacts (store-and-forward, reaches them offline /
    /// out of mesh range).
    func broadcastSafetyCheckin(_ checkin: SafetyCheckin) {
        (meshService as? BLEService)?.sendSafetyCheckin(checkin)
        broadcastSafetyCheckinViaNostr(checkin)
    }

    /// Sends the check-in over Nostr (NIP-17 gift-wrap) to each emergency-override
    /// contact with a known npub. Embeds the local Agent Card so the recipient can
    /// verify it via TOFU even without a prior handshake.
    func broadcastSafetyCheckinViaNostr(_ checkin: SafetyCheckin) {
        let recipients = emergencyOverridePeerIDs()
        guard !recipients.isEmpty, let localCard = MINATOAgentStore.shared.localCard else { return }
        let now = UInt64(Date().timeIntervalSince1970)
        // Precise location (E-4b) is only ever attached here — over the encrypted
        // Nostr gift-wrap, never the cleartext BLE broadcast — and only for a
        // recipient whose active emergency override grants it.
        let preciseLocation = SafetyLocationProvider().preciseLocation(now: Date())

        for peerID in recipients {
            let npub = MINATOAgentStore.shared.remoteCard(for: peerID)?.agentId
            let settings = npub.flatMap { MINATOAgentStore.shared.trustSettings(for: $0) }
            let precision = SafetyLocationPolicy.allowedPrecision(for: settings, now: now)

            let recipientCheckin: SafetyCheckin
            if precision == .precise, let preciseLocation {
                recipientCheckin = checkin.withLocation(preciseLocation)
            } else {
                recipientCheckin = checkin   // coarse (from the store) or undisclosed
            }

            guard let contextValue = try? recipientCheckin.asContextValue() else { continue }
            let payloadContent = PayloadContent(
                intent: Intent.safetyCheckin.rawValue,
                content: recipientCheckin.content,
                originalLanguage: localCard.ownerLocale,
                translatedContent: nil,
                status: nil, requestId: nil, action: nil,
                context: [MINATOPayload.safetyCheckinContextKey: contextValue],
                proposedEvent: nil,
                agentCard: localCard
            )
            sendMINATOViaNostr(type: .agentMessage, payload: payloadContent, to: peerID)
        }
    }

    /// Request location permission + a fresh fix so disaster-mode check-ins can
    /// carry a coarse geohash. Called on activation.
    func prepareSafetyLocation() {
        LocationStateManager.shared.enableLocationChannels()
    }

    /// PeerIDs of known contacts that currently have an active emergency override.
    private func emergencyOverridePeerIDs() -> [PeerID] {
        let now = UInt64(Date().timeIntervalSince1970)
        var result: [PeerID] = []
        var seen = Set<String>()
        for (hexKey, card) in MINATOAgentStore.shared.allRemoteCards where !card.agentId.isEmpty {
            guard seen.insert(card.agentId).inserted else { continue }
            if let override = MINATOAgentStore.shared.trustSettings(for: card.agentId)?.emergencyOverride,
               override.isActive(now: now) {
                result.append(PeerID(str: hexKey))
            }
        }
        return result
    }

    /// Begin battery-throttled periodic re-broadcast (E-3b). Call on activation,
    /// after the initial broadcast.
    func startSafetyBroadcast() {
        safetyBroadcastScheduler.start()
    }

    /// Stop periodic re-broadcast when leaving disaster mode.
    func stopSafetyBroadcast() {
        safetyBroadcastScheduler.stop()
    }

    // MARK: - Emergency Override (E-4a)

    /// Known MINATO contacts (deduped by npub) with their current override state,
    /// for the emergency-contacts management UI.
    func emergencyContacts() -> [EmergencyContact] {
        var seen = Set<String>()
        var result: [EmergencyContact] = []
        for card in MINATOAgentStore.shared.allRemoteCards.values where !card.agentId.isEmpty {
            guard seen.insert(card.agentId).inserted else { continue }
            let override = MINATOAgentStore.shared.trustSettings(for: card.agentId)?.emergencyOverride
            result.append(EmergencyContact(npub: card.agentId, displayName: card.displayName, override: override))
        }
        return result.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Grant a time-boxed emergency override to a contact. Scoped to `safety.*`
    /// capabilities only — never escalates trust / schedule / message intents.
    func grantEmergencyOverride(
        npub: String,
        duration: EmergencyOverrideDuration,
        capabilities: [Capability] = Capability.safetyCapabilities
    ) {
        guard !npub.isEmpty else { return }
        var settings = MINATOAgentStore.shared.trustSettings(for: npub) ?? TrustSettings.defaultSettings()
        let now = UInt64(Date().timeIntervalSince1970)
        let safetyCaps = capabilities.filter { $0.isSafety }.map(\.rawValue)
        settings.emergencyOverride = EmergencyOverride(
            grantedAt: now,
            expiresAt: duration.expiry(from: now),
            capabilities: safetyCaps
        )
        settings.lastInteraction = now
        MINATOAgentStore.shared.updateTrustSettings(settings, for: npub)
        SecureLogger.info("Emergency override granted to \(npub.prefix(12)) dur=\(duration.rawValue) caps=\(safetyCaps.count)", category: .security)
        objectWillChange.send()
    }

    /// Revoke any emergency override for a contact (one-tap, no confirmation).
    func revokeEmergencyOverride(npub: String) {
        guard var settings = MINATOAgentStore.shared.trustSettings(for: npub) else { return }
        settings.emergencyOverride = nil
        settings.lastInteraction = UInt64(Date().timeIntervalSince1970)
        MINATOAgentStore.shared.updateTrustSettings(settings, for: npub)
        SecureLogger.info("Emergency override revoked for \(npub.prefix(12))", category: .security)
        objectWillChange.send()
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
