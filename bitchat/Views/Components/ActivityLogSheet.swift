import SwiftUI

/// Displays the autonomous-action log for a specific peer (AGENT_LOG / full_auto audit trail).
struct ActivityLogSheet: View {
    let peerID: PeerID
    let onClose: () -> Void

    @State private var entries: [AgentActivityLog] = []
    @Environment(\.colorScheme) private var colorScheme

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    var body: some View {
        NavigationView {
            Group {
                if entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("アクティビティなし")
                            .font(.bitchatSystem(size: 14, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: iconFor(action: entry.action))
                                    .foregroundColor(colorFor(action: entry.action))
                                Text(labelFor(action: entry.action))
                                    .font(.bitchatSystem(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(colorFor(action: entry.action))
                                Spacer()
                                Text(Self.dateFormatter.string(from: entry.timestamp))
                                    .font(.bitchatSystem(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Text("→ @\(entry.peerName)")
                                .font(.bitchatSystem(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(entry.content)
                                .font(.bitchatSystem(size: 13, design: .monospaced))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("AIアクティビティ")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { onClose() }
                }
            }
        }
        .onAppear {
            entries = MINATOAgentStore.shared.activityLog(for: peerID)
        }
    }

    private func iconFor(action: AgentActivityLog.ActionType) -> String {
        switch action {
        case .autoReply: return "bubble.left.and.bubble.right.fill"
        case .autoScheduleAck: return "checkmark.circle.fill"
        case .autoScheduleReject: return "xmark.circle.fill"
        }
    }

    private func labelFor(action: AgentActivityLog.ActionType) -> String {
        switch action {
        case .autoReply: return "自動返信"
        case .autoScheduleAck: return "自動承認"
        case .autoScheduleReject: return "自動辞退"
        }
    }

    private func colorFor(action: AgentActivityLog.ActionType) -> Color {
        switch action {
        case .autoReply: return .cyan
        case .autoScheduleAck: return .green
        case .autoScheduleReject: return .red
        }
    }
}
