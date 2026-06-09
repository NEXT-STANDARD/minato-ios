# MINATO Remote Contact Invite

How two people who are **not** in Bluetooth range add each other and start
chatting over Nostr — the thing the proximity-first bitchat base could not do.

Status: **Phase 1 (PR1)** — invite link + invitee-side accept. The inviter-side
**approval gate** (auto-quarantine of incoming requests) is **Phase 2 (PR2)**.

## The invite link

A contact invite is the **same self-signed identity bundle** as the verification
QR, carried under a different host so it can be opened remotely:

```
minato://add?v=1&noise=<hex>&sign=<hex>&nick=<name>&ts=<unix>&nonce=<b64u>&sig=<hex>&npub=<npub>
```

- `VerificationService.buildMyInviteString(nickname:npub:)` builds it.
- `VerificationService.verifyInvite(_:)` parses + checks the Ed25519
  self-signature over the canonical bytes. **No freshness window** — invites are
  sent out-of-band and opened later; the signature proves authenticity and replay
  is harmless because adding requires explicit approval and is idempotent.
- Shared from the verify sheet via a "招待リンクを共有" `ShareLink`.

## Flow (Phase 1)

1. **Inviter** shares their `minato://add` link (Messages, etc.). Distribution of
   the app itself is via **TestFlight** (custom-scheme links only work once the
   app is installed — chosen scope).
2. **Invitee** taps the link → `MessageListView.handleOpenURL` `case "add"` →
   `ChatViewModel.receiveContactInvite` verifies it and shows a confirmation
   prompt (name **and** a short npub prefix, so a spoofed display name alone
   can't fool the user).
3. On **Add**, `acceptContactInvite` → `addContact`:
   - adds the inviter as a **favorite** (durable contact, keyed on their Noise
     key, carrying their npub),
   - sends a one-way Nostr **hello** that embeds the **invitee's own** invite
     link, so the inviter can add back with one tap,
   - confirms with a system message. The chat does **not** auto-open: a one-way
     favorite is blocked from messaging until it's mutual (avoids a confusing
     "requires mutual favorite" wall). It opens automatically once mutual.
4. **Inviter** receives the hello (a DM containing the invitee's `minato://add`
   link). Tapping it adds the invitee back → **mutual favorite** → both can chat.
   PR2 replaces this manual tap with a proper **request inbox** (Accept/Decline).

## Security model

- **Approval-gated** (the user's chosen model). The npub is already semi-public
  (broadcast in geohash channels), so the real control is on the receiving side:
  Phase 2 quarantines incoming requests from non-contacts.
- **Self-signature verified** before any state change.
- **Input validation** on the untrusted link: Noise/Sign keys must be 64-hex
  (32-byte); the nickname is run through `InputValidator.validateNickname`
  (length cap + control/format-char stripping) before storage **and** display;
  npub is required (a contact with no Nostr key is unreachable).
- **Self-add guard** on both the Noise key and the npub (npub alone is bypassable
  by stripping it from the link).
- **The hello is bounded** to the just-added favorite (not arbitrary npubs).

### Known, accepted limitations (Phase 1)

- **Host is not part of the signed bytes** — a `minato://verify` QR can be
  rewritten as a `minato://add` invite and vice-versa. Acceptable because both
  carry the same authentic identity and adding requires explicit approval; if the
  two intents must be cryptographically distinct, fold the host into the signed
  payload in a future protocol revision.
- **Accepting reveals your identity bundle** (incl. your Noise key) to the link's
  npub — inherent to the add-back design, and the npub is already semi-public.
- **No expiry / key-rotation handling** — an old invite stays valid until the
  owner removes the favorite. Fine for Phase 1 (idempotent, manually removable).
