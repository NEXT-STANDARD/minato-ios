# MINATO Agent Protocol — iOS 実装ガイド

最終更新: 2026-05-11

この文書は `minato-ios` における MINATO Agent Protocol の日本語ガイドです。
プロトコル全体の source of truth は `NEXT-STANDARD/minato-spec` ですが、このリポジトリでは iOS 実装上の shape と運用判断を明示してから spec 反映候補を分離します。

詳細な wire shape は次を参照してください。

- `docs/MINATO-message-shapes.md`
- `docs/examples/minato-ios/*.json`
- `bitchatTests/MINATO/MINATOMessageShapeGoldenTests.swift`

---

## 目的

MINATO は、人間同士のチャットの上に「ユーザーの代理として動く Agent」を重ねるためのプロトコル層です。

`minato-ios` では Bitchat の既存 transport を再利用します。

| 層 | iOS 実装 |
|---|---|
| UI / app state | SwiftUI, `ChatViewModel` |
| Agent layer | `bitchat/MINATO/` |
| MINATO protocol | `0x30`〜`0x37` |
| Transport | BLE Mesh / Nostr fallback |
| Crypto | Noise Protocol infrastructure + Ed25519 signatures |

設計方針:

- Bitchat の transport / crypto / mesh は必要最小限の拡張に留める。
- MINATO 固有のモデル、署名、Trust Mode、AI / calendar 連携は `bitchat/MINATO/` に置く。
- iOS 実装都合の shape は、spec に混ぜず「iOS proposal candidate」として文書化する。

---

## 主要コンポーネント

| ファイル | 役割 |
|---|---|
| `bitchat/MINATO/Protocol/MINATOMessageType.swift` | `0x30`〜`0x37` の message type と envelope |
| `bitchat/MINATO/Models/AgentCard.swift` | Agent Card モデルと canonical signing payload |
| `bitchat/MINATO/Models/Capability.swift` | capability / intent enum |
| `bitchat/MINATO/Models/TrustMode.swift` | `plan` / `suggest` / `auto` / `full_auto` |
| `bitchat/MINATO/Services/MINATOSigning.swift` | Ed25519 sign / verify helper |
| `bitchat/MINATO/Services/BLEService+MINATO.swift` | BLE 経由の encode / decode / handler |
| `bitchat/ViewModels/Extensions/ChatViewModel+MINATOTransport.swift` | BLE / Nostr 経路選択 |
| `bitchat/MINATO/Services/Stores/` | Agent Card, Trust, Negotiation, Activity Log stores |

---

## Agent Card

Agent Card は MINATO agent の名刺です。`AGENT_HANDSHAKE` で交換され、以後の envelope 署名検証に使われます。

主なフィールド:

| フィールド | 内容 |
|---|---|
| `minato_version` | 現在 `"0.1"` |
| `agent_id` | 現在は Nostr `npub` |
| `display_name` | UI 表示名 |
| `owner_locale` | 所有者の主言語 |
| `capabilities` | agent が扱える操作 |
| `default_trust_mode` | 新規接続時の Trust Mode |
| `supported_intents` | 対応 intent |
| `ai_engine` | 利用 AI engine の情報 |
| `ed25519_pub_key` | iOS 実装の envelope 検証用公開鍵 |
| `signature` | Agent Card 自己署名 |

`ed25519_pub_key` と Agent Card 署名は iOS 実装で試行している shape です。protocol 全体へ広げる場合は spec 側へ別途提案します。

---

## 署名フロー

MINATO では Agent Card と envelope の両方を Ed25519 で署名します。

### Agent Card 署名

1. `AgentCard.create(...)` で unsigned card を作る。
2. `ed25519_pub_key` に local Ed25519 public key hex を入れる。
3. `signature` を除いた sorted-key JSON を canonical bytes とする。
4. canonical bytes を署名し、`signature` に hex 文字列を入れる。
5. 受信側は `AGENT_HANDSHAKE` で Agent Card 自己署名を検証してから remote card として保存する。

### Envelope 署名

