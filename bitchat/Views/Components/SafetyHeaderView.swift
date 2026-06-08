import SwiftUI

/// Compact header that surfaces disaster-mode entry / state at the top of
/// `ContentView`. Off-state shows an unobtrusive call-to-action; on-state
/// shows the owner's current safety status with a hint that tapping opens
/// the full disaster screen.
///
/// Scope (D-3): visual surface + tap callbacks. No timer, no transport,
/// no family list — those land in later disaster-mode phases.
struct SafetyHeaderView: View {
    @ObservedObject var store: DisasterModeStore

    /// Fired when the owner taps the off-state banner. Caller is expected
    /// to confirm activation (e.g. confirmationDialog) before calling
    /// `store.activate()`.
    let onRequestActivate: () -> Void

    /// Fired when the owner taps the on-state status row. Caller opens the
    /// full disaster screen.
    let onOpenDashboard: () -> Void

    var body: some View {
        Group {
            if store.isActive {
                onView
            } else {
                offView
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Off-state banner

    private var offView: some View {
        Button(action: onRequestActivate) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("災害モード")
                    .font(.bitchatSystem(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                Spacer()
                Text("タップして起動")
                    .font(.bitchatSystem(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("災害モードを起動")
        .accessibilityHint("タップで起動確認を表示します")
    }

    // MARK: - On-state status row

    private var onView: some View {
        Button(action: onOpenDashboard) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("災害モード ON")
                    .font(.bitchatSystem(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                Spacer()
                Text(store.myStatus.headerLabel)
                    .font(.bitchatSystem(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.08))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("災害モード ON、現在のステータスは \(store.myStatus.headerLabel)")
        .accessibilityHint("タップで安否ダッシュボードを開きます")
    }
}

// MARK: - Status display helper

private extension DisasterStatus {
    /// Short emoji+label used in the on-state header row.
    var headerLabel: String {
        switch self {
        case .ok:        return "🟢 無事"
        case .injured:   return "🟡 軽傷"
        case .needsHelp: return "🔴 要救助"
        case .unknown:   return "❓ 未設定"
        }
    }
}
