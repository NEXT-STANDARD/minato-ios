import Testing
import Foundation
@testable import bitchat

/// The contact-request inbox dedups by npub and supports removal — the backing
/// for the approval gate (PR2 of the remote contact-invite feature).
@Suite("ContactRequestStore")
@MainActor
struct ContactRequestStoreTests {

    private func invite(npub: String, nick: String = "alice") -> VerificationService.VerificationQR {
        VerificationService.VerificationQR(
            v: 1, noiseKeyHex: "aa", signKeyHex: "bb", npub: npub,
            nickname: nick, ts: 1_700_000_000, nonceB64: "x", sigHex: "cc"
        )
    }

    private func request(npub: String, at ts: TimeInterval, nick: String = "alice") -> ContactRequest {
        ContactRequest(invite: invite(npub: npub, nick: nick),
                       senderPubkeyHex: "deadbeef",
                       receivedAt: Date(timeIntervalSince1970: ts))
    }

    @Test("add then remove")
    func addRemove() {
        let store = ContactRequestStore()
        store.add(request(npub: "npub1a", at: 1))
        #expect(store.requests.count == 1)
        #expect(store.hasPending)
        store.remove(id: "npub1a")
        #expect(store.requests.isEmpty)
        #expect(!store.hasPending)
    }

    @Test("dedups by npub, keeping the newest")
    func dedupByNpub() {
        let store = ContactRequestStore()
        store.add(request(npub: "npub1a", at: 100, nick: "old"))
        store.add(request(npub: "npub1a", at: 200, nick: "new"))
        #expect(store.requests.count == 1)
        #expect(store.requests.first?.displayName == "new")
    }

    @Test("distinct npubs coexist")
    func distinctNpubs() {
        let store = ContactRequestStore()
        store.add(request(npub: "npub1a", at: 1))
        store.add(request(npub: "npub1b", at: 1))
        #expect(store.requests.count == 2)
    }

    @Test("id falls back to noise key when npub is nil")
    func idFallback() {
        let req = ContactRequest(
            invite: VerificationService.VerificationQR(
                v: 1, noiseKeyHex: "abcd", signKeyHex: "bb", npub: nil,
                nickname: "x", ts: 1, nonceB64: "y", sigHex: "cc"
            ),
            senderPubkeyHex: "ff", receivedAt: Date(timeIntervalSince1970: 1)
        )
        #expect(req.id == "abcd")
    }
}
