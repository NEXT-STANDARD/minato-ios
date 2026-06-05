import Foundation
import Testing
@testable import bitchat

// MARK: - DisasterSafetyPayload Tests

@Suite("DisasterSafetyPayload Tests")
struct DisasterSafetyPayloadTests {

    // MARK: - Round-trip

    @Test("encode then decode preserves every field",
          arguments: DisasterStatus.allCases)
    func roundTripPreservesAllFields(status: DisasterStatus) throws {
        let original = DisasterSafetyPayload(
            status: status,
            batteryPct: 23,
            batteryState: .charging,
            locationHint: "東京駅周辺",
            lastActiveAt: 1715000000
        )
        let ctx = original.toContext()
        let decoded = try #require(DisasterSafetyPayload.from(context: ctx))
        #expect(decoded == original)
    }

    @Test("round-trip works with optional fields omitted")
    func roundTripWorksWithOptionalsOmitted() throws {
        let original = DisasterSafetyPayload(
            status: .ok,
            batteryPct: 80,
            batteryState: .discharging
        )
        let ctx = original.toContext()
        // Optional keys must not appear in the encoded form.
        #expect(ctx["location_hint"] == nil)
        #expect(ctx["last_active_at"] == nil)

        let decoded = try #require(DisasterSafetyPayload.from(context: ctx))
        #expect(decoded == original)
        #expect(decoded.locationHint == nil)
        #expect(decoded.lastActiveAt == nil)
    }

    // MARK: - Battery clamping

    @Test("battery percentage is clamped to 0...100",
          arguments: [(-25, 0), (-1, 0), (0, 0), (50, 50), (100, 100), (101, 100), (250, 100)])
    func batteryIsClamped(input: Int, expected: Int) {
        let payload = DisasterSafetyPayload(
            status: .ok,
            batteryPct: input,
            batteryState: .full
        )
        #expect(payload.batteryPct == expected)
    }

    // MARK: - Decode rejects missing required fields

    @Test("decode returns nil when context is nil")
    func decodeRejectsNilContext() {
        #expect(DisasterSafetyPayload.from(context: nil) == nil)
    }

    @Test("decode returns nil when `status` is missing")
    func decodeRejectsMissingStatus() {
        let ctx: [String: AnyCodableValue] = [
            "battery_pct": .int(50),
            "battery_state": .string("charging")
        ]
        #expect(DisasterSafetyPayload.from(context: ctx) == nil)
    }

    @Test("decode returns nil when `battery_pct` is missing")
    func decodeRejectsMissingBatteryPct() {
        let ctx: [String: AnyCodableValue] = [
            "status": .string("ok"),
            "battery_state": .string("charging")
        ]
        #expect(DisasterSafetyPayload.from(context: ctx) == nil)
    }

    @Test("decode returns nil when `battery_state` is missing")
    func decodeRejectsMissingBatteryState() {
        let ctx: [String: AnyCodableValue] = [
            "status": .string("ok"),
            "battery_pct": .int(50)
        ]
        #expect(DisasterSafetyPayload.from(context: ctx) == nil)
    }

    // MARK: - Decode rejects bad enum values

    @Test("decode returns nil for an unrecognised status string")
    func decodeRejectsUnknownStatus() {
        let ctx: [String: AnyCodableValue] = [
            "status": .string("dead"),
            "battery_pct": .int(50),
            "battery_state": .string("charging")
        ]
        #expect(DisasterSafetyPayload.from(context: ctx) == nil)
    }

    @Test("decode returns nil for an unrecognised battery_state string")
    func decodeRejectsUnknownBatteryState() {
        let ctx: [String: AnyCodableValue] = [
            "status": .string("ok"),
            "battery_pct": .int(50),
            "battery_state": .string("plugged_in_kinda")
        ]
        #expect(DisasterSafetyPayload.from(context: ctx) == nil)
    }

    @Test("decode returns nil when battery_pct is not an int")
    func decodeRejectsBatteryPctOfWrongType() {
        let ctx: [String: AnyCodableValue] = [
            "status": .string("ok"),
            "battery_pct": .string("fifty"),
            "battery_state": .string("charging")
        ]
        #expect(DisasterSafetyPayload.from(context: ctx) == nil)
    }

    // MARK: - Optional field handling

    @Test("decode tolerates location_hint of wrong type by leaving it nil")
    func decodeIgnoresInvalidLocationHint() throws {
        let ctx: [String: AnyCodableValue] = [
            "status": .string("ok"),
            "battery_pct": .int(50),
            "battery_state": .string("full"),
            "location_hint": .int(42)  // wrong type, treat as absent
        ]
        let decoded = try #require(DisasterSafetyPayload.from(context: ctx))
        #expect(decoded.locationHint == nil)
    }

    @Test("decode drops a negative last_active_at rather than crashing")
    func decodeRejectsNegativeTimestamp() throws {
        let ctx: [String: AnyCodableValue] = [
            "status": .string("ok"),
            "battery_pct": .int(50),
            "battery_state": .string("full"),
            "last_active_at": .int(-1)
        ]
        let decoded = try #require(DisasterSafetyPayload.from(context: ctx))
        #expect(decoded.lastActiveAt == nil)
    }

    // MARK: - Wire constants

    @Test("intent constant is bound to Intent.disasterSafety")
    func intentConstantMatchesEnum() {
        #expect(DisasterSafetyPayload.intent == "disaster.safety")
        #expect(DisasterSafetyPayload.intent == Intent.disasterSafety.rawValue)
    }

    @Test("DisasterStatus raw values match the wire contract")
    func statusRawValues() {
        #expect(DisasterStatus.ok.rawValue == "ok")
        #expect(DisasterStatus.injured.rawValue == "injured")
        #expect(DisasterStatus.needsHelp.rawValue == "needs_help")
        #expect(DisasterStatus.unknown.rawValue == "unknown")
    }

    @Test("BatteryState raw values match the wire contract")
    func batteryStateRawValues() {
        #expect(BatteryState.charging.rawValue == "charging")
        #expect(BatteryState.discharging.rawValue == "discharging")
        #expect(BatteryState.full.rawValue == "full")
        #expect(BatteryState.unknown.rawValue == "unknown")
    }

    // MARK: - Capability classification

    @Test("disaster.share_safety is high-risk and not granted by default")
    func disasterCapabilityClassification() {
        #expect(Capability.highRisk.contains(.disasterShareSafety))
        #expect(!Capability.defaults.contains(.disasterShareSafety))
        #expect(Capability.isHighRisk("disaster.share_safety"))
    }
}
