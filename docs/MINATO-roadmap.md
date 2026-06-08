# MINATO Agent Protocol — iOS 実装ロードマップ

最終更新: 2026-06-08
参照 spec: `NEXT-STANDARD/minato-spec` @ `3dc97b6` (2026-05-11)

注意: `minato-ios` は `minato-spec` の思想を踏襲した派生実装のひとつ。iOS 側の実装都合をそのまま spec に反映しない。protocol 全体へ広げたい変更は、まず iOS 側 docs で shape を明文化し、必要な場合だけ spec への提案候補として分離する。

---

## 完了済みフェーズ

### Phase 0: プロジェクト基盤
- [x] minato-ios リポジトリ作成（bitchat Option C fork）
- [x] `MINATO/` ディレクトリ構造確立

### Phase 1: プロトコル基盤
コミット: `334358f feat: MINATO Agent Protocol layer（Phase 1 foundation）`
- [x] `MINATOMessageType.swift` — 0x30–0x37 enum 定義
- [x] `AgentCard.swift` — Agent Card モデル（spec §4 準拠）
- [x] `TrustMode.swift` — plan/suggest/auto/full_auto 定義
- [x] `BLEService+MINATO.swift` — ルーティング基盤

### Phase 2: Trust Mode UI + Nostr フォールバック
コミット: `c76ea69`, `1590cdc`
- [x] Trust Mode 設定 UI（peer コンテキストメニュー）
- [x] MINATO メッセージの Nostr NIP-17 フォールバック
- [x] Agent Card 情報の peer 一覧表示
- [x] handshake end-to-end 結線

### Phase 3: AI 自動返信 / スケジュール交渉 / 多言語
コミット: `0765f73 feat: complete Phase 3 — AI auto-reply, schedule negotiation, multilingual, AGENT_LOG`
- [x] Gemini AI エンジン統合（`GeminiEngine.swift`）
- [x] スケジュール交渉ステートマシン（proposed → counterOffered → confirmed/rejected/cancelled）
- [x] EventKit 競合チェック + イベント作成（`CalendarAdapter.swift`）
- [x] 多言語対応（`original_language` / `translated_content`）
- [x] AGENT_LOG ローカル永続化（ActivityLogStore — max 200件、Keychain）
- [x] ActivityLog UI（`ActivityLogSheet.swift`）

### Phase 3.5: ストアリファクタリング
コミット: `aa7d3ff refactor: split MINATOAgentStore into four focused stores behind a facade`
- [x] `MINATOAgentStore` → `AgentIdentityStore` / `TrustStore` / `NegotiationStore` / `ActivityLogStore` に分割

---

## 完了済みトラック

### Track A-1: Ed25519 署名実装（仕様違反解消）
**ステータス**: 完了（2026-04-15）
**spec note**: `789c7d2` は `3dc97b6` で revert 済み。現状は iOS 派生実装側の shape。
**iOS commit**: `9311b12 feat(minato): implement Ed25519 signature for Agent Cards and envelopes`

背景: `signature` フィールドは常に `nil` 送出（仕様違反）。
既存 `NoiseEncryptionService` の Ed25519 鍵インフラを流用する。

- [x] **iOS proposal**: `ed25519_pub_key` と署名正規形を iOS 実装で試行
- [x] **iOS**: `AgentCard.swift` に `ed25519PubKey: String` 追加 + `signaturePayloadData()`
- [x] **iOS**: `MINATOMessageType.swift` に envelope の `signaturePayloadData()`
- [x] **iOS**: `MINATOSigning.swift` 新設（sign/verify 共通ヘルパ）
- [x] **iOS**: `BitchatApp.swift` + `ChatViewModel.swift` の AgentCard 生成に署名組み込み
- [x] **iOS**: `BLEService+MINATO.swift` 送信側に署名挿入
- [x] **iOS**: `ChatViewModel+MINATOTransport.swift` Nostr 経路も署名対応
- [x] **iOS**: `BLEService+MINATO.swift` 受信側に検証（handshake でキャッシュ → 以降検証）
- [x] **iOS**: `AgentCardSigningTests.swift` 新設（round-trip + 改ざん検出）
- [x] **iOS**: `MINATOPayloadSigningTests.swift` 新設（全 8 メッセージタイプ）

### Track A-2: AGENT_REVOKE (0x35) 実装
**ステータス**: 完了（2026-05-11）
**spec note**: `45d6b5b` は `ca0daed` で revert 済み。現状は iOS 派生実装側の shape。

- [x] **iOS proposal**: `scope` を `trust` / `agent_card` / `all` として試行
- [x] **iOS**: `PayloadContent` に `scope` / `reason` 追加
- [x] **iOS**: `RevokeScope` enum 追加
- [x] **iOS**: `handleAgentRevoke(_:)` 実装
- [x] **iOS**: `sendAgentRevoke(to:scope:reason:)` 実装
- [x] **iOS**: `TrustStore.removeTrustSettings(for:)` 追加
- [x] **iOS**: `AgentRevokeTests.swift` 追加（payload round-trip + TrustStore removal）

