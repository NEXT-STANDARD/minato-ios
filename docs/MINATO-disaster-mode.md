# MINATO Disaster Mode — Design Plan

最終更新: 2026-05-11

この文書は `minato-ios` に災害時の安否確認・位置共有・助け合い情報を組み込むための設計計画です。
平時の MINATO は agent-to-agent の生活支援を担い、非常時の MINATO は基地局やインターネットが失われた状況でも、BLE mesh と store-and-forward で安否と救助に必要な情報を届けることを目指します。

---

## Product Thesis

日本では地震、津波、台風、豪雨、停電などにより、基地局や通信インフラが局所的または広域に失われることがあります。
災害初期にはスマートフォンのバッテリーが残っている一方で、通常の通信経路が使えないことがあります。

MINATO Disaster Mode の目的は、災害初動の数時間に次を可能にすることです。

- 近くの人や信頼先へ安否を届ける
- 粗い位置情報を安全に共有する
- 助けが必要な人を優先的に見つける
- 電池残量を含めて「今すぐ対応すべきか」を判断する
- ネット圏外でも BLE mesh で情報を中継し、誰かがネット圏内へ出たら Nostr / Internet fallback で届ける

---

## MVP Scope

最初の実装では、災害時に一番価値が高い「少ない操作で安否と必要情報を出す」ことに集中します。

### User Actions

| Action | Purpose |
|---|---|
| `無事です` | 自分が生存・避難可能であることを共有 |
| `助けが必要` | 救助・支援が必要なことを優先度高く共有 |
| `家族を探す` | 信頼先・近隣 mesh に探索情報を共有 |
| `近くの情報を見る` | 避難所、充電、水、医療、道路状況などを確認 |

### First-screen Information

安否カードの初期表示には、必ずバッテリー情報を含めます。

```text
無事です
最終更新: 14:08
場所: 渋谷区周辺
電池: 12% 低電力モード
通信: メッシュ経由 3 hops
```

```text
助けが必要
最終更新: 14:08
場所: 江東区沿岸部周辺
電池: 6% 残りわずか
けが: あり
必要: 水 / 医療 / 充電
```

Battery level is not decorative. It affects triage:

- Low battery means the contact window may close soon.
- Charging implies access to power and possible relay capacity.
- High battery devices can safely relay more messages.
- Low Power Mode should reduce beacon/send frequency.

---

## Proposed Intents

These are iOS proposal candidates until coordinated with `NEXT-STANDARD/minato-spec`.

| Intent | Meaning |
|---|---|
| `safety.checkin` | Safety status broadcast |
| `safety.request_help` | Urgent help request |
| `safety.resource_offer` | Offer water, power, medical supplies, shelter, etc. |
| `safety.resource_request` | Request water, power, medical help, transport, etc. |
| `safety.location_share` | Share coarse or precise location |
| `safety.evacuation_notice` | Evacuation site / route / hazard notice |
| `safety.person_search` | Search for family or trusted contacts |

---

## Proposed Capabilities

| Capability | Risk | Meaning |
|---|---|---|
| `safety.status.write` | low | Send safety status |
| `safety.location.coarse` | medium | Share coarse geohash / area label |
| `safety.location.precise` | high | Share precise coordinates |
| `safety.relay` | medium | Store-and-forward other safety messages |
| `safety.broadcast` | medium | Broadcast safety/resource notices |
| `safety.person_search` | high | Search or broadcast identity-linked person search |

Unknown safety capabilities should be treated as high risk.

---

## Safety Payload Shape

Disaster Mode can reuse `MINATOPayload` and carry safety-specific fields under `payload.context` initially, then graduate to typed Swift models once the shape stabilizes.

Proposed `safety.checkin` example:

```json
{
  "intent": "safety.checkin",
  "content": "無事です。避難所へ移動中です。",
  "status": "safe",
  "battery": {
    "level": 0.12,
    "state": "unplugged",
    "low_power_mode": true,
    "reported_at": 1778499480,
    "contact_window": "short"
  },
  "location": {
    "precision": "coarse",
    "geohash": "xn76u",
    "label": "渋谷区周辺"
  },
  "relay": {
    "delivery": "mesh",
    "hops": 3,
    "direct": false,
    "last_seen_at": 1778499480,
    "relay_seen_at": 1778499540
  },
  "needs": ["charging"],
  "expires_at": 1778503080
}
```

### Battery Object

| Field | Type | Required | Notes |
|---|---|---:|---|
| `level` | number | yes | 0.0〜1.0 |
| `state` | string | yes | `charging`, `unplugged`, `full`, `unknown` |
| `low_power_mode` | boolean | yes | iOS Low Power Mode |
| `reported_at` | uint64 | yes | Unix seconds from the device that produced the battery report |
| `contact_window` | string | no | `short`, `medium`, `long`, `unknown` |

`contact_window` should be coarse. Avoid pretending to know exact remaining battery time.

Suggested mapping:

| Condition | Contact Window |
|---|---|
| `level < 0.15` and not charging | `short` |
| `level < 0.40` and not charging | `medium` |
| charging or `level >= 0.40` | `long` |
| battery unknown | `unknown` |

### Location Object

| Field | Type | Required | Notes |
|---|---|---:|---|
| `precision` | string | yes | `none`, `coarse`, `precise` |
| `geohash` | string | no | Coarse default; precision should be intentionally limited |
| `latitude` | number | no | Only for explicit precise sharing |
| `longitude` | number | no | Only for explicit precise sharing |
| `label` | string | no | Human-readable area |

