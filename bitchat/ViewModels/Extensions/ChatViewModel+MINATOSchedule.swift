//
// ChatViewModel+MINATOSchedule.swift
// bitchat
//
// MINATO schedule negotiation: REQUEST/RESPONSE/ACK delegates, owner actions,
// group schedule, calendar integration, @mention resolution.
//

import Foundation

extension ChatViewModel {

    // MARK: - Formatting

    static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let eventDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "M/d (EEE) HH:mm"
        return f
    }()

    /// Format ISO 8601 timestamp for display.
    static func formatEventTime(_ isoString: String) -> String {
        guard let date = iso8601Formatter.date(from: isoString) else { return isoString }
        return eventDisplayFormatter.string(from: date)
    }

    /// Detect schedule intent from message content using keyword matching.
    /// Fast (no AI call) — used as pre-filter before AI classification.
    /// The AI makes the final decision via `isSchedule` field.
    static func hasScheduleIntent(_ content: String) -> Bool {
        let lower = content.lowercased()

        // Quick reject for common idioms that contain keywords but aren't schedule requests
        let negativePatterns = [
            "free software", "free will", "free time is",
            "feel free", "for free",
            "hang in there", "hang on",
            "yesterday", "last night", "last week",
            "i had dinner", "i had lunch",
            "meeting was", "meeting went",
        ]
        if negativePatterns.contains(where: { lower.contains($0) }) {
            return false
        }

        let keywords = [
            // Japanese
            "暇", "空いてる", "空いている", "予定", "スケジュール",
            "飯", "ご飯", "食事", "飲み", "飲もう", "飲みに",
            "ランチ", "ディナー", "会おう", "会わない", "集まり",
            "何時", "いつ", "今夜", "今晩", "明日", "週末", "来週",
            // English
            "free", "available", "schedule", "meet", "meeting",
            "dinner", "lunch", "drinks", "grab", "hangout", "hang out",
            "tonight", "tomorrow", "weekend", "next week", "what time"
        ]
        return keywords.contains { lower.contains($0) }
    }

    // MARK: - Schedule Negotiation Delegates

    func didReceiveAgentRequest(from peerID: PeerID, requestId: String, intent: String?, action: String?, proposedEvent: ProposedEvent?, content: String?, translatedContent: String?, timestamp: Date) {
        Task { @MainActor in
            let card = MINATOAgentStore.shared.remoteCard(for: peerID)
            let peerName = card?.displayName ?? "Agent-\(peerID.id.prefix(4))"

            // Display the proposal in chat
            let displayContent: String
            if let event = proposedEvent {
                displayContent = "📅 \(event.title)\n🕐 \(Self.formatEventTime(event.start)) – \(Self.formatEventTime(event.end))\(event.location.map { "\n📍 \($0)" } ?? "")"
            } else {
                displayContent = translatedContent ?? content ?? ""
            }

            let msg = BitchatMessage(
                id: requestId,
                sender: "🤖 \(peerName)",
                content: displayContent,
                timestamp: timestamp,
                isRelay: false,
                isPrivate: true,
                recipientNickname: nickname,
                senderPeerID: peerID,
                mentions: nil,
                deliveryStatus: nil
            )

            if privateChats[peerID] == nil { privateChats[peerID] = [] }
            privateChats[peerID]?.append(msg)

            // Queue for owner approval if there's a proposed event
            if let event = proposedEvent {
                let approval = PendingScheduleApproval(
                    requestId: requestId,
                    peerID: peerID,
                    proposedEvent: event,
                    content: content,
                    translatedContent: translatedContent,
                    peerName: peerName,
                    createdAt: Date()
                )
                pendingScheduleApprovals[requestId] = approval

                // Async conflict check (requires calendar access)
                Task { [weak self] in
                    guard let self else { return }
                    let hasConflict = await self.checkCalendarConflictAsync(event)
                    await MainActor.run {
                        if var updated = self.pendingScheduleApprovals[requestId] {
                            updated.hasConflict = hasConflict
                            self.pendingScheduleApprovals[requestId] = updated
                            self.objectWillChange.send()
                        }
                    }
                }
                MINATOAgentStore.shared.addPendingScheduleApproval(approval)

                NotificationService.shared.sendAgentConfirmationNotification(
                    from: peerName,
                    message: "📅 \(event.title)",
                    peerID: peerID,
                    requestId: requestId
                )
            }

            if selectedPrivateChatPeer != peerID {
                unreadPrivateMessages.insert(peerID)
            }
            objectWillChange.send()
        }
    }

    func didReceiveAgentResponse(from peerID: PeerID, requestId: String, proposedEvent: ProposedEvent?, content: String?, translatedContent: String?, status: String?, timestamp: Date) {
        Task { @MainActor in
            let card = MINATOAgentStore.shared.remoteCard(for: peerID)
            let peerName = card?.displayName ?? "Agent-\(peerID.id.prefix(4))"

            let displayContent: String
            if let event = proposedEvent {
                displayContent = "🔄 別日提案:\n📅 \(event.title)\n🕐 \(Self.formatEventTime(event.start)) – \(Self.formatEventTime(event.end))\(event.location.map { "\n📍 \($0)" } ?? "")"
            } else {
                displayContent = translatedContent ?? content ?? ""
            }

            let msg = BitchatMessage(
                id: UUID().uuidString,
                sender: "🤖 \(peerName)",
                content: displayContent,
                timestamp: timestamp,
                isRelay: false,
                isPrivate: true,
                recipientNickname: nickname,
                senderPeerID: peerID,
                mentions: nil,
                deliveryStatus: nil
            )

            if privateChats[peerID] == nil { privateChats[peerID] = [] }
            privateChats[peerID]?.append(msg)

            if let event = proposedEvent {
                let approval = PendingScheduleApproval(
                    requestId: requestId,
                    peerID: peerID,
                    proposedEvent: event,
                    content: content,
                    translatedContent: translatedContent,
                    peerName: peerName,
                    createdAt: Date()
                )
                pendingScheduleApprovals[requestId] = approval
                MINATOAgentStore.shared.addPendingScheduleApproval(approval)
            }

            if selectedPrivateChatPeer != peerID {
                unreadPrivateMessages.insert(peerID)
            }
            objectWillChange.send()
        }
    }

    func didReceiveAgentAck(from peerID: PeerID, requestId: String, status: String, content: String?, translatedContent: String?, timestamp: Date) {
        Task { @MainActor in
            let card = MINATOAgentStore.shared.remoteCard(for: peerID)
            let peerName = card?.displayName ?? "Agent-\(peerID.id.prefix(4))"

            // Check if this ACK belongs to a GROUP negotiation we initiated
            if let group = MINATOAgentStore.shared.groupNegotiation(for: requestId) {
                self.handleGroupAck(group: group, fromPeerID: peerID, peerName: peerName, status: status, timestamp: timestamp)
                return
            }

            let emoji = status == "confirmed" ? "✅" : "❌"
            let statusText = status == "confirmed" ? "確定" : "辞退"
            let eventDetails: String
            if status == "confirmed",
               let negotiation = MINATOAgentStore.shared.negotiation(for: requestId),
               let event = negotiation.proposedEvent {
                eventDetails = "\n📅 \(event.title)\n🕐 \(Self.formatEventTime(event.start)) – \(Self.formatEventTime(event.end))\(event.location.map { "\n📍 \($0)" } ?? "")"
            } else {
                eventDetails = translatedContent.map { "\n\($0)" } ?? content.map { "\n\($0)" } ?? ""
            }
            let displayContent = "\(emoji) スケジュール\(statusText)\(eventDetails)"

            let msg = BitchatMessage(
                id: UUID().uuidString,
                sender: "🤖 \(peerName)",
                content: displayContent,
                timestamp: timestamp,
                isRelay: false,
                isPrivate: true,
                recipientNickname: nickname,
                senderPeerID: peerID,
                mentions: nil,
                deliveryStatus: nil
            )

            if privateChats[peerID] == nil { privateChats[peerID] = [] }
            privateChats[peerID]?.append(msg)

            pendingScheduleApprovals.removeValue(forKey: requestId)
            MINATOAgentStore.shared.removePendingScheduleApproval(for: requestId)

            if status == "confirmed",
               let negotiation = MINATOAgentStore.shared.negotiation(for: requestId),
               let event = negotiation.proposedEvent {
                self.addToCalendar(event)
            }

            if selectedPrivateChatPeer != peerID {
                unreadPrivateMessages.insert(peerID)
            }
            objectWillChange.send()
        }
    }

    // MARK: - Schedule Actions

    /// Owner approves a schedule proposal — sends AGENT_ACK with "confirmed".
    @MainActor
    func approveSchedule(requestId: String) {
        guard let approval = pendingScheduleApprovals[requestId] else { return }

        let msg = BitchatMessage(
            id: UUID().uuidString,
            sender: nickname,
            content: "✅ スケジュール確定: \(approval.proposedEvent.title)",
            timestamp: Date(),
            isRelay: false, isPrivate: true, recipientNickname: nil,
            senderPeerID: meshService.myPeerID, mentions: nil, deliveryStatus: nil
        )
        if privateChats[approval.peerID] == nil { privateChats[approval.peerID] = [] }
        privateChats[approval.peerID]?.append(msg)

        let ackContent = "スケジュールを確定しました"
        let payload = PayloadContent(
            intent: Intent.scheduleConfirm.rawValue, content: ackContent,
            originalLanguage: MINATOAgentStore.shared.localCard?.ownerLocale,
            translatedContent: nil, status: "confirmed", requestId: requestId,
            action: nil, context: nil, proposedEvent: nil, agentCard: nil
        )
        sendMINATO(type: .agentAck, payload: payload, to: approval.peerID)

        MINATOAgentStore.shared.updateNegotiation(requestId: requestId, state: .confirmed)
        pendingScheduleApprovals.removeValue(forKey: requestId)
        MINATOAgentStore.shared.removePendingScheduleApproval(for: requestId)

        addToCalendar(approval.proposedEvent)

        objectWillChange.send()
    }

    /// Owner sends a counter-proposal with different times.
    @MainActor
    func counterSchedule(requestId: String, counterEvent: ProposedEvent) {
        guard let approval = pendingScheduleApprovals[requestId] else { return }

        let displayContent = "🔄 別日提案:\n📅 \(counterEvent.title)\n🕐 \(Self.formatEventTime(counterEvent.start)) – \(Self.formatEventTime(counterEvent.end))\(counterEvent.location.map { "\n📍 \($0)" } ?? "")"

        let msg = BitchatMessage(
            id: UUID().uuidString,
            sender: nickname,
            content: displayContent,
            timestamp: Date(),
            isRelay: false, isPrivate: true, recipientNickname: nil,
            senderPeerID: meshService.myPeerID, mentions: nil, deliveryStatus: nil
        )
        if privateChats[approval.peerID] == nil { privateChats[approval.peerID] = [] }
        privateChats[approval.peerID]?.append(msg)

        let counterPayload = PayloadContent(
            intent: Intent.scheduleNegotiate.rawValue, content: displayContent,
            originalLanguage: MINATOAgentStore.shared.localCard?.ownerLocale,
            translatedContent: nil, status: nil, requestId: requestId,
            action: nil, context: nil, proposedEvent: counterEvent, agentCard: nil
        )
        sendMINATO(type: .agentResponse, payload: counterPayload, to: approval.peerID)

        MINATOAgentStore.shared.updateNegotiation(requestId: requestId, state: .counterOffered, event: counterEvent)
        pendingScheduleApprovals.removeValue(forKey: requestId)
        MINATOAgentStore.shared.removePendingScheduleApproval(for: requestId)
        objectWillChange.send()
    }

    /// Owner declines a schedule proposal.
    @MainActor
    func declineSchedule(requestId: String) {
        guard let approval = pendingScheduleApprovals[requestId] else { return }

        let msg = BitchatMessage(
            id: UUID().uuidString,
            sender: nickname,
            content: "❌ スケジュール辞退",
            timestamp: Date(),
            isRelay: false, isPrivate: true, recipientNickname: nil,
            senderPeerID: meshService.myPeerID, mentions: nil, deliveryStatus: nil
        )
        if privateChats[approval.peerID] == nil { privateChats[approval.peerID] = [] }
        privateChats[approval.peerID]?.append(msg)

        let declineContent = "スケジュールを辞退しました"
        let declinePayload = PayloadContent(
            intent: Intent.scheduleCancel.rawValue, content: declineContent,
            originalLanguage: MINATOAgentStore.shared.localCard?.ownerLocale,
            translatedContent: nil, status: "rejected", requestId: requestId,
            action: nil, context: nil, proposedEvent: nil, agentCard: nil
        )
        sendMINATO(type: .agentAck, payload: declinePayload, to: approval.peerID)

        MINATOAgentStore.shared.updateNegotiation(requestId: requestId, state: .rejected)
        pendingScheduleApprovals.removeValue(forKey: requestId)
        MINATOAgentStore.shared.removePendingScheduleApproval(for: requestId)
        objectWillChange.send()
    }

    /// Send a schedule request using AI to extract event details from natural language.
    @MainActor
    func sendScheduleRequest(_ message: String, to peerID: PeerID) {
        let msg = BitchatMessage(
            id: UUID().uuidString,
            sender: nickname,
            content: message,
            timestamp: Date(),
            isRelay: false, isPrivate: true, recipientNickname: nil,
            senderPeerID: meshService.myPeerID, mentions: nil, deliveryStatus: nil
        )

        Task { @MainActor in
            if privateChats[peerID] == nil { privateChats[peerID] = [] }
            privateChats[peerID]?.append(msg)
            objectWillChange.send()
        }

        let localLang = MINATOAgentStore.shared.localCard?.ownerLocale ?? "ja"
        let peerLang = MINATOAgentStore.shared.remoteCard(for: peerID)?.ownerLocale ?? "en"

        Task {
            let requestId = UUID().uuidString
            var event: ProposedEvent?
            var displayMessage = message

            if let engine = MINATOAgentStore.shared.aiEngine {
                do {
                    let busySlots = MINATOAgentStore.shared.calendarAdapter?.busySlots(forNextDays: 7) ?? []
                    let areaHint: String? = {
                        if let locale = MINATOAgentStore.shared.localCard?.ownerLocale {
                            return Locale(identifier: locale).region?.identifier
                        }
                        return nil
                    }()
                    let result = try await engine.extractScheduleProposal(from: message, locale: localLang, busySlots: busySlots, areaHint: areaHint)
                    if result.isSchedule {
                        event = result.event
                        displayMessage = result.displayMessage ?? message
                    }
                } catch {
                    // AI extraction failed — fall back to regular chat
                }
            }

            guard let event else {
                await MainActor.run {
                    self.sendAgentMessage(message, to: peerID)
                }
                return
            }

            let translated = await self.translateOwnerMessage(displayMessage, from: localLang, to: peerLang)

            await MainActor.run {
                let proposalMsg = BitchatMessage(
                    id: UUID().uuidString,
                    sender: "📅 提案送信",
                    content: "📅 \(event.title)\n🕐 \(Self.formatEventTime(event.start)) – \(Self.formatEventTime(event.end))\(event.location.map { "\n📍 \($0)" } ?? "")",
                    timestamp: Date(),
                    isRelay: false, isPrivate: true, recipientNickname: nil,
                    senderPeerID: self.meshService.myPeerID, mentions: nil, deliveryStatus: nil
                )
                if self.privateChats[peerID] == nil { self.privateChats[peerID] = [] }
                self.privateChats[peerID]?.append(proposalMsg)

                let negotiation = ScheduleNegotiation(
                    id: requestId,
                    peerID: peerID,
                    initiatedByLocal: true,
                    proposedEvent: event,
                    state: .proposed,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                MINATOAgentStore.shared.addNegotiation(negotiation)

                let intent = Intent.scheduleNegotiate.rawValue
                let action = Capability.scheduleWrite.rawValue
                let payload = PayloadContent(
                    intent: intent, content: displayMessage,
                    originalLanguage: localLang,
                    translatedContent: translated, status: nil,
                    requestId: requestId, action: action, context: nil,
                    proposedEvent: event, agentCard: nil
                )
                self.sendMINATO(type: .agentRequest, payload: payload, to: peerID)
            }
        }
    }

    // MARK: - Group Schedule

    /// Handle an ACK that belongs to a group negotiation.
    @MainActor
    func handleGroupAck(group: GroupScheduleNegotiation, fromPeerID: PeerID, peerName: String, status: String, timestamp: Date) {
        let response: GroupScheduleNegotiation.PeerResponse = status == "confirmed" ? .confirmed : .rejected
        guard let updated = MINATOAgentStore.shared.updateGroupResponse(requestId: group.id, peerID: fromPeerID, response: response) else { return }

        let displayPeerID = group.peerIDs.first ?? fromPeerID
        let confirmed = updated.confirmedCount
        let total = updated.peerIDs.count
        let emoji = status == "confirmed" ? "✅" : "❌"
        let actionText = status == "confirmed" ? "承認" : "辞退"

        let progressMsg = BitchatMessage(
            id: UUID().uuidString,
            sender: "📅 グループ進捗",
            content: "\(emoji) @\(peerName) が\(actionText) (\(confirmed)/\(total))",
            timestamp: timestamp,
            isRelay: false, isPrivate: true, recipientNickname: nickname,
            senderPeerID: meshService.myPeerID, mentions: nil, deliveryStatus: nil
        )
        if privateChats[displayPeerID] == nil { privateChats[displayPeerID] = [] }
        privateChats[displayPeerID]?.append(progressMsg)

        if updated.isComplete {
            let event = updated.proposedEvent
            let finalMsg: BitchatMessage
            if updated.allConfirmed {
                finalMsg = BitchatMessage(
                    id: UUID().uuidString,
                    sender: "🎉 確定",
                    content: "🎉 全員の予定が揃いました！\n📅 \(event.title)\n🕐 \(Self.formatEventTime(event.start)) – \(Self.formatEventTime(event.end))\(event.location.map { "\n📍 \($0)" } ?? "")",
                    timestamp: Date(),
                    isRelay: false, isPrivate: true, recipientNickname: nickname,
                    senderPeerID: meshService.myPeerID, mentions: nil, deliveryStatus: nil
                )
                if !updated.calendarRegistered {
                    addToCalendar(event)
                    MINATOAgentStore.shared.markGroupCalendarRegistered(requestId: updated.id)
                }
            } else {
                let decliners = updated.responses.filter { $0.value == .rejected }
                    .compactMap { updated.peerNames[$0.key] }
                    .map { "@\($0)" }
                    .joined(separator: ", ")
                finalMsg = BitchatMessage(
                    id: UUID().uuidString,
                    sender: "ℹ️ グループ",
                    content: "\(decliners) が辞退しました。再調整してください。",
                    timestamp: Date(),
                    isRelay: false, isPrivate: true, recipientNickname: nickname,
                    senderPeerID: meshService.myPeerID, mentions: nil, deliveryStatus: nil
                )
            }
            privateChats[displayPeerID]?.append(finalMsg)
        }

        objectWillChange.send()
    }

    /// Resolve @mention tokens to MINATO-capable peerIDs (with display names).
    @MainActor
    func resolvePeerIDsForMentions(_ mentions: [String]) -> [(peerID: PeerID, name: String)] {
        let peerNicknames = meshService.getPeerNicknames()
        let allRemoteCards = MINATOAgentStore.shared.allRemoteCards

        var results: [(peerID: PeerID, name: String)] = []
        for mention in mentions {
            let base = mention.split(separator: "#").first.map(String.init) ?? mention
            if let entry = peerNicknames.first(where: { $0.value.lowercased() == base.lowercased() }) {
                if allRemoteCards[entry.key.id] != nil {
                    results.append((entry.key, entry.value))
                }
            } else {
                if let match = allRemoteCards.first(where: { $0.value.displayName.lowercased() == base.lowercased() }) {
                    results.append((PeerID(str: match.key), match.value.displayName))
                }
            }
        }
        return results
    }

    /// Send a group schedule request to multiple peers sharing a single request_id.
    @MainActor
    func sendGroupScheduleRequest(_ message: String, to invitees: [(peerID: PeerID, name: String)], in hostPeerID: PeerID) {
        guard !invitees.isEmpty else { return }

        let outgoingMsg = BitchatMessage(
            id: UUID().uuidString,
            sender: nickname,
            content: message,
            timestamp: Date(),
            isRelay: false, isPrivate: true, recipientNickname: nil,
            senderPeerID: meshService.myPeerID, mentions: nil, deliveryStatus: nil
        )
        if privateChats[hostPeerID] == nil { privateChats[hostPeerID] = [] }
        privateChats[hostPeerID]?.append(outgoingMsg)
        objectWillChange.send()

        let localLang = MINATOAgentStore.shared.localCard?.ownerLocale ?? "ja"

        Task { @MainActor in
            let requestId = UUID().uuidString
            var event: ProposedEvent?
            var displayMessage = message

            if let engine = MINATOAgentStore.shared.aiEngine {
                do {
                    let busySlots = MINATOAgentStore.shared.calendarAdapter?.busySlots(forNextDays: 7) ?? []
                    let areaHint = Locale(identifier: localLang).region?.identifier
                    let result = try await engine.extractScheduleProposal(from: message, locale: localLang, busySlots: busySlots, areaHint: areaHint)
                    if result.isSchedule {
                        event = result.event
                        displayMessage = result.displayMessage ?? message
                    }
                } catch {
                    // fall through
                }
            }

            guard let event else {
                self.sendAgentMessage(message, to: hostPeerID)
                return
            }

            var responses: [String: GroupScheduleNegotiation.PeerResponse] = [:]
            var peerNames: [String: String] = [:]
            for invitee in invitees {
                responses[invitee.peerID.id] = .pending
                peerNames[invitee.peerID.id] = invitee.name
            }
            let group = GroupScheduleNegotiation(
                id: requestId,
                peerIDs: invitees.map { $0.peerID },
                peerNames: peerNames,
                proposedEvent: event,
                responses: responses,
                createdAt: Date(),
                updatedAt: Date()
            )
            MINATOAgentStore.shared.addGroupNegotiation(group)

            let inviteeList = invitees.map { "@\($0.name)" }.joined(separator: " ")
            let proposalMsg = BitchatMessage(
                id: UUID().uuidString,
                sender: "📅 グループ提案送信",
                content: "to: \(inviteeList)\n📅 \(event.title)\n🕐 \(Self.formatEventTime(event.start)) – \(Self.formatEventTime(event.end))\(event.location.map { "\n📍 \($0)" } ?? "")",
                timestamp: Date(),
                isRelay: false, isPrivate: true, recipientNickname: nil,
                senderPeerID: self.meshService.myPeerID, mentions: nil, deliveryStatus: nil
            )
            self.privateChats[hostPeerID]?.append(proposalMsg)
            self.objectWillChange.send()

            let intent = Intent.scheduleNegotiate.rawValue
            let action = Capability.scheduleWrite.rawValue

            for invitee in invitees {
                let peerLang = MINATOAgentStore.shared.remoteCard(for: invitee.peerID)?.ownerLocale ?? "en"
                let translated = await self.translateOwnerMessage(displayMessage, from: localLang, to: peerLang)
                await MainActor.run {
                    let payload = PayloadContent(
                        intent: intent, content: displayMessage,
                        originalLanguage: localLang, translatedContent: translated,
                        status: nil, requestId: requestId, action: action, context: nil,
                        proposedEvent: event, agentCard: nil
                    )
                    self.sendMINATO(type: .agentRequest, payload: payload, to: invitee.peerID)
                }
            }
        }
    }

    // MARK: - Calendar Integration

    /// Add a confirmed event to the device calendar (best-effort, never blocks protocol flow).
    func addToCalendar(_ event: ProposedEvent) {
        guard let adapter = MINATOAgentStore.shared.calendarAdapter else { return }
        Task {
            let granted = await adapter.requestAccess()
            guard granted else { return }
            do {
                _ = try adapter.createEvent(from: event)
            } catch {
                // Calendar registration is best-effort; don't interrupt protocol flow
            }
        }
    }

    /// Check if a proposed event conflicts with existing calendar events.
    func checkCalendarConflict(_ event: ProposedEvent) -> Bool {
        guard let adapter = MINATOAgentStore.shared.calendarAdapter else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let start = formatter.date(from: event.start),
              let end = formatter.date(from: event.end) else { return false }
        return !adapter.checkAvailability(start: start, end: end)
    }

    /// Async variant that ensures calendar access is requested before checking.
    func checkCalendarConflictAsync(_ event: ProposedEvent) async -> Bool {
        guard let adapter = MINATOAgentStore.shared.calendarAdapter else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let start = formatter.date(from: event.start),
              let end = formatter.date(from: event.end) else { return false }
        let result = await adapter.checkAvailabilityAsync(start: start, end: end)
        return result.hasAccess && !result.isAvailable
    }
}
