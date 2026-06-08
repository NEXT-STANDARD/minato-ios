import Foundation
import Testing
@testable import bitchat

@Suite("MINATO Safety Payload Tests")
struct SafetyPayloadTests {
    @Test("Battery contact window derives from level and charging state")
    func batteryContactWindowDerivation() {
        #expect(SafetyBatterySnapshot.deriveContactWindow(level: 0.10, state: .unplugged) == .short)
        #expect(SafetyBatterySnapshot.deriveContactWindow(level: 0.25, state: .unplugged) == .medium)
        #expect(SafetyBatterySnapshot.deriveContactWindow(level: 0.80, state: .unplugged) == .long)
        #expect(SafetyBatterySnapshot.deriveContactWindow(level: 0.05, state: .charging) == .long)
        #expect(SafetyBatterySnapshot.deriveContactWindow(level: nil, state: .unknown) == .unknown)
    }

    @Test("Safety check-in encodes snake_case fields")
    func safetyCheckinEncodingUsesProtocolKeys() throws {
        let battery = SafetyBatterySnapshot(
            level: 0.12,
            state: .unplugged,
            lowPowerMode: true,
            reportedAt: 1_778_499_480
        )
        let checkin = SafetyCheckin(
            id: "safety-001",
            status: .needsHelp,
            content: "助けが必要です。",
            battery: battery,
            location: SafetyLocation(
                precision: .coarse,
                geohash: "xn76u",
                latitude: nil,
                longitude: nil,
                label: "渋谷区周辺"
            ),
            relay: SafetyRelayMetadata(
                delivery: .mesh,
                hops: 3,
                direct: false,
                lastSeenAt: 1_778_499_480,
                relaySeenAt: 1_778_499_540
            ),
            needs: [.water, .medical, .charging],
            expiresAt: 1_778_503_080
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(checkin)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"low_power_mode\":true"))
        #expect(json.contains("\"reported_at\":1778499480"))
        #expect(json.contains("\"contact_window\":\"short\""))
        #expect(json.contains("\"last_seen_at\":1778499480"))
        #expect(json.contains("\"relay_seen_at\":1778499540"))
        #expect(json.contains("\"expires_at\":1778503080"))

        let decoded = try JSONDecoder().decode(SafetyCheckin.self, from: data)
        #expect(decoded == checkin)
    }

    @Test("Local preview includes urgent needs for help requests")
    func localPreviewDefaults() {
        let battery = SafetyBatterySnapshot(
            level: 0.06,
            state: .unplugged,
            lowPowerMode: true,
            reportedAt: 1_778_499_480
        )
        let preview = SafetyCheckin.makeLocalPreview(
            status: .needsHelp,
            battery: battery,
            now: Date(timeIntervalSince1970: 1_778_499_480)
        )

        #expect(preview.status == .needsHelp)
        #expect(preview.needs == [.water, .medical, .charging])
        #expect(preview.location.precision == .none)
        #expect(preview.relay.direct)
        #expect(preview.expiresAt == 1_778_503_080)
    }
}
