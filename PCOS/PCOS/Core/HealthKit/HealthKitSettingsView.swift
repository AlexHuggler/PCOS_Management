import SwiftUI
import UIKit

struct HealthKitSettingsView: View {
    private struct HealthKitDataDisclosureItem: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let healthKitType: String
        let usage: String
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var healthKitManager = HealthKitManager()
    @State private var authorizationTriggered = false

    private var dataDisclosureItems: [HealthKitDataDisclosureItem] {
        [
            HealthKitDataDisclosureItem(
                id: "bodyMass",
                icon: "scalemass",
                tint: AppTheme.sage,
                title: localized("Body Mass"),
                healthKitType: localized("HealthKit type: Body Mass"),
                usage: localized("Used for daily weight and weight trends. Shown on Today when Apple Health has synced daily context.")
            ),
            HealthKitDataDisclosureItem(
                id: "sleepAnalysis",
                icon: "bed.double.fill",
                tint: Color.blue,
                title: localized("Sleep Analysis"),
                healthKitType: localized("HealthKit type: Sleep Analysis"),
                usage: localized("Used for sleep hours and sleep/recovery insights.")
            ),
            HealthKitDataDisclosureItem(
                id: "activeEnergyBurned",
                icon: "flame.fill",
                tint: Color.orange,
                title: localized("Active Energy Burned"),
                healthKitType: localized("HealthKit type: Active Energy Burned"),
                usage: localized("Used as activity context for daily logs and activity insights.")
            ),
            HealthKitDataDisclosureItem(
                id: "bloodGlucose",
                icon: "drop.fill",
                tint: AppTheme.coralAccent,
                title: localized("Blood Glucose"),
                healthKitType: localized("HealthKit type: Blood Glucose"),
                usage: localized("Used for blood sugar history and metabolic insight context. Imported readings appear in Blood Sugar History with an Apple Health label.")
            ),
            HealthKitDataDisclosureItem(
                id: "stepCount",
                icon: "figure.walk",
                tint: Color.teal,
                title: localized("Step Count"),
                healthKitType: localized("HealthKit type: Step Count"),
                usage: localized("Requested for activity context; not saved or used for insights.")
            ),
            HealthKitDataDisclosureItem(
                id: "restingHeartRate",
                icon: "heart.circle",
                tint: AppTheme.coralAccent,
                title: localized("Resting Heart Rate"),
                healthKitType: localized("HealthKit type: Resting Heart Rate"),
                usage: localized("Used for daily resting BPM and recovery context.")
            ),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                connectionCard
                dataAccessCard
                privacyCard

                if healthKitManager.isConfigured {
                    syncCard
                }
            }
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.top, AppTheme.spacing16)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(localized("Apple Health"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await healthKitManager.refreshAuthorizationState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            Task {
                await healthKitManager.refreshAuthorizationState()
            }
        }
    }

    // MARK: - Premium Cards

    @ViewBuilder
    private var connectionCard: some View {
        if healthKitManager.authorizationState != .unavailable {
            Button {
                handleConnectionCardTap()
            } label: {
                connectionCardContent
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: authorizationTriggered)
            .accessibilityIdentifier("settings.healthkit.connection")
        } else {
            connectionCardContent
                .accessibilityIdentifier("settings.healthkit.connection")
        }
    }

