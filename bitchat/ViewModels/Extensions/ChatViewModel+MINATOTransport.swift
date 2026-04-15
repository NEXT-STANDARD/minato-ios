//
// ChatViewModel+MINATOTransport.swift
// bitchat
//
// MINATO transport abstraction: BLE/Nostr routing for agent messages.
//

import Foundation

extension ChatViewModel {

    // MARK: - Transport

    /// Unified MINATO send: automatically selects BLE or Nostr based on peer reachability.
    /// This is the single entry point for all MINATO message sending.
    @MainActor
    func sendMINATO(type: MINATOMessageType, payload: PayloadContent, to peerID: PeerID) {
        if isBLEReachable(peerID), let bleService = meshService as? BLEService {
            // Use typed BLE methods where available for better semantics
            switch type {
            case .agentMessage:
                let isAutoReply: Bool = {
                    if let ctx = payload.context, case .bool(let val) = ctx["auto_reply"] { return val }
                    return false
                }()
                bleService.sendAgentMessage(
                    to: peerID,
                    content: payload.content ?? "",
                    translatedContent: payload.translatedContent,
                    intent: payload.intent ?? Intent.messageChat.rawValue,
                    isAutoReply: isAutoReply
                )
            case .agentRequest:
                bleService.sendAgentRequest(
                    to: peerID,
                    requestId: payload.requestId ?? UUID().uuidString,
                    intent: payload.intent ?? Intent.scheduleNegotiate.rawValue,
                    action: payload.action ?? Capability.scheduleWrite.rawValue,
                    proposedEvent: payload.proposedEvent,
                    content: payload.content,
                    translatedContent: payload.translatedContent
                )
            case .agentResponse:
                bleService.sendAgentResponse(
                    to: peerID,
                    requestId: payload.requestId ?? "",
                    proposedEvent: payload.proposedEvent,
                    content: payload.content,
                    translatedContent: payload.translatedContent,
                    status: payload.status
                )
            case .agentAck:
                bleService.sendAgentAck(
                    to: peerID,
                    requestId: payload.requestId ?? "",
                    status: payload.status ?? "confirmed",
                    content: payload.content,
                    translatedContent: payload.translatedContent
                )
            default:
                // Fallback for other types via generic encoding
                sendMINATOViaNostr(type: type, payload: payload, to: peerID)
            }
        } else {
            sendMINATOViaNostr(type: type, payload: payload, to: peerID)
        }
    }

    /// Send any MINATO message type via Nostr (used as BLE fallback).
    func sendMINATOViaNostr(type: MINATOMessageType, payload: PayloadContent, to peerID: PeerID) {
        guard let nostrTransport = messageRouter.nostrTransport else { return }
        let unsigned = MINATOPayload(
            type: type.description,
            version: "0.1",
            from: MINATOAgentStore.shared.localCard?.agentId ?? "",
            to: MINATOAgentStore.shared.remoteCard(for: peerID)?.agentId ?? "",
            timestamp: UInt64(Date().timeIntervalSince1970),
            nonce: UUID().uuidString,
            payload: payload,
            signature: nil
        )
        let envelope = MINATOSigning.sign(unsigned, using: meshService.getNoiseService())
        guard let jsonData = try? JSONEncoder().encode(envelope) else { return }
        nostrTransport.sendMINATOMessage(type: type, jsonPayload: jsonData, to: peerID)
    }

    /// Check if peer is BLE-reachable (used to decide BLE vs Nostr fallback).
    func isBLEReachable(_ peerID: PeerID) -> Bool {
        meshService.isPeerConnected(peerID) || meshService.isPeerReachable(peerID)
    }
}
