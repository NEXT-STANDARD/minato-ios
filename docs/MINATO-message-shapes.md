# MINATO Message Shapes — iOS Implementation

最終更新: 2026-05-11

このドキュメントは `minato-ios` が現在送受信している MINATO message shape を記録する。
`NEXT-STANDARD/minato-spec` への即時反映ではなく、iOS 派生実装の現状と提案候補を分けて扱う。

参照実装:
- `bitchat/MINATO/Protocol/MINATOMessageType.swift`
- `bitchat/MINATO/Models/AgentCard.swift`
- `bitchat/MINATO/Services/BLEService+MINATO.swift`
- `bitchat/ViewModels/Extensions/ChatViewModel+MINATOTransport.swift`

---

## Transport Layering

MINATO messages are serialized as JSON inside `BitchatPacket.payload`.

| Layer | Shape |
|---|---|
| Bitchat packet type | `0x30`〜`0x37` |
| Bitchat packet payload | UTF-8 JSON encoded `MINATOPayload` |
| MINATO envelope signature | Ed25519 hex over canonical sorted-key JSON with `signature` omitted |
| Agent Card signature | Ed25519 hex over canonical sorted-key Agent Card JSON with `signature` omitted |

Declared encryption policy:

| Type | Encryption |
|---|---|
| `AGENT_HANDSHAKE` (`0x30`) | Cleartext |
| `AGENT_PING` (`0x36`) | Cleartext |
| All others | `MINATOMessageType.requiresEncryption == true` |

Current implementation note: BLE MINATO sends are direct `BitchatPacket` sends containing the signed JSON envelope, not `noiseEncrypted` wrapper packets. Nostr fallback also sends the same signed JSON envelope. Non-handshake, non-ping packets are accepted only after a verified remote Agent Card has provided `ed25519_pub_key`, and the envelope signature verifies against that key.

---

## Common Envelope

All message types use this top-level JSON envelope:

```json
{
  "type": "AGENT_MESSAGE",
  "version": "0.1",
  "from": "npub1...",
  "to": "npub1...",
  "timestamp": 1712800000,
  "nonce": "550e8400-e29b-41d4-a716-446655440000",
  "payload": {},
  "signature": "ed25519_signature_hex"
}
```

| Field | Type | Required | Notes |
|---|---|---:|---|
| `type` | string | yes | One of `AGENT_HANDSHAKE`, `AGENT_MESSAGE`, `AGENT_REQUEST`, `AGENT_RESPONSE`, `AGENT_ACK`, `AGENT_REVOKE`, `AGENT_PING`, `AGENT_LOG` |
| `version` | string | yes | Currently `"0.1"` |
| `from` | string | yes | Sender Agent Card `agent_id` (`npub` in current iOS implementation) |
| `to` | string | yes | Recipient Agent Card `agent_id`; may be empty if no remote card is known |
| `timestamp` | uint64 | yes | Unix seconds |
| `nonce` | string | yes | UUID string generated per envelope |
| `payload` | object | yes | Type-specific `PayloadContent` |
| `signature` | string | yes for signed sends | Ed25519 signature hex; omitted from canonical signing payload |

Swift `JSONEncoder` omits `nil` optional fields, so examples below show only fields sent for that shape.

---

## Common Payload Fields

`PayloadContent` is a shared optional-field struct. Message types define which fields are meaningful.

| Field | Type | Used by | Notes |
|---|---|---|---|
| `intent` | string | most types | See Intent Values |
| `content` | string | message/request/response/ack/log | Human-readable message, proposal, or log text |
| `original_language` | string | message/request/response/ack/revoke | Local owner locale, usually BCP 47-like (`ja`, `en`) |
| `translated_content` | string | message/request/response/ack | Translation for recipient locale |
| `status` | string | response/ack | `confirmed`, `rejected`, or an implementation-specific response status |
| `request_id` | string | request/response/ack | Correlates schedule negotiation messages |
| `action` | string | request/log | Capability invoked or autonomous log action |
| `scope` | string | revoke | `trust`, `agent_card`, `all` |
| `reason` | string | revoke | Human-readable reason |
| `log_id` | string | log | Idempotency key for log dedupe |
| `trust_mode` | string | log | `auto` or `full_auto` accepted for network logs |
| `context` | object | message/revoke/log | Flexible JSON values (`string`, number, bool, array, object, null) |
| `proposed_event` | object | request/response | Schedule proposal |
| `agent_card` | object | handshake | Signed Agent Card |

