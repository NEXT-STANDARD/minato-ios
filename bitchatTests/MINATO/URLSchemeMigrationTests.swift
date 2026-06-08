import Testing
import Foundation
@testable import bitchat

/// Phase 1 of the bitchat -> minato URL scheme migration: accept BOTH schemes
/// everywhere (backward compatible), emit `minato://` for in-app deep links, and
/// keep emitting the legacy scheme / Nostr prefix for cross-client formats.
@Suite("URL scheme migration (Phase 1)")
struct URLSchemeMigrationTests {

    // MARK: - MinatoBrand scheme constants

    @Test("primary scheme is minato, legacy is bitchat, both accepted")
    func schemeConstants() {
        #expect(MinatoBrand.urlScheme == "minato")
        #expect(MinatoBrand.legacyURLScheme == "bitchat")
        let hasNew = MinatoBrand.acceptedURLSchemes.contains("minato")
        let hasOld = MinatoBrand.acceptedURLSchemes.contains("bitchat")
        #expect(hasNew)
        #expect(hasOld)
    }

    @Test("acceptsURLScheme accepts both schemes (case-insensitive) and rejects others")
    func acceptsScheme() {
        #expect(MinatoBrand.acceptsURLScheme("minato"))
        #expect(MinatoBrand.acceptsURLScheme("bitchat"))
        #expect(MinatoBrand.acceptsURLScheme("MINATO"))
        let rejectsEvil = MinatoBrand.acceptsURLScheme("evil") == false
        let rejectsNil = MinatoBrand.acceptsURLScheme(nil) == false
        #expect(rejectsEvil)
        #expect(rejectsNil)
    }

    @Test("Nostr embed prefix: still emits bitchat1, accepts both bitchat1 and minato1")
    func nostrEmbedPrefix() {
        #expect(MinatoBrand.nostrEmbedPrefix == "bitchat1:")
        #expect(MinatoBrand.nostrEmbedPrefix(matching: "bitchat1:AAAA") == "bitchat1:")
        #expect(MinatoBrand.nostrEmbedPrefix(matching: "minato1:AAAA") == "minato1:")
        let rejectsOther = MinatoBrand.nostrEmbedPrefix(matching: "nostr:AAAA") == nil
        #expect(rejectsOther)
    }

    // MARK: - QR verification dual-scheme accept

    private func sampleQR() -> VerificationService.VerificationQR {
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

    @Test("verification QR is now emitted with the minato:// scheme (Phase 2)")
    func qrEmitsMinatoScheme() {
        let s = sampleQR().toURLString()
        #expect(s.hasPrefix("minato://verify"))
    }

    @Test("verification QR round-trips from its own (minato) URL")
    func qrRoundTrip() {
        let qr = sampleQR()
        let url = URL(string: qr.toURLString())
        let parsed = url.flatMap { VerificationService.VerificationQR.fromURL($0) }
        let ok = parsed != nil
        #expect(ok)
        #expect(parsed?.noiseKeyHex == "aabbcc")
        #expect(parsed?.nickname == "alice")
    }

    @Test("verification QR still parses a legacy bitchat:// code (backward compatible)")
    func qrAcceptsLegacyScheme() {
        let current = sampleQR().toURLString()
        let legacy = current.replacingOccurrences(of: "minato://", with: "bitchat://")
        let parsed = URL(string: legacy).flatMap { VerificationService.VerificationQR.fromURL($0) }
        let ok = parsed != nil
        #expect(ok)
        #expect(parsed?.signKeyHex == "ddeeff")
    }

    @Test("verification QR rejects an unknown scheme")
    func qrRejectsUnknownScheme() {
        let current = sampleQR().toURLString()
        let evil = current.replacingOccurrences(of: "minato://", with: "evil://")
        let parsed = URL(string: evil).flatMap { VerificationService.VerificationQR.fromURL($0) }
        let rejected = parsed == nil
        #expect(rejected)
    }
}
