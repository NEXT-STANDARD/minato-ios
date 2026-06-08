# MINATO Branding & Theme

This fork (`NEXT-STANDARD/minato-ios`) ships as **MINATO**, but still merges
upstream security patches from `jackjackbits/bitchat`. To keep the rebrand from
being silently reverted on merge — and to make future redesign mechanical — all
brand/theme values live in a small single-source layer.

## Concept

**港 (minato) = harbor.** A safe haven in disaster, and the port where AI agents
connect. The name, tagline, and visual theme (calm navy / off-white "生成り" +
teal "sea" accent + amber "beacon 灯台"; high-alert red/amber in disaster mode)
all derive from this metaphor.

## Single-source files (edit these, not scattered call sites)

| Concern | File | Notes |
|---|---|---|
| Name / tagline / scheme | `bitchat/MINATO/Theme/MinatoBrand.swift` | `MinatoBrand.displayName` etc. |
| Colors (港 palette) | `bitchat/MINATO/Theme/MinatoTheme.swift` | colorScheme-aware, cross-platform |
| Typography | `bitchat/MINATO/Theme/Font+MINATO.swift` | `.minatoSystem(...)` (delegates to bitchat font for now) |

Prefer `MinatoBrand.*`, `MinatoTheme.*`, `.minatoSystem(...)` in all MINATO-owned
views. Adoption across inherited bitchat screens is incremental.

## Upstream-shared files that need re-apply after `git merge upstream/main`

These are NOT pure code and can be reverted by an upstream merge. After every
merge, re-check / re-apply:

- `bitchat/Info.plist` → `CFBundleDisplayName = MINATO`
- `bitchatShareExtension/Info.plist` → `CFBundleDisplayName = MINATO`
- `bitchat/LaunchScreen.storyboard` → splash label text `MINATO`
- `bitchat/Views/ContentView.swift` header → `Text(verbatim: MinatoBrand.headerTitle)` (not `"bitchat/"`)
- `bitchat/Views/AppInfoView.swift` title → `MinatoBrand.displayName`
- `bitchat/Services/NotificationService.swift` → notification copy uses `MinatoBrand.displayName`

## Deferred (not in the foundation PR)

- **URL scheme** `bitchat://` → `minato://` — breaking (deep links + Nostr
  `bitchat1:` interop). Needs version negotiation; do as a deliberate step.
- **App icon / Assets** — redesign into a separate `Assets-MINATO.xcassets` to
  avoid upstream asset conflicts.
- **Localizable.xcstrings** — consider a MINATO sidecar `MINATO.xcstrings` for
  MINATO-specific strings to keep upstream-merge diffs small.
- **Full palette adoption** — migrate inherited screens from the hardcoded green
  to `MinatoTheme` colors, screen by screen.
- **Disaster high-alert mode** — when disaster mode is active, shift the whole UI
  to `MinatoTheme.alertBackground` / `alertAccent`.
