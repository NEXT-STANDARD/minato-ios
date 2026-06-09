# MINATO Remote Contact Invite

How two people who are **not** in Bluetooth range add each other and start
chatting over Nostr — the thing the proximity-first bitchat base could not do.

Status: **Phase 1 (PR1)** — invite link + invitee-side accept — **and Phase 2
(PR2)** — inviter-side approval gate (auto-quarantine + Accept/Decline inbox).

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
4. **Inviter** receives the hello. Instead of it appearing as a chat, the
   **approval gate** quarantines it as a **contact request** (PR2). The inviter
   sees a banner → a request inbox → **Accept** (the sender becomes a mutual
   favorite; we mark `theyFavoritedUs` from the request and send a `[FAVORITED]`
   back so their side also becomes mutual) or **Decline** (drop + block).

## The approval gate (PR2)

In the incoming-Nostr-DM path (`handlePrivateMessage`, shared with geohash DMs),
*after* the existing block check and dedup, a message is quarantined as a
`ContactRequest` (held in `ContactRequestStore`, not shown as a chat) **only when
all** hold:

- the sender is **not already a contact** (`findNoiseKey == nil`), and
- the content carries a **verifiable** `minato://add` invite
  (`extractInvite` → self-signature + 64-hex keys; scan bounded to 8 KB), and
- the invite's **npub matches the actual Nostr sender** — a sender can only
  assert their own identity, so this blocks forging a request that claims a
  **third party's** keys (the bundle's keys are self-signed but otherwise
  unbound, so without this check an attacker could make you "mutually favorite" a
  victim).

Normal/geohash/cold DMs (no verifiable invite, or a mismatched npub) flow through
unchanged. Declined senders are **blocked** (filtered before the gate on their
next DM); accepted senders become favorites (no longer gated). The store is
in-memory — gift-wrapped requests re-arrive from relays on launch, so the set
re-derives without persistence.

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
