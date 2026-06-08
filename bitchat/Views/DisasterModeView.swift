import SwiftUI

/// On-state disaster screen presented over `ContentView` once the owner
/// activates disaster mode. D-3 surfaces the active state and provides a
/// deactivate path; the status picker (F3), family list (F3.5), and the
/// outbound broadcast loop land in later phases per docs/disaster-mode.md.
struct DisasterModeView: View {
    @ObservedObject var store: DisasterModeStore

    /// Fired when the owner taps "閉じる" or "災害モードを終了".
    let onDismiss: () -> Void

    /// Confirmation prompt for the destructive "終了" action — keeps an
    /// accidental tap from dropping out of disaster mode silently.
    @State private var showDeactivateConfirm = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                activeBanner

                ScrollView {
                    VStack(spacing: 16) {
                        myStatusCard
                        batteryCard
                        placeholderCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(backgroundColor)
            }
            .navigationTitle("災害モード")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: onDismiss)
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showDeactivateConfirm = true
                    } label: {
                        Text("終了")
                    }
                }
            }
            .confirmationDialog(
                "災害モードを終了しますか？",
                isPresented: $showDeactivateConfirm,
                titleVisibility: .visible
            ) {
                Button("終了する", role: .destructive) {
                    store.deactivate()
                    onDismiss()
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("安否 broadcast が停止します。")
            }
        }
    }

    // MARK: - Active banner

    private var activeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            Text("災害モード ON")
                .font(.bitchatSystem(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red)
    }

    // MARK: - Cards

    private var myStatusCard: some View {
        cardContainer(title: "あなたのステータス") {
            HStack {
                Text(store.myStatus.dashboardLabel)
                    .font(.bitchatSystem(size: 16, weight: .semibold, design: .monospaced))
                Spacer()
            }
            // Picker (F3) is added in a later phase.
            Text("ステータス変更はこの後のフェーズで追加されます。")
                .font(.bitchatSystem(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private var batteryCard: some View {
        cardContainer(title: "電池残量") {
            HStack(spacing: 8) {
                Image(systemName: batteryIcon)
                    .foregroundColor(batteryTint)
                Text("\(store.battery.pct)%")
                    .font(.bitchatSystem(size: 16, weight: .semibold, design: .monospaced))
                Text(store.battery.state.dashboardLabel)
                    .font(.bitchatSystem(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button("更新") { store.refresh() }
                    .font(.bitchatSystem(size: 12, design: .monospaced))
            }
        }
    }

    private var placeholderCard: some View {
        cardContainer(title: "家族の状態") {
            Text("家族リストはこの後のフェーズで追加されます。")
                .font(.bitchatSystem(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func cardContainer<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.bitchatSystem(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground)
        .cornerRadius(8)
    }

    private var cardBackground: Color {
        #if os(iOS)
        return Color(.secondarySystemBackground)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }

    private var backgroundColor: Color {
        #if os(iOS)
        return Color(.systemBackground)
        #else
        return Color.clear
        #endif
    }

    private var batteryIcon: String {
        switch store.battery.state {
        case .charging: return "battery.100.bolt"
        case .full:     return "battery.100"
        case .discharging:
            switch store.battery.pct {
            case ...15:  return "battery.25"
            case ...50:  return "battery.50"
            default:     return "battery.100"
            }
        case .unknown:  return "battery.0"
        }
    }

    private var batteryTint: Color {
        switch store.battery.state {
        case .charging, .full: return .green
        case .discharging:
            return store.battery.pct <= 15 ? .red : .primary
        case .unknown:         return .secondary
        }
    }
}

// MARK: - Display helpers

private extension DisasterStatus {
    var dashboardLabel: String {
        switch self {
        case .ok:        return "🟢 無事"
        case .injured:   return "🟡 軽傷"
        case .needsHelp: return "🔴 要救助"
        case .unknown:   return "❓ 未設定"
        }
    }
}

private extension BatteryState {
    var dashboardLabel: String {
        switch self {
        case .charging:    return "充電中"
        case .discharging: return "放電中"
        case .full:        return "満充電"
        case .unknown:     return "不明"
        }
    }
}
