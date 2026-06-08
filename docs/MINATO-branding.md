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

- `bitchat.xcodeproj/project.pbxproj` → `INFOPLIST_KEY_CFBundleDisplayName = MINATO` (6 build configs: iOS/macOS app + share extension × Debug/Release). **This build setting overrides the Info.plist value**, so it is the authoritative home-screen name.
- `bitchat/Info.plist` → `CFBundleDisplayName = MINATO` (kept consistent with the build setting)
- `bitchatShareExtension/Info.plist` → `CFBundleDisplayName = MINATO`
- `bitchat/LaunchScreen.storyboard` → splash label text `MINATO`
- `bitchat/Views/ContentView.swift` header → `Text(verbatim: MinatoBrand.headerTitle)` (not `"bitchat/"`)
- `bitchat/Views/AppInfoView.swift` title → `MinatoBrand.displayName`
- `bitchat/Services/NotificationService.swift` → notification copy uses `MinatoBrand.displayName`

## Palette adoption status

- **A1 (done)** — primary surfaces: `ContentView` + `DisasterModeView` color
  helpers and the `AccentColor` asset (→ harbor teal).
- **A2 (done)** — inherited screens migrated from the hardcoded bitchat
  green/black theme to `MinatoTheme`: AppInfoView, FingerprintView,
  VerificationViews, LocationChannelsSheet, LocationNotesView, SafetyHeaderView,
  EmergencyContactsSheet, ActivityLogSheet, DeliveryStatusView,
  CommandSuggestionsView, PaymentChipView, TextMessageView, GeohashPeopleList,
  MeshPeerList, MINATOOnboardingSheet, VoiceNoteView, WaveformView, and the
  remaining stray usages in ContentView/DisasterModeView. Canonical mapping:
  black/white screen → `background`; panel/row wash → `surface`; primary green
  text → `ink` / secondary → `inkSecondary`; decorative/brand/link/selection
  green → `accent`; success/verified/connected → `safe`; warning/unverified →
  `warn`; error/destructive/needsHelp/recording-active → `danger`; unread/
  attention → `beacon`. Trust-mode badge is a distinct autonomy ramp:
  `plan→safe`, `suggest→accent`, `auto→beacon`, `fullAuto→danger`.

### Intentionally NOT migrated (categorical, not the inherited theme)

These carry meaning the current `MinatoTheme` has no token for; left raw on
purpose (a future "categorical tokens" pass could add `MinatoTheme.nostr` /
`selfMark`):

- **`.purple` = Nostr / internet-relay reachability** (globe indicators,
  activity-log count badge). Distinguishes internet transport from local mesh.
- **`.orange` = "you" (self) identity highlight** (own nickname / suffix).
- **Media chrome** — full-screen photo backdrops, scrim overlays, and shadows in
  `ImagePreviewView` / `BlockRevealImageView` / `VoiceNoteView` use literal
  `Color.black`/`Color.white` by design (not theme surfaces).
- **`#Preview` scaffolding** — sample colors passed to previews are not shipped.

## Deferred (not in the foundation PR)

- **URL scheme** `bitchat://` → `minato://` — breaking (deep links + Nostr
  `bitchat1:` interop). Needs version negotiation; do as a deliberate step.
- **App icon / Assets** — redesign into a separate `Assets-MINATO.xcassets` to
  avoid upstream asset conflicts.
- **Localizable.xcstrings** — consider a MINATO sidecar `MINATO.xcstrings` for
  MINATO-specific strings to keep upstream-merge diffs small.
- **Categorical color tokens** — add `MinatoTheme.nostr` / `selfMark` so the
  purple (Nostr) and orange (self) indicators above can be themed too.
- **Disaster high-alert mode** — when disaster mode is active, shift the whole UI
  to `MinatoTheme.alertBackground` / `alertAccent`.
