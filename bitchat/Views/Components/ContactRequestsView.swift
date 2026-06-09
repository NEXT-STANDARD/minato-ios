import SwiftUI

/// Inbox of incoming contact requests (approval-gated invites). The owner accepts
/// (adds the sender as a mutual contact) or declines (drops + blocks). Quarantining
/// keeps strangers out of the chat list until explicitly approved.
struct ContactRequestsView: View {
    @ObservedObject private var store = ContactRequestStore.shared
    @EnvironmentObject private var viewModel: ChatViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.minatoAlert) private var isHighAlert
    let onClose: () -> Void

    var body: some View {
        NavigationView {
            Group {
                if store.requests.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(MinatoTheme.background(colorScheme, alert: isHighAlert))
            .navigationTitle(Text("contact.requests.title", comment: "Title of the contact-requests inbox"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Text("common.close", comment: "Close button")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(MinatoTheme.inkSecondary(colorScheme, alert: isHighAlert))
            Text("contact.requests.empty", comment: "Shown when there are no pending contact requests")
                .font(.bitchatSystem(size: 13, design: .monospaced))
                .foregroundColor(MinatoTheme.inkSecondary(colorScheme, alert: isHighAlert))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(store.requests) { request in
                    row(request)
                }
            }
            .padding(16)
        }
    }

    private func row(_ request: ContactRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 22))
                    .foregroundColor(MinatoTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.displayName)
                        .font(.bitchatSystem(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(MinatoTheme.ink(colorScheme, alert: isHighAlert))
                    Text(request.npubShort)
                        .font(.bitchatSystem(size: 11, design: .monospaced))
                        .foregroundColor(MinatoTheme.inkSecondary(colorScheme, alert: isHighAlert))
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.acceptContactRequest(request)
                } label: {
                    Text("contact.requests.accept", comment: "Accept a contact request")
                        .font(.bitchatSystem(size: 13, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(MinatoTheme.accent)

                Button(role: .destructive) {
                    viewModel.declineContactRequest(request)
                } label: {
                    Text("contact.requests.decline", comment: "Decline (and block) a contact request")
                        .font(.bitchatSystem(size: 13, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .tint(MinatoTheme.danger)
            }
        }
        .padding(14)
        .background(MinatoTheme.surface(colorScheme, alert: isHighAlert))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
