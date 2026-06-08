# MINATO Agent Protocol — iOS Implementation Guide

Last updated: 2026-05-11

This guide describes how `minato-ios` implements the MINATO Agent Protocol on top of the Bitchat transport stack.
The protocol source of truth lives in `NEXT-STANDARD/minato-spec`; this repository documents iOS-specific trial shapes separately before proposing them upstream.

Reference documents:

- `docs/MINATO-message-shapes.md`
- `docs/examples/minato-ios/*.json`
- `bitchatTests/MINATO/MINATOMessageShapeGoldenTests.swift`

---

## Architecture

`minato-ios` reuses Bitchat's transport and crypto layers, then adds MINATO-specific agent behavior above them.

| Layer | iOS implementation |
|---|---|
| App | SwiftUI, `ChatViewModel` |
| Agent | `bitchat/MINATO/` |
| MINATO protocol | packet types `0x30` through `0x37` |
| Transport | BLE mesh with Nostr fallback |
| Crypto | Noise infrastructure plus Ed25519 signatures |

Keep MINATO changes isolated where possible:

- Transport, mesh, Noise, and Nostr code should be extended only when the agent layer needs a bridge.
- Protocol models, signing, trust, schedule negotiation, activity logs, AI, and calendar behavior belong under `bitchat/MINATO/`.
- iOS-only protocol experiments should be documented as proposal candidates rather than silently treated as accepted spec.

---

## Important Files

| File | Responsibility |
|---|---|
| `bitchat/MINATO/Protocol/MINATOMessageType.swift` | message type enum, `MINATOPayload`, `PayloadContent`, `ProposedEvent` |
| `bitchat/MINATO/Models/AgentCard.swift` | Agent Card model and canonical card signing payload |
| `bitchat/MINATO/Models/Capability.swift` | capabilities and intents |
| `bitchat/MINATO/Models/TrustMode.swift` | trust modes and trust settings |
| `bitchat/MINATO/Services/MINATOSigning.swift` | Ed25519 signing and verification |
| `bitchat/MINATO/Services/BLEService+MINATO.swift` | BLE packet encode/decode and handlers |
| `bitchat/ViewModels/Extensions/ChatViewModel+MINATOTransport.swift` | BLE-vs-Nostr routing |
| `bitchat/MINATO/Services/Stores/` | Agent Card, trust, negotiation, and activity-log stores |

---

## Wire Format

Every MINATO message is JSON encoded as a `MINATOPayload` inside `BitchatPacket.payload`.

```json
{
  "type": "AGENT_MESSAGE",
  "version": "0.1",
  "from": "npub1...",
  "to": "npub1...",
  "timestamp": 1712800000,
  "nonce": "uuid",
  "payload": {},
  "signature": "ed25519_signature_hex"
}
```

Packet types:

| Type | Name | Purpose |
|---:|---|---|
| `0x30` | `AGENT_HANDSHAKE` | Agent Card exchange |
| `0x31` | `AGENT_MESSAGE` | agent conversation / AI reply |
| `0x32` | `AGENT_REQUEST` | action request, currently schedule negotiation |
| `0x33` | `AGENT_RESPONSE` | request response or counter-proposal |
| `0x34` | `AGENT_ACK` | confirm or reject |
| `0x35` | `AGENT_REVOKE` | revoke trust, cached Agent Card, or both |
| `0x36` | `AGENT_PING` | no-op heartbeat placeholder |
| `0x37` | `AGENT_LOG` | post-hoc autonomous-action notification |

For field-level details, use `docs/MINATO-message-shapes.md`.

---

## Signing

The iOS implementation signs both Agent Cards and MINATO envelopes with Ed25519 keys from `NoiseEncryptionService.signingKey`.

### Agent Card Signing

1. Create an unsigned `AgentCard`.
2. Set `ed25519_pub_key` to the local Ed25519 public key hex.
3. Build canonical sorted-key JSON with `signature` omitted.
4. Sign the canonical bytes.
5. Store the signature as hex in `agent_card.signature`.

On receive, `AGENT_HANDSHAKE` is accepted only if the Agent Card self-signature verifies against `agent_card.ed25519_pub_key`.

### Envelope Signing

1. Build `MINATOPayload` with `signature: nil`.
2. Build canonical sorted-key JSON with `signature` omitted.
3. Sign the canonical bytes.
4. Store the signature as top-level `signature`.

