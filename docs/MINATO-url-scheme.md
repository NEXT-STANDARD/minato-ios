# MINATO URL Scheme Migration (`bitchat://` → `minato://`)

The fork inherits bitchat's `bitchat://` deep-link scheme and `bitchat1:` Nostr
embed prefix. Migrating the brand to **MINATO** means moving to `minato://`, but
some of these formats cross the app boundary, so the migration is **phased and
version-managed** rather than a flag-day rename.

All scheme strings are single-sourced in `MinatoBrand`
(`bitchat/MINATO/Theme/MinatoBrand.swift`).

## The three classes of scheme usage

| Class | Examples | Crosses a boundary? | Migration |
|---|---|---|---|
| **In-app deep links** | `://user/<id>`, `://geohash/<gh>`, `://share`, notification deeplinks | No — same app instance generates & handles them | **Emit `minato://`** now |
| **QR verification** | `://verify?…` | Yes — scanned by *another device* (possibly an older app) | **Keep emitting `bitchat://verify`**; accept both on scan |
| **Nostr embed** | `bitchat1:<base64url>` packet in Nostr DMs | Yes — wire format shared with the bitchat Nostr network | **Keep emitting `bitchat1:`**; accept both on receive |

## Phase 1 (current) — "accept both, emit new where safe"

Decided strategy: **interop-first / staged**.

- **Receive: accept both everywhere.** `Info.plist` registers `minato` **and**
  `bitchat`. Every handler uses `MinatoBrand.acceptsURLScheme(_:)` /
  `MinatoBrand.nostrEmbedPrefix(matching:)` instead of hard-coding `"bitchat"`:
  - `BitchatApp.handleURL` (`://share`)
  - `MessageListView.handleOpenURL` (`://user` / `://geohash`)
  - `VerificationService.VerificationQR.fromURL` (`://verify`)
  - `ChatViewModel+Nostr.decodeEmbeddedBitChatPacket` (`bitchat1:` / `minato1:`)
- **Emit `minato://`** for in-app deep links (`ChatViewModel` user/geohash links,
  `NotificationService` geohash deeplink).
- **Keep emitting the legacy format** for the two cross-client cases:
  - `VerificationQR.toURLString()` → `MinatoBrand.legacyURLScheme` (`bitchat://verify`)
  - `NostrEmbeddedBitChat` → `MinatoBrand.nostrEmbedPrefix` (`bitchat1:`)

This is fully backward compatible: existing `bitchat://` links, old QR codes, and
the bitchat Nostr network keep working; nothing a current install produced breaks.

## Phase 2 (later) — flip the wire formats

Once enough installs accept `minato://` / `minato1:` (and, for Nostr, once the
change is reflected in `minato-spec` with version negotiation), flip:

- `VerificationQR.toURLString()` → `minato://verify`
- `NostrEmbeddedBitChat` → `minato1:`

then eventually stop registering/emitting `bitchat://` (keep *accepting* it for a
long tail). Each flip is a one-line change in `MinatoBrand`.

## NOT a scheme (do not touch)

- `VerificationQR.context = "bitchat-verify-v1"` is the **signature context**
  baked into the signed canonical bytes — it is not a URL scheme. Changing it
  breaks signature verification across devices. It is versioned separately.

## After `git merge upstream/main`

`bitchat/Info.plist` `CFBundleURLSchemes` and the handlers above are
upstream-shared. Re-check that `minato` is still registered and the handlers
still go through `MinatoBrand`. (Tracked alongside the other re-apply items in
`docs/MINATO-branding.md`.)
