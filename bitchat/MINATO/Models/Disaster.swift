import Foundation

// MARK: - Disaster Status

/// Owner's safety status reported via `intent: "disaster.safety"`.
/// Four levels deliberately chosen so the picker UI stays a 2x2 grid
/// readable at a glance in a high-stress moment.
enum DisasterStatus: String, CaseIterable, Codable {
    case ok        = "ok"          // 🟢 無事
    case injured   = "injured"     // 🟡 軽傷
    case needsHelp = "needs_help"  // 🔴 要救助
    case unknown   = "unknown"     // ❓ 不明 (default until owner updates)
}

// MARK: - Battery State

/// Mirror of `UIDevice.BatteryState`. We keep our own enum so the model
/// stays UIKit-free for testability and so the wire string is stable
/// even if Apple's enum changes.
enum BatteryState: String, CaseIterable, Codable {
    case charging    = "charging"
    case discharging = "discharging"
    case full        = "full"
    case unknown     = "unknown"
}

// MARK: - Disaster Safety Payload

/// Structured payload for `intent: "disaster.safety"`. Carried inside
/// `PayloadContent.context` as a `[String: AnyCodableValue]` dictionary
/// on the wire — `toContext()` / `from(context:)` handle that round-trip.
///
/// Required fields: `status`, `battery_pct`, `battery_state`.
/// Optional: `location_hint`, `last_active_at`.
///
/// See: docs/disaster-mode.md §プロトコル拡張
struct DisasterSafetyPayload: Equatable {
    /// Intent string this payload is bound to.
    static let intent = Intent.disasterSafety.rawValue

    /// Owner's chosen safety level.
    let status: DisasterStatus

    /// Battery percentage at sample time. iOS reports in 5% increments;
    /// values outside 0–100 are clamped on construction.
    let batteryPct: Int

    /// Whether the device is currently charging.
    let batteryState: BatteryState

    /// Rounded place name in peacetime ("東京駅周辺"), GPS-derived hint
    /// in disaster mode. `nil` when the owner has not granted location or
    /// no fix is available.
    let locationHint: String?

    /// Unix timestamp of the last owner-driven foreground interaction.
    /// Lets receivers distinguish "owner is alive and actively using the
    /// phone" from "agent has been auto-broadcasting unattended".
    let lastActiveAt: UInt64?

    init(
        status: DisasterStatus,
        batteryPct: Int,
        batteryState: BatteryState,
        locationHint: String? = nil,
        lastActiveAt: UInt64? = nil
    ) {
        self.status = status
        self.batteryPct = max(0, min(100, batteryPct))
        self.batteryState = batteryState
        self.locationHint = locationHint
        self.lastActiveAt = lastActiveAt
    }
}

// MARK: - Context Round-Trip

extension DisasterSafetyPayload {
    /// Serialises the payload into the `[String: AnyCodableValue]` shape
    /// expected by `PayloadContent.context`. Optional fields are omitted
    /// (not encoded as `null`) so the wire form stays compact.
    func toContext() -> [String: AnyCodableValue] {
        var ctx: [String: AnyCodableValue] = [
            "status": .string(status.rawValue),
            "battery_pct": .int(batteryPct),
            "battery_state": .string(batteryState.rawValue)
        ]
        if let locationHint = locationHint {
            ctx["location_hint"] = .string(locationHint)
        }
        if let lastActiveAt = lastActiveAt {
            // Unix timestamps fit easily in `Int` on every platform we target.
            ctx["last_active_at"] = .int(Int(lastActiveAt))
        }
        return ctx
    }

    /// Reconstructs a payload from an inbound `PayloadContent.context`.
    /// Returns `nil` if any required field is missing or carries an
    /// unrecognised enum value — callers should treat that as "ignore
    /// this packet" rather than guessing defaults.
    static func from(context: [String: AnyCodableValue]?) -> DisasterSafetyPayload? {
        guard let context = context else { return nil }

        guard case .string(let statusRaw) = context["status"],
              let status = DisasterStatus(rawValue: statusRaw)
        else { return nil }

        guard case .int(let battery) = context["battery_pct"] else { return nil }

        guard case .string(let stateRaw) = context["battery_state"],
              let state = BatteryState(rawValue: stateRaw)
        else { return nil }

        let locationHint: String? = {
            if case .string(let v) = context["location_hint"] { return v }
            return nil
        }()

        let lastActiveAt: UInt64? = {
            if case .int(let v) = context["last_active_at"], v >= 0 {
                return UInt64(v)
            }
            return nil
        }()

        return DisasterSafetyPayload(
            status: status,
            batteryPct: battery,
            batteryState: state,
            locationHint: locationHint,
            lastActiveAt: lastActiveAt
        )
    }
}