### Track A-3: AGENT_LOG (0x37) ネットワーク送出
**ステータス**: 完了（2026-05-11）
**spec note**: `5d9ff3d` は `00e19ce` で revert 済み。現状は iOS 派生実装側の shape。

- [x] **iOS proposal**: `action` を `auto_reply` / `auto_schedule_ack` / `auto_schedule_reject` として試行
- [x] **iOS**: `PayloadContent` に `log_id` / `trust_mode` 追加
- [x] **iOS**: `AgentActivityLog.ActionType` に protocol snake_case 変換を追加（永続化 rawValue は互換維持）
- [x] **iOS**: full_auto/auto の自動返信後に 0x37 `AGENT_LOG` を送出
- [x] **iOS**: `handleAgentLog(_:)` 実装
- [x] **iOS**: `ActivityLogStore` で `log_id` 重複排除
- [x] **iOS**: `AgentLogTests.swift` 追加（action mapping + payload round-trip + dedupe）

### Track B: iOS message shape 整理（0x30〜0x37）
**ステータス**: 完了（2026-05-11）

- [x] `docs/MINATO-message-shapes.md` 新設
- [x] 0x30〜0x37 の iOS 実装上の payload shape を一覧化
- [x] `AGENT_HANDSHAKE` は実装済み shape と検証方式を明記
- [x] `AGENT_PING` は現状 no-op heartbeat と明記
- [x] spec 反映候補は「提案候補」として分離

### Track C-2: iOS examples / golden test
**ステータス**: 完了（2026-05-11）

- [x] `docs/examples/minato-ios/` に 0x30〜0x37 の canonical JSON examples を追加
- [x] iOS 側 docs/examples JSON を decode → re-encode して差分ゼロを確認
- [x] spec 連携は、提案候補が固まってから別トラックで扱う

### Track D: ドキュメント運用
**ステータス**: 完了（2026-05-11）

- [x] `CLAUDE.md` に「MINATO 署名フロー」セクション追加
- [x] spec 更新時の iOS 側追従チェックリストを `CLAUDE.md` に追記

### Track B-2: docs/ 充実
**ステータス**: 完了（2026-05-11）

- [x] `docs/ja/MINATO_PROTOCOL.md` — 日本語版復元
- [x] `docs/en/IMPLEMENTATION_GUIDE.md` — 英語実装ガイド

### Track E: Disaster Mode 設計
**ステータス**: 設計完了（2026-05-11）

- [x] `docs/MINATO-disaster-mode.md` 新設
- [x] 安否確認 / 位置共有 / 助け合い情報の MVP scope を定義
- [x] battery 情報を safety payload の初期表示・triage 必須要素として定義
- [x] `safety.*` intents / capabilities の iOS proposal candidate を整理
- [x] privacy / abuse risk / battery policy を明文化
- [x] Phase 1〜5 の実装計画を定義

---

## 次期実装候補

### Track E-1: Disaster Mode local models + UI（store / banner / dashboard）
**ステータス**: 完了（2026-06-08）

> 設計判断: `Safety*` を災害モードの正系実装とする。並行して存在していた
> `Disaster*` 系（`Disaster.swift` の `DisasterStatus` / `DisasterModeStore` /
> `BatteryMonitor`、PR #4/#5/#6 由来）は `Safety*` に統合し削除した。中央
> `Capability`/`Intent` enum の `disaster.*` 追加も差し戻し、safety 名前空間は
> `SafetyModels.swift` の `SafetyCapability`/`SafetyIntent` を単一の出所とする
> （AgentCard への capability 統合は E-2 で扱う）。

- [x] `SafetyStatus`(6値), `SafetyBatterySnapshot`, `SafetyLocation`, `SafetyRelayMetadata`, `SafetyCheckin` モデル追加
- [x] iOS battery snapshot helper 追加（level/state/low power mode/contact window）— `BatterySnapshotProvider`
- [x] `DisasterModeView` ダッシュボード（`無事です` / `助けが必要` / `家族を探す` / `近くの情報を見る`）
- [x] local preview cards に battery / timestamp / location precision / relay status を表示
- [x] `SafetyModeStore` 共有ストア（isActive / checkin / lastActiveAt、battery sampling 注入可能）
- [x] `SafetyHeaderView` ホームバナー（OFF=起動 CTA / ON=現在ステータス表示）
- [x] `ContentView` 配線（バナー → 起動確認ダイアログ → full-screen ダッシュボード）
- [x] `SafetyPayloadTests` / `SafetyModeStoreTests` 追加

