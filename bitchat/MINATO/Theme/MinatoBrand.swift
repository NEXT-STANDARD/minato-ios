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

    /// Deep-link URL scheme. NOTE: still "bitchat" — migrating to "minato"
    /// is a separate, breaking step (deep links + Nostr interop) handled later.
    static let urlScheme = "bitchat"
}
