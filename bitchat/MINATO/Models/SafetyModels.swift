import Foundation

// MARK: - Disaster Mode Safety Models

// Safety intents and capabilities live in the central `Intent` / `Capability`
// enums (see Capability.swift) so they participate in Agent Card advertisement
// and high-risk gating. e.g. `Intent.safetyCheckin`, `Capability.safetyLocationPrecise`.

enum SafetyStatus: String, Codable, CaseIterable, Equatable, Identifiable {
    case safe
    case injured
    case needsHelp = "needs_help"
    case evacuating
    case searching
    case unknown

    var id: String { rawValue }

    var displayNameJA: String {
        switch self {
        case .safe: return "無事です"
        case .injured: return "けがあり"
        case .needsHelp: return "助けが必要"
        case .evacuating: return "避難中"
        case .searching: return "家族を探しています"
        case .unknown: return "状況不明"
        }
    }

    var defaultContentJA: String {
        switch self {
        case .safe: return "無事です。安全な場所へ移動しています。"
        case .injured: return "けががあります。状況を確認しています。"
        case .needsHelp: return "助けが必要です。近くの人に知らせてください。"
        case .evacuating: return "避難中です。移動できる状態です。"
        case .searching: return "家族または信頼先を探しています。"
        case .unknown: return "状況はまだ確認できていません。"
        }
    }
}

enum SafetyNeed: String, Codable, CaseIterable, Equatable, Identifiable {
    case water
    case food
    case medical
    case charging
    case shelter
    case transport
    case rescue

    var id: String { rawValue }

    var displayNameJA: String {
        switch self {
        case .water: return "水"
        case .food: return "食料"
        case .medical: return "医療"
        case .charging: return "充電"
        case .shelter: return "避難場所"
        case .transport: return "移動手段"
        case .rescue: return "救助"
        }
    }
}

enum SafetyBatteryState: String, Codable, Equatable {
    case charging
    case unplugged
    case full
    case unknown
}

enum SafetyContactWindow: String, Codable, Equatable {
    case short
    case medium
    case long
    case unknown

    var displayNameJA: String {
        switch self {
        case .short: return "残りわずか"
        case .medium: return "要注意"
        case .long: return "余裕あり"
        case .unknown: return "不明"
        }
    }
}

struct SafetyBatterySnapshot: Codable, Equatable {
    let level: Double?
    let state: SafetyBatteryState
    let lowPowerMode: Bool
    let reportedAt: UInt64
    let contactWindow: SafetyContactWindow

    enum CodingKeys: String, CodingKey {
        case level, state
        case lowPowerMode = "low_power_mode"
        case reportedAt = "reported_at"
        case contactWindow = "contact_window"
    }

    init(
        level: Double?,
        state: SafetyBatteryState,
        lowPowerMode: Bool,
        reportedAt: UInt64,
        contactWindow: SafetyContactWindow? = nil
    ) {
        self.level = level.map { min(max($0, 0.0), 1.0) }
        self.state = state
        self.lowPowerMode = lowPowerMode
        self.reportedAt = reportedAt
        self.contactWindow = contactWindow ?? Self.deriveContactWindow(
            level: self.level,
            state: state
        )
    }

    static func deriveContactWindow(level: Double?, state: SafetyBatteryState) -> SafetyContactWindow {
        switch state {
        case .charging, .full:
            return .long
        case .unknown:
            return .unknown
        case .unplugged:
            guard let level else { return .unknown }
            if level < 0.15 { return .short }
            if level < 0.40 { return .medium }
            return .long
        }
    }

    var percentageText: String {
        guard let level else { return "電池: 不明" }
        return "電池: \(Int((level * 100).rounded()))%"
    }
}

enum SafetyLocationPrecision: String, Codable, Equatable {
    case none
    case coarse
    case precise
}

struct SafetyLocation: Codable, Equatable {
    let precision: SafetyLocationPrecision
    let geohash: String?
    let latitude: Double?
    let longitude: Double?
    let label: String?

    static let undisclosed = SafetyLocation(
        precision: .none,
        geohash: nil,
        latitude: nil,
        longitude: nil,
        label: nil
    )
}

enum SafetyRelayDelivery: String, Codable, Equatable {
    case direct
    case mesh
    case nostr
    case unknown
}

struct SafetyRelayMetadata: Codable, Equatable {
    let delivery: SafetyRelayDelivery
    let hops: Int?
    let direct: Bool
    let lastSeenAt: UInt64
    let relaySeenAt: UInt64?

    enum CodingKeys: String, CodingKey {
        case delivery, hops, direct
        case lastSeenAt = "last_seen_at"
        case relaySeenAt = "relay_seen_at"
    }
}

struct SafetyCheckin: Codable, Equatable, Identifiable {
    let id: String
    let status: SafetyStatus
    let content: String
    let battery: SafetyBatterySnapshot
    let location: SafetyLocation
    let relay: SafetyRelayMetadata
    let needs: [SafetyNeed]
    let expiresAt: UInt64

    enum CodingKeys: String, CodingKey {
        case id, status, content, battery, location, relay, needs
        case expiresAt = "expires_at"
    }

    static func makeLocalPreview(
        status: SafetyStatus,
        battery: SafetyBatterySnapshot,
        location: SafetyLocation = .undisclosed,
        now: Date = Date()
    ) -> SafetyCheckin {
        let timestamp = UInt64(now.timeIntervalSince1970)
        let needs: [SafetyNeed] = status == .needsHelp ? [.water, .medical, .charging] : []
        return SafetyCheckin(
            id: UUID().uuidString,
            status: status,
            content: status.defaultContentJA,
            battery: battery,
            location: location,
            relay: SafetyRelayMetadata(
                delivery: .direct,
                hops: nil,
                direct: true,
                lastSeenAt: timestamp,
                relaySeenAt: nil
            ),
            needs: needs,
            expiresAt: timestamp + 3600
        )
    }

    /// Returns a copy of this check-in with a different location (same id /
    /// status / battery / expiry). Used to attach precise location for a
    /// directed, encrypted send while the broadcast copy stays coarse.
    func withLocation(_ location: SafetyLocation) -> SafetyCheckin {
        SafetyCheckin(
            id: id,
            status: status,
            content: content,
            battery: battery,
            location: location,
            relay: relay,
            needs: needs,
            expiresAt: expiresAt
        )
    }
}