    private var connectionCardContent: some View {
        healthKitCard {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                HStack(alignment: .top, spacing: AppTheme.spacing12) {
                    iconBadge(
                        systemName: "heart.text.square.fill",
                        tint: healthKitManager.isConfigured ? AppTheme.sage : AppTheme.coralAccent,
                        size: 48
                    )

                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(connectionTitle)
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(.primary)

                        Text(connectionSubtitle)
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: AppTheme.spacing8)
                    connectionAccessory
                }

                HStack(spacing: AppTheme.spacing8) {
                    if healthKitManager.isConfigured {
                        statusPill(
                            localized("Connected"),
                            systemImage: "checkmark.circle.fill",
                            tint: AppTheme.sage
                        )
                    }

                    statusPill(
                        localized("Read-only"),
                        systemImage: "eye.fill",
                        tint: AppTheme.sage
                    )

                    statusPill(
                        localized("On device"),
                        systemImage: "iphone",
                        tint: AppTheme.coralAccent
                    )
                }
            }
        }
    }

    private var dataAccessCard: some View {
        healthKitCard {
            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(localized("Health Data Access"))
                        .appFont(.headline, weight: .semibold)

                    Text(localized("These data types are read only after you connect Apple Health."))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(dataDisclosureItems) { item in
                        dataTypeRow(item)

                        if item.id != dataDisclosureItems.last?.id {
                            Divider()
                                .padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }

    private var privacyCard: some View {
        healthKitCard {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                iconBadge(systemName: "lock.shield.fill", tint: AppTheme.sage, size: 40)

                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(localized("Health data stays private"))
                        .appFont(.subheadline, weight: .semibold)

                    Text(localized("CycleBalance reads data only after you grant permission. Data stays on your device and helps enrich logs, trends, and insights."))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(localized("No writes to Apple Health"), systemImage: "hand.raised.fill")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.sage)
                }
            }
        }
    }

    private var syncCard: some View {
        healthKitCard {
            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                HStack(spacing: AppTheme.spacing8) {
                    Label(localized("Sync"), systemImage: "arrow.triangle.2.circlepath")
                        .appFont(.headline, weight: .semibold)

                    Spacer()

                    statusPill(
                        localized("Connected"),
                        systemImage: "checkmark.circle.fill",
                        tint: AppTheme.sage
                    )
                }

                syncButton

                if let lastSync = healthKitManager.lastSyncDate {
                    HStack {
                        Label(localized("Last Synced"), systemImage: "clock")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastSync, style: .relative)
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = healthKitManager.lastError {
                    HStack(alignment: .top, spacing: AppTheme.spacing8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.coralAccent)
                        Text(error)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(AppTheme.spacing12)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                            .fill(AppTheme.coralAccent.opacity(AppTheme.opacitySubtle))
                    )
                }
            }
        }
    }

    // MARK: - Subviews

    private var connectionTitle: String {
        if healthKitManager.authorizationState == .unavailable {
            localized("HealthKit Unavailable")
        } else if healthKitManager.isConfigured {
            localized("Connected to Apple Health")
        } else {
            localized("Connect to Apple Health")
        }
    }

    private var connectionSubtitle: String {
        if healthKitManager.authorizationState == .unavailable {
            localized("Apple Health is not available on this device. HealthKit integration requires a physical iPhone.")
        } else if healthKitManager.isConfigured {
            localized("Health access is configured. Manage permissions in Settings.")
        } else {
            localized("Allow CycleBalance to read your health data")
        }
    }

    @ViewBuilder
    private var connectionAccessory: some View {
        if healthKitManager.authorizationState == .unavailable {
            Image(systemName: "xmark.circle.fill")
                .appFont(.title3)
                .foregroundStyle(.secondary)
        } else if healthKitManager.isConfigured {
            Image(systemName: "arrow.up.right.square")
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(AppTheme.sage)
        } else {
            Image(systemName: "chevron.right")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.tertiary)
                .padding(.top, AppTheme.spacing4)
        }
    }

    private func dataTypeRow(_ item: HealthKitDataDisclosureItem) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            iconBadge(systemName: item.icon, tint: item.tint, size: 38)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(item.title)
                    .appFont(.subheadline, weight: .semibold)

                Text(item.usage)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.healthKitType)
                    .appFont(.caption2, weight: .medium)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.spacing8)
    }

    private func iconBadge(systemName: String, tint: Color, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size > 40 ? 20 : 16, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size / 2.8, style: .continuous)
                    .fill(tint.opacity(AppTheme.opacityLight))
            )
    }

    private func statusPill(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .appFont(.caption2, weight: .semibold)
            .foregroundStyle(tint)
            .padding(.horizontal, AppTheme.spacing8)
            .padding(.vertical, AppTheme.spacing4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(AppTheme.opacityLight))
            )
    }

    private func healthKitCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(AppTheme.spacing16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusXL, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusXL, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    private func handleConnectionCardTap() {
        Task {
            let currentState = await healthKitManager.refreshAuthorizationState()

            switch currentState {
            case .configured:
                openAppSettings()
            case .needsAuthorization:
                await healthKitManager.connectAndSync(modelContext: modelContext)
                if healthKitManager.isConfigured {
                    authorizationTriggered.toggle()
                }
            case .unavailable:
                break
            }
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(settingsURL)
    }

    private var syncButton: some View {
        Button {
            Task {
                await healthKitManager.performFullSync(modelContext: modelContext)
            }
        } label: {
            HStack(spacing: AppTheme.spacing8) {
                if healthKitManager.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text(localized("Syncing..."))
                } else {
                    Label(localized("Sync Now"), systemImage: "arrow.triangle.2.circlepath")
                }

                Spacer()
            }
            .appFont(.subheadline, weight: .semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.vertical, AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                    .fill(AppTheme.sage.opacity(healthKitManager.isSyncing ? 0.65 : 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(healthKitManager.isSyncing)
        .sensoryFeedback(.success, trigger: healthKitManager.lastSyncDate)
        .accessibilityIdentifier("settings.healthkit.sync_now")
    }

    private func localized(_ key: String) -> String {
        L10n.string(key, defaultValue: key)
    }
}

#Preview {
    NavigationStack {
        HealthKitSettingsView()
    }
}
