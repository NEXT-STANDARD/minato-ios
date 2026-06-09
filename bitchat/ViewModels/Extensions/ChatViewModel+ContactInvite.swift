import Foundation
import BitLogger

/// A verified incoming contact invite (`minato://add`) awaiting the owner's
/// confirmation before it becomes a durable contact.
struct PendingContactInvite: Identifiable {
    let id = UUID()
    let invite: VerificationService.VerificationQR

    /// Sanitized name for display in the prompt (the raw name is untrusted link input).
    var displayName: String { InputValidator.validateNickname(invite.nickname) ?? "?" }
    var npub: String? { invite.npub }

    /// Short npub prefix so the owner can distinguish identities beyond the
    /// (spoofable) display name in the confirmation prompt.
    var npubShort: String {
        guard let npub = invite.npub, npub.count > 16 else { return invite.npub ?? "" }
        return String(npub.prefix(12)) + "…"
    }
}

/// Remote contact-invite flow (Phase 1 / PR1).
///
/// An invite link carries the sender's self-signed identity bundle (the same one
/// the verification QR uses) under `minato://add`. When the owner opens a friend's
/// link we verify the self-signature, ask for confirmation, then add the friend
/// as a favorite and send a one-way Nostr "hello" that embeds **our own** invite
/// link — so the friend can add us back with a single tap (the inviter-side
/// approval gate that automates this is PR2).
extension ChatViewModel {

    /// Handle a tapped `minato://add` link. No-op if the link is invalid, tampered,
    /// missing a Nostr key, points at our own identity, or is already pending.
    func receiveContactInvite(from url: URL) {
        guard let qr = VerificationService.shared.verifyInvite(url.absoluteString) else {
            SecureLogger.warning("Ignoring invalid/tampered contact invite link", category: .security)
            return
        }
        // A remote contact without a Nostr key is unreachable — reject npub-less invites.
        guard let npub = qr.npub, !npub.isEmpty else {
            SecureLogger.warning("Ignoring contact invite with no npub (not remotely reachable)", category: .security)
            return
        }
        // Don't add yourself — match on either the Noise key or the npub
        // (the npub-only guard alone is bypassable by stripping npub).
        let myNoiseHex = meshService.getNoiseService().getStaticPublicKeyData().hexEncodedString().lowercased()
        if qr.noiseKeyHex.lowercased() == myNoiseHex { return }
        if let mine = myNpub(), mine == npub { return }
        // Dedup: the same invite is already awaiting confirmation (handleOpenURL can
        // fire on more than one mounted MessageListView).
        if let existing = pendingContactInvite, existing.npub == npub { return }
        pendingContactInvite = PendingContactInvite(invite: qr)
    }

    /// Owner confirmed the add prompt.
    func acceptContactInvite() {
        guard let pending = pendingContactInvite else { return }
        pendingContactInvite = nil
        addContact(from: pending.invite, greet: true)
    }

    /// Owner dismissed the add prompt.
    func declineContactInvite() {
        pendingContactInvite = nil
    }

    // MARK: - Incoming contact requests (inviter side / PR2)

    /// Approve a quarantined incoming request: add the sender as a contact, mark the
    /// relationship mutual (the request itself proves they favorited us), tell them
    /// we favorited them back (so their side becomes mutual too), and open the chat.
    func acceptContactRequest(_ request: ContactRequest) {
        let qr = request.invite
        ContactRequestStore.shared.remove(id: request.id)
        guard let noiseKey = Data(hexString: qr.noiseKeyHex) else {
            SecureLogger.warning("Contact request: malformed Noise key, ignoring", category: .security)
            return
        }
        let safeNick = InputValidator.validateNickname(qr.nickname)
            ?? String(localized: "contact.invite.unknown_name", defaultValue: "名称未設定")

        FavoritesPersistenceService.shared.addFavorite(
            peerNoisePublicKey: noiseKey,
            peerNostrPublicKey: qr.npub,
            peerNickname: safeNick
        )
        // The request is proof they favorited us — record it so we're mutual.
        FavoritesPersistenceService.shared.updatePeerFavoritedUs(
            peerNoisePublicKey: noiseKey,
            favorited: true,
            peerNickname: safeNick,
            peerNostrPublicKey: qr.npub
        )
        // Tell them we favorited them back so their side also becomes mutual.
        sendFavoriteNotificationViaNostr(noisePublicKey: noiseKey, isFavorite: true)

        // Don't open the chat here: that would present a second sheet over the
        // requests inbox. The contact is now a mutual favorite and appears in the
        // people list; the original hello DM was only an invite carrier, so dropping
        // it (the gate returned before storing it) is intentional.
        objectWillChange.send()
    }

