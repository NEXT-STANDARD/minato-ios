# minato-ios 災害モード — MVP 設計

最終更新: 2026-05-05
ステータス: **設計合意済み、実装未着手**

---

## なぜ作るか

minato-ios はメッシュ × エージェント代理を持つ唯一の iOS アプリ。この組み合わせが最も価値を発揮する文脈が **災害時の家族安否確認**。

差別化メッセージ:
> 「電波が死んだ瞬間、家族と繋がる準備ができているスマホ」

bitchat / 一般チャットアプリ / AI チャット のいずれでもない identity を、災害モード一機能で打ち出す。

---

## ターゲット・ユースケース

第一読者: **日本に住む、家族が複数人いるユーザー**。

代表シナリオ:
1. **大地震直後**: ネット死亡 → 家族の安否を mesh 経由で確認したい
2. **帰宅困難（鉄道停止・通信混雑）**: 家族と「どこにいる、何時頃合流」を agent 同士で擦り合わせたい
3. **避難所到着**: 家族にいる場所を継続的に知らせたい（電池節約しつつ）

非ターゲット (v2 以降):
- 不特定多数への安否情報リレー
- 災害情報の自治体配信中継
- Apple Watch / Siri 連携

---

## MVP スコープ

### 含む

| ID | 機能 | 概要 |
|---|---|---|
| F1 | 災害モード本体 | ホーム画面の大ボタンで ON/OFF。ON 中は 5 分ごとに安否 broadcast |
| F1.5 | 安否ペイロード | `intent: "disaster.safety"` に status / battery / location / last_active を含める |
| F2 | 緊急連絡先事前登録 | 平時に 2-5 人を MINATO peer から登録 |
| F3 | ステータス 4 段階 | 🟢無事 / 🟡軽傷 / 🔴要救助 / ❓不明 |
| F3.5 | 家族リスト UI | 各人の状態 + battery + 位置 + 時刻表示。低 battery は警告色 |
| B | ロック画面ウィジェット | rectangular。iOS 17+ Interactive、iOS 16 informational |
| N | Nostr push 通知 | 家族の誰かが災害モード ON → NIP-17 で他家族に通知 |

### 含まない（明記）

| 項目 | 理由 |
|---|---|
| C: J-ALERT 連携 | iOS API の PoC リスク。v2 で再検討 |
| 常時バックグラウンド起動 | iOS BLE 制約 + 電池消費。常時起動はしない設計 |
| Apple Watch / WatchOS | 開発コスト過大。v2 以降 |
| Siri ショートカット | MVP 後の早期 follow-up に回す |
| 不特定多数への安否情報リレー | スコープ拡大を避ける |
| 自治体・公的災害情報リレー | 同上 |
| 災害モード平時訓練機能 | v2 以降 |

---

## プロトコル拡張

新しい wire type は追加しない。既存 `AGENT_MESSAGE` (0x31) の `intent` に新値を追加し、`context` に災害固有情報を載せる。

### `intent: "disaster.safety"` （安否 broadcast）

```json
{
  "intent": "disaster.safety",
  "context": {
    "status": "ok",                  // ok | injured | needs_help | unknown
    "battery_pct": 23,               // 0-100, iOS は 5% 刻み
    "battery_state": "discharging",  // charging | discharging | full | unknown
    "location_hint": "東京駅周辺",     // 平時は丸めた地名、災害時は詳細
    "last_active_at": 1715000000     // owner が最後にスマホを触った unix 時刻
  }
}
```

最低 3 フィールド (`status`, `battery_pct`, `battery_state`) は **必須**。

### `intent: "disaster.safety_query"`（特定家族の安否を問い合わせ）

直接届かない家族について、間に挟まれた他者の agent 経由で情報を取りに行く（mesh を多段ホップ）。MVP では **直接届く家族へのみ問い合わせ可能**、多段ホップは v2。

```json
{
  "intent": "disaster.safety_query",
  "context": {
    "target_npub": "npub1...",
    "max_age_seconds": 1800
  }
}
```

返答は通常の `disaster.safety` で来る。受信側 agent が直近の自分の状態をそのまま返す。

### Nostr push: `disaster.mode_activated`（家族間トリガ）

NIP-17 gift wrap に乗せて緊急連絡先 npub 全員に送信。

```json
{
  "kind": "minato.disaster.mode_activated",
  "originator_npub": "npub1...",
  "originator_display_name": "田中太郎",
  "location_hint": "東京駅周辺",
  "timestamp": 1715000000,
  "message": "災害モードを起動しました。皆さん大丈夫ですか？"
}
```

受信側はローカル通知に「災害モードに参加」アクションボタンを出す。タップで自端末も災害モード ON。

---

## Permission モデル

平時に登録、災害時は確認なしで実行。

### 平時の設定 UX

設定画面に「緊急連絡先」セクションを新設。