### Intent Values

Current iOS enum values:

| Intent | Meaning |
|---|---|
| `message.chat` | General chat |
| `schedule.negotiate` | Schedule proposal/counter-proposal |
| `schedule.confirm` | Schedule confirmation |
| `schedule.cancel` | Schedule rejection/cancellation |
| `info.exchange` | Information exchange |
| `trust.upgrade` | Trust mode upgrade |
| `trust.downgrade` | Trust mode downgrade |
| `connection.establish` | Agent Card handshake |
| `connection.terminate` | Revoke/disconnect |
| `safety.checkin` | Disaster mode: unsolicited safety check-in (iOS-derived) |
| `safety.request_help` | Disaster mode: request help (iOS-derived) |
| `safety.resource_offer` | Disaster mode: offer resources (iOS-derived) |
| `safety.resource_request` | Disaster mode: request resources (iOS-derived) |
| `safety.location_share` | Disaster mode: share location (iOS-derived) |
| `safety.evacuation_notice` | Disaster mode: evacuation notice (iOS-derived) |
| `safety.person_search` | Disaster mode: search for a person (iOS-derived) |

### Proposed Event

```json
{
  "title": "Coffee",
  "start": "2026-05-12T10:00:00+09:00",
  "end": "2026-05-12T10:30:00+09:00",
  "location": "Shibuya"
}
```

| Field | Type | Required | Notes |
|---|---|---:|---|
| `title` | string | yes | Event title |
| `start` | string | yes | ISO 8601 string |
| `end` | string | yes | ISO 8601 string |
| `location` | string | no | Optional location |

---

## Agent Card Shape

`AGENT_HANDSHAKE` carries a signed Agent Card in `payload.agent_card`.

```json
{
  "minato_version": "0.1",
  "agent_id": "npub1...",
  "display_name": "Alice",
  "owner_locale": "ja",
  "capabilities": [
    "schedule.read",
    "message.reply",
    "info.exchange",
    "language.translate"
  ],
  "default_trust_mode": "suggest",
  "supported_intents": [
    "message.chat",
    "schedule.negotiate",
    "schedule.confirm",
    "info.exchange"
  ],
  "ai_engine": "claude",
  "created_at": 1712800000,
  "ed25519_pub_key": "32_byte_public_key_hex",
  "signature": "ed25519_signature_hex"
}
```

`ed25519_pub_key` is an iOS implementation field used to verify subsequent MINATO envelopes. The public key comes from `NoiseEncryptionService.signingKey` infrastructure, reused for MINATO envelope signatures.

---

## Message Type Shapes

### 0x30 `AGENT_HANDSHAKE`

Purpose: exchange and verify Agent Cards.

Payload shape:

```json
{
  "intent": "connection.establish",
  "agent_card": {}
}
```

Required payload fields:

| Field | Required | Notes |
|---|---:|---|
| `intent` | yes | `connection.establish` |
| `agent_card` | yes | Must include valid Agent Card self-signature |

Receive behavior:
- Decode `MINATOPayload`.
- Verify `payload.agent_card.signature` using `agent_card.ed25519_pub_key`.
- Save remote card only after verification succeeds.
- If this is the first exchange with that peer, send the local Agent Card back.

### 0x31 `AGENT_MESSAGE`

Purpose: general agent conversation and AI replies.

Payload shape:

```json
{
  "intent": "message.chat",
  "content": "元の本文",
  "original_language": "ja",
  "translated_content": "Translated body",
  "context": {
    "auto_reply": true
  }
}
```

Required payload fields:

| Field | Required | Notes |
|---|---:|---|
| `intent` | yes in sender helpers | Defaults to `message.chat` in routing helpers |
| `content` | yes in sender helpers | Display falls back to empty string if absent |

Optional behavior:
- `translated_content` is preferred for display when present.
- `context.auto_reply == true` prevents infinite auto-reply loops.
- Human-originated messages can trigger AI reply depending on local trust mode.
- Auto/full_auto replies append local activity logs and send `AGENT_LOG`.

