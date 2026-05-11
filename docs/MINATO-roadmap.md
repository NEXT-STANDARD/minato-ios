# MINATO Agent Protocol — iOS 実装ロードマップ

最終更新: 2026-05-11
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

---

## 未着手

### Track B: iOS message shape 整理（0x30〜0x37）
次は spec 変更ではなく、iOS 側で現在の message shape を明文化する:
- `docs/MINATO-message-shapes.md` 新設
- 0x30〜0x37 の iOS 実装上の payload shape を一覧化
- `AGENT_HANDSHAKE` は実装済み shape と検証方式を明記
- `AGENT_PING` は現状 no-op heartbeat と明記
- spec 反映候補は「提案候補」として分離

### Track B-2: docs/ 充実
- `docs/ja/MINATO_PROTOCOL.md` — 日本語版復元
- `docs/en/` — 英語実装ガイド

### Track C-2: iOS examples / golden test
- iOS 側 docs/examples JSON を decode → re-encode して差分ゼロを確認
- spec 連携は、提案候補が固まってから別トラックで扱う

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
| `789c7d2` | `ed25519_pub_key` 追加 | `3dc97b6` で revert 済み。iOS shape として継続 |
| `45d6b5b` | `AGENT_REVOKE` payload/schema/example 追加 | `ca0daed` で revert 済み。iOS shape として継続 |
| `5d9ff3d` | `AGENT_LOG` payload/schema/example 追加 | `00e19ce` で revert 済み。iOS shape として継続 |
