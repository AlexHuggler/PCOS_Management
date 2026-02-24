import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    HStack {
                        Label("Subscription", systemImage: "star.circle")
                        Spacer()
                        Text(appState.isPremium ? "Premium" : "Free")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Data") {
                    Label("Export Data", systemImage: "square.and.arrow.up")

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }

                Section("Health") {
                    Label("HealthKit Access", systemImage: "heart.text.square")
                    Label("CloudKit Sync", systemImage: "icloud")
                }

                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    Label("Privacy Policy", systemImage: "hand.raised")
                    Label("Terms of Service", systemImage: "doc.text")
                }

                Section {
                    VStack(alignment: .center, spacing: 4) {
                        Text("CycleBalance")
                            .font(.footnote)
                            .fontWeight(.medium)
                        Text("Not a medical device. Always consult your healthcare provider.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
                Button("Delete Everything", role: .destructive) {
                    // TODO: Implement data deletion
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all your cycle data, symptoms, and insights. This action cannot be undone.")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