### 0x32 `AGENT_REQUEST`

Purpose: request an action, currently schedule negotiation.

Payload shape:

```json
{
  "intent": "schedule.negotiate",
  "content": "Can we meet tomorrow at 10?",
  "original_language": "en",
  "translated_content": "明日10時に会えますか？",
  "request_id": "request-uuid",
  "action": "schedule.write",
  "proposed_event": {
    "title": "Meeting",
    "start": "2026-05-12T10:00:00+09:00",
    "end": "2026-05-12T10:30:00+09:00"
  }
}
```

Required payload fields:

| Field | Required | Notes |
|---|---:|---|
| `request_id` | yes in sender helpers | Receiver generates UUID fallback if absent |
| `intent` | yes in sender helpers | Usually `schedule.negotiate` |
| `action` | yes in sender helpers | Usually `schedule.write` |

Receive behavior:
- Creates `ScheduleNegotiation` with state `proposed`.
- Delegates to UI / owner approval flow.

### 0x33 `AGENT_RESPONSE`

Purpose: respond to a request, commonly with a counter-proposal.

Payload shape:

```json
{
  "intent": "schedule.negotiate",
  "content": "How about 11 instead?",
  "original_language": "en",
  "translated_content": "11時ではどうですか？",
  "request_id": "request-uuid",
  "status": "counter_offered",
  "proposed_event": {
    "title": "Meeting",
    "start": "2026-05-12T11:00:00+09:00",
    "end": "2026-05-12T11:30:00+09:00"
  }
}
```

Required payload fields:

| Field | Required | Notes |
|---|---:|---|
| `request_id` | yes in sender helpers | Receiver falls back to `"unknown"` if absent |
| `intent` | yes in BLE sender | Currently `schedule.negotiate` |

Receive behavior:
- If `proposed_event` exists, updates negotiation state to `counterOffered`.
- Delegates response details to UI.

### 0x34 `AGENT_ACK`

Purpose: confirm or reject a request/response chain.

Payload shape:

```json
{
  "intent": "schedule.confirm",
  "content": "Confirmed.",
  "original_language": "en",
  "translated_content": "確定しました。",
  "request_id": "request-uuid",
  "status": "confirmed"
}
```

Required payload fields:

| Field | Required | Notes |
|---|---:|---|
| `request_id` | yes in sender helpers | Receiver falls back to `"unknown"` if absent |
| `status` | yes in sender helpers | `confirmed` maps to `confirmed`; any other value maps to `rejected` in current receiver |
| `intent` | yes in BLE sender | `schedule.confirm` when confirmed, `schedule.cancel` otherwise |

Receive behavior:
- Updates negotiation state to `confirmed` when `status == "confirmed"`.
- Updates negotiation state to `rejected` for all other statuses.

### 0x35 `AGENT_REVOKE`

Purpose: revoke trust settings, cached Agent Card, or both.

Payload shape:

```json
{
  "intent": "connection.terminate",
  "original_language": "ja",
  "scope": "all",
  "reason": "Owner revoked this agent connection",
  "context": {
    "initiated_by": "owner"
  }
}
```

Required payload fields:

| Field | Required | Notes |
|---|---:|---|
| `intent` | yes | Receiver rejects unless `connection.terminate` |
| `scope` | no | Defaults to `all` when absent or unknown |

Scope values:

| Scope | Effect |
|---|---|
| `trust` | Remove trust settings and pending reply |
| `agent_card` | Remove remote Agent Card and pending reply |
| `all` | Remove trust settings, remote Agent Card, and pending reply |

The sender applies the same revoke scope locally after queueing the packet.

### 0x36 `AGENT_PING`

Purpose: heartbeat / liveness placeholder.

Payload shape:

```json
{}
```

Current iOS behavior:
- `requiresEncryption == false`.
- Receiver only logs `AGENT_PING`.
- No pong, latency measurement, or state transition is implemented yet.

### 0x37 `AGENT_LOG`

Purpose: post-hoc notification for autonomous actions in `auto` / `full_auto`.

Payload shape:

```json
{
  "intent": "message.chat",
  "content": "メッセージを受け取り、自動返信しました。",
  "action": "auto_reply",
  "log_id": "log-20260413-0001",
  "trust_mode": "full_auto",
  "context": {
    "peer_id": "0123456789abcdef",
    "peer_name": "Alice"
  }
}
```

Required payload fields:

| Field | Required | Notes |
|---|---:|---|
| `log_id` | yes | Used for dedupe in `ActivityLogStore` |
| `action` | yes | Must map to a known `AgentActivityLog.ActionType` |
| `content` | yes | Human-readable action summary/content |
| `trust_mode` | yes | Receiver accepts only `auto` or `full_auto` |

Action values:

| Action | Meaning |
|---|---|
| `auto_reply` | Agent sent a reply automatically |
| `auto_schedule_ack` | Agent confirmed a schedule automatically |
| `auto_schedule_reject` | Agent rejected a schedule automatically |

Receive behavior:
- Rejects payloads missing `log_id`, `action`, `content`, or valid `trust_mode`.
- Deduplicates by `log_id`.
- Persists newest-first, capped at 200 entries.

### Safety Check-in (iOS-derived, rides on `0x31` `AGENT_MESSAGE`)

Purpose: disaster-mode safety status broadcast. Trialed as an iOS-derived shape on the existing `AGENT_MESSAGE` type rather than a new wire type — the structured data is carried under `payload.context`.

- `payload.intent` = `safety.checkin`
- `payload.content` = human-readable status line (e.g. `無事です。…`)
- `payload.context.safety_checkin` = the encoded check-in object

Check-in object (`safety_checkin`):

```json
{
  "id": "safety-checkin-001",
  "status": "needs_help",
  "content": "助けが必要です。近くの人に知らせてください。",
  "battery": {
    "level": 0.18,
    "state": "unplugged",
    "low_power_mode": true,
    "reported_at": 1712800200,
    "contact_window": "medium"
  },
  "location": {
    "precision": "coarse",
    "geohash": "xn76u",
    "label": "渋谷区周辺"
  },
  "relay": {
    "delivery": "mesh",
    "direct": false,
    "hops": 2,
    "last_seen_at": 1712800200,
    "relay_seen_at": 1712800260
  },
  "needs": ["water", "medical", "charging"],
  "expires_at": 1712803800
}
```

| Field | Type | Required | Notes |
|---|---|---:|---|
| `id` | string | yes | Unique check-in id |
| `status` | string | yes | `safe` / `injured` / `needs_help` / `evacuating` / `searching` / `unknown` |
| `content` | string | yes | Human-readable status line |
| `battery` | object | yes | `level` (0–1, nullable), `state`, `low_power_mode`, `reported_at`, `contact_window` (`short`/`medium`/`long`/`unknown`) |
| `location` | object | yes | `precision` (`none`/`coarse`/`precise`); `geohash`/`latitude`/`longitude`/`label` optional. Coarse by default; precise is high-risk |
| `relay` | object | yes | `delivery` (`direct`/`mesh`/`nostr`/`unknown`), `direct`, `hops?`, `last_seen_at`, `relay_seen_at?` |
| `needs` | array | yes | Subset of `water`/`food`/`medical`/`charging`/`shelter`/`transport`/`rescue` |
| `expires_at` | number | yes | Unix expiry (default +1h) |

Canonical example: `docs/examples/minato-ios/safety_checkin.json`.

#### Broadcast & reception (E-3a)