1. `MINATOPayload` を `signature: nil` で作る。
2. `signature` を除いた sorted-key JSON を canonical bytes とする。
3. canonical bytes を署名し、top-level `signature` に hex 文字列を入れる。
4. 受信側は cached remote Agent Card の `ed25519_pub_key` で検証する。

`AGENT_HANDSHAKE` と `AGENT_PING` 以外は、remote Agent Card が未検証または未保存なら drop します。

---

## Message Types

| Type | Name | 目的 |
|---:|---|---|
| `0x30` | `AGENT_HANDSHAKE` | Agent Card 交換 |
| `0x31` | `AGENT_MESSAGE` | agent conversation / AI reply |
| `0x32` | `AGENT_REQUEST` | 行動リクエスト。現在は schedule negotiation 中心 |
| `0x33` | `AGENT_RESPONSE` | request への応答 / counter proposal |
| `0x34` | `AGENT_ACK` | confirm / reject |
| `0x35` | `AGENT_REVOKE` | trust / Agent Card / all の revoke |
| `0x36` | `AGENT_PING` | 現状 no-op heartbeat |
| `0x37` | `AGENT_LOG` | auto / full_auto の事後通知 |

各 type の payload shape は `docs/MINATO-message-shapes.md` を参照してください。canonical JSON examples は `docs/examples/minato-ios/` にあります。

---

## Trust Mode

| 値 | 表示名 | 振る舞い |
|---|---|---|
| `plan` | Apprentice / 見習い | すべて owner approval |
| `suggest` | Partner / 相棒 | 短い低リスク返信は自動、それ以外は approval |
| `auto` | Lieutenant / 右腕 | 低リスクは自動、高リスクは capability policy に従う |
| `full_auto` | Alter Ego / 分身 | 自動実行し、`AGENT_LOG` で事後通知 |

高リスク capability:

- `schedule.write`
- `schedule.delete`
- `location.precise`

未知の capability は high-risk として扱います。

---

## Schedule Negotiation

スケジュール調整は `request_id` で紐づく `AGENT_REQUEST` → `AGENT_RESPONSE` → `AGENT_ACK` の chain として扱います。

状態:

| State | 意味 |
|---|---|
| `proposed` | request を受信 / 送信し、応答待ち |
| `counterOffered` | counter proposal あり |
| `confirmed` | `AGENT_ACK` with `status == "confirmed"` |
| `rejected` | `AGENT_ACK` with non-confirmed status |
| `cancelled` | cancel intent |

`NegotiationStore` は in-memory です。再起動後は再提案させる設計です。

---

## Activity Log

`auto` / `full_auto` で agent が自動実行した場合、`AGENT_LOG` を送信し、local `ActivityLogStore` に保存します。

主な payload:

| フィールド | 内容 |
|---|---|
| `log_id` | idempotency key |
| `action` | `auto_reply`, `auto_schedule_ack`, `auto_schedule_reject` |
| `trust_mode` | `auto` または `full_auto` |
| `content` | 事後通知本文 |

受信側は `log_id` で重複排除します。local storage は newest-first、上限 200 件です。

---

## 実装変更時のチェックリスト

MINATO の wire shape を変える場合:

1. `bitchat/MINATO/Protocol/MINATOMessageType.swift` と関連 model / handler を更新する。
2. `docs/MINATO-message-shapes.md` を更新する。
3. `docs/examples/minato-ios/*.json` を更新する。
4. golden test を実行する。

```bash
xcodebuild -project bitchat.xcodeproj \
  -scheme "bitchat (iOS)" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:bitchatTests_iOS/MINATOMessageShapeGoldenTests \
  test
```

署名に関係する変更では、次も実行します。

```bash
xcodebuild -project bitchat.xcodeproj \
  -scheme "bitchat (iOS)" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:bitchatTests_iOS/AgentCardSigningTests \
  -only-testing:bitchatTests_iOS/MINATOPayloadSigningTests \
  test
```

spec へ広げたい変更は、まず iOS docs の「提案候補」として分離してから `NEXT-STANDARD/minato-spec` に提案します。
