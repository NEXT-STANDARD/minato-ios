# MINATO Agent Protocol — iOS 実装ロードマップ

最終更新: 2026-05-11
参照 spec: `NEXT-STANDARD/minato-spec` @ `45d6b5b` (2026-05-11)

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

## 進行中

### Track A-3: AGENT_LOG (0x37) ネットワーク送出
- 現状はローカル記録のみ（`BLEService+MINATO.swift` 内 "future feature"）
- spec 側: `schema/agent-log.json` 追加
- iOS 側: full_auto 実行完了時に相手へ 0x37 送出（冪等性のため `log_id` を payload に）

---

## 完了済みトラック

### Track A-1: Ed25519 署名実装（仕様違反解消）
**ステータス**: 完了（2026-04-15）
**spec commit**: `789c7d2 feat(agent-card): add ed25519_pub_key for signature verification`
**iOS commit**: `9311b12 feat(minato): implement Ed25519 signature for Agent Cards and envelopes`

背景: `signature` フィールドは常に `nil` 送出（仕様違反）。
既存 `NoiseEncryptionService` の Ed25519 鍵インフラを流用する。

- [x] **spec**: `MINATO_PROTOCOL.md` §4 に `ed25519_pub_key` 追加、署名正規形を規定
- [x] **spec**: `schema/agent-card.json` に `ed25519_pub_key` (required) 追加
- [x] **spec**: `schema/common.json` に `ed25519_pub_key` 共通定義追加
- [x] **spec**: `examples/handshake/` の Agent Card サンプル更新
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
**spec commit**: `45d6b5b feat(schema): add AGENT_REVOKE payload`

- [x] **spec**: `schema/agent-revoke.json` 追加
- [x] **spec**: `examples/revoke/01-revoke-all.json` + README 追加
- [x] **spec**: `MINATO_PROTOCOL.md` §10 に `AGENT_REVOKE` payload 定義追加
- [x] **spec**: `scope` を `trust` / `agent_card` / `all` として定義
- [x] **iOS**: `PayloadContent` に `scope` / `reason` 追加
- [x] **iOS**: `RevokeScope` enum 追加
- [x] **iOS**: `handleAgentRevoke(_:)` 実装
- [x] **iOS**: `sendAgentRevoke(to:scope:reason:)` 実装
- [x] **iOS**: `TrustStore.removeTrustSettings(for:)` 追加
- [x] **iOS**: `AgentRevokeTests.swift` 追加（payload round-trip + TrustStore removal）

---

## 未着手

### Track B: スキーマ網羅（0x30/0x35/0x36/0x37）
spec 側で 4 スキーマを追加し、schema カバレッジを 0x30–0x37 完備に:
- `schema/agent-handshake.json` (0x30)
- `schema/agent-revoke.json` (0x35) — Track A-2 で完了
- `schema/agent-ping.json` (0x36)
- `schema/agent-log.json` (0x37) — Track A-3 と一体

### Track B-2: docs/ 充実
- `docs/ja/MINATO_PROTOCOL.md` — 日本語版復元
- `docs/en/` — 英語実装ガイド

### Track C-2: Spec examples との golden test
- spec examples JSON を iOS 側で decode → re-encode して差分ゼロを CI で確認
- `ajv-cli` で examples が schema に適合することを CI で確認

### Track D: ドキュメント運用
- `CLAUDE.md` に「MINATO 署名フロー」セクション追加
- spec 更新時の iOS 側追従チェックリストを `CLAUDE.md` に追記

---

## 既知の技術的判断

| 判断 | 内容 |
|------|------|
| **Noise 署名鍵の多重用途** | `NoiseEncryptionService.signingKey` を MINATO envelope にも使用。将来 MINATO 専用鍵を別 Keychain エントリで導入する余地を残す。 |
| **Negotiation は in-memory のみ** | `NegotiationStore` は意図的に永続化なし。再起動時は再提案させる設計（`NegotiationStore.swift:6-11`）。 |
| **AGENT_LOG は max 200件** | ActivityLogStore の設計上限。将来的にページネーション対応の余地あり。 |
| **旧バージョン互換なし** | 署名実装前に `signature: nil` 端末が存在しないため一斉切替で可。 |

---

## spec 参照コミット追跡

| spec commit | 内容 | iOS 側反映状況 |
|---|---|---|
| `60f991c` | CLAUDE.md 更新（schema/examples レイアウト） | — |
| `2e30010` | examples 追加 | — |
| `9186365` | schema 初版 (6 ファイル) | 準拠 |
| `83f4e72` | transport fallback / schedule negotiation / AGENT_RESPONSE / persistence | Phase 3 で実装済み |
| `4d2ad7e` | request_id を payload 内に移動 | 反映済み (`payload.request_id`) |
| `789c7d2` | `ed25519_pub_key` 追加 | iOS `9311b12` で反映済み |
| `45d6b5b` | `AGENT_REVOKE` payload/schema/example 追加 | Track A-2 で反映済み |
