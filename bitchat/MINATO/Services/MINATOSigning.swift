import Foundation
import CryptoKit
import BitLogger

// MARK: - MINATO Signing

/// Centralized Ed25519 sign/verify helpers for the MINATO Agent Protocol.
///
/// **Key separation**: `agent_id` is a Nostr/secp256k1 identifier; all MINATO
/// signatures use the separate Ed25519 key managed by `NoiseEncryptionService`
/// (`Curve25519.Signing`). See MINATO_PROTOCOL.md §4.
///
/// **Canonical form**: sign/verify operates on sorted-keys JSON with `signature`
/// excluded. See `AgentCard.signaturePayloadData()` and `MINATOPayload.signaturePayloadData()`.
enum MINATOSigning {

    // MARK: - Envelope (MINATOPayload)

    /// Signs a MINATOPayload envelope and returns a new payload with `signature` populated.
    /// - Returns: A signed payload, or the original payload unchanged if signing fails.
    static func sign(_ payload: MINATOPayload, using noiseService: NoiseEncryptionService) -> MINATOPayload {
        guard
            let data = payload.signaturePayloadData(),
            let sigData = noiseService.signData(data)
        else {
            SecureLogger.warning("MINATOSigning: failed to sign payload from \(payload.from)", category: .security)
            return payload
        }
        return payload.withSignature(sigData.hexEncodedString())
    }

    /// Verifies a MINATOPayload envelope signature against the sender's Ed25519 public key.
    /// - Parameters:
    ///   - payload: The received MINATO envelope.
    ///   - senderEd25519Hex: Hex-encoded Ed25519 public key (64 chars, 32 bytes) from
    ///     the sender's Agent Card (`ed25519_pub_key`).
    /// - Returns: `true` if the signature is valid, `false` otherwise (including missing signature).
    static func verify(_ payload: MINATOPayload, senderEd25519Hex: String) -> Bool {
        guard
            let sigHex = payload.signature,
            let sigData = Data(hexString: sigHex),
            let pubKeyData = Data(hexString: senderEd25519Hex),
            let canonicalData = payload.signaturePayloadData()
        else { return false }
        return verifyEd25519(signature: sigData, for: canonicalData, publicKey: pubKeyData)
    }

    // MARK: - Agent Card

    /// Signs an AgentCard and returns a new card with `signature` populated.
    /// - Returns: A signed card, or the original card unchanged if signing fails.
    static func sign(_ card: AgentCard, using noiseService: NoiseEncryptionService) -> AgentCard {
        guard
            let data = card.signaturePayloadData(),
            let sigData = noiseService.signData(data)
        else {
            SecureLogger.warning("MINATOSigning: failed to sign AgentCard for \(card.agentId)", category: .security)
            return card
        }
        return card.signed(with: sigData.hexEncodedString())
    }

    /// Verifies an AgentCard's self-signature using its own `ed25519_pub_key`.
    /// - Returns: `true` if the card is self-consistent and the signature is valid.
    static func verify(_ card: AgentCard) -> Bool {
        guard
            let sigHex = card.signature,
            let sigData = Data(hexString: sigHex),
            let pubKeyHex = card.ed25519PubKey,
            let pubKeyData = Data(hexString: pubKeyHex),
            let canonicalData = card.signaturePayloadData()
        else { return false }
        return verifyEd25519(signature: sigData, for: canonicalData, publicKey: pubKeyData)
    }

    // MARK: - Private

    private static func verifyEd25519(signature: Data, for data: Data, publicKey: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signature, for: data)
    }
}
