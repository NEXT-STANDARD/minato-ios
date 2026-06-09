import Foundation
import Combine

/// An incoming, not-yet-accepted contact request: a Nostr DM bearing a verifiable
/// `minato://add` identity bundle from someone who is not yet a contact. Held here
/// (quarantined) instead of appearing as a normal chat, so the owner approves
/// before a stranger can reach them.
struct ContactRequest: Identifiable, Equatable {
    /// Dedup key = the sender's npub (from the signed bundle).
    var id: String { invite.npub ?? invite.noiseKeyHex }
    let invite: VerificationService.VerificationQR
    /// The Nostr sender pubkey (hex) the request arrived from — used to block on decline.
    let senderPubkeyHex: String
    let receivedAt: Date

    var displayName: String { InputValidator.validateNickname(invite.nickname) ?? "?" }

    var npubShort: String {
        guard let npub = invite.npub, npub.count > 16 else { return invite.npub ?? "" }
        return String(npub.prefix(12)) + "…"
    }

    static func == (lhs: ContactRequest, rhs: ContactRequest) -> Bool { lhs.id == rhs.id }
}

/// Pending contact requests awaiting the owner's approval (PR2 of the remote
/// contact-invite feature). In-memory: gift-wrapped requests re-arrive from Nostr
/// relays on launch, accepted senders become favorites (no longer gated), and
/// declined senders are blocked, so the set re-derives correctly without
/// persistence.
@MainActor
final class ContactRequestStore: ObservableObject {
    static let shared = ContactRequestStore()

    @Published private(set) var requests: [ContactRequest] = []

    var hasPending: Bool { !requests.isEmpty }

    /// Add (or refresh) a request, deduped by npub. Newest `receivedAt` wins.
    func add(_ request: ContactRequest) {
        if let idx = requests.firstIndex(where: { $0.id == request.id }) {
            // Keep the most recent; don't duplicate.
            if request.receivedAt >= requests[idx].receivedAt {
                requests[idx] = request
            }
        } else {
            requests.append(request)
        }
    }

    func request(withID id: String) -> ContactRequest? {
        requests.first { $0.id == id }
    }

    func remove(id: String) {
        requests.removeAll { $0.id == id }
    }

    func clear() {
        requests.removeAll()
    }
}
