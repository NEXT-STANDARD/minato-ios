import Foundation

/// Single source of truth for MINATO brand identity.
///
/// Keep every user-visible brand string referencing this so a rebrand is one
/// edit, and so upstream (bitchat) merges that touch shared files (Info.plist,
/// LaunchScreen) can be re-applied from one checklist. See CLAUDE.md "Branding".
///
/// 港 (minato) = harbor: a safe haven in disaster, and the port where agents
/// connect. That metaphor drives the name, tagline, and theme.
enum MinatoBrand {
    /// Product display name (home screen, About, share sheet).
    static let displayName = "MINATO"

    /// Title shown in the main chat header.
    static let headerTitle = "MINATO"

    /// Short tagline.
    static let tagline = "圏外でもつながる、安全な港。"

    // MARK: - URL scheme migration (bitchat -> minato)
    //
    // Phase 1 (current): accept BOTH schemes everywhere (backward compatible);
    // emit `minato://` for in-app deep links (user / geohash / share / notifications);
    // keep emitting the LEGACY scheme for cross-client formats (QR verify, Nostr
    // embed) so existing bitchat / older-MINATO installs still interop. The wire
    // formats flip to minato in a later phase once adoption catches up.
    // See docs/MINATO-url-scheme.md.

    /// Primary deep-link scheme — emitted for in-app links (user/geohash/share/notifications).
    static let urlScheme = "minato"

    /// Legacy scheme — still accepted, and still EMITTED for cross-client formats
    /// (QR verify) to preserve interop with existing installs.
    static let legacyURLScheme = "bitchat"

    /// Every scheme accepted on inbound deep links / QR. Order = preference.
    static let acceptedURLSchemes = ["minato", "bitchat"]

    /// Prefix EMITTED on outbound Nostr embedded packets. Kept as the legacy value
    /// for network interop (changing it is a protocol-level decision; see docs).
    static let nostrEmbedPrefix = "bitchat1:"

    /// Prefixes accepted on inbound Nostr embedded packets (forward-compatible).
    static let acceptedNostrEmbedPrefixes = ["bitchat1:", "minato1:"]

    /// True if `scheme` is one we accept on inbound deep links (case-insensitive).
    static func acceptsURLScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return acceptedURLSchemes.contains(scheme)
    }

    /// Returns the matching accepted Nostr embed prefix for `content`, or nil.
    static func nostrEmbedPrefix(matching content: String) -> String? {
        acceptedNostrEmbedPrefixes.first(where: { content.hasPrefix($0) })
    }
}