Default location behavior should be coarse or none. Precise location is high risk and requires explicit confirmation except for narrowly scoped emergency overrides.

### Relay Metadata

| Field | Type | Required | Notes |
|---|---|---:|---|
| `delivery` | string | yes | `direct`, `mesh`, `nostr`, `unknown` |
| `hops` | int | no | Mesh hop count when available |
| `direct` | boolean | yes | Whether this came directly from the sender |
| `last_seen_at` | uint64 | yes | Timestamp from sender-originated report |
| `relay_seen_at` | uint64 | no | Timestamp when relay observed it |

Relay metadata is important because stale or relayed safety information must not look like fresh direct contact.

---

## Status and Needs

Suggested `status` values:

| Status | Meaning |
|---|---|
| `safe` | Safe / alive |
| `injured` | Injured but able to report |
| `needs_help` | Needs urgent help |
| `evacuating` | Moving to shelter or safer area |
| `searching` | Looking for family / trusted contact |
| `unknown` | Status uncertain |

Suggested `needs` values:

| Need | Meaning |
|---|---|
| `water` | Needs water |
| `food` | Needs food |
| `medical` | Needs medical help |
| `charging` | Needs power / battery support |
| `shelter` | Needs shelter |
| `transport` | Needs transport |
| `rescue` | Needs rescue |

---

## Trust and Emergency Overrides

Disaster Mode should integrate with Trust Mode, not bypass it casually.

Recommended defaults:

| Recipient | Default sharing |
|---|---|
| Public / nearby mesh | Status + coarse location only |
| Trusted contacts | Status + coarse location + battery |
| Emergency override contacts | Auto-share safety check-in during Disaster Mode |
| Anyone | Precise location only after explicit confirmation |

Emergency overrides should be:

- Off by default.
- Easy to understand.
- Easy to revoke.
- Scoped to safety intents only.
- Expiring automatically after Disaster Mode ends or after a fixed duration.

---

## Privacy and Abuse Risks

Disaster Mode must account for high-risk users and contexts:

- DV / stalking risk
- Political or social persecution risk
- False rescue lures
- Doxxing via precise location
- Stale messages being interpreted as current
- Resource misinformation and panic amplification

Required mitigations:

- Coarse location by default.
- `expires_at` on all safety broadcasts.
- `reported_at`, `last_seen_at`, and relay metadata shown in UI.
- One-tap hide / stop broadcasting.
- One-tap revoke for trusted recipients.
- Clear direct vs relayed display.
- Signed messages and local dedupe.

---

## Battery Policy

Battery preservation is part of the feature, not an optimization afterthought.

Suggested behavior:

| Condition | Behavior |
|---|---|
| Battery < 15% | Reduce beacon frequency, prioritize own safety packets |
| Low Power Mode | Disable nonessential sync, lower relay duty |
| Charging | Allow higher relay duty if user permits |
| Battery unknown | Conservative relay behavior |

Safety messages should have priority over normal chat and nonurgent agent activity while Disaster Mode is active.

---

## Implementation Phases

### Phase 1: Local Models and UI Shell

- Add safety status model.
- Add battery snapshot helper using `UIDevice`.
- Add Disaster Mode screen with large actions: `無事です`, `助けが必要`, `家族を探す`, `近くの情報を見る`.
- Add local preview cards with battery, timestamp, location precision, and relay status.

### Phase 2: MINATO Payload Integration

- Add safety intent / capability constants.
- Encode `safety.checkin` using `MINATOPayload`.
- Keep safety-specific fields under `payload.context` for the first iteration.
- Add unit tests for safety payload encode/decode.
- Add docs examples for safety payloads.

### Phase 3: BLE Mesh Broadcast and Relay

- Send safety check-ins over BLE mesh.
- Add TTL / expiry / dedupe.
- Prefer low-power behavior when battery is low.
- Mark direct vs relayed messages.

### Phase 4: Trusted Contacts and Emergency Overrides

- Allow user to choose contacts for emergency auto-share.
- Add per-contact safety permissions.
- Add one-tap revoke / stop broadcasting.
- Keep precise location high risk.

### Phase 5: Nostr / Internet Fallback

- Store-and-forward safety packets.
- Relay to Nostr when internet becomes available.
- Preserve origin timestamps and relay metadata.

---

## Initial Engineering Tasks

Status: Phase 1 local models + UI shell completed on 2026-05-11.

1. [x] Create `SafetyStatus`, `SafetyBatterySnapshot`, `SafetyLocation`, and `SafetyRelayMetadata` models.
2. [x] Add `SafetyIntent` / `SafetyCapability` constants without changing existing `Intent` / `Capability` enum behavior until the shape is stable.
3. [x] Implement `BatterySnapshotProvider` for iOS.
4. [x] Add `DisasterModeView` shell.
5. [x] Add `SafetyPayloadTests` for JSON encode/decode.
6. [ ] Add `docs/examples/minato-ios/safety_checkin.json`.
7. [ ] Extend `docs/MINATO-message-shapes.md` with a safety payload section after the first implementation pass.

---

## Open Questions

- Should safety messages use existing `AGENT_MESSAGE`, or should MINATO reserve a distinct disaster packet type in the future?
- What TTL and rebroadcast interval best balance delivery and battery preservation?
- Should relay nodes be able to redact precise location when forwarding to wider mesh scopes?
- How should the UI distinguish owner-generated, agent-generated, and relay-observed safety information?
- What emergency override duration should be the default: 6 hours, 12 hours, 24 hours, or until manually disabled?