```
緊急連絡先 (2/5)
┌────────────────────────┐
│ + 緊急連絡先を追加     │  ← 既存 MINATO peer から選択
└────────────────────────┘

家族リスト:
  父さん     [編集] [削除]
  ハナコ     [編集] [削除]
```

各登録時に 1 回だけ大きな確認モーダル:

> 「災害モードでは、緊急連絡先には自動で
> ・現在地（詳細）
> ・電池残量
> ・最終操作時刻
> を共有します。よろしいですか？」

[同意して登録] / [キャンセル]

この同意はローカル Keychain に保存。災害モード時はこの同意済みフラグを参照して **個別確認なしで** 自動共有する。

### 災害時の挙動

災害モード ON → 緊急連絡先全員に対し:

| 設定 | 災害時の値 |
|---|---|
| TrustMode | **強制 Full Auto** （元の設定に関わらず） |
| 位置粒度 | **詳細 GPS 座標** |
| 自動応答 | 安否問い合わせに常に応答 |
| Capability | `disaster.share_safety` 自動付与 |

緊急連絡先 **以外** の peer:
- 通常の TrustMode を維持
- 安否情報は broadcast 範囲（peer 自身が要求しない限り見えない）には含めない
- 災害モード状態自体（「私が災害モード ON である」）は周辺に告知（プライバシー上は安全）

---

## アクティベーション経路

3 つの入口で起動できる。常時バックグラウンド起動はしない。

### 経路 1: ホーム画面大ボタン

アプリを開いた最初の画面に、視認性の高い「🚨 災害モード ON」ボタンを置く。長押し or 二段階タップで誤発動を防ぐ。

### 経路 2: ロック画面ウィジェット

iOS 16+ で表示、iOS 17+ で interactive。詳細は「ロック画面ウィジェット仕様」参照。

### 経路 3: Nostr push 通知

家族の誰かが ON にしたら、自分の端末に通知が届く。タップで「災害モードに参加」。

### MVP に入らない経路（明記）

- バックグラウンド常時 BLE スキャン
- iOS の J-ALERT 受信トリガ（v2 PoC）
- Background App Refresh による定期チェック
- 加速度センサーでの揺れ検知

---

## UI 構成

### ホーム画面（既存 ChatView を災害モード対応に拡張、または分離）

災害モード OFF 時:
- 通常の minato UI（チャット中心）
- 上部に「🚨 災害モード」エントリー（小さめ）

災害モード ON 時:
- 全画面が「家族の安否ダッシュボード」に切り替わる
- 自分のステータス変更が大きく目立つ
- 家族リスト（status / battery / 位置 / 時刻）
- チャット UI はサブ画面に降格

### 家族リスト UI

```
┌─────────────────────────────────────┐
│  家族の状態                         │
├─────────────────────────────────────┤
│ 父さん                              │
│   🟢 無事                           │
│   📱 23% 🔌 充電中  3分前          │
│   📍 東京駅 中央改札付近            │
├─────────────────────────────────────┤
│ ハナコ                              │
│   🟢 無事                           │
│   📱 8% ⚠️  充電なし  1分前         │ ← 警告色
│   📍 自宅                           │
├─────────────────────────────────────┤
│ タロウ                              │
│   ❓ 不明                           │
│   📱 ---                            │
│   最終応答: 27分前                  │
└─────────────────────────────────────┘
```

低 battery（< 15%）かつ充電なし は **赤系警告色**。直感的に「先に連絡すべき相手」が分かる。

### 自ステータス変更 UI

巨大なタップエリアで 4 段階を切替:

```
┌─────────────┬─────────────┐
│  🟢 無事    │  🟡 軽傷    │
├─────────────┼─────────────┤
│  🔴 要救助  │  ❓ 不明     │
└─────────────┴─────────────┘
```

タップで即時 broadcast。手が震える / 暗い / グローブ越しでも操作できることを優先。

---

## ロック画面ウィジェット仕様

### サイズ

MVP では **rectangular** のみ実装。circular / inline は v2。

### 表示内容

```
┌──────────────────────────┐
│ 🟢 私: 無事    📱 23%   │
│ 🚨 災害モード ON         │
│ 家族: ●●○ 2/3 OK         │
└──────────────────────────┘
```

要素優先度:

| 要素 | MVP |
|---|---|
| 自分のステータス（🟢🟡🔴❓） | ★★★ 必須 |
| 自分の battery | ★★★ 必須 |
| 災害モード ON/OFF | ★★★ 必須 |
| 家族の集計（2/3 OK 等） | ★★☆ |
| 災害モード ON した人 | ★☆☆ v2 |
| 周辺 mesh ピア数 | ★☆☆ v2 |
| 最終 broadcast 時刻 | ★☆☆ v2 |

### インタラクション

iOS 17+ (App Intent):

| タップ箇所 | 動作 |
|---|---|
| 自分ステータス | クイック変更（🟢→🟡→🔴 巡回 or アクションシート） |
| 災害モード | OFF↔ON トグル（誤発動防止のため確認ダイアログ） |
| 家族集計 | アプリの家族リスト画面を開く |

