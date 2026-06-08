import Testing
import Foundation
@testable import bitchat

@Suite("Emergency Override (E-4a)")
struct EmergencyOverrideTests {

    private let precise = Capability.safetyLocationPrecise.rawValue
    private let coarse = Capability.safetyLocationCoarse.rawValue

    private func override(expiresAt: UInt64?, caps: [String]) -> EmergencyOverride {
        EmergencyOverride(grantedAt: 1000, expiresAt: expiresAt, capabilities: caps)
    }

    private func settings(mode: TrustMode = .plan, override: EmergencyOverride? = nil) -> TrustSettings {
        TrustSettings(mode: mode, customPermissions: [:], establishedAt: 0, lastInteraction: 0, emergencyOverride: override)
    }

    // MARK: - EmergencyOverride

    @Test("isActive honors expiry and manual (nil) duration")
    func isActive() {
        #expect(override(expiresAt: 2000, caps: []).isActive(now: 1000))   // future
        #expect(override(expiresAt: 500, caps: []).isActive(now: 1000) == false) // past
        #expect(override(expiresAt: nil, caps: []).isActive(now: 1000))    // manual = active
    }

    @Test("grants requires active + capability present")
    func grants() {
        let active = override(expiresAt: 2000, caps: [precise])
        #expect(active.grants(precise, now: 1000))
        #expect(active.grants(coarse, now: 1000) == false)               // not granted
        let expired = override(expiresAt: 500, caps: [precise])
        #expect(expired.grants(precise, now: 1000) == false)            // expired
    }

    @Test("grants enforces safety.* scope even if a non-safety capability is stored")
    func grantsScopeEnforced() {
        // Defense in depth: a non-safety capability must never be granted,
        // even if it somehow ended up in the stored list.
        let tampered = override(expiresAt: 2000, caps: ["schedule.write", "message.initiate"])
        #expect(!tampered.grants("schedule.write", now: 1000))
        #expect(!tampered.grants("message.initiate", now: 1000))
    }

    // MARK: - Duration

    @Test("duration maps to seconds and expiry")
    func duration() {
        // Precompute Optional comparisons outside #expect — comparing Optional
        // operands directly inside the #expect macro crashes SILGen on the CI
        // toolchain (Swift 6.1). The Bool result is safe to pass to #expect.
        let sixHoursSecondsOK = EmergencyOverrideDuration.sixHours.seconds == 6 * 3600
        let daySecondsOK = EmergencyOverrideDuration.twentyFourHours.seconds == 24 * 3600
        let manualSecondsNil = EmergencyOverrideDuration.manual.seconds == nil
        let sixHoursExpiryOK = EmergencyOverrideDuration.sixHours.expiry(from: 1000) == 1000 + 6 * 3600
        let manualExpiryNil = EmergencyOverrideDuration.manual.expiry(from: 1000) == nil

        #expect(sixHoursSecondsOK)
        #expect(daySecondsOK)
        #expect(manualSecondsNil)
        #expect(sixHoursExpiryOK)
        #expect(manualExpiryNil)
        #expect(EmergencyOverrideDuration.default == .sixHours)
    }

    // MARK: - TrustSettings gating

    @Test("active override unlocks precise even in plan mode")
    func overrideUnlocksPrecise() {
        let s = settings(mode: .plan, override: override(expiresAt: 2000, caps: [precise]))
        #expect(s.isCapabilityAllowed(precise, now: 1000))
    }

    @Test("expired override does not unlock precise in plan mode")
    func expiredOverrideLocksPrecise() {
        let s = settings(mode: .plan, override: override(expiresAt: 500, caps: [precise]))
        #expect(s.isCapabilityAllowed(precise, now: 1000) == false)
    }

    @Test("coarse is allowed by default (not high-risk)")
    func coarseAllowedByDefault() {
        #expect(settings(mode: .plan).isCapabilityAllowed(coarse, now: 1000))
    }

    @Test("backward compatibility: legacy TrustSettings JSON without emergency_override decodes")
    func legacyDecodes() throws {
        let legacy = #"{"mode":"plan","custom_permissions":{},"established_at":1,"last_interaction":1}"#
        let decoded = try JSONDecoder().decode(TrustSettings.self, from: Data(legacy.utf8))
        let overrideIsNil = decoded.emergencyOverride == nil   // precompute (see duration())
        #expect(overrideIsNil)
        #expect(decoded.mode == .plan)
    }

    // MARK: - SafetyLocationPolicy

    @Test("allowedPrecision: unknown contact gets none")
    func precisionUnknown() {
        #expect(SafetyLocationPolicy.allowedPrecision(for: nil, now: 1000) == SafetyLocationPrecision.none)
    }

    @Test("allowedPrecision: known contact defaults to coarse")
    func precisionKnownCoarse() {
        #expect(SafetyLocationPolicy.allowedPrecision(for: settings(mode: .plan), now: 1000) == .coarse)
    }

    @Test("allowedPrecision: active precise override yields precise")
    func precisionOverridePrecise() {
        let s = settings(mode: .plan, override: override(expiresAt: 2000, caps: [precise]))
        #expect(SafetyLocationPolicy.allowedPrecision(for: s, now: 1000) == .precise)
    }

    @Test("allowedPrecision: high trust mode alone does NOT unlock precise")
    func precisionHighTrustStillCoarse() {
        // Even fullAuto, without an explicit emergency override, stays coarse.
        #expect(SafetyLocationPolicy.allowedPrecision(for: settings(mode: .fullAuto), now: 1000) == .coarse)
    }

    @Test("allowedPrecision: expired override falls back to coarse")
    func precisionExpiredCoarse() {
        let s = settings(mode: .plan, override: override(expiresAt: 500, caps: [precise]))
        #expect(SafetyLocationPolicy.allowedPrecision(for: s, now: 1000) == .coarse)
    }
}
