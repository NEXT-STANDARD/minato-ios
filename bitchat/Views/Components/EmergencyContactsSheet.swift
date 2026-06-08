import SwiftUI

/// Manage time-boxed emergency overrides for known MINATO contacts (E-4a).
/// Per-contact grant (with a duration picker) / one-tap revoke. Overrides are
/// scoped to `safety.*` capabilities and auto-expire.
///
/// See: docs/MINATO-disaster-mode.md
struct EmergencyContactsSheet: View {
    @EnvironmentObject private var viewModel: ChatViewModel
    let onClose: () -> Void

    @State private var pendingGrantNpub: String?

    var body: some View {
        NavigationView {
            List {
                Section {
                    let contacts = viewModel.emergencyContacts()
                    if contacts.isEmpty {
                        Text("ハンドシェイク済みの MINATO 連絡先がまだありません。")
                            .font(.bitchatSystem(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(contacts) { contact in
                            contactRow(contact)
                        }
                    }
                } header: {
                    Text("緊急連絡先")
                } footer: {
                    Text("緊急オーバーライドは safety 情報の共有のみを許可し（trust やスケジュールは昇格しません）、災害モード終了または期限で自動失効します。精密位置は明示的なオーバーライドがある相手だけに共有されます。")
                }
            }
            .navigationTitle("緊急連絡先")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { onClose() }
                }
            }
            .confirmationDialog(
                "オーバーライドの有効期間",
                isPresented: Binding(
                    get: { pendingGrantNpub != nil },
                    set: { if !$0 { pendingGrantNpub = nil } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(EmergencyOverrideDuration.allCases) { duration in
                    Button(duration.displayNameJA) {
                        if let npub = pendingGrantNpub {
                            viewModel.grantEmergencyOverride(npub: npub, duration: duration)
                        }
                        pendingGrantNpub = nil
                    }
                }
                Button("キャンセル", role: .cancel) { pendingGrantNpub = nil }
            }
        }
    }

    @ViewBuilder
    private func contactRow(_ contact: EmergencyContact) -> some View {
        let active = contact.override?.isActive(now: UInt64(Date().timeIntervalSince1970)) ?? false
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName.isEmpty ? "(no name)" : contact.displayName)
                    .font(.bitchatSystem(size: 14, weight: .semibold, design: .monospaced))
                Text(statusText(contact.override))
                    .font(.bitchatSystem(size: 11, design: .monospaced))
                    .foregroundColor(active ? MinatoTheme.danger : .secondary)
            }
            Spacer()
            if active {
                Button("解除") { viewModel.revokeEmergencyOverride(npub: contact.npub) }
                    .buttonStyle(.bordered)
                    .tint(MinatoTheme.danger)
            } else {
                Button("付与") { pendingGrantNpub = contact.npub }
                    .buttonStyle(.borderedProminent)
                    .tint(MinatoTheme.warn)
            }
        }
    }

    private func statusText(_ override: EmergencyOverride?) -> String {
        guard let override, override.isActive(now: UInt64(Date().timeIntervalSince1970)) else {
            return "緊急共有: OFF"
        }
        guard let expiresAt = override.expiresAt else {
            return "緊急共有: ON（手動解除まで）"
        }
        let date = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "M/d HH:mm"
        return "緊急共有: ON（〜\(formatter.string(from: date))）"
    }
}
