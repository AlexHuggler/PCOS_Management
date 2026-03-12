import SwiftUI

struct HealthKitSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var healthKitManager = HealthKitManager()
    @State private var authorizationTriggered = false

    var body: some View {
        Group {
            if healthKitManager.isAvailable {
                availableContent
            } else {
                unavailableContent
            }
        }
    }

    // MARK: - Available Content

    private var availableContent: some View {
        Group {
            Section {
                connectionRow
            } header: {
                Text("Apple Health")
            } footer: {
                Text("CycleBalance reads health data to enrich your daily logs. No data is written to Apple Health.")
            }

            if healthKitManager.isAuthorized {
                Section("Data Types") {
                    dataTypeRow(
                        icon: "scalemass",
                        title: "Weight",
                        subtitle: "Body mass measurements"
                    )
                    dataTypeRow(
                        icon: "bed.double.fill",
                        title: "Sleep",
                        subtitle: "Sleep analysis data"
                    )
                    dataTypeRow(
                        icon: "flame.fill",
                        title: "Active Energy",
                        subtitle: "Activity minutes"
                    )
                    dataTypeRow(
                        icon: "drop.fill",
                        title: "Blood Glucose",
                        subtitle: "Glucose readings (mg/dL)"
                    )
                    dataTypeRow(
                        icon: "figure.walk",
                        title: "Steps",
                        subtitle: "Daily step count"
                    )
                }

                Section {
                    syncButton

                    if let lastSync = healthKitManager.lastSyncDate {
                        HStack {
                            Label("Last Synced", systemImage: "clock")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(lastSync, style: .relative)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = healthKitManager.lastError {
                        HStack(spacing: AppTheme.spacing8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.coralAccent)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Sync")
                }
            }
        }
    }

    // MARK: - Unavailable Content

    private var unavailableContent: some View {
        Section("Apple Health") {
            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                HStack(spacing: AppTheme.spacing12) {
                    Image(systemName: "heart.text.square")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text("HealthKit Unavailable")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Apple Health is not available on this device. HealthKit integration requires a physical iPhone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, AppTheme.spacing4)
        }
    }

    // MARK: - Subviews

    private var connectionRow: some View {
        Button {
            Task {
                do {
                    try await healthKitManager.requestAuthorization()
                    authorizationTriggered = healthKitManager.isAuthorized
                } catch {
                    authorizationTriggered = false
                    healthKitManager.lastError = error.localizedDescription
                }
            }
        } label: {
            HStack(spacing: AppTheme.spacing12) {
                Image(systemName: "heart.text.square")
                    .font(.title2)
                    .foregroundStyle(healthKitManager.isAuthorized ? AppTheme.sage : AppTheme.coralAccent)

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(healthKitManager.isAuthorized ? "Connected to Apple Health" : "Connect to Apple Health")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(healthKitManager.isAuthorized
                         ? "Tap to update permissions in Health app"
                         : "Allow CycleBalance to read your health data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if healthKitManager.isAuthorized {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.sage)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .sensoryFeedback(.success, trigger: authorizationTriggered)
    }

    private func dataTypeRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(AppTheme.sage)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundStyle(AppTheme.sage)
        }
    }

    private var syncButton: some View {
        Button {
            Task {
                await healthKitManager.performFullSync(modelContext: modelContext)
            }
        } label: {
            HStack {
                if healthKitManager.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                Spacer()
            }
        }
        .disabled(healthKitManager.isSyncing)
        .sensoryFeedback(.success, trigger: healthKitManager.lastSyncDate)
    }
}

#Preview {
    List {
        HealthKitSettingsView()
    }
}
