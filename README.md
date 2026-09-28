<p align="center">
  <img width="180" height="180" alt="MINATO app icon — a beacon over a calm night harbor" src="bitchat/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" />
</p>

<h1 align="center">MINATO</h1>

<p align="center"><strong>圏外でも、家族に「無事」を届ける。</strong><br/>
Tell your family you're safe — even off the grid.</p>

---

MINATO（港）は、**地震・津波・台風・停電などで通信インフラが落ちても**、近くの人や信頼する相手に安否を届けるための、オフラインファースト安否確認アプリです。基地局もインターネットも要りません。スマートフォン同士が **Bluetooth LE mesh** で直接つながり、メッセージを多段中継（store-and-forward）し、誰かがネット圏内に出たら **Nostr / インターネット** 経由で外へ運びます。

平時の MINATO は、AI エージェント同士が予定調整などの生活支援を行う **MINATO Agent Protocol** のリファレンス実装です。非常時には同じ mesh が、安否・粗い位置・「助けが必要」を運ぶ災害モードに切り替わります。

> **港（minato）= harbor.** 災害時の安全な避難港であり、エージェントが接続する港。この比喩が名前・タグライン・テーマ（凪いだ紺青に灯台のアンバー、災害モードでは高警戒の赤／橙）の由来です。

