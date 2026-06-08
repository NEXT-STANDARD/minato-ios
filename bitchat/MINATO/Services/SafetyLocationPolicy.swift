import Foundation

/// Decides the location precision a given recipient is allowed to receive in a
/// safety check-in. Deliberately stricter than `TrustSettings.isCapabilityAllowed`:
/// precise location requires an **active emergency override** that explicitly
/// grants it — a high trust mode alone does not unlock precise location (a
/// safeguard against domestic-violence / stalking misuse). Pure and testable.
///
/// Scope (E-4a): the gate. Actually producing coarse/precise coordinates from
/// CoreLocation is E-4b — until then check-ins remain `.undisclosed`.
///
/// See: docs/MINATO-disaster-mode.md
enum SafetyLocationPolicy {
    /// Highest location precision permitted for a recipient with the given
    /// trust settings (`nil` for an unknown contact).
    static func allowedPrecision(
        for settings: TrustSettings?,
        now: UInt64 = UInt64(Date().timeIntervalSince1970)
    ) -> SafetyLocationPrecision {
        guard let settings else { return .none }
        if let override = settings.emergencyOverride,
           override.grants(Capability.safetyLocationPrecise.rawValue, now: now) {
            return .precise
        }
        // Coarse is the default for any known contact; broadcasts to the open
        // mesh should also use coarse (callers pass nil for unknown recipients).
        return .coarse
    }
}
