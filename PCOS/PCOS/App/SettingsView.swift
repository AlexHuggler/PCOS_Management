import SwiftUI
import SwiftData
import os

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false
    @State private var showDeletedFeedback = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var exportSuccessToggle = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    NavigationLink {
                        PaywallView()
                    } label: {
                        HStack {
                            Label("Subscription", systemImage: "star.circle")
                            Spacer()
                            Text(appState.isPremium ? "Premium" : "Free")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Data") {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share Export", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            generateExport()
                        } label: {
                            Label("Export Data", systemImage: "square.and.arrow.up")
                        }
                    }

                    NavigationLink {
                        ReportConfigView()
                    } label: {
                        Label("Health Report", systemImage: "doc.richtext")
                    }

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }

                Section("Health") {
                    NavigationLink {
                        HealthKitSettingsView()
                    } label: {
                        Label("HealthKit Access", systemImage: "heart.text.square")
                    }
                    Label("CloudKit Sync", systemImage: "icloud")
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
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

                    Button {
                        appState.onboardingProfile.resetOnboarding()
                        appState.hasCompletedOnboarding = false
                    } label: {
                        Label("Replay Welcome Tour", systemImage: "arrow.counterclockwise")
                    }
                }

                Section {
                    VStack(alignment: .center, spacing: AppTheme.spacing4) {
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
            .scrollContentBackground(.hidden)
            .background(AppTheme.warmNeutral)
            .sensoryFeedback(.warning, trigger: showDeleteConfirmation)
            .sensoryFeedback(.success, trigger: showDeletedFeedback)
            .sensoryFeedback(.success, trigger: exportSuccessToggle)
            .alert("Export Failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "An unknown error occurred.")
            }
            .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
                Button("Delete Everything", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all your cycle data, symptoms, and insights. This action cannot be undone.")
            }
        }
    }

    private func generateExport() {
        do {
            let service = SettingsDataExportService(modelContext: modelContext)
            exportURL = try service.generateCSVExport()
            exportSuccessToggle.toggle()
        } catch {
            exportError = "Could not create export file: \(error.localizedDescription)"
        }
    }

    private func deleteAllData() {
        do {
            let service = SettingsDataDeletionService(modelContext: modelContext)
            try service.deleteAllData()
            showDeletedFeedback.toggle()
        } catch {
            Logger.database.error("Failed to delete all data: \(error.localizedDescription)")
            exportError = "Failed to delete data: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