MINATO は、実戦投入され公開監査されている **[bitchat](https://github.com/jackjackbits/bitchat)** の BLE mesh / Nostr トランスポートと Noise Protocol 暗号の上に構築されています。自前の暗号は書いていません — 実証済みのスタックの上に立つことは意図的な信頼上の判断です（詳細は [Credits](#credits--provenance)）。

## なぜ MINATO か

災害初動の数時間、スマホのバッテリーは残っていても通常の通信経路は使えないことがあります。MINATO 災害モードはその数時間に次を可能にします。

- **無事を届ける** — 近くの人や信頼先へ「無事です」を broadcast
- **粗い位置を安全に共有** — 既定は coarse（geohash / エリア名）。precise は明示確認が要る高リスク操作
- **助けが必要な人を優先的に見つける** — `助けが必要` をトリアージ用に高優先で
- **電池残量を判断材料に** — 「今すぐ対応すべきか」を残量・低電力モードから読む
- **圏外でも中継** — BLE mesh で運び、誰かがネットに出たら Nostr fallback で外へ

## Features

- **オフラインファースト安否確認（災害モード）** — `無事です` / `助けが必要` / `家族を探す` / `近くの情報を見る` の大きな操作。安否カードはバッテリー・最終更新・位置精度・direct/relay を表示
- **MINATO Agent Protocol（0x30–0x37）** — Agent Card 交換、Trust Mode（`plan` / `suggest` / `auto` / `full_auto`）、capabilities / intents、Ed25519 署名付きエンベロープ
- **デュアルトランスポート** — オフラインの Bluetooth mesh ＋ インターネットの Nostr。経路は自動選択（Bluetooth → Nostr fallback）
- **多段中継 mesh** — ピア自動探索と multi-hop relay（Bluetooth LE）
- **エンドツーエンド暗号** — mesh は [Noise Protocol](https://noiseprotocol.org)、Nostr は NIP-17 gift-wrap
- **プライバシーファースト** — アカウント・電話番号・永続 IDなし。コンタクト交換は QR / 招待リンク（承認ゲート付き）
- **緊急ワイプ** — トリプルタップで全データを即時消去
- **多言語** — UI とパーミッション文言を 29 言語にローカライズ

## How it works（アーキテクチャ）

MINATO のトランスポートは bitchat 由来の **ハイブリッド構成** です。MINATO はその上に Agent Protocol と災害安否レイヤーを載せています。

```
Application      SwiftUI（ContentView, Views/, ViewModels/）
Agent / Safety   bitchat/MINATO/（Agent Card, Trust Mode, Disaster Mode, stores）
MINATO Protocol  0x30–0x37 メッセージタイプ（Ed25519 署名）
Transport        BLE Mesh（offline）/ Nostr Relay（internet）  ← bitchat base
Crypto           Noise Protocol / secp256k1                    ← bitchat base
```

### Bluetooth Mesh（オフライン）

- 圏内のピアと直接 P2P、近隣デバイス経由で multi-hop relay（最大 7 hops）
- インターネット不要 — 災害シナリオで完全オフライン動作
- Noise Protocol による forward secrecy 付き E2E 暗号
- BLE 制約に最適化したコンパクトなバイナリプロトコル、適応的な省電力デューティサイクル

### Nostr Protocol（インターネット）

- ネット圏内に出たデバイスが安否を外へ store-and-forward
- geohash ベースの位置チャンネル、分散リレー網
- NIP-17 gift-wrap による DM 秘匿、geohash エリアごとの ephemeral 鍵

詳細は [Technical Whitepaper](WHITEPAPER.md) と `docs/`（[MINATO-disaster-mode.md](docs/MINATO-disaster-mode.md) / [MINATO-message-shapes.md](docs/MINATO-message-shapes.md)）を参照。

## Setup

> 内部の Xcode プロジェクト／ターゲット名は、upstream（bitchat）ベースのため引き続き `bitchat`（例: `bitchat.xcodeproj`, scheme `bitchat (iOS)`）です。ホーム画面・About・ストア表示はすべて **MINATO** です。

### 前提

- Xcode（最新安定版）、macOS
- BLE テストには実機 iPhone が必要（Simulator は BLE 非対応）

### ローカル設定

```bash
# Local.xcconfig に Team ID を設定
cp Configs/Local.xcconfig.example Configs/Local.xcconfig
# DEVELOPMENT_TEAM（必要なら PRODUCT_BUNDLE_IDENTIFIER）を編集
```

```bash
# iOS 向けビルド（署名なし・クイックチェック）
xcodebuild -project bitchat.xcodeproj \
  -scheme "bitchat (iOS)" -configuration Debug \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

ビルド・配布の詳細は [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md) を参照。

## Credits & Provenance

MINATO は **[bitchat](https://github.com/jackjackbits/bitchat)**（jackjackbits/bitchat）の上に構築されています。bitchat から受け継いでいるもの:

- **BLE mesh ＋ Nostr** デュアルトランスポート
- **Noise Protocol** によるエンドツーエンド暗号
- バイナリパケット形式、gossip/sync、ルーティング

bitchat は **The Unlicense**（パブリックドメイン）で公開されており、帰属の法的義務はありません。それでも明記するのは、**実証済みで監査されたトランスポート／暗号スタックの上に立つことが、意図的な信頼上の判断**だからです。MINATO は自前の暗号を実装していません。upstream のセキュリティパッチは継続的にマージしています（`upstream` remote）。

MINATO 固有の追加分（Agent Protocol 0x30–0x37、Trust Mode、災害安否確認モード、29 言語の MINATO パーミッション文言、ブランド／テーマ／アイコン）は本リポジトリ（NEXT-STANDARD/minato-ios）で開発しています。プロトコル仕様の source of truth は別リポジトリ [NEXT-STANDARD/minato-spec](https://github.com/NEXT-STANDARD/minato-spec) です。

## License

本プロジェクトはパブリックドメインで公開されています（base である bitchat の Unlicense を踏襲）。詳細は [LICENSE](LICENSE) を参照。

## Localization

- ベースのアプリ文言は `bitchat/Localization/Base.lproj/`。新規コピーは `Localizable.strings`、複数形は `Localizable.stringsdict` に追加
- Share Extension の文言は `bitchatShareExtension/Localization/` に分離
- ブランド文言は単一の真実源（`bitchat/MINATO/Theme/MinatoBrand.swift`）を参照すること。詳細は [docs/MINATO-branding.md](docs/MINATO-branding.md)
