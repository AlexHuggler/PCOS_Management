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
    @State private var contributionSummaries: [HealthKitContributionSummary] = []

    private var positiveTint: Color {
        AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : AppTheme.sage
    }

    private var secondaryTint: Color {
        AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorSecondaryAccentColor : AppTheme.accentColor
    }

    private var warningTint: Color {
        AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorWarningAccentColor : AppTheme.coralAccent
    }

    private var dataDisclosureItems: [HealthKitDataDisclosureItem] {
        HealthKitDataTypeDescriptor.disclosureItems.map { descriptor in
            HealthKitDataDisclosureItem(
                id: descriptor.id,
                icon: descriptor.systemImage,
                tint: tint(for: descriptor.category),
                title: localized(descriptor.title),
                healthKitType: localized(descriptor.healthKitTypeDescription),
                usage: localized(descriptor.usageDescription)
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                connectionCard
                dataAccessCard
                contributionCard
                privacyCard

                if healthKitManager.isConfigured {
                    syncCard
                }
            }
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.top, AppTheme.spacing16)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background {
            if AppTheme.usesPremiumEditorStyling {
                BotanicalScreenBackground(style: .quiet)
            } else {
                AppTheme.groupedBackground.ignoresSafeArea()
            }
        }
        .navigationTitle(localized("Apple Health"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground : AppTheme.groupedBackground, for: .navigationBar)
        .toolbarColorScheme(AppTheme.preferredColorScheme, for: .navigationBar)
        .tint(positiveTint)
        .task {
            await healthKitManager.refreshAuthorizationState()
            refreshContributionSummaries()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            Task {
                await healthKitManager.refreshAuthorizationState()
                refreshContributionSummaries()
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
                        tint: healthKitManager.isConfigured ? positiveTint : warningTint,
                        size: 48
                    )

                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(connectionTitle)
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)

                        Text(connectionSubtitle)
                            .appFont(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
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
                        tint: positiveTint
                    )
                }

                statusPill(
                    localized("Read-only"),
                    systemImage: "eye.fill",
                    tint: positiveTint
                )

                statusPill(
                    localized("On device"),
                    systemImage: "iphone",
                    tint: secondaryTint
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
                        .foregroundStyle(AppTheme.primaryText)

                    Text(localized("These data types are read only after you connect Apple Health. Source summaries show which apps contributed data."))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                VStack(spacing: 0) {
                    ForEach(dataDisclosureItems) { item in
                        dataTypeRow(item)

                        if item.id != dataDisclosureItems.last?.id {
                            Divider()
                                .overlay(AppTheme.premiumEditorBorder.opacity(AppTheme.usesPremiumEditorStyling ? 0.42 : 0.16))
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
                iconBadge(systemName: "lock.shield.fill", tint: positiveTint, size: 40)

                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(localized("Health data stays private"))
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)

                    Text(localized("CycleBalance reads data only after you grant permission. Data stays on your device and helps enrich logs, trends, and insights."))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(localized("No writes to Apple Health"), systemImage: "hand.raised.fill")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(positiveTint)
                }
            }
        }
    }

    private var contributionCard: some View {
        healthKitCard {
            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(localized("Apple Health Contributions"))
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)

                    Text(localized("See where Apple Health data is currently enriching CycleBalance. Counts reflect recent on-device records only."))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: AppTheme.spacing8) {
                    ForEach(contributionSummaries) { summary in
                        HStack {
                            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                Text(localized(summary.title))
                                    .appFont(.subheadline, weight: .medium)
                                    .foregroundStyle(AppTheme.primaryText)
                                Text(localized(summary.sourceLabel))
                                    .appFont(.caption2)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }

                            Spacer()

                            Text(summary.displayText)
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(summary.sampleCount > 0 ? positiveTint : AppTheme.secondaryText)
                        }
                        .padding(.vertical, AppTheme.spacing4)
                    }
                }
            }
        }
        .accessibilityIdentifier("settings.healthkit.contributions")
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
                        tint: positiveTint
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
                            .foregroundStyle(warningTint)
                        Text(error)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(AppTheme.spacing12)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                            .fill(warningTint.opacity(AppTheme.opacitySubtle))
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
                .foregroundStyle(AppTheme.secondaryText)
        } else if healthKitManager.isConfigured {
            Image(systemName: "arrow.up.right.square")
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(positiveTint)
        } else {
            Image(systemName: "chevron.right")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.76))
                .padding(.top, AppTheme.spacing4)
        }
    }

    private func dataTypeRow(_ item: HealthKitDataDisclosureItem) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            iconBadge(systemName: item.icon, tint: item.tint, size: 38)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(item.title)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Text(item.usage)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.healthKitType)
                    .appFont(.caption2, weight: .medium)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.72))
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
        let usesPremium = AppTheme.usesPremiumEditorStyling

        return content()
            .padding(AppTheme.spacing16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusXL, style: .continuous)
                    .fill(usesPremium ? AppTheme.premiumEditorSurface.opacity(0.82) : AppTheme.cardBackground)
                    .shadow(
                        color: usesPremium ? AppTheme.premiumEditorAccentColor.opacity(0.14) : Color.black.opacity(0.05),
                        radius: usesPremium ? 22 : 18,
                        x: 0,
                        y: usesPremium ? 10 : 8
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusXL, style: .continuous)
                    .stroke(usesPremium ? AnyShapeStyle(AppTheme.premiumEditorBorderGradient) : AnyShapeStyle(Color.primary.opacity(0.06)), lineWidth: usesPremium ? 0.9 : 1)
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
                refreshContributionSummaries()
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
                refreshContributionSummaries()
            }
        } label: {
            HStack(spacing: AppTheme.spacing8) {
                if healthKitManager.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.premiumEditorCTAForeground)
                    Text(localized("Syncing..."))
                } else {
                    Label(localized("Sync Now"), systemImage: "arrow.triangle.2.circlepath")
                }

                Spacer()
            }
            .appFont(.subheadline, weight: .semibold)
            .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorCTAForeground : .white)
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.vertical, AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                    .fill(AppTheme.usesPremiumEditorStyling ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.sage))
                    .opacity(healthKitManager.isSyncing ? 0.65 : 1)
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

    private func tint(for category: HealthKitDataTypeDescriptor.Category) -> Color {
        if AppTheme.usesPremiumEditorStyling {
            switch category {
            case .body, .nutrition, .cycle, .reproductiveContext:
                return positiveTint
            case .activity, .sleep:
                return secondaryTint
            case .heart, .glucose, .symptoms:
                return warningTint
            }
        }

        switch category {
        case .body, .nutrition:
            return AppTheme.sage
        case .activity:
            return Color.orange
        case .heart, .glucose, .symptoms:
            return AppTheme.coralAccent
        case .sleep:
            return Color.blue
        case .cycle, .reproductiveContext:
            return AppTheme.accentColor
        }
    }

    private func refreshContributionSummaries() {
        do {
            contributionSummaries = try HealthKitContributionSummaryService(modelContext: modelContext).summaries()
        } catch {
            contributionSummaries = []
        }
    }
}

#Preview {
    NavigationStack {
        HealthKitSettingsView()
    }
}
