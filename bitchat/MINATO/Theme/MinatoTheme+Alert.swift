import SwiftUI

/// Disaster high-alert plumbing for the MINATO harbor theme.
///
/// When disaster mode is active the whole UI shifts to the high-alert palette:
///   1. surfaces/ink flip via the `alert:` flag on `MinatoTheme` accessors, and
///   2. a persistent danger frame + an environment flag (`\.minatoAlert`) let
///      child views and sheets pick up the alert state without each one having
///      to observe `SafetyModeStore`.
///
/// The owner of the state (`ContentView`) injects the flag from
/// `SafetyModeStore.shared.isActive` and applies `.minatoHighAlert(_:)` on its
/// root; descendants just read `@Environment(\.minatoAlert)`.

// MARK: - Environment flag

private struct MinatoAlertKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while disaster (high-alert) mode is active. Default: false.
    var minatoAlert: Bool {
        get { self[MinatoAlertKey.self] }
        set { self[MinatoAlertKey.self] = newValue }
    }
}

// MARK: - High-alert framing modifier

/// Frames the whole screen with a danger-red border while disaster mode is
/// active — an unmistakable "you are in emergency mode" cue that does not fight
/// readability of the content underneath. Also publishes `\.minatoAlert` so
/// descendants (and presented sheets) inherit the alert state.
private struct MinatoHighAlertModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.minatoAlert, active)
            .overlay {
                if active {
                    Rectangle()
                        .strokeBorder(MinatoTheme.danger, lineWidth: 3)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    /// Apply the disaster high-alert frame + publish `\.minatoAlert` when
    /// `active` is true. No-op chrome when false.
    func minatoHighAlert(_ active: Bool) -> some View {
        modifier(MinatoHighAlertModifier(active: active))
    }
}