### Track E-2: Safety payload integration
**ステータス**: 完了（2026-06-08）

> 設計判断: `safety.checkin` は新 wire 型を作らず **`AGENT_MESSAGE`(0x31) + `intent=safety.checkin`** に乗せ、安否データは **`payload.context["safety_checkin"]`** に格納する iOS-derived shape。docs では iOS proposal candidate として明示。

- [x] `SafetyCheckin` ⇄ `AnyCodableValue` ブリッジ（`SafetyPayload+MINATO.swift`）
- [x] `MINATOPayload.safetyCheckin(...)` builder + `decodedSafetyCheckin()` extractor + `isSafetyCheckin`
- [x] safety intents/capabilities を中央 `Intent`/`Capability` に統合（`safety.location.precise` を highRisk）。`SafetyModels` の standalone enum は集約・削除
- [x] `docs/examples/minato-ios/safety_checkin.json`（canonical）追加 + golden test に登録
- [x] `docs/MINATO-message-shapes.md` に safety section（intent/capability/shape）追記
- [x] `SafetyCheckinEnvelopeTests` 追加（round-trip / intent / 署名正規形 / highRisk）

### Track E-3a: BLE mesh send + TOFU reception
**ステータス**: 完了（2026-06-08）

> 設計判断: 受信は **自己署名 TOFU**（safety.checkin に AgentCard を同梱、初回に自己署名検証→キャッシュ）。未ハンドシェイクの近隣他者からも改ざん検出付きで受信可。送信は **ステータス変更/起動時に1回ブロードキャスト**（周期ループは E-3b）。mesh リレー/TTL 転送は既存 Bitchat トランスポートが担当。

- [x] `sendSafetyCheckin(_:)` — AgentCard 同梱でブロードキャスト（`recipientID` nil, `ttl=safetyTTL`）
- [x] TOFU 受信検証（`verifiedSafetyCard(cachedKey:)` 純関数 + `handleMINATOPacket` 分岐 + 鍵衝突拒否）
- [x] `SafetyCheckinStore` — `id` dedupe / `expires_at` 破棄 / cap、`deliveredVia`/`hops` 付与
- [x] `handleAgentMessage` で safety.checkin を受信ストアへ（chat/AI返信から分離）
- [x] direct vs relayed メタデータを packet TTL から算出し DisasterModeView に表示
- [x] DisasterModeView の status 変更/起動で送信トリガ配線（ContentView → ChatViewModel → BLEService）
- [x] テスト: store dedupe/expiry/cap、TOFU 検証、delivery メタデータ

### Track E-3b: 周期再送 + 電池スロットリング（保留）
- 起動中の定期再ブロードキャスト
- low battery / low power mode で送信頻度を抑制（送信間隔判定は純関数でテスト）
- 実機必須（Simulator 検証不可）のため分離

---

## 既知の技術的判断

| 判断 | 内容 |
|------|------|
| **Noise 署名鍵の多重用途** | `NoiseEncryptionService.signingKey` を MINATO envelope にも使用。将来 MINATO 専用鍵を別 Keychain エントリで導入する余地を残す。 |
| **Negotiation は in-memory のみ** | `NegotiationStore` は意図的に永続化なし。再起動時は再提案させる設計（`NegotiationStore.swift:6-11`）。 |
| **AGENT_LOG は max 200件** | ActivityLogStore の設計上限。将来的にページネーション対応の余地あり。 |
| **旧バージョン互換なし** | 署名実装前に `signature: nil` 端末が存在しないため一斉切替で可。 |
| **Disaster Mode は coarse location default** | precise location は high-risk とし、明示確認または期限付き emergency override に限定する。 |
| **battery は safety triage 必須情報** | `safety.*` payload には battery snapshot と reported_at を含め、初動判断に使う。 |

---

## spec 参照コミット追跡

| spec commit | 内容 | iOS 側反映状況 |
|---|---|---|
| `60f991c` | CLAUDE.md 更新（schema/examples レイアウト） | — |
| `2e30010` | examples 追加 | — |
| `9186365` | schema 初版 (6 ファイル) | 準拠 |
| `83f4e72` | transport fallback / schedule negotiation / AGENT_RESPONSE / persistence | Phase 3 で実装済み |
| `4d2ad7e` | request_id を payload 内に移動 | 反映済み (`payload.request_id`) |
| `789c7d2` | `ed25519_pub_key` 追加 | `3dc97b6` で revert 済み。iOS shape として継続 |
| `45d6b5b` | `AGENT_REVOKE` payload/schema/example 追加 | `ca0daed` で revert 済み。iOS shape として継続 |
| `5d9ff3d` | `AGENT_LOG` payload/schema/example 追加 | `00e19ce` で revert 済み。iOS shape として継続 |