- **Broadcast**: sent to the mesh with no specific recipient (`to` empty, `recipientID` nil) at TTL `5` (`MINATOPayload.safetyTTL`, higher than the default `3` for reach). Mesh relay/forwarding is handled by the existing Bitchat transport.
- **Embedded Agent Card (TOFU)**: a broadcast additionally carries the sender's signed Agent Card in `payload.agent_card`. Receivers that have not handshaken with the sender verify the card self-signature, check that the envelope `from` matches `agent_card.agent_id`, verify the envelope signature against `agent_card.ed25519_pub_key`, and cache the card on first contact (trust-on-first-use). A later check-in whose embedded key differs from the cached key is rejected (no identity swap). The golden example omits `agent_card` to show the minimal context shape.
- **Dedupe / expiry**: receivers store check-ins keyed by `id`, replacing on repeat and dropping entries past `expires_at`.
- **Direct vs relayed**: receivers derive best-effort delivery metadata from the packet TTL (`hops = safetyTTL − packet.ttl`; `direct` when `hops == 0`) for display. This is receive-side metadata, separate from the signed `relay` object.
- **Nostr store-and-forward (E-5)**: while in disaster mode, the same signed envelope is *also* sent over Nostr as an NIP-17 gift-wrap (kind 1059), directed to each emergency-override contact's npub, so it reaches them offline / out of mesh range via relay store-and-forward. The signed origin timestamps (`reported_at` / `expires_at`) stay authoritative — the Nostr event time is recorded only as receive-side `relaySeenAt`. Receivers verify it via the same self-attested TOFU path, dedupe by `id` across mesh + Nostr, and mark delivery as `nostr`. (Public geohash events / kind 20001 are out of scope — they need location.)

Status: E-2 = models + envelope encode/decode + golden example. E-3a = broadcast send + TOFU reception + dedupe/expiry + direct/relayed display. E-3b = periodic re-broadcast throttled by battery / Low Power Mode (`SafetyBroadcastPolicy`: base 5 min, ≤ 30 min, never fully stops). E-4a = time-boxed per-contact emergency overrides (precise location gated to explicit override). E-5 = directed Nostr gift-wrap store-and-forward to emergency-override contacts.

---

## Capability Values

Current iOS enum values:

| Capability | Risk note |
|---|---|
| `schedule.read` | Default |
| `schedule.write` | High-risk |
| `schedule.delete` | High-risk |
| `message.reply` | Default |
| `message.initiate` |  |
| `info.exchange` | Default |
| `language.translate` | Default |
| `location.area` |  |
| `location.precise` | High-risk |
| `safety.status.write` | Disaster mode (iOS-derived) |
| `safety.location.coarse` | Disaster mode (iOS-derived) |
| `safety.location.precise` | Disaster mode, High-risk (iOS-derived) |
| `safety.relay` | Disaster mode (iOS-derived) |
| `safety.broadcast` | Disaster mode (iOS-derived) |
| `safety.person_search` | Disaster mode (iOS-derived) |

Unknown capabilities are treated as high-risk by `Capability.isHighRisk(_:)`.

---

## Trust Mode Values

| Value | Display | Behavior |
|---|---|---|
| `plan` | Apprentice / 見習い | Always require owner approval |
| `suggest` | Partner / 相棒 | Can auto-send short low-stakes messages; requires approval for substantive actions |
| `auto` | Lieutenant / 右腕 | Auto for low-risk; high-risk needs explicit confirmation by capability policy |
| `full_auto` | Alter Ego / 分身 | Fully autonomous with post-hoc `AGENT_LOG` |

---

## iOS Proposal Candidates

These fields/shapes are implemented in iOS and may be proposed upstream separately:

| Candidate | iOS shape | Reason |
|---|---|---|
| Agent Card signing key | `agent_card.ed25519_pub_key` | Enables self-signature verification and later envelope verification |
| Envelope signature canonical form | sorted-key JSON with `signature` omitted | Keeps all `0x30`〜`0x37` payloads tamper-evident |
| `AGENT_REVOKE` payload | `scope`, `reason` | Separates trust revocation from card cache removal |
| `AGENT_LOG` payload | `log_id`, `action`, `trust_mode` | Enables idempotent post-hoc audit notifications |
| `AGENT_PING` current semantics | no-op heartbeat | Reserves the type without pretending latency/pong behavior exists |
| Disaster-mode safety check-in | `AGENT_MESSAGE` + `intent=safety.checkin` + `context.safety_checkin` | Trials safety broadcast without a new wire type; data isolated under `payload.context` |

---

## Known Implementation Notes

- `AGENT_HANDSHAKE` verifies only the Agent Card self-signature before saving the remote card.
- All non-handshake/non-ping packet verification depends on the remote card already being cached for the sender `PeerID`.
- `request_id` lives inside `payload`, not the top-level envelope.
- Schedule negotiation state is in-memory only.
- `ActivityLogStore` deduplicates by `log_id` and caps local storage at 200 entries.
- BLE and Nostr paths both encode the same signed `MINATOPayload` JSON envelope.
