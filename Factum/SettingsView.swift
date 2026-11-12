import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Support")) {
                    NavigationLink {
                        AboutView()
                    } label: {
                        settingsRow(icon: "info.circle", title: "About")
                    }
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        settingsRow(icon: "lock.shield", title: "Privacy")
                    }
                    NavigationLink {
                        SupportView()
                    } label: {
                        settingsRow(icon: "questionmark.circle", title: "Support")
                    }
                    NavigationLink {
                        AccountDeletionView()
                    } label: {
                        settingsRow(icon: "trash.fill", title: "Delete Account")
                    }
                    .listRowBackground(PigeonTheme.cardBackground)
                }
                // Other sections...
            }
            .navigationTitle("Settings")
        }
    }
}

import SafariServices

struct AccountDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var showConfirm = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Delete Account")
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)

                Text("Deleting your account permanently removes your profile, study history, and any associated content. This action cannot be undone.")
                    .font(PigeonTheme.bodyFont)
                    .foregroundStyle(PigeonTheme.secondaryText)

                Text("What happens")
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)

                VStack(alignment: .leading, spacing: 8) {
                    Text("• Your profile and sessions will be deleted from our servers.")
                    Text("• Friends will no longer see your account.")
                    Text("• This cannot be undone.")
                }
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.secondaryText)

                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    HStack {
                        if isSubmitting { ProgressView().tint(PigeonTheme.accentText) }
                        Text("Delete My Account")
                            .font(PigeonTheme.subheadlineFont)
                    }
                    .foregroundStyle(PigeonTheme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PigeonTheme.destructive)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSubmitting)

                Text("Alternatively, you can complete account deletion on the web.")
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.secondaryText)

                Link(destination: URL(string: "https://pigeonstudy.ing/delete")!) {
                    Text("Open Account Deletion Page")
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(PigeonTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.destructive)
                }
            }
            .padding(16)
        }
        .background(PigeonTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Delete Account")
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }
        }
        .alert("Delete Account?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await submitDeletion() } }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    @MainActor
    private func submitDeletion() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await SupabaseService.shared.requestAccountDeletion()
            // Show a simple acknowledgement and pop back
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
    }
}
