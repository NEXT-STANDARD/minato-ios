# MINATO — TestFlight / App Store Release

Distribution prep for shipping MINATO to TestFlight (and later the App Store).
The **repo-side artifacts are done** (this PR); the **App Store Connect side** is
yours (Apple account). Two items below need your **explicit confirmation** as the
publisher (marked ⚠️).

## Repo-side artifacts (done)

| Artifact | Purpose |
|---|---|
| `bitchat/PrivacyInfo.xcprivacy` | App **privacy manifest** (Apple-required). Declares no tracking, no developer-side data collection, and the required-reason APIs the app (and its share extension) use: **UserDefaults** (`CA92.1`) + **file timestamps** (`DDA9.1`). |
| `bitchat/Info.plist` → `ITSAppUsesNonExemptEncryption = false` | ⚠️ **Export-compliance** declaration (see below). Avoids the per-upload prompt. |
| `Configs/ExportOptions.plist` | `xcodebuild -exportArchive` options (App Store, automatic signing). |
| `scripts/testflight-archive.sh` | One-shot archive → export `.ipa`. |

The manifest is auto-included (`bitchat/` is a synchronized group) and verified to
ship in `MINATO.app/PrivacyInfo.xcprivacy`. The share extension's required-reason
API usage (UserDefaults via the app group) is covered by this app-level manifest —
a separate extension manifest is only needed for **third-party SDKs**, which ship
their own (e.g. swift-crypto already does).

## ⚠️ Decisions to confirm (publisher's call)

1. **Encryption export compliance** — set to `ITSAppUsesNonExemptEncryption =
   false`, i.e. the app's encryption qualifies for exemption (standard algorithms:
   Noise / ChaCha20-Poly1305 / secp256k1 / Curve25519, used to protect the app's
   own messaging). This is the usual answer for an E2E messaging app using
   standard crypto, but **you are the exporter** — confirm you qualify for the BIS
   exemption. If you later add non-standard crypto, revisit (may require the annual
   self-classification report / CCATS).
2. **App privacy questionnaire** (App Store Connect → App Privacy) — the manifest
   declares **no data collection** (P2P; Nostr relays are public infrastructure
   carrying E2E-encrypted DMs; you run no servers). Confirm this matches your
   **published privacy policy** and answer the ASC questionnaire accordingly.

## Versioning

- `Configs/Release.xcconfig`: `MARKETING_VERSION = 1.5.1` (inherited from bitchat),
  `CURRENT_PROJECT_VERSION = 1`.
- ⚠️ Decide MINATO's marketing version (e.g. `1.0.0` for a fresh product, or keep
  `1.5.1`). **Each TestFlight upload needs a unique, higher `CURRENT_PROJECT_VERSION`**
  — bump it before every archive (or wire a CI/agvtool/date-based scheme).

## App Store Connect side (you)

1. **Register the app**: ASC → My Apps → +. Bundle ID = the one in
   `Configs/Local.xcconfig` (`PRODUCT_BUNDLE_IDENTIFIER`, currently
   `chat.bitchat.<TEAM>`). Create a matching App ID + an **App Store** provisioning
   profile (automatic signing in Xcode will create the distribution cert/profile on
   first archive if you're signed in).
2. **App information**: name (MINATO), primary language, category, privacy policy
   URL (required), and the App Privacy answers (see ⚠️ #2).
3. **TestFlight → Test Information**: beta description, feedback email, and the
   **export-compliance** answer (matches ⚠️ #1).
4. **External testers**: create a group → enable the **public link** (up to 10,000
   testers; first build needs a light **Beta App Review**). Internal testers (ASC
   users) get builds without review and faster.

## Build → upload

First time, the **Xcode GUI** is simplest: select "Any iOS Device", **Product ▸
Archive**, then **Distribute App ▸ App Store Connect ▸ Upload**.

Scripted / repeat / CI:

```bash
# 1) bump the build number first (unique per upload)
#    e.g. edit Configs/Release.xcconfig: CURRENT_PROJECT_VERSION = <n+1>

# 2) archive + export a signed .ipa
scripts/testflight-archive.sh   # → build/export/*.ipa

# 3) upload to App Store Connect
#    • Transporter.app (drag the .ipa), or
xcrun altool --upload-app -f build/export/*.ipa --type ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
#    (ASC API key .p8 in ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8)
```

After processing (a few minutes), the build appears in TestFlight → add it to the
external group / share the public link.

## After `git merge upstream/main`

`ITSAppUsesNonExemptEncryption` and the privacy manifests are app files an upstream
merge could touch — re-check them (tracked alongside the brand re-apply list in
`docs/MINATO-branding.md`).