iOS 16 (Tap to Open):
- どこをタップしてもアプリの災害モード画面を開く（informational only）

### データ共有

App Group 経由で widget からアクセス可能な軽量 store を用意。Widget は読み取りのみ、変更は App Intent でメインプロセスを起動して行う。

---

## iOS 技術メモ

### Battery API

```swift
UIDevice.current.isBatteryMonitoringEnabled = true
let pct = UIDevice.current.batteryLevel  // 0.0 - 1.0, または -1.0 (unknown)
let state = UIDevice.current.batteryState // .unknown | .unplugged | .charging | .full
```

- **シミュレータでは batteryLevel が -1.0** になるのでテスト時はモック必須
- 粒度は 5% 刻み（iOS の制約）
- 災害モード中は 5 分ごとに値を取得して payload に含める

### Location API

平時:
- `CLLocationManager` の `requestWhenInUseAuthorization`
- `desiredAccuracy = kCLLocationAccuracyKilometer` （丸め）
- `location_hint` は CLGeocoder で逆ジオコード（オフライン時はキャッシュから）

災害時:
- `desiredAccuracy = kCLLocationAccuracyBest`
- 緯度経度を payload に含める
- 逆ジオコードは可能な範囲で

### iOS BLE バックグラウンド制約（再確認）

- バックグラウンドスキャンは制限あり、優先度低、いつでも kill される
- 災害モード ON 中は前景もしくは前景接続維持。ユーザーがアプリを閉じる場合の挙動は要 PoC
- ユーザー教育: 「災害モード中はアプリを開いたままにしてください」をモード起動時に表示

### Widget Background Refresh

- Widget は WidgetCenter.shared.reloadTimelines(ofKind:) でアプリ側から更新通知できる
- 更新頻度には iOS の制約あり（連続 reload は無視される）
- 災害モード ON 中は最低 1 分間隔で reload を試みる

---

## 実装フェーズ

設計確定後の実装順:

| フェーズ | 内容 | 期待コミット数 |
|---|---|---|
| **D-0** | この設計ドキュメント | 1 |
| **D-1** | `disaster.safety` ペイロードの値型 + 単体テスト（Capability / Intent 追加 + payload encode/decode） | 1-2 |
| **D-2** | `DisasterModeStore` （ON/OFF state、battery/location サンプリング） | 1-2 |
| **D-3** | F1 災害モード ON/OFF UI（ホーム大ボタン） | 1 |
| **D-4** | F2 緊急連絡先 UI（設定画面の新セクション） | 1-2 |
| **D-5** | F3 / F3.5 ステータス変更 + 家族リスト UI | 2-3 |
| **D-6** | B ロック画面ウィジェット（informational + interactive） | 2-3 |
| **D-7** | N Nostr push トリガ（送信 + 受信通知 + 参加導線） | 2-3 |
| **D-8** | E2E 動作確認 + drive-by fix（CalendarAdapter macOS 14 ガード等） | 1-2 |

合計 12-17 コミット程度。各フェーズは独立してレビュー可能。

---

## 開いている設計疑問

実装に入る前に、必要なら追加議論:

1. **緊急連絡先は MINATO peer に限るか、Nostr npub 直接入力も認めるか**
   - MVP は「既存の MINATO peer から選ぶ」のが安全。直接入力は v2

2. **災害モード解除のタイミング**
   - 手動 OFF のみか、N 時間で自動 OFF か、「全員無事確認」で自動 OFF か
   - MVP は手動 OFF のみ、想起のため N 時間後に確認通知が無難

3. **位置共有の粒度設定をユーザー側で調整可能にするか**
   - 「災害時でも丸めにしたい」「家族にだけ詳細、他は丸め」等の細粒度
   - MVP は「緊急連絡先 = 詳細 / それ以外 = 共有しない」固定。設定追加は v2

4. **災害モード中のバッテリー消費の expectation**
   - 何分持つか、ユーザーに事前提示する必要があるか
   - 実機 PoC で測ってから提示（D-8 のタスク）

5. **複数の家族が同時に災害モード ON した時の挙動**
   - 重複通知の抑制、リーダー選出は要らないか
   - MVP は「全員から push が来る、UI 側で重複排除」で良い

6. **災害モードのアプリ内ヘルプ / 初回起動チュートリアル**
   - 平時に登録しないと意味がないので、初回起動時に促したい
   - MVP に「設定セクション + 初回バナー」を入れる方針

---

## 関連ドキュメント

- [MINATO Agent Protocol — iOS 実装ロードマップ](./MINATO-roadmap.md)（既存機能の Phase 0-3 + Track A/B/C）
- minato-spec の wire format リファレンス（別 repo）

このドキュメントは MINATO Phase 4 にあたるが、roadmap.md とは独立して管理する。災害モードは spec の派生機能であり、必要に応じて将来 spec へ昇格させる余地は残す。
