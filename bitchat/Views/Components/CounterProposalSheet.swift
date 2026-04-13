import SwiftUI

/// Sheet for composing a counter-proposal to a schedule request.
struct CounterProposalSheet: View {
    let requestId: String
    let originalEvent: ProposedEvent?
    let onSubmit: (ProposedEvent) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(7200)
    @State private var location: String = ""

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("イベント詳細")) {
                    TextField("タイトル", text: $title)
                        .font(.bitchatSystem(size: 14, design: .monospaced))
                    DatePicker("開始", selection: $startDate)
                        .font(.bitchatSystem(size: 14, design: .monospaced))
                    DatePicker("終了", selection: $endDate, in: startDate...)
                        .font(.bitchatSystem(size: 14, design: .monospaced))
                    TextField("場所（任意）", text: $location)
                        .font(.bitchatSystem(size: 14, design: .monospaced))
                }
            }
            .navigationTitle("別日提案")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送信") {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime]
                        let event = ProposedEvent(
                            title: title,
                            start: formatter.string(from: startDate),
                            end: formatter.string(from: endDate),
                            location: location.isEmpty ? nil : location
                        )
                        onSubmit(event)
                    }
                    .disabled(title.isEmpty || endDate <= startDate)
                }
            }
        }
        .onAppear {
            if let event = originalEvent {
                title = event.title
                location = event.location ?? ""
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime]
                if let start = isoFormatter.date(from: event.start) {
                    startDate = start
                }
                if let end = isoFormatter.date(from: event.end) {
                    endDate = end
                }
            }
        }
    }
}
