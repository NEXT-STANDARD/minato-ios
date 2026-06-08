import SwiftUI

/// MINATO "harbor (港)" visual theme.
///
/// Peacetime: calm deep-navy / off-white (生成り) with a teal "sea" accent and an
/// amber "beacon (灯台)" highlight. Disaster mode shifts to a high-alert palette.
/// Explicit safety semantics (safe/warn/danger) are shared across both.
///
/// colorScheme-aware and cross-platform (no UIKit). This is the single place to
/// tune the palette; adoption across screens is incremental (PR1 only defines it).
enum MinatoTheme {

    // MARK: - Surfaces (peacetime ⇄ disaster high-alert)
    //
    // Every surface/ink accessor takes an `alert` flag (default false). When
    // disaster mode is active the whole UI passes `alert: true` so the calm
    // harbor palette flips to the high-alert (red/amber) palette in one place.
    // See MinatoTheme+Alert.swift for the `\.minatoAlert` environment + the
    // `.minatoHighAlert(_:)` framing modifier.

    static func background(_ scheme: ColorScheme, alert: Bool = false) -> Color {
        if alert { return alertBackground(scheme) }
        return scheme == .dark
            ? Color(red: 0.04, green: 0.06, blue: 0.11)   // 深い紺（夜の海）
            : Color(red: 0.96, green: 0.95, blue: 0.91)   // 生成り
    }

    static func surface(_ scheme: ColorScheme, alert: Bool = false) -> Color {
        if alert { return danger.opacity(scheme == .dark ? 0.16 : 0.08) }
        return scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    // MARK: - Ink (text)

    static func ink(_ scheme: ColorScheme, alert: Bool = false) -> Color {
        if alert {
            // Warm, high-contrast ink so copy stays readable on the red wash.
            return scheme == .dark
                ? Color(red: 0.99, green: 0.93, blue: 0.92)
                : Color(red: 0.34, green: 0.09, blue: 0.10)
        }
        return scheme == .dark
            ? Color(red: 0.90, green: 0.92, blue: 0.96)   // 明るい生成り寄り
            : Color(red: 0.11, green: 0.16, blue: 0.29)   // 藍/紺
    }

    static func inkSecondary(_ scheme: ColorScheme, alert: Bool = false) -> Color {
        ink(scheme, alert: alert).opacity(0.7)
    }

    // MARK: - Accents

    /// Primary accent — teal "sea".
    static let accent = Color(red: 0.16, green: 0.55, blue: 0.60)
    /// Beacon (灯台) highlight — warm amber.
    static let beacon = Color(red: 0.88, green: 0.57, blue: 0.18)

    /// Interactive tint resolved for the current mode: teal in peacetime,
    /// danger red in disaster high-alert. Use for primary chrome that should
    /// read as "emergency" when disaster mode is active.
    static func tint(alert: Bool = false) -> Color { alert ? alertAccent : accent }

    // MARK: - Safety semantics (shared peacetime/disaster)

    static let safe   = Color(red: 0.25, green: 0.71, blue: 0.42)
    static let warn   = Color(red: 0.88, green: 0.57, blue: 0.18)
    static let danger = Color(red: 0.90, green: 0.28, blue: 0.30)

    // MARK: - Disaster high-alert

    static func alertBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.18, green: 0.04, blue: 0.05)
            : Color(red: 0.99, green: 0.93, blue: 0.90)
    }
    static let alertAccent = danger
}
