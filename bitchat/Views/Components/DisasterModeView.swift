import SwiftUI

/// Full-screen disaster-mode dashboard. Renders the owner's current safety
/// check-in (status, battery, relay metadata, needs) and lets them switch
/// status. State is owned by `SafetyModeStore`; this view is a pure surface.
///
/// Scope (D-3): local preview only. MINATO payload encoding + BLE mesh send
/// land in Phase 2 (E-2/E-3).
struct DisasterModeView: View {
    @ObservedObject var store: SafetyModeStore
    @ObservedObject private var inbox = SafetyCheckinStore.shared
    let onDismiss: () -> Void
    /// Called with the current check-in whenever the owner changes status, so the
    /// caller can broadcast it to the mesh.
    var onBroadcast: (SafetyCheckin) -> Void = { _ in }
    /// Called when the owner ends disaster mode, so the caller can stop the
    /// periodic re-broadcast and deactivate.
    var onDeactivate: () -> Void = {}

    @EnvironmentObject private var viewModel: ChatViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showEmergencyContacts = false

    private var checkin: SafetyCheckin { store.checkin }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusCard
                    primaryActions
                    nearbyInformation
                    policyNote
                    if store.isActive {
                        emergencyContactsButton
                        deactivateButton
                    }
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
        .sheet(isPresented: $showEmergencyContacts) {
            EmergencyContactsSheet(onClose: { showEmergencyContacts = false })
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
            Text("周辺の安否")
                .font(.bitchatSystem(size: 14, weight: .semibold, design: .monospaced))

            let items = inbox.activeCheckins()
            if items.isEmpty {
                Text("まだ周辺の安否情報は受信していません。")
                    .font(.bitchatSystem(size: 12, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(items) { item in
                    receivedRow(item)
                }
            }
        }
        .padding(12)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func receivedRow(_ item: SafetyCheckinStore.Received) -> some View {
        let entry = item.checkin
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: entry.status == .needsHelp ? "exclamationmark.triangle.fill" : "person.fill")
                    .foregroundColor(entry.status == .needsHelp ? .red : .green)
                    .font(.system(size: 12))
                Text(entry.status.displayNameJA)
                    .font(.bitchatSystem(size: 13, weight: .semibold, design: .monospaced))
                Spacer()
                Text(deliveryLabel(item))
                    .font(.bitchatSystem(size: 11, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
            }
            Text(entry.content)
                .font(.bitchatSystem(size: 11, design: .monospaced))
                .foregroundColor(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.needs.isEmpty {
                Text("必要: \(entry.needs.map(\.displayNameJA).joined(separator: " / "))")
                    .font(.bitchatSystem(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func deliveryLabel(_ item: SafetyCheckinStore.Received) -> String {
        switch item.deliveredVia {
        case .direct: return "直接"
        case .mesh: return "メッシュ \(item.hops) hops"
        case .nostr: return "Nostr 経由"
        case .unknown: return "不明"
        }
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

    private var emergencyContactsButton: some View {
        Button {
            showEmergencyContacts = true
        } label: {
            Label("緊急連絡先を管理", systemImage: "person.2.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private var deactivateButton: some View {
        Button(role: .destructive) {
            onDeactivate()
        } label: {
            Label("災害モードを終了", systemImage: "stop.circle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    private func actionButton(status: SafetyStatus, icon: String) -> some View {
        Button {
            store.setStatus(status)
            onBroadcast(store.checkin)
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
