# MINATO Privacy Policy

*Last updated: June 2026*

## Our Commitment

MINATO is designed with privacy as its foundation. We believe private communication — and the ability to tell people you are safe — is a fundamental human right. This policy explains how MINATO protects your privacy, including in Disaster Mode where you can share your safety status and approximate location.

MINATO builds on the open-source [bitchat](https://github.com/jackjackbits/bitchat) transport. Like bitchat, it runs without accounts or servers; MINATO adds safety check-ins and an agent protocol on top.

## Summary

- **No personal data collection** — We don't collect names, emails, or phone numbers, and nothing is sent to us or to any server we operate.
- **No servers** — Everything happens on your device and through peer-to-peer connections. (Nostr relays are public infrastructure that carry end-to-end-encrypted data when you go online; we run none of them.)
- **No tracking** — No analytics, no telemetry, no advertising identifiers, no user profiling. Our [privacy manifest](bitchat/PrivacyInfo.xcprivacy) declares this to Apple.
- **You control sharing** — Safety status, location, and battery are shared **only when you choose to broadcast a safety check-in** (or enable an emergency override). Coarse by default.
- **Open source** — You can verify these claims by reading our code.

## What MINATO Stores

### On Your Device Only

1. **Identity Key** — A cryptographic key generated on first launch, stored in your device's secure storage. Lets you maintain "favorite"/contact relationships across restarts. Never leaves your device.
2. **Nickname** — The display name you choose (or an auto-generated one). Stored on device; shared with peers you communicate with.
3. **Contacts & Favorites** — Public keys (and optional petnames) of peers you have deliberately added via QR / invite link, with mutual approval. Stored only on your device.
4. **Emergency Contacts & Overrides** — If you choose to set them, the contacts you allow to auto-receive your safety check-ins during Disaster Mode, and the override's scope/expiry. Off by default; stored only on your device.
5. **Message History** (if enabled) — When retention is enabled, messages are saved encrypted on your device. You can delete this at any time.

### Temporary Session Data

During each session MINATO temporarily maintains active peer connections, routing information, and briefly-cached messages for offline peers — all forgotten when no longer needed.

## What Is Shared, and When

### With nearby peers (general use)

When you use MINATO, nearby peers can see your chosen nickname, your ephemeral public key (changes each session), the messages you send to public channels or directly to them, and your approximate Bluetooth signal strength (for connection quality).

### Safety check-ins (Disaster Mode) — user-initiated

A safety check-in is shared **only when you choose to send one** (or via an emergency override you enabled). When you do, a cryptographically **signed** check-in may include:

- **Status** — e.g. `safe`, `needs_help`, `injured`, `evacuating`, `searching`.
- **Location** — **coarse by default** (a geohash / area label such as "渋谷区周辺"). **Precise location is never shared automatically**; it is a high-risk action that requires your explicit, per-share confirmation (or a narrowly-scoped emergency override), and is sent only to the directed recipient — the broadcast copy stays coarse.
- **Battery** — your self-reported battery level, charging state, and Low Power Mode, so others can judge whether your contact window may close soon. This is information your device asserts; it is not independently verifiable by recipients.
- **Needs** — e.g. water, medical, charging, shelter.
- **Timestamps and an expiry** (`expires_at`) — so stale information is not mistaken for fresh, and delivery metadata (direct vs relayed) is shown.

A safety check-in is broadcast to nearby mesh peers and may be **relayed multi-hop** through other devices so it can reach people out of direct range. If a relaying device has internet access, it may forward the check-in over **Nostr** so it can reach your contacts who are online. You can **stop broadcasting with one tap**, and check-ins expire automatically.

### Emergency override contacts

If you enable an emergency override, your safety check-ins are auto-shared to the contacts you chose during Disaster Mode. Overrides are **off by default**, **scoped to safety information only**, **easy to revoke**, and **expire automatically** (after Disaster Mode ends or a fixed duration you pick).

## Location

MINATO accesses your location **only** for features you actively use:

- **Location channels** — joining geohash-based public channels uses your **approximate** location.
- **Safety check-ins** — sharing your area in Disaster Mode (coarse by default; precise only with explicit confirmation).

Your location is **never** used for tracking, **never** stored on a server, and **never** sent to the developer. As the in-app permission states: *"MINATO uses your approximate location to find local public channels and share your area in disaster mode. Your exact GPS location is never shared automatically."* You can revoke location access at any time in system settings.

## What We DON'T Do

MINATO **never**:

- Collects personal information or sends your data to us or our servers (we operate none).
- Tracks your location or uses your location for anything beyond the feature you invoked.
- Shares data with third parties, advertisers, or data brokers.
- Uses analytics, telemetry, or advertising identifiers.
- Creates user profiles or requires registration.

## Encryption

Private communication uses end-to-end encryption:

- **X25519** for key exchange, **AES-256-GCM** / **ChaCha20-Poly1305** for message encryption
- **Ed25519** for digital signatures (including signed Agent Cards and safety check-ins)
- **Noise Protocol** for mesh sessions; **NIP-17** gift-wrapping for Nostr private messages

Safety check-ins are signed so recipients can verify they were not tampered with in transit. (A signature proves the message came from a given key — it does not, by itself, prove the sender's real-world identity. MINATO surfaces whether a sender is a verified contact.)

## Your Rights

- **Delete Everything** — Triple-tap to instantly wipe all keys, sessions, and cached state.
- **Stop Broadcasting** — One tap to stop sharing your safety status.
- **Revoke Overrides** — Remove emergency-override contacts at any time.
- **Leave Anytime** — Close the app and your presence disappears.
- **No Account** — Nothing to delete from servers, because there are none.

## Bluetooth & Permissions

- **Bluetooth** — Required for the peer-to-peer mesh. Used only for communication, not for tracking. Revocable in system settings.
- **Location** — Optional, requested only when you use location channels or share your area in a safety check-in. Approximate by default; revocable at any time.

## Children's Privacy

MINATO does not knowingly collect information from children. The app has no age verification because it collects no personal information from anyone.

## Data Retention

- **Messages** — Ephemeral in memory; bounded per chat and trimmed (cached briefly for offline peers, then dropped).
- **Safety check-ins** — Expire automatically (`expires_at`); de-duplicated and bounded locally.
- **Identity Key / Contacts / Emergency Contacts** — Persist on device until you remove them or delete the app.
- **Everything else** — Exists only during active sessions.

## Security Measures

- All private communication is encrypted; signed messages prevent tampering.
- No data transmitted to servers (there are none).
- Open-source code for public audit; upstream security patches from bitchat are merged regularly.
- Conservative logging that filters potential secrets; debug verbosity suppressed in release builds.

## Changes to This Policy

If we update this policy, the "Last updated" date will change and the updated policy will be included in the app. We cannot retroactively change data handling for data we don't collect.

## Contact

MINATO is an open-source project. For privacy questions:

- View our source code: [https://github.com/NEXT-STANDARD/minato-ios](https://github.com/NEXT-STANDARD/minato-ios)
- Open an issue on GitHub

## Philosophy

Privacy isn't just a feature — it's the foundation. MINATO proves that you can reach the people who matter, and tell them you're safe when it counts most, without surrendering your privacy. No accounts, no servers, no surveillance. Just people, connected — even off the grid.

---

*MINATO builds on bitchat, which is released into the public domain under The Unlicense. This policy is likewise released into the public domain.*