    /// True when the invite's npub matches the Nostr pubkey (hex) the request
    /// actually arrived from — a sender can only assert their own identity.
    nonisolated static func inviteNpub(_ invite: VerificationService.VerificationQR, matchesSenderHex senderHex: String) -> Bool {
        guard let npub = invite.npub,
              let decoded = try? Bech32.decode(npub) else { return false }
        return decoded.data.hexEncodedString().lowercased() == senderHex.lowercased()
    }

    /// Reject a quarantined request: drop it and block the sender so they can't
    /// re-request or otherwise reach us (reversible via unblock).
    func declineContactRequest(_ request: ContactRequest) {
        ContactRequestStore.shared.remove(id: request.id)
        identityManager.setNostrBlocked(request.senderPubkeyHex.lowercased(), isBlocked: true)
        SecureLogger.info("Declined + blocked contact request from \(request.senderPubkeyHex.prefix(8))…", category: .session)
    }

    // MARK: - Private

    private func myNpub() -> String? {
        try? idBridge.getCurrentNostrIdentity()?.npub
    }

    private func addContact(from qr: VerificationService.VerificationQR, greet: Bool) {
        guard let noiseKey = Data(hexString: qr.noiseKeyHex) else {
            SecureLogger.warning("Contact invite: malformed Noise key, ignoring", category: .security)
            return
        }

        // Sanitize the untrusted nickname before storing/displaying it.
        let safeNick = InputValidator.validateNickname(qr.nickname)
            ?? String(localized: "contact.invite.unknown_name", defaultValue: "名称未設定")

        // Durable contact: favorite keyed on the friend's Noise key, carrying their npub.
        FavoritesPersistenceService.shared.addFavorite(
            peerNoisePublicKey: noiseKey,
            peerNostrPublicKey: qr.npub,
            peerNickname: safeNick
        )

        let peerID = PeerID(str: qr.noiseKeyHex)

        if greet {
            sendInviteHello(to: peerID, recipientNickname: safeNick)
        }

        // Approval-gated: do NOT open the chat yet — a one-way favorite is blocked
        // from messaging until the friend adds us back (startPrivateChat would show
        // a "requires mutual favorite" wall). Confirm the invite was sent instead;
        // the conversation opens automatically once it becomes mutual (PR2).
        addSystemMessage(String(
            format: String(
                localized: "contact.invite.sent",
                defaultValue: "「%@」を連絡先に追加し、招待を送信しました。相手が承認すると会話できます。"
            ),
            safeNick
        ))
        objectWillChange.send()
    }

    /// Send a one-way "hello" carrying our own invite link so the friend can add
    /// us back. Routes straight through the message router (Nostr), bypassing the
    /// mutual-favorite gate that normal sends use — the friend hasn't favorited us
    /// yet by design.
    private func sendInviteHello(to peerID: PeerID, recipientNickname: String) {
        guard let myLink = VerificationService.shared.buildMyInviteString(nickname: nickname, npub: myNpub()) else {
            return
        }
        let hello = String(
            format: String(
                localized: "contact.invite.hello",
                defaultValue: "👋 %1$@ さんが %2$@ で繋がりたいそうです。追加するにはこのリンクをタップ：\n%3$@"
            ),
            nickname, MinatoBrand.displayName, myLink
        )
        messageRouter.sendPrivate(
            hello,
            to: peerID,
            recipientNickname: recipientNickname,
            messageID: UUID().uuidString
        )
    }
}
