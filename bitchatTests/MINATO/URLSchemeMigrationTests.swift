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

    @Test("verification QR is emitted with the legacy scheme (cross-device interop)")
    func qrEmitsLegacyScheme() {
        let s = sampleQR().toURLString()
        #expect(s.hasPrefix("bitchat://verify"))
    }

    @Test("verification QR round-trips from its own (legacy) URL")
    func qrRoundTripLegacy() {
        let qr = sampleQR()
        let url = URL(string: qr.toURLString())
        let parsed = url.flatMap { VerificationService.VerificationQR.fromURL($0) }
        let ok = parsed != nil
        #expect(ok)
        #expect(parsed?.noiseKeyHex == "aabbcc")
        #expect(parsed?.nickname == "alice")
    }

    @Test("verification QR also parses from a minato:// URL (forward compatible)")
    func qrAcceptsMinatoScheme() {
        let legacy = sampleQR().toURLString()
        let migrated = legacy.replacingOccurrences(of: "bitchat://", with: "minato://")
        let parsed = URL(string: migrated).flatMap { VerificationService.VerificationQR.fromURL($0) }
        let ok = parsed != nil
        #expect(ok)
        #expect(parsed?.signKeyHex == "ddeeff")
    }

    @Test("verification QR rejects an unknown scheme")
    func qrRejectsUnknownScheme() {
        let legacy = sampleQR().toURLString()
        let evil = legacy.replacingOccurrences(of: "bitchat://", with: "evil://")
        let parsed = URL(string: evil).flatMap { VerificationService.VerificationQR.fromURL($0) }
        let rejected = parsed == nil
        #expect(rejected)
    }
}
