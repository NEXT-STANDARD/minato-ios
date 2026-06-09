import Testing
import Foundation
@testable import bitchat

/// Contact-invite links (`minato://add?…`) carry the same signed identity bundle
/// as the verification QR, but are openable remotely to add the sender as a
/// contact. These tests cover the URL build/parse layer (the crypto verify path
/// reuses the proven verify-QR signature check).
@Suite("Contact invite link")
struct ContactInviteTests {

    private func sample() -> VerificationService.VerificationQR {
        VerificationService.VerificationQR(
            v: 1,
            noiseKeyHex: "aabbcc",
            signKeyHex: "ddeeff",
            npub: "npub1example",
            nickname: "alice",
            ts: 1_700_000_000,
            nonceB64: "bm9uY2U=",
            sigHex: "0011"
        )
    }

    @Test("invite link uses the minato://add host")
    func inviteUsesAddHost() {
        let s = sample().toInviteURLString()
        #expect(s.hasPrefix("minato://add"))
    }

    @Test("verify QR and invite differ only by host, same signed payload")
    func verifyVsInviteDifferOnlyByHost() {
        let qr = sample()
        let verify = qr.toURLString()
        let invite = qr.toInviteURLString()
        #expect(verify.hasPrefix("minato://verify"))
        #expect(invite.hasPrefix("minato://add"))
        // Same query string after the host.
        let vq = verify.replacingOccurrences(of: "minato://verify", with: "")
        let iq = invite.replacingOccurrences(of: "minato://add", with: "")
        #expect(vq == iq)
    }

    @Test("fromURL parses an add-host invite (round-trip)")
    func fromURLParsesInvite() {
        let invite = sample().toInviteURLString()
        let parsed = URL(string: invite).flatMap { VerificationService.VerificationQR.fromURL($0) }
        let ok = parsed != nil
        #expect(ok)
        #expect(parsed?.noiseKeyHex == "aabbcc")
        #expect(parsed?.npub == "npub1example")
        #expect(parsed?.nickname == "alice")
    }

    @Test("fromURL still parses the verify host")
    func fromURLParsesVerify() {
        let parsed = URL(string: sample().toURLString()).flatMap { VerificationService.VerificationQR.fromURL($0) }
        let ok = parsed != nil
        #expect(ok)
    }

    @Test("fromURL also accepts a legacy bitchat:// invite (backward compatible)")
    func fromURLAcceptsLegacyInvite() {
        let legacy = sample().toInviteURLString().replacingOccurrences(of: "minato://", with: "bitchat://")
        let parsed = URL(string: legacy).flatMap { VerificationService.VerificationQR.fromURL($0) }
        let ok = parsed != nil
        #expect(ok)
    }

    @Test("fromURL rejects an unknown host")
    func fromURLRejectsUnknownHost() {
        let bad = sample().toInviteURLString().replacingOccurrences(of: "minato://add", with: "minato://evil")
        let parsed = URL(string: bad).flatMap { VerificationService.VerificationQR.fromURL($0) }
        let rejected = parsed == nil
        #expect(rejected)
    }

    // MARK: - npub/sender binding (anti-impersonation gate, PR2)

    private func invite(npub: String?) -> VerificationService.VerificationQR {
        VerificationService.VerificationQR(
            v: 1, noiseKeyHex: "aa", signKeyHex: "bb", npub: npub,
            nickname: "x", ts: 1, nonceB64: "y", sigHex: "cc"
        )
    }

    @Test("invite npub matches the sender hex it was derived from")
    func npubMatchesSender() throws {
        let hex = "1122334455667788990011223344556677889900112233445566778899001122"
        let npub = try Bech32.encode(hrp: "npub", data: try #require(Data(hexString: hex)))
        #expect(ChatViewModel.inviteNpub(invite(npub: npub), matchesSenderHex: hex))
        #expect(ChatViewModel.inviteNpub(invite(npub: npub), matchesSenderHex: hex.uppercased()))
    }

    @Test("invite npub does NOT match a different sender (forged third-party identity)")
    func npubMismatchRejected() throws {
        let hex = "1122334455667788990011223344556677889900112233445566778899001122"
        let other = "9988776655443322110099887766554433221100998877665544332211009988"
        let npub = try Bech32.encode(hrp: "npub", data: try #require(Data(hexString: hex)))
        let mismatched = ChatViewModel.inviteNpub(invite(npub: npub), matchesSenderHex: other) == false
        #expect(mismatched)
    }

    @Test("invite without npub never matches a sender")
    func nilNpubRejected() {
        let none = ChatViewModel.inviteNpub(invite(npub: nil), matchesSenderHex: "aabb") == false
        #expect(none)
    }
}