On receive, every non-handshake, non-ping packet requires a cached remote Agent Card. The envelope signature is verified against that card's `ed25519_pub_key`.

---

## Transport Behavior

The declared MINATO encryption policy is:

| Type | Policy |
|---|---|
| `AGENT_HANDSHAKE` | cleartext |
| `AGENT_PING` | cleartext |
| all others | `MINATOMessageType.requiresEncryption == true` |

Current implementation note: BLE MINATO sends are direct `BitchatPacket` sends carrying the signed JSON envelope, not `noiseEncrypted` wrapper packets. Nostr fallback sends the same signed JSON envelope. Integrity comes from the MINATO envelope signature.

`ChatViewModel.sendMINATO(...)` selects BLE when the peer is reachable and falls back to Nostr when necessary.

---

## Trust Modes

| Value | Display | Behavior |
|---|---|---|
| `plan` | Apprentice | owner approval for every action |
| `suggest` | Partner | auto-send short low-stakes replies; approval for substantive actions |
| `auto` | Lieutenant | automatic low-risk execution; high-risk actions require policy approval |
| `full_auto` | Alter Ego | automatic execution with post-hoc `AGENT_LOG` |

High-risk capabilities:

- `schedule.write`
- `schedule.delete`
- `location.precise`

Unknown capabilities are treated as high risk.

---

## Schedule Negotiation

Schedule negotiation uses a `request_id` inside `payload` to correlate the message chain.

Typical flow:

1. `AGENT_REQUEST` with `intent: "schedule.negotiate"`, `action: "schedule.write"`, and optional `proposed_event`.
2. `AGENT_RESPONSE` with a counter-proposal or status.
3. `AGENT_ACK` with `status: "confirmed"` or a rejection status.

State is tracked in `NegotiationStore`:

| State | Meaning |
|---|---|
| `proposed` | waiting for response |
| `counterOffered` | counter-proposal received |
| `confirmed` | confirmed by ACK |
| `rejected` | rejected by ACK |
| `cancelled` | cancelled intent |

Negotiations are intentionally in-memory. After restart, peers should re-propose.

---

## Activity Logs

When the agent acts automatically in `auto` or `full_auto`, it sends `AGENT_LOG` and stores a local activity-log entry.

Required network fields:

| Field | Meaning |
|---|---|
| `log_id` | idempotency key |
| `action` | `auto_reply`, `auto_schedule_ack`, or `auto_schedule_reject` |
| `trust_mode` | `auto` or `full_auto` |
| `content` | human-readable action summary |

`ActivityLogStore` deduplicates by `log_id`, stores newest-first, and caps storage at 200 entries.

---

## Changing Message Shapes

When changing `MINATOPayload`, `PayloadContent`, `AgentCard`, `ProposedEvent`, or any `0x30` through `0x37` handler:

1. Update the Swift model or handler.
2. Update `docs/MINATO-message-shapes.md`.
3. Update `docs/examples/minato-ios/*.json`.
4. Run the golden test.

```bash
xcodebuild -project bitchat.xcodeproj \
  -scheme "bitchat (iOS)" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:bitchatTests_iOS/MINATOMessageShapeGoldenTests \
  test
```

For signing changes, also run:

```bash
xcodebuild -project bitchat.xcodeproj \
  -scheme "bitchat (iOS)" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:bitchatTests_iOS/AgentCardSigningTests \
  -only-testing:bitchatTests_iOS/MINATOPayloadSigningTests \
  test
```

---

## Upstream Spec Coordination

When `NEXT-STANDARD/minato-spec` changes:

1. Record the spec commit in `docs/MINATO-roadmap.md`.
2. Compare spec schemas/examples with `docs/MINATO-message-shapes.md`.
3. Decide whether each difference is spec-aligned, iOS-only, or a candidate for upstream proposal.
4. Update examples and golden tests before changing app behavior broadly.

Current iOS proposal candidates include:

- `agent_card.ed25519_pub_key`
- canonical envelope signing with sorted-key JSON and omitted `signature`
- `AGENT_REVOKE` fields: `scope`, `reason`
- `AGENT_LOG` fields: `log_id`, `action`, `trust_mode`
- `AGENT_PING` as a reserved no-op heartbeat
