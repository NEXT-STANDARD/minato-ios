import SwiftUI

/// Full-screen disaster-mode dashboard. Renders the owner's current safety
/// check-in (status, battery, relay metadata, needs) and lets them switch
/// status. State is owned by `SafetyModeStore`; this view is a pure surface.
///
/// Scope (D-3): local preview only. MINATO payload encoding + BLE mesh send
/// land in Phase 2 (E-2/E-3).
struct DisasterModeView: View {
    @ObservedObject var store: SafetyModeStore
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var checkin: SafetyCheckin { store.checkin }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusCard
                    primaryActions
                    nearbyInformation
                    policyNote
                }
                .padding(18)
            }
            .background(backgroundColor)
            .foregroundColor(textColor)
            .navigationTitle("災害モード")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { onDismiss() }
                }
            }
        }
        .onAppear {
            store.refresh()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(checkin.status.displayNameJA)
                        .font(.bitchatSystem(size: 20, weight: .bold, design: .monospaced))
                    Text(checkin.content)
                        .font(.bitchatSystem(size: 13, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
                Spacer()
                Image(systemName: checkin.status == .needsHelp ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(checkin.status == .needsHelp ? .red : .green)
            }

            Divider()

            infoRow(icon: "clock", label: "最終更新", value: formattedTime(checkin.relay.lastSeenAt))
            infoRow(icon: "location", label: "場所", value: checkin.location.label ?? locationFallbackText)
            infoRow(icon: batteryIcon, label: "電池", value: batterySummary)
            infoRow(icon: "antenna.radiowaves.left.and.right", label: "通信", value: relaySummary)

            if !checkin.needs.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "cross.case.fill")
                        .foregroundColor(.red)
                        .frame(width: 20)
                    Text("必要: \(checkin.needs.map(\.displayNameJA).joined(separator: " / "))")
                        .font(.bitchatSystem(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(14)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var primaryActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                actionButton(status: .safe, icon: "checkmark.circle.fill")
                actionButton(status: .needsHelp, icon: "exclamationmark.triangle.fill")
            }
            HStack(spacing: 10) {
                actionButton(status: .searching, icon: "person.crop.circle.badge.questionmark")
                Button(action: {}) {
                    Label("近くの情報を見る", systemImage: "map.fill")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
        }
    }

    private var nearbyInformation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("初期実装")
                .font(.bitchatSystem(size: 14, weight: .semibold, design: .monospaced))
            Text("この画面はローカルの安否カードとバッテリー snapshot を表示します。次の段階で MINATO payload 化、BLE mesh 送信、relay metadata を接続します。")
                .font(.bitchatSystem(size: 12, design: .monospaced))
                .foregroundColor(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var policyNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("位置情報は粗く共有", systemImage: "location.slash")
                .font(.bitchatSystem(size: 13, weight: .semibold, design: .monospaced))
            Text("精密な位置情報は high-risk として扱い、明示確認または期限付き emergency override がある場合だけ共有します。")
                .font(.bitchatSystem(size: 12, design: .monospaced))
                .foregroundColor(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionButton(status: SafetyStatus, icon: String) -> some View {
        Button {
            store.setStatus(status)
        } label: {
            Label(status.displayNameJA, systemImage: icon)
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.borderedProminent)
        .tint(status == .needsHelp ? .red : .green)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.bitchatSystem(size: 12, design: .monospaced))
                .foregroundColor(secondaryTextColor)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.bitchatSystem(size: 13, weight: .semibold, design: .monospaced))
            Spacer(minLength: 0)
        }
    }

    private var batterySummary: String {
        var parts = [checkin.battery.percentageText.replacingOccurrences(of: "電池: ", with: "")]
        if checkin.battery.lowPowerMode {
            parts.append("低電力モード")
        }
        parts.append(checkin.battery.contactWindow.displayNameJA)
        return parts.joined(separator: " ")
    }

    private var batteryIcon: String {
        switch checkin.battery.contactWindow {
        case .short: return "battery.25"
        case .medium: return "battery.50"
        case .long: return "battery.100"
        case .unknown: return "battery.0"
        }
    }

    private var relaySummary: String {
        switch checkin.relay.delivery {
        case .direct: return "直接"
        case .mesh: return "メッシュ経由 \(checkin.relay.hops ?? 0) hops"
        case .nostr: return "Nostr 経由"
        case .unknown: return "不明"
        }
    }

    private var locationFallbackText: String {
        switch checkin.location.precision {
        case .none: return "未共有"
        case .coarse: return checkin.location.geohash.map { "#\($0)" } ?? "周辺のみ"
        case .precise: return "精密位置"
        }
    }

    private func formattedTime(_ timestamp: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var textColor: Color {
        colorScheme == .dark ? .green : Color(red: 0, green: 0.5, blue: 0)
    }

    private var secondaryTextColor: Color {
        textColor.opacity(0.75)
    }

    private var panelBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }
}
