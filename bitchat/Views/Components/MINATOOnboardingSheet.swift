import SwiftUI

/// One-time onboarding shown after the first successful MINATO handshake.
/// Explains what just happened, what Trust Mode is, and how to change it.
struct MINATOOnboardingSheet: View {
    let peerName: String
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🤖 AIエージェント接続成立")
                            .font(.bitchatSystem(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                        Text("\(peerName) さんのAIとカードを交換しました。")
                            .font(.bitchatSystem(size: 14, design: .monospaced))
                    }

                    divider

                    // What is this?
                    section(
                        icon: "sparkles",
                        color: .cyan,
                        title: "これは何？",
                        body: "MINATO は、AIエージェント同士が人間の代わりに話をするプロトコルです。飲み会の時間調整、言語の違う相手との会話などを、あなたが一言発するだけでエージェントが処理します。"
                    )

                    // Trust Mode
                    section(
                        icon: "shield.lefthalf.filled",
                        color: .orange,
                        title: "Trust Mode（信頼レベル）",
                        body: "AIがどこまで自動で動くかを、相手ごとに設定できます:"
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        modeRow(emoji: "👨‍🎓", name: "見習い (plan)", desc: "毎回あなたに確認", isDefault: true)
                        modeRow(emoji: "🤝", name: "相棒 (suggest)", desc: "短い返事は自動、大事な返信は確認")
                        modeRow(emoji: "💼", name: "右腕 (auto)", desc: "ほぼ自動、カレンダー操作のみ確認")
                        modeRow(emoji: "🧠", name: "分身 (fullAuto)", desc: "完全自律、事後ログで確認")
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    )

                    // Current setting
                    section(
                        icon: "info.circle",
                        color: .green,
                        title: "現在の設定: 見習い",
                        body: "\(peerName) さんとの関係は「見習い」モードです。AIが返信案を出したら、あなたの承認を待って送信します。\n\nプライベートチャット画面の上部バッジから、いつでもモードを変更できます。"
                    )

                    divider

                    // Tips
                    section(
                        icon: "lightbulb",
                        color: .yellow,
                        title: "試してみよう",
                        body: "「今夜飲み行こう？」のような予定の相談をすると、AIが日時・場所まで提案して、相手に構造化された招待を送ります。"
                    )
                }
                .padding(20)
            }
            .navigationTitle("MINATO へようこそ")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("はじめる") { onDismiss() }
                        .font(.bitchatSystem(size: 14, weight: .semibold, design: .monospaced))
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(height: 1)
    }

    private func section(icon: String, color: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(color)
                Text(title)
                    .font(.bitchatSystem(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }
            Text(body)
                .font(.bitchatSystem(size: 13, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modeRow(emoji: String, name: String, desc: String, isDefault: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(emoji).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.bitchatSystem(size: 13, weight: .semibold, design: .monospaced))
                    if isDefault {
                        Text("← 初期値")
                            .font(.bitchatSystem(size: 10, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                Text(desc)
                    .font(.bitchatSystem(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
}
