import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import os

struct SettingsView: View {
    private enum PendingJSONImportSource {
        case url(URL)
        case data(Data)
    }

    private struct PendingSharePayload: Identifiable {
        enum Kind: String {
            case csvExport
            case jsonBackup
            case csvTemplate
        }

        let id = UUID()
        let kind: Kind
        let url: URL
    }

    private enum SettingsFileImportRequest {
        case jsonBackup
        case externalCSV

        var allowedContentTypes: [UTType] {
            switch self {
            case .jsonBackup:
                [UTType.json]
            case .externalCSV:
                [UTType.commaSeparatedText, UTType.plainText]
            }
        }
    }

    private enum SettingsSheet: Identifiable {
        case csvImportGuide
        case share(PendingSharePayload)

        var id: String {
            switch self {
            case .csvImportGuide:
                "csv-import-guide"
            case .share(let payload):
                payload.id.uuidString
            }
        }
    }

    private enum LunarReminderKind {
        case period
        case symptoms
        case supplements
    }

    private enum LunarSettingsMood: String, CaseIterable, Identifiable {
        case great
        case good
        case okay
        case low
        case tough

        var id: String { rawValue }

        var title: String {
            switch self {
            case .great:
                L10n.string("Great", defaultValue: "Great")
            case .good:
                L10n.string("Good", defaultValue: "Good")
            case .okay:
                L10n.string("Okay", defaultValue: "Okay")
            case .low:
                L10n.string("Low", defaultValue: "Low")
            case .tough:
                L10n.string("Tough", defaultValue: "Tough")
            }
        }

        var systemImage: String {
            switch self {
            case .great:
                "sun.max.fill"
            case .good:
                "cloud.sun.fill"
            case .okay:
                "cloud.fill"
            case .low:
                "cloud.rain.fill"
            case .tough:
                "bolt.fill"
            }
        }

        var tint: Color {
            switch self {
            case .great:
                AppTheme.softGoldAccent
            case .good:
                AppTheme.premiumEditorAccentColor
            case .okay:
                AppTheme.lavenderAccent
            case .low:
                AppTheme.accentColor
            case .tough:
                AppTheme.premiumEditorSecondaryAccentColor
            }
        }
    }

    fileprivate struct ImportResultPresentation: Identifiable {
        let id = UUID()
        let title: String
        let summary: String
        let channelTitle: String
        let changeCounts: SettingsDataImportService.ImportChangeCounts
        let issues: [SettingsDataImportService.ImportIssue]
    }

    @Environment(AppState.self) private var appState
    @Environment(AppLockManager.self) private var appLockManager
    @Environment(AppearancePreferences.self) private var appearancePreferences
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var showDeleteConfirmation = false
    @State private var pendingJSONImportSource: PendingJSONImportSource?
    @State private var activeFileImportRequest: SettingsFileImportRequest?
    @State private var activeSheet: SettingsSheet?
    @State private var showingCSVImportGuide = false
    @State private var importResult: ImportResultPresentation?
    @State private var showImportConfirmation = false
    @State private var lastImportSummary: SettingsDataImportService.ImportSummary?
    @State private var operationError: String?
    @State private var deleteSuccessToggle = false
    @State private var exportSuccessToggle = false
    @State private var importSuccessToggle = false
    @State private var showingPregnancyActivation = false
    @State private var showingPregnancyEnd = false
    @State private var showingPrivateJournal = false
    @State private var pregnancyViewModel: PregnancyViewModel?
    @State private var selectedProfilePhotoItem: PhotosPickerItem?
    @State private var profilePhotoData: Data?
    @State private var lunarNotificationManager: NotificationManager?
    @State private var lunarPeriodReminderEnabled = false
    @State private var lunarSymptomReminderEnabled = false
    @State private var lunarSupplementReminderEnabled = false
    @State private var lunarCheckInMood: LunarSettingsMood = .good
    @AppStorage("mealScan.enableMealPhotoRetention") private var enableMealPhotoRetention = true

    private let profilePhotoStore = LocalProfilePhotoStore()

#if DEBUG
    @State private var debugTools = SettingsDebugToolsState()
    @State private var debugTapCount = 0
    @State private var showDebugSections = false
#endif

    var body: some View {
        NavigationStack {
            List {
                if AppTheme.usesImmersiveHomeShell {
                    Section {
                        lunarSupportOverview
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if appState.showsSubscriptionUI {
                    Section(L10n.string("Account", defaultValue: "Account")) {
                        HStack {
                            Label(L10n.string("Subscription", defaultValue: "Subscription"), systemImage: "star.circle")
                            Spacer()
                            Text(
                                appState.isPremium
                                    ? L10n.string("Premium", defaultValue: "Premium")
                                    : L10n.string("Free", defaultValue: "Free")
                            )
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.showPremiumPaywall = true
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            appState.showPremiumPaywall = true
                        }
                        .accessibilityIdentifier("settings.subscription.row")
                    }
                }

                Section {
                    switch appState.lifecycleMode {
                    case .cycling:
                        Button {
                            showingPregnancyActivation = true
                        } label: {
                            HStack {
                                Label(
                                    L10n.string("Enter Pregnancy Mode", defaultValue: "Enter Pregnancy Mode"),
                                    systemImage: "heart.fill"
                                )
                                Spacer()
                                Text(L10n.string("Not active", defaultValue: "Not active"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("settings.pregnancy.enter")

                    case .pregnant:
                        HStack {
                            Label(
                                L10n.string("Pregnancy Mode", defaultValue: "Pregnancy Mode"),
                                systemImage: "heart.fill"
                            )
                            Spacer()
                            Text(pregnancyViewModel?.gestationalDisplayText ?? L10n.string("Active", defaultValue: "Active"))
                                .foregroundStyle(.secondary)
                        }

                        if let pvm = pregnancyViewModel, pvm.canUndoActivation {
                            Button {
                                undoPregnancyActivation()
                            } label: {
                                Label(
                                    L10n.string("Undo Activation", defaultValue: "Undo Activation"),
                                    systemImage: "arrow.uturn.backward"
                                )
                                .foregroundStyle(.orange)
                            }
                        }

                        Button {
                            showingPregnancyEnd = true
                        } label: {
                            Label(
                                L10n.string("End Pregnancy Mode", defaultValue: "End Pregnancy Mode"),
                                systemImage: "xmark.circle"
                            )
                        }

                    case .postpartum:
                        HStack {
                            Label(
                                L10n.string("Postpartum", defaultValue: "Postpartum"),
                                systemImage: "heart.fill"
                            )
                            Spacer()
                            Text(L10n.string("Postpartum", defaultValue: "Postpartum"))
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            showingPregnancyActivation = true
                        } label: {
                            Label(
                                L10n.string("Enter Pregnancy Mode", defaultValue: "Enter Pregnancy Mode"),
                                systemImage: "heart.fill"
                            )
                        }
                        .accessibilityIdentifier("settings.pregnancy.enter")

                        Button {
                            pregnancyViewModel?.returnToCycling(appState: appState)
                        } label: {
                            Label(
                                L10n.string("Return to Normal Tracking", defaultValue: "Return to Normal Tracking"),
                                systemImage: "arrow.counterclockwise"
                            )
                        }
                    }
                } header: {
                    Text(L10n.string("Pregnancy & Postpartum", defaultValue: "Pregnancy & Postpartum"))
                } footer: {
                    Group {
                        switch appState.lifecycleMode {
                        case .cycling:
                            Text(L10n.string(
                                "Pregnancy mode pauses cycle tracking and predictions while you're expecting. Your existing cycle data is preserved. When you're ready, postpartum mode helps you ease back into tracking as your cycles return.",
                                defaultValue: "Pregnancy mode pauses cycle tracking and predictions while you're expecting. Your existing cycle data is preserved. When you're ready, postpartum mode helps you ease back into tracking as your cycles return."
                            ))
                        case .pregnant:
                            Text(L10n.string(
                                "Cycle tracking and predictions are paused while pregnancy mode is active. Your previous cycle data is safe and will be used to improve predictions once you return to normal tracking.",
                                defaultValue: "Cycle tracking and predictions are paused while pregnancy mode is active. Your previous cycle data is safe and will be used to improve predictions once you return to normal tracking."
                            ))
                        case .postpartum:
                            Text(L10n.string(
                                "Your cycles may be irregular as your body recovers. Log your first period when it arrives to resume cycle tracking. CycleBalance will adapt its predictions as your cycles stabilize.",
                                defaultValue: "Your cycles may be irregular as your body recovers. Log your first period when it arrives to resume cycle tracking. CycleBalance will adapt its predictions as your cycles stabilize."
                            ))
                        }
                    }
                }

                Section(L10n.string("Language", defaultValue: "Language")) {
                    NavigationLink {
                        AppLanguageSelectionView(
                            selection: Binding(
                                get: { appState.selectedAppLanguage },
                                set: { appState.selectedAppLanguage = $0 }
                            )
                        )
                    } label: {
                        HStack {
                            Label(L10n.string("App Language", defaultValue: "App Language"), systemImage: "globe")
                            Spacer()
                            Text(appState.selectedAppLanguage.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings.app_language.row")

                    Text(
                        L10n.string(
                            "Language changes apply immediately. Some system surfaces update the next time they appear.",
                            defaultValue: "Language changes apply immediately. Some system surfaces update the next time they appear."
                        )
                    )
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.string("Display", defaultValue: "Display")) {
                    Toggle(isOn: Binding(
                        get: { appState.showScientificDetail },
                        set: { appState.showScientificDetail = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(L10n.string("Show Scientific Details", defaultValue: "Show Scientific Details"))
                            Text(L10n.string(
                                "Display confidence percentages, sample sizes, and statistical notation on insight cards.",
                                defaultValue: "Display confidence percentages, sample sizes, and statistical notation on insight cards."
                            ))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if appearancePreferences.experimentalThemeControlVisible {
                        Toggle(isOn: Binding(
                            get: { appearancePreferences.experimentalThemesEnabled },
                            set: { appearancePreferences.setExperimentalThemesEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                Text(L10n.string("Experimental Themes", defaultValue: "Experimental Themes"))
                                Text(L10n.string(
                                    "Unlock internal design lab themes like Lunar Calm for review before public release.",
                                    defaultValue: "Unlock internal design lab themes like Lunar Calm for review before public release."
                                ))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("settings.display.experimental_themes")
                    }

                    Picker(
                        L10n.string("Color Theme", defaultValue: "Color Theme"),
                        selection: Binding(
                            get: { appearancePreferences.themeOption },
                            set: { appearancePreferences.setThemeOption($0) }
                        )
                    ) {
                        ForEach(appearancePreferences.availableThemeOptions) { theme in
                            Text(theme.displayName)
                                .tag(theme)
                        }
                    }
                    .accessibilityIdentifier("settings.display.theme")

                    ThemePaletteSwatchRow(themeOption: appearancePreferences.themeOption)

                    Picker(
                        L10n.string("App Font", defaultValue: "App Font"),
                        selection: Binding(
                            get: { appearancePreferences.fontOption },
                            set: { appearancePreferences.setFontOption($0) }
                        )
                    ) {
                        ForEach(FontOption.allCases) { fontOption in
                            Text(fontOption.displayName)
                                .tag(fontOption)
                        }
                    }
                    .accessibilityIdentifier("settings.display.font")

                    ThemeDesignPreviewCard(themeOption: appearancePreferences.themeOption)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("settings.display.theme_preview")
                }

                Section(L10n.string("Privacy", defaultValue: "Privacy")) {
                    Toggle(
                        isOn: Binding(
                            get: { appLockManager.settings.isEnabled },
                            set: { appLockManager.setEnabled($0) }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(L10n.string("App Lock", defaultValue: "App Lock"))
                            Text(
                                L10n.string(
                                    "Require Face ID, Touch ID, or your device passcode after the app backgrounds.",
                                    defaultValue: "Require Face ID, Touch ID, or your device passcode after the app backgrounds."
                                )
                            )
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings.privacy.app_lock")

                    if MealScanFeatureFlags.current.enableMealScanV2 {
                        Toggle(isOn: $enableMealPhotoRetention) {
                            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                Text(L10n.string("Keep Saved Meal Photos", defaultValue: "Keep Saved Meal Photos"))
                                Text(L10n.string(
                                    "Meal estimate photos are stored locally only after you save the meal. Turn this off to save nutrition without keeping a photo.",
                                    defaultValue: "Meal estimate photos are stored locally only after you save the meal. Turn this off to save nutrition without keeping a photo."
                                ))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("settings.privacy.meal_scan_photo_retention")
                    }

                    if appLockManager.settings.isEnabled {
                        Picker(
                            L10n.string("Relock timing", defaultValue: "Relock timing"),
                            selection: Binding(
                                get: { appLockManager.settings.relockDelay },
                                set: { appLockManager.setRelockDelay($0) }
                            )
                        ) {
                            ForEach(AppLockRelockDelay.allCases) { delay in
                                Text(delay.displayName)
                                    .tag(delay)
                            }
                        }
                        .accessibilityIdentifier("settings.privacy.relock_delay")

                        if let errorMessage = appLockManager.lastAuthErrorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .appFont(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                let profilePhotoPickerTitle = profilePhotoData == nil
                    ? L10n.string("Choose Profile Photo", defaultValue: "Choose Profile Photo")
                    : L10n.string("Change Profile Photo", defaultValue: "Change Profile Photo")

                Section(L10n.string("Profile", defaultValue: "Profile")) {
                    HStack(spacing: AppTheme.spacing12) {
                        profilePhotoPreview

                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(L10n.string("Profile Photo", defaultValue: "Profile Photo"))
                                .appFont(.body, weight: .medium)
                            Text(
                                L10n.string(
                                    "Optional and stored only on this device.",
                                    defaultValue: "Optional and stored only on this device."
                                )
                            )
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, AppTheme.spacing4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.profile.photo_preview")

                    PhotosPicker(
                        selection: $selectedProfilePhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            profilePhotoPickerTitle,
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                    .accessibilityIdentifier("settings.profile.photo_picker")

                    if profilePhotoData != nil {
                        Button(role: .destructive) {
                            deleteProfilePhoto()
                        } label: {
                            Label(L10n.string("Remove Profile Photo", defaultValue: "Remove Profile Photo"), systemImage: "trash")
                        }
                        .accessibilityIdentifier("settings.profile.photo_delete")
                    }
                }

                Section(L10n.string("Data", defaultValue: "Data")) {
                    Button {
                        generateCSVExport()
                    } label: {
                        Label(L10n.string("Export Data (CSV)", defaultValue: "Export Data (CSV)"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("settings.export_csv")

                    Button {
                        generateJSONBackup()
                    } label: {
                        Label(L10n.string("Export Backup (JSON)", defaultValue: "Export Backup (JSON)"), systemImage: "tray.and.arrow.up")
                    }
                    .accessibilityIdentifier("settings.export_json_backup")

                    Button {
                        generateCSVTemplate()
                    } label: {
                        Label(L10n.string("Download CSV Template", defaultValue: "Download CSV Template"), systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("settings.download_csv_template")

                    Button {
                        showingCSVImportGuide = true
                    } label: {
                        Label(L10n.string("CSV Import Guide", defaultValue: "CSV Import Guide"), systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("settings.csv_import_guide")

                    Button {
                        triggerJSONBackupImport()
                    } label: {
                        Label(L10n.string("Import Backup (JSON)", defaultValue: "Import Backup (JSON)"), systemImage: "tray.and.arrow.down")
                    }
                    .accessibilityIdentifier("settings.import_json_backup")

                    Button {
                        triggerExternalCSVImport()
                    } label: {
                        Label(L10n.string("Import External Data (CSV)", defaultValue: "Import External Data (CSV)"), systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("settings.import_external_csv")

                    if let lastImportSummary {
                        importSummaryCard(lastImportSummary)
                    }

                    healthReportRow

                    NavigationLink {
                        FSAHSAResourcesView()
                    } label: {
                        HStack(alignment: .top, spacing: AppTheme.spacing12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .appFont(.body)
                                .foregroundStyle(.primary)
                                .frame(width: 22, alignment: .center)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                Text(L10n.string("FSA/HSA Tools", defaultValue: "FSA/HSA Tools"))
                                    .appFont(.body, weight: .medium)

                                Text(
                                    L10n.string(
                                        "Generate a Letter of Medical Necessity for FSA/HSA reimbursement of PCOS-related wellness expenses.",
                                        defaultValue: "Generate a Letter of Medical Necessity for FSA/HSA reimbursement of PCOS-related wellness expenses."
                                    )
                                )
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .accessibilityIdentifier("settings.fsa_hsa.row")

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Label(L10n.string("Delete All Data", defaultValue: "Delete All Data"), systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityIdentifier("settings.delete_all_data")
                }

#if DEBUG
                if showDebugSections {
                    Section("Debug: Demo Data") {
                        Text("Replaces existing data with realistic irregular-cycle demo scenarios.")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(DemoDataScenario.allCases) { scenario in
                            Button {
                                importDemoScenario(scenario)
                            } label: {
                                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                    Text("Load \(scenario.displayName)")
                                        .appFont(.subheadline, weight: .medium)
                                    Text(scenario.subtitle)
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let summary = debugTools.lastImportSummary {
                            importSummaryCard(summary)
                        }
                    }

                    Section("Debug: Premium QA") {
                        LabeledContent("Billing Backend", value: debugTools.billingBackend)
                        LabeledContent("Entitlement", value: debugTools.entitlementStatus)

                        if !debugTools.entitlementIDs.isEmpty {
                            LabeledContent("Product IDs", value: debugTools.entitlementIDs.joined(separator: ", "))
                        }

                        if let revenueCatAppUserID = debugTools.revenueCatAppUserID,
                           !revenueCatAppUserID.isEmpty {
                            LabeledContent("RevenueCat App User ID", value: revenueCatAppUserID)
                        }

                        if let statusMessage = debugTools.statusMessage {
                            Text(statusMessage)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let billingBackendWarning = debugTools.billingBackendWarning {
                            Text(billingBackendWarning)
                                .appFont(.caption)
                                .foregroundStyle(AppTheme.coralAccent)
                        }

                        Button {
                            Task {
                                await refreshPremiumDebugStatus()
                            }
                        } label: {
                            Label("Refresh Premium Status", systemImage: "arrow.clockwise")
                        }
                        .disabled(debugTools.isRefreshingPremiumStatus)

                        Button {
                            debugTools.showDebugPaywallSheet = true
                        } label: {
                            Label("Open Paywall", systemImage: "creditcard")
                        }
                    }

                    Section("Debug: Apple Ads Attribution") {
                        LabeledContent(
                            "Last Result",
                            value: debugTools.appleAdsDiagnostics.lastResult?.debugDisplayName
                                ?? String(localized: "Unknown", comment: "Fallback debug label when the Apple Ads attribution status is unavailable.")
                        )

                        if let lastAttemptedAt = debugTools.appleAdsDiagnostics.lastAttemptedAt {
                            LabeledContent("Last Attempt", value: appleAdsDebugTimestamp(lastAttemptedAt))
                        }

                        if let latestSuccessfulFetchedAt = debugTools.appleAdsDiagnostics.latestSuccessfulFetchedAt {
                            LabeledContent("Last Success", value: appleAdsDebugTimestamp(latestSuccessfulFetchedAt))
                        }

                        if let tokenPreview = debugTools.appleAdsDiagnostics.tokenPreview {
                            LabeledContent("Token Preview", value: tokenPreview)
                        }

                        if let lastErrorDescription = debugTools.appleAdsDiagnostics.lastErrorDescription,
                           !lastErrorDescription.isEmpty {
                            Text(lastErrorDescription)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            refreshAppleAdsDebugStatus()
                        } label: {
                            Label("Refresh Apple Ads Diagnostics", systemImage: "megaphone")
                        }
                        .disabled(debugTools.isRefreshingAppleAdsDiagnostics)
                    }
                }
#endif

                Section(L10n.string("Health", defaultValue: "Health")) {
                    NavigationLink {
                        HealthKitSettingsView()
                    } label: {
                        Label(L10n.string("HealthKit Access", defaultValue: "HealthKit Access"), systemImage: "heart.text.square")
                    }
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label(L10n.string("Notifications", defaultValue: "Notifications"), systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("settings.notifications.row")
                }

                Section(L10n.string("About", defaultValue: "About")) {
                    HStack {
                        Label(L10n.string("Version", defaultValue: "Version"), systemImage: "info.circle")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                            .foregroundStyle(.secondary)
                    }
#if DEBUG
                    .contentShape(Rectangle())
                    .onTapGesture {
                        debugTapCount += 1
                        if debugTapCount >= 7 && !showDebugSections {
                            showDebugSections = true
                        }
                    }
#endif
                    if let url = AppLinks.privacyPolicy {
                        Link(destination: url) {
                            Label(L10n.string("Privacy Policy", defaultValue: "Privacy Policy"), systemImage: "hand.raised")
                        }
                    }

                    if let url = AppLinks.termsOfService {
                        Link(destination: url) {
                            Label(L10n.string("Terms of Service", defaultValue: "Terms of Service"), systemImage: "doc.text")
                        }
                    }

                    if let url = AppLinks.feedbackMail {
                        Link(destination: url) {
                            Label(L10n.string("Get in Touch with the Dev Team ⚡!", defaultValue: "Get in Touch with the Dev Team ⚡!"), systemImage: "envelope")
                        }
                    }

                }

                Section {
                    VStack(alignment: .center, spacing: AppTheme.spacing4) {
                        Text("CycleBalance")
                            .appFont(.footnote, weight: .medium)
                        Text(
                            L10n.string(
                                "Not a medical device. Always consult your healthcare provider.",
                                defaultValue: "Not a medical device. Always consult your healthcare provider."
                            )
                        )
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.settings")
            .navigationTitle(AppTheme.usesImmersiveHomeShell ? "" : L10n.string("Settings", defaultValue: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(AppTheme.usesImmersiveHomeShell ? .hidden : .visible, for: .navigationBar)
            .scrollContentBackground(.hidden)
            .background(AppTheme.usesImmersiveHomeShell ? AppTheme.premiumEditorBackground : AppTheme.warmNeutral)
            .sensoryFeedback(.warning, trigger: showDeleteConfirmation)
            .sensoryFeedback(.success, trigger: deleteSuccessToggle)
            .sensoryFeedback(.success, trigger: exportSuccessToggle)
            .sensoryFeedback(.success, trigger: importSuccessToggle)
            .lunarSettingsItemPresentation(item: $importResult) { result in
                SettingsImportResultView(result: result)
            }
            .lunarSettingsPresentation(isPresented: $showingCSVImportGuide) {
                SettingsCSVImportGuideView()
            }
            .lunarSettingsPresentation(isPresented: $showingPrivateJournal) {
                DailyJournalEditorView()
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .csvImportGuide:
                    SettingsCSVImportGuideView()
                case .share(let payload):
                    SettingsActivityShareSheet(url: payload.url)
                }
            }
            .lunarSettingsPresentation(isPresented: $showingPregnancyActivation, onDismiss: {
                pregnancyViewModel?.loadData()
            }) {
                PregnancyActivationView()
            }
            .lunarSettingsPresentation(isPresented: $showingPregnancyEnd, onDismiss: {
                pregnancyViewModel?.loadData()
            }) {
                PregnancyEndView()
            }
            .fileImporter(
                isPresented: fileImportPresentationBinding,
                allowedContentTypes: activeFileImportRequest?.allowedContentTypes ?? SettingsFileImportRequest.jsonBackup.allowedContentTypes,
                allowsMultipleSelection: false,
                onCompletion: { result in
                    let request = activeFileImportRequest
                    activeFileImportRequest = nil

                    guard let request else {
                        return
                    }

                    switch result {
                    case .success(let urls):
                        guard let selectedURL = urls.first else { return }
                        handleImportedFileURL(selectedURL, for: request)
                    case .failure(let error):
                        handleFileImportError(error, for: request)
                    }
                },
                onCancellation: {
                    activeFileImportRequest = nil
                }
            )
            .alert(L10n.string("Operation Failed", defaultValue: "Operation Failed"), isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button(L10n.string("OK", defaultValue: "OK"), role: .cancel) {}
            } message: {
                Text(operationError ?? L10n.string("An unknown error occurred.", defaultValue: "An unknown error occurred."))
            }
            .alert(L10n.string("Replace Existing Data?", defaultValue: "Replace Existing Data?"), isPresented: $showImportConfirmation) {
                Button(L10n.string("Import Backup", defaultValue: "Import Backup"), role: .destructive) {
                    confirmPendingJSONImport()
                }
                Button(L10n.string("Cancel", defaultValue: "Cancel"), role: .cancel) {
                    pendingJSONImportSource = nil
                }
            } message: {
                Text(L10n.string("Importing a backup will replace all existing app data.", defaultValue: "Importing a backup will replace all existing app data."))
            }
            .alert(L10n.string("Delete All Data?", defaultValue: "Delete All Data?"), isPresented: $showDeleteConfirmation) {
                Button(L10n.string("Delete Everything", defaultValue: "Delete Everything"), role: .destructive) {
                    deleteAllData()
                }
                Button(L10n.string("Cancel", defaultValue: "Cancel"), role: .cancel) {}
            } message: {
                Text(
                    L10n.string(
                        "This will permanently delete all your cycle data, symptoms, and insights. This action cannot be undone.",
                        defaultValue: "This will permanently delete all your cycle data, symptoms, and insights. This action cannot be undone."
                    )
                )
            }
            .onAppear {
                if pregnancyViewModel == nil {
                    pregnancyViewModel = PregnancyViewModel(modelContext: modelContext)
                    pregnancyViewModel?.loadData()
                }
                loadProfilePhoto()
                configureLunarReminderState()
            }
            .onChange(of: selectedProfilePhotoItem) { _, newItem in
                Task {
                    await importSelectedProfilePhoto(from: newItem)
                }
            }
#if DEBUG
            .sheet(isPresented: Binding(
                get: { debugTools.showDebugPaywallSheet },
                set: { debugTools.showDebugPaywallSheet = $0 }
            )) {
                PaywallView()
            }
            .onAppear {
                debugTools.primePremiumStatus(appState: appState)
            }
#endif
        }
    }

    private var lunarSupportOverview: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    HStack(spacing: AppTheme.spacing8) {
                        Text(L10n.string("You've got this", defaultValue: "You've got this"))
                            .appHeadingFont(.title2, weight: .regular)
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)

                        Image(systemName: "sparkle")
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
                            .accessibilityHidden(true)
                    }

                    Text(L10n.string("Small steps. Big difference.", defaultValue: "Small steps. Big difference."))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacing8)

                ZStack {
                    Circle()
                        .fill(AppTheme.premiumEditorAccentGradient)
                    Image(systemName: "moon.stars.fill")
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                }
                .frame(width: 52, height: 52)
                .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.22), radius: 16, y: 8)
                .accessibilityHidden(true)
            }

            lunarReminderPanel
            lunarDailyCheckInPanel
            lunarPrivateNotesPanel
            lunarEncouragementPanel
        }
        .padding(.horizontal, AppTheme.spacing16)
        .padding(.top, AppTheme.spacing4)
        .padding(.bottom, AppTheme.spacing8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.lunar.support_overview")
    }

    private var lunarReminderPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(L10n.string("Reminders", defaultValue: "Reminders"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            lunarReminderRow(
                title: L10n.string("Log your symptoms", defaultValue: "Log your symptoms"),
                subtitle: L10n.string("Daily reminder", defaultValue: "Daily reminder"),
                timeLabel: lunarSymptomReminderTimeText,
                systemImage: "bell.fill",
                tint: AppTheme.premiumEditorSecondaryAccentColor,
                isOn: Binding(
                    get: { lunarSymptomReminderEnabled },
                    set: { setLunarReminder(.symptoms, enabled: $0) }
                ),
                accessibilityIdentifier: "settings.lunar.reminder.symptoms"
            )

            lunarReminderRow(
                title: L10n.string("Period predictions", defaultValue: "Period predictions"),
                subtitle: L10n.string("Two days before", defaultValue: "Two days before"),
                timeLabel: L10n.string("Adaptive", defaultValue: "Adaptive"),
                systemImage: "calendar.badge.clock",
                tint: AppTheme.premiumEditorWarningAccentColor,
                isOn: Binding(
                    get: { lunarPeriodReminderEnabled },
                    set: { setLunarReminder(.period, enabled: $0) }
                ),
                accessibilityIdentifier: "settings.lunar.reminder.period"
            )

            lunarReminderRow(
                title: L10n.string("Supplements", defaultValue: "Supplements"),
                subtitle: L10n.string("Use your saved schedule", defaultValue: "Use your saved schedule"),
                timeLabel: L10n.string("On device", defaultValue: "On device"),
                systemImage: "drop.fill",
                tint: AppTheme.premiumEditorAccentColor,
                isOn: Binding(
                    get: { lunarSupplementReminderEnabled },
                    set: { setLunarReminder(.supplements, enabled: $0) }
                ),
                accessibilityIdentifier: "settings.lunar.reminder.supplements"
            )
        }
        .padding(AppTheme.spacing12)
        .lunarSettingsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.lunar.reminders")
    }

    private var lunarDailyCheckInPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("Daily check-in", defaultValue: "Daily check-in"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.string("Your check-in helps improve your insights.", defaultValue: "Your check-in helps improve your insights."))
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: AppTheme.spacing8) {
                ForEach(LunarSettingsMood.allCases) { mood in
                    Button {
                        lunarCheckInMood = mood
                    } label: {
                        VStack(spacing: AppTheme.spacing8) {
                            Image(systemName: mood.systemImage)
                                .appFont(.subheadline, weight: .semibold)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(mood.tint)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(mood.tint.opacity(mood == lunarCheckInMood ? 0.24 : 0.14)))
                                .overlay(Circle().stroke(mood.tint.opacity(mood == lunarCheckInMood ? 0.52 : 0), lineWidth: 0.8))

                            Text(mood.title)
                                .appFont(.caption2, weight: mood == lunarCheckInMood ? .semibold : .regular)
                                .foregroundStyle(mood == lunarCheckInMood ? AppTheme.primaryText : AppTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mood.title)
                    .accessibilityAddTraits(mood == lunarCheckInMood ? .isSelected : [])
                    .accessibilityIdentifier("settings.lunar.mood.\(mood.rawValue)")
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarSettingsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.lunar.daily_checkin")
    }

    private var lunarPrivateNotesPanel: some View {
        Button {
            showingPrivateJournal = true
        } label: {
            HStack(spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(L10n.string("Your space", defaultValue: "Your space"))
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(L10n.string("Write freely, reflect, and release.", defaultValue: "Write freely, reflect, and release."))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacing8)

                Image(systemName: "pencil.and.scribble")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.76)))
                    .overlay(Circle().stroke(AppTheme.premiumEditorBorder.opacity(0.48), lineWidth: 0.8))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .padding(AppTheme.spacing12)
        .lunarSettingsCard()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("settings.lunar.private_notes.open")
    }

    private var lunarEncouragementPanel: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: "heart.fill")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                .frame(width: 40, height: 40)
                .background(Circle().fill(AppTheme.premiumEditorWarningAccentColor.opacity(0.16)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("Your feelings are valid.", defaultValue: "Your feelings are valid."))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.string("You are not alone.", defaultValue: "You are not alone."))
                    .appFont(.subheadline, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.string("We're here for you, always.", defaultValue: "We're here for you, always."))
                    .appFont(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppTheme.spacing8)
        .lunarSettingsCard()
        .overlay(alignment: .bottomTrailing) {
            SettingsLunarWaveMark()
                .frame(width: 142, height: 62)
                .opacity(0.76)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.lunar.support_card")
    }

    private var lunarSymptomReminderTimeText: String {
        let manager = lunarNotificationManager ?? NotificationManager()
        let formatter = DateFormatter()
        formatter.locale = L10n.locale()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: manager.symptomReminderTime)
    }

    private func lunarReminderRow(
        title: String,
        subtitle: String,
        timeLabel: String,
        systemImage: String,
        tint: Color,
        isOn: Binding<Bool>,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: systemImage)
                .appFont(.headline, weight: .semibold)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(0.16)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(title)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Text(L10n.format("%@, %@", defaultValue: "%@, %@", subtitle, timeLabel))
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: AppTheme.spacing8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppTheme.premiumEditorAccentColor)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder.opacity(0.48), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private var profilePhotoPreview: some View {
        ZStack {
            Circle()
                .fill(AppTheme.groupedBackground)

            if profilePhotoIsMasked {
                Image(systemName: "lock.fill")
                    .appFont(.title2, weight: .semibold)
                    .foregroundStyle(.secondary)
            } else if let profilePhotoData, let image = UIImage(data: profilePhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary.opacity(0.6))
                    .padding(AppTheme.spacing8)
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var profilePhotoIsMasked: Bool {
        profilePhotoStore.shouldMaskProfilePhoto(
            isAppLockEnabled: appLockManager.settings.isEnabled,
            isContentMasked: appLockManager.shouldMaskContent(for: scenePhase)
        )
    }

    private func loadProfilePhoto() {
        do {
            profilePhotoData = try profilePhotoStore.loadProfilePhoto()
        } catch {
            operationError = String(
                localized: "Could not load profile photo: \(error.localizedDescription)",
                comment: "Error shown when the local profile photo cannot be loaded."
            )
        }
    }

    private func importSelectedProfilePhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                operationError = L10n.string(
                    "Could not import profile photo.",
                    defaultValue: "Could not import profile photo."
                )
                return
            }

            try profilePhotoStore.saveProfilePhoto(data)
            profilePhotoData = data
            selectedProfilePhotoItem = nil
        } catch {
            operationError = String(
                localized: "Could not import profile photo: \(error.localizedDescription)",
                comment: "Error shown when profile photo import fails."
            )
        }
    }

    private func deleteProfilePhoto() {
        do {
            try profilePhotoStore.deleteProfilePhoto()
            profilePhotoData = nil
        } catch {
            operationError = String(
                localized: "Could not remove profile photo: \(error.localizedDescription)",
                comment: "Error shown when the local profile photo cannot be removed."
            )
        }
    }

    private func configureLunarReminderState() {
        let manager = lunarNotificationManager ?? NotificationManager()
        lunarPeriodReminderEnabled = manager.periodRemindersEnabled
        lunarSymptomReminderEnabled = manager.symptomRemindersEnabled
        lunarSupplementReminderEnabled = manager.supplementRemindersEnabled
        lunarNotificationManager = manager
    }

    private func setLunarReminder(_ kind: LunarReminderKind, enabled: Bool) {
        let manager = lunarNotificationManager ?? NotificationManager()
        lunarNotificationManager = manager

        switch kind {
        case .period:
            lunarPeriodReminderEnabled = enabled
            manager.periodRemindersEnabled = enabled
            if !enabled {
                manager.cancelReminders(withPrefix: "period.")
            }
        case .symptoms:
            lunarSymptomReminderEnabled = enabled
            manager.symptomRemindersEnabled = enabled
            if enabled {
                manager.scheduleSymptomLoggingReminder()
            } else {
                manager.cancelReminders(withPrefix: "symptom.")
            }
        case .supplements:
            lunarSupplementReminderEnabled = enabled
            manager.supplementRemindersEnabled = enabled
            if !enabled {
                manager.cancelReminders(withPrefix: "supplement.")
            }
        }
    }

    @ViewBuilder
    private func importSummaryCard(_ summary: SettingsDataImportService.ImportSummary) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text(L10n.string("Last Import", defaultValue: "Last Import"))
                .appFont(.caption, weight: .semibold)
            Text(importSummaryTitle(summary))
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Text(importSummaryDetail(summary))
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Text(summary.importedAt.formatted(date: .abbreviated, time: .shortened))
                .appFont(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, AppTheme.spacing4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.import_summary")
    }

    private func importSummaryTitle(_ summary: SettingsDataImportService.ImportSummary) -> String {
        switch summary.channel {
        case .externalCSV:
            L10n.string("External CSV Import", defaultValue: "External CSV Import")
        case .jsonBackup(_, let source):
            switch source.kind {
            case .demoScenario:
                L10n.string("Demo Data Import", defaultValue: "Demo Data Import")
            case .userExport:
                L10n.string("JSON Backup Import", defaultValue: "JSON Backup Import")
            }
        }
    }

    private func importSummaryDetail(_ summary: SettingsDataImportService.ImportSummary) -> String {
        switch summary.channel {
        case .externalCSV:
            if summary.changeCounts.rejected > 0 {
                return L10n.format(
                    "%lld inserted • %lld updated • %lld skipped • %lld rejected",
                    defaultValue: "%lld inserted • %lld updated • %lld skipped • %lld rejected",
                    summary.changeCounts.inserted,
                    summary.changeCounts.updated,
                    summary.changeCounts.skipped,
                    summary.changeCounts.rejected
                )
            }

            return L10n.format(
                "%lld inserted • %lld updated • %lld skipped",
                defaultValue: "%lld inserted • %lld updated • %lld skipped",
                summary.changeCounts.inserted,
                summary.changeCounts.updated,
                summary.changeCounts.skipped
            )
        case .jsonBackup(let schemaVersion, _):
            if summary.changeCounts.rejected > 0 {
                return L10n.format(
                    "%lld imported • %lld rejected • schema v%lld",
                    defaultValue: "%lld imported • %lld rejected • schema v%lld",
                    summary.counts.total,
                    summary.changeCounts.rejected,
                    schemaVersion
                )
            }

            return L10n.format(
                "%lld records • schema v%lld",
                defaultValue: "%lld records • schema v%lld",
                summary.counts.total,
                schemaVersion
            )
        }
    }

    private func generateCSVExport() {
        do {
            let service = SettingsDataExportService(modelContext: modelContext)
            let url = try service.generateCSVExport()
            presentShareSheet(for: url, kind: .csvExport)
            exportSuccessToggle.toggle()
        } catch {
            operationError = String(
                localized: "Could not create CSV export: \(error.localizedDescription)",
                comment: "Error shown when CSV export generation fails."
            )
        }
    }

    private func generateJSONBackup() {
        do {
            let service = SettingsDataBackupService(modelContext: modelContext)
            let url = try service.generateJSONBackup()
            presentShareSheet(for: url, kind: .jsonBackup)
#if DEBUG
            debugTools.jsonBackupURL = url
#endif
            exportSuccessToggle.toggle()
        } catch {
            operationError = String(
                localized: "Could not create JSON backup: \(error.localizedDescription)",
                comment: "Error shown when JSON backup generation fails."
            )
        }
    }

    private func generateCSVTemplate() {
        do {
            let service = SettingsExternalDataCSVService(modelContext: modelContext)
            let url = try service.generateTemplate()
            presentShareSheet(for: url, kind: .csvTemplate)
            exportSuccessToggle.toggle()
        } catch {
            operationError = String(
                localized: "Could not create CSV template: \(error.localizedDescription)",
                comment: "Error shown when external CSV template generation fails."
            )
        }
    }

    private func presentShareSheet(for url: URL, kind: PendingSharePayload.Kind) {
        activeSheet = .share(PendingSharePayload(kind: kind, url: url))
    }

    private func triggerJSONBackupImport() {
#if DEBUG
        if let fixtureData = uiTestJSONBackupFixtureData() {
            pendingJSONImportSource = .data(fixtureData)
            showImportConfirmation = true
            return
        }
#endif
        activeFileImportRequest = .jsonBackup
    }

    private func confirmPendingJSONImport() {
        guard let pendingJSONImportSource else {
            return
        }

        defer {
            self.pendingJSONImportSource = nil
        }

        switch pendingJSONImportSource {
        case .url(let url):
            importBackup(from: url)
        case .data(let data):
            importBackup(data: data)
        }
    }

    private func importBackup(from url: URL) {
        let didAccessScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let service = SettingsDataImportService(modelContext: modelContext)
            let summary = try service.importJSONBackup(from: url)
            handleImportSummary(summary)
        } catch {
            handleBackupImportError(error)
        }
    }

    private func importBackup(data: Data) {
        do {
            let service = SettingsDataImportService(modelContext: modelContext)
            let summary = try service.importJSONBackup(data: data)
            handleImportSummary(summary)
        } catch {
            handleBackupImportError(error)
        }
    }

    private func triggerExternalCSVImport() {
#if DEBUG
        if let fixtureData = uiTestCSVFixtureData() {
            importExternalCSV(data: fixtureData)
            return
        }
#endif
        activeFileImportRequest = .externalCSV
    }

    private var fileImportPresentationBinding: Binding<Bool> {
        Binding(
            get: { activeFileImportRequest != nil },
            set: { _ in
                // Cleanup happens in onCompletion/onCancellation so the active request
                // is still available when the file importer callback runs.
            }
        )
    }

    private func handleImportedFileURL(_ url: URL, for request: SettingsFileImportRequest) {
        switch request {
        case .jsonBackup:
            pendingJSONImportSource = .url(url)
            showImportConfirmation = true
        case .externalCSV:
            importExternalCSV(from: url)
        }
    }

    private func handleFileImportError(_ error: Error, for request: SettingsFileImportRequest) {
        switch request {
        case .jsonBackup:
            operationError = String(
                localized: "Could not open backup: \(error.localizedDescription)",
                comment: "Error shown when the user selects an unreadable backup file."
            )
        case .externalCSV:
            operationError = String(
                localized: "Could not open external CSV: \(error.localizedDescription)",
                comment: "Error shown when the user selects an unreadable external CSV file."
            )
        }
    }

    private func importExternalCSV(from url: URL) {
        let didAccessScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let service = SettingsExternalDataCSVService(modelContext: modelContext)
            let summary = try service.importCSV(from: url)
            handleImportSummary(summary)
        } catch {
            handleExternalCSVImportError(error)
        }
    }

    private func importExternalCSV(data: Data) {
        do {
            let service = SettingsExternalDataCSVService(modelContext: modelContext)
            let summary = try service.importCSV(data: data)
            handleImportSummary(summary)
        } catch {
            handleExternalCSVImportError(error)
        }
    }

    private func recordImport(_ summary: SettingsDataImportService.ImportSummary) {
        lastImportSummary = summary
#if DEBUG
        debugTools.lastImportSummary = summary
#endif
    }

    private func handleImportSummary(_ summary: SettingsDataImportService.ImportSummary) {
        if summary.changeCounts.successful > 0 || !summary.hasIssues {
            recordImport(summary)
        }

        if summary.hasIssues {
            importResult = makeImportResultPresentation(from: summary)
        } else {
            importSuccessToggle.toggle()
        }
    }

    private func handleBackupImportError(_ error: Error) {
        if let error = error as? SettingsDataImportService.ImportError {
            importResult = makeImportFailurePresentation(
                title: L10n.string("Import Failed", defaultValue: "Import Failed"),
                summary: L10n.string(
                    "No records were imported because the backup could not be validated.",
                    defaultValue: "No records were imported because the backup could not be validated."
                ),
                channelTitle: L10n.string("JSON Backup Import", defaultValue: "JSON Backup Import"),
                issues: [SettingsDataImportService.ImportIssue(location: nil, reason: error.errorDescription ?? error.localizedDescription)]
            )
            return
        }

        operationError = (error as? LocalizedError)?.errorDescription ?? String(
            localized: "Could not import backup: \(error.localizedDescription)",
            comment: "Fallback error shown when importing a JSON backup fails."
        )
    }

    private func handleExternalCSVImportError(_ error: Error) {
        if let error = error as? SettingsExternalDataCSVService.ImportError {
            importResult = makeImportFailurePresentation(
                title: L10n.string("Import Failed", defaultValue: "Import Failed"),
                summary: L10n.string(
                    "No records were imported because the CSV file could not be validated.",
                    defaultValue: "No records were imported because the CSV file could not be validated."
                ),
                channelTitle: L10n.string("External CSV Import", defaultValue: "External CSV Import"),
                issues: [error.importIssue]
            )
            return
        }

        operationError = (error as? LocalizedError)?.errorDescription ?? String(
            localized: "Could not import external CSV: \(error.localizedDescription)",
            comment: "Fallback error shown when importing an external CSV file fails."
        )
    }

    private func makeImportResultPresentation(
        from summary: SettingsDataImportService.ImportSummary
    ) -> ImportResultPresentation {
        let importedRecords = summary.changeCounts.successful
        let rejectedRecords = summary.changeCounts.rejected

        if importedRecords > 0 {
            return ImportResultPresentation(
                title: L10n.string("Import Completed with Issues", defaultValue: "Import Completed with Issues"),
                summary: L10n.format(
                    "%lld records were applied. %lld records need attention.",
                    defaultValue: "%lld records were applied. %lld records need attention.",
                    importedRecords,
                    rejectedRecords
                ),
                channelTitle: importSummaryTitle(summary),
                changeCounts: summary.changeCounts,
                issues: summary.issues
            )
        }

        return makeImportFailurePresentation(
            title: L10n.string("Import Failed", defaultValue: "Import Failed"),
            summary: L10n.format(
                "No records were imported. %lld records need attention.",
                defaultValue: "No records were imported. %lld records need attention.",
                rejectedRecords
            ),
            channelTitle: importSummaryTitle(summary),
            issues: summary.issues,
            changeCounts: summary.changeCounts
        )
    }

    private func makeImportFailurePresentation(
        title: String,
        summary: String,
        channelTitle: String,
        issues: [SettingsDataImportService.ImportIssue],
        changeCounts: SettingsDataImportService.ImportChangeCounts = .init()
    ) -> ImportResultPresentation {
        ImportResultPresentation(
            title: title,
            summary: summary,
            channelTitle: channelTitle,
            changeCounts: changeCounts,
            issues: issues
        )
    }

    private func undoPregnancyActivation() {
        guard let pregnancyViewModel else { return }
        do {
            try pregnancyViewModel.undoActivation(appState: appState)
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func deleteAllData() {
        do {
            let service = SettingsDataDeletionService(modelContext: modelContext)
            try service.deleteAllData()
            deleteSuccessToggle.toggle()
        } catch {
            Logger.database.error("Failed to delete all data: \(error.localizedDescription)")
            operationError = String(
                localized: "Failed to delete data: \(error.localizedDescription)",
                comment: "Error shown when deleting all app data fails."
            )
        }
    }

#if DEBUG
    private func importDemoScenario(_ scenario: DemoDataScenario) {
        do {
            let backup = DemoDataBuilder().makeBackup(for: scenario)
            let service = SettingsDataImportService(modelContext: modelContext)
            let summary = try service.replaceAll(with: backup)
            lastImportSummary = summary
            debugTools.lastImportSummary = summary

            appState.onboardingProfile.resetOnboarding()
            scenario.applyOnboardingDefaults(to: appState.onboardingProfile)
            appState.hasCompletedOnboarding = true

            importSuccessToggle.toggle()
        } catch {
            operationError = (error as? LocalizedError)?.errorDescription ?? String(
                localized: "Could not import demo data: \(error.localizedDescription)",
                comment: "Fallback error shown when loading a debug demo scenario fails."
            )
        }
    }

    private func refreshPremiumDebugStatus() async {
        await debugTools.refreshPremiumStatus(appState: appState)
    }

    private func refreshAppleAdsDebugStatus() {
        debugTools.refreshAppleAdsDiagnostics()
    }

    private func appleAdsDebugTimestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func uiTestJSONBackupFixtureData() -> Data? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("UITestMode") else {
            return nil
        }

        guard let rawValue = launchArgumentValue(for: "settings.jsonImportFixture", in: arguments) else {
            return nil
        }

        return SettingsDataImportService.uiTestFixture(named: rawValue)
    }

    private func uiTestCSVFixtureData() -> Data? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("UITestMode") else {
            return nil
        }

        guard let rawValue = launchArgumentValue(for: "settings.csvImportFixture", in: arguments) else {
            return nil
        }

        return SettingsExternalDataCSVService.uiTestFixture(named: rawValue)
    }

    private func launchArgumentValue(for key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-\(key)") else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }

        return arguments[valueIndex]
    }
#endif
}

private struct ThemePaletteSwatchRow: View {
    let themeOption: ThemeOption

    private var palette: ThemePalette {
        themeOption.palette
    }

    private var colors: [Color] {
        var baseColors = [
            palette.accent.color,
            palette.sage.color,
            palette.coral.color,
            palette.warmNeutralLight.color,
            palette.flowSpottingLight.color,
            palette.flowLightLight.color,
            palette.flowMediumLight.color,
            palette.flowHeavyLight.color,
        ]
        if themeOption == .botanicalJournal {
            baseColors.insert(AppTheme.botanicalLavenderRGB.color, at: 3)
            baseColors.append(AppTheme.botanicalGoldRGB.color)
        } else if themeOption == .lunarCalm {
            baseColors.insert(AppTheme.lunarCalmPeachRGB.color, at: 3)
            baseColors.append(AppTheme.lunarCalmGoldRGB.color)
        }
        return baseColors
    }

    var body: some View {
        HStack(spacing: AppTheme.spacing8) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .fill(color)
                    .frame(height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .padding(.vertical, AppTheme.spacing4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.format(
                "%@ palette preview",
                defaultValue: "%@ palette preview",
                themeOption.displayName
            )
        )
        .accessibilityIdentifier("settings.display.theme_swatch")
    }
}

private struct ThemeDesignPreviewCard: View {
    let themeOption: ThemeOption

    private var palette: ThemePalette {
        themeOption.palette
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                        .fill(previewGradient)

                    Image(systemName: themeOption.previewSystemImage)
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(iconForegroundColor)
                        .accessibilityHidden(true)
                }
                .frame(width: 54, height: 54)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(themeOption.displayName)
                        .appHeadingFont(.title3, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(themeOption.previewSubtitle)
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: AppTheme.spacing8) {
                ForEach(themeOption.previewTraits, id: \.self) { trait in
                    Text(trait)
                        .appFont(.caption2, weight: .semibold)
                        .foregroundStyle(traitForegroundColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, AppTheme.spacing8)
                        .padding(.vertical, AppTheme.spacing4)
                        .background(
                            Capsule()
                                .fill(traitFillColor)
                        )
                }
            }

            Text(L10n.string(
                "Theme and font changes apply across the app right away. PDF exports keep their current report styling.",
                defaultValue: "Theme and font changes apply across the app right away. PDF exports keep their current report styling."
            ))
            .appFont(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AppTheme.spacing8)
        .cardStyle(cornerRadius: AppTheme.largeCardCornerRadius)
    }

    private var previewGradient: LinearGradient {
        LinearGradient(
            colors: [
                palette.accent.color,
                palette.sage.color,
                palette.coral.color,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconForegroundColor: Color {
        themeOption == .lunarCalm
            ? AppTheme.lunarCalmBackgroundRGB.color
            : palette.warmNeutralLight.color
    }

    private var traitForegroundColor: Color {
        themeOption == .lunarCalm ? AppTheme.lunarCalmTealRGB.color : AppTheme.accentColor
    }

    private var traitFillColor: Color {
        themeOption == .lunarCalm
            ? AppTheme.lunarCalmTealRGB.color.opacity(0.12)
            : AppTheme.accentColor.opacity(AppTheme.opacitySubtle)
    }
}

private extension ThemeOption {
    var previewSystemImage: String {
        switch self {
        case .botanicalJournal:
            "leaf.fill"
        case .lunarCalm:
            "moon.stars.fill"
        case .sage:
            "checkmark.seal.fill"
        case .sunrise:
            "sunrise.fill"
        case .ocean:
            "water.waves"
        case .botanicalMist:
            "camera.macro"
        case .blushMoonrise:
            "sparkles"
        case .fruitGrove:
            "circle.grid.2x2.fill"
        case .highContrast:
            "circle.lefthalf.filled"
        }
    }

    var previewSubtitle: String {
        switch self {
        case .botanicalJournal:
            L10n.string("Warm cream paper, watercolor botanicals, and editorial serif headings.", defaultValue: "Warm cream paper, watercolor botanicals, and editorial serif headings.")
        case .lunarCalm:
            L10n.string("Moonlit cards, true-dark contrast, gentle gradients, and quiet review language.", defaultValue: "Moonlit cards, true-dark contrast, gentle gradients, and quiet review language.")
        case .sage:
            L10n.string("Calm clinical greens with crisp structure for daily health review.", defaultValue: "Calm clinical greens with crisp structure for daily health review.")
        case .sunrise:
            L10n.string("Sun-warmed clay tones for grounded morning planning and reflection.", defaultValue: "Sun-warmed clay tones for grounded morning planning and reflection.")
        case .ocean:
            L10n.string("Clear tidepool blues for scan-friendly tracking, charts, and trends.", defaultValue: "Clear tidepool blues for scan-friendly tracking, charts, and trends.")
        case .botanicalMist:
            L10n.string("Soft botanical neutrals with enough definition for dense health inputs.", defaultValue: "Soft botanical neutrals with enough definition for dense health inputs.")
        case .blushMoonrise:
            L10n.string("Polished blush and teal contrast for expressive, reassuring check-ins.", defaultValue: "Polished blush and teal contrast for expressive, reassuring check-ins.")
        case .fruitGrove:
            L10n.string("Fresh grove tones that make frequent logging feel lighter and more energetic.", defaultValue: "Fresh grove tones that make frequent logging feel lighter and more energetic.")
        case .highContrast:
            L10n.string("Sharper separation, stronger borders, and direct hierarchy for readability.", defaultValue: "Sharper separation, stronger borders, and direct hierarchy for readability.")
        }
    }

    var previewTraits: [String] {
        switch self {
        case .botanicalJournal:
            [L10n.string("Editorial", defaultValue: "Editorial"), L10n.string("Soft", defaultValue: "Soft"), L10n.string("Reflective", defaultValue: "Reflective")]
        case .lunarCalm:
            [L10n.string("True dark", defaultValue: "True dark"), L10n.string("Glassy", defaultValue: "Glassy"), L10n.string("Calm", defaultValue: "Calm")]
        case .sage:
            [L10n.string("Grounded", defaultValue: "Grounded"), L10n.string("Clinical", defaultValue: "Clinical"), L10n.string("Quiet", defaultValue: "Quiet")]
        case .sunrise:
            [L10n.string("Warm", defaultValue: "Warm"), L10n.string("Steady", defaultValue: "Steady"), L10n.string("Morning", defaultValue: "Morning")]
        case .ocean:
            [L10n.string("Clear", defaultValue: "Clear"), L10n.string("Analytical", defaultValue: "Analytical"), L10n.string("Cool", defaultValue: "Cool")]
        case .botanicalMist:
            [L10n.string("Airy", defaultValue: "Airy"), L10n.string("Natural", defaultValue: "Natural"), L10n.string("Refined", defaultValue: "Refined")]
        case .blushMoonrise:
            [L10n.string("Polished", defaultValue: "Polished"), L10n.string("Expressive", defaultValue: "Expressive"), L10n.string("Gentle", defaultValue: "Gentle")]
        case .fruitGrove:
            [L10n.string("Fresh", defaultValue: "Fresh"), L10n.string("Bright", defaultValue: "Bright"), L10n.string("Quick", defaultValue: "Quick")]
        case .highContrast:
            [L10n.string("Readable", defaultValue: "Readable"), L10n.string("Precise", defaultValue: "Precise"), L10n.string("Direct", defaultValue: "Direct")]
        }
    }
}

private extension View {
    @ViewBuilder
    func lunarSettingsPresentation<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if AppTheme.usesImmersivePresentation {
            fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        } else {
            sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        }
    }

    @ViewBuilder
    func lunarSettingsItemPresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        if AppTheme.usesImmersivePresentation {
            fullScreenCover(item: item, content: content)
        } else {
            sheet(item: item, content: content)
        }
    }

    @ViewBuilder
    func lunarSettingsSecondaryNavigation() -> some View {
        if AppTheme.usesImmersivePresentation {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    func lunarSettingsCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.premiumEditorRaisedSurface.opacity(0.92),
                            AppTheme.premiumEditorSurface.opacity(0.78),
                            AppTheme.premiumEditorBackground.opacity(0.9),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.8)
                .opacity(0.72)
        )
        .shadow(color: AppTheme.cardShadowColor, radius: 14, y: 8)
    }
}

private struct SettingsLunarWaveMark: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            WaveBand(offsetY: 14, color: AppTheme.accentColor)
            WaveBand(offsetY: 3, color: AppTheme.premiumEditorAccentColor)
            WaveBand(offsetY: -8, color: AppTheme.premiumEditorSecondaryAccentColor)
        }
        .mask(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .padding(.leading, 16)
        )
    }

    private struct WaveBand: View {
        let offsetY: CGFloat
        let color: Color

        var body: some View {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 62))
                path.addCurve(
                    to: CGPoint(x: 142, y: 30 + offsetY),
                    control1: CGPoint(x: 36, y: 32 + offsetY),
                    control2: CGPoint(x: 86, y: 4 + offsetY)
                )
                path.addLine(to: CGPoint(x: 142, y: 62))
                path.closeSubpath()
            }
            .fill(color.opacity(0.68))
        }
    }
}

extension SettingsView {
    @ViewBuilder
    fileprivate var healthReportRow: some View {
        NavigationLink {
            ReportConfigView()
        } label: {
            HStack {
                Label(
                    L10n.string("Export Health Report PDF", defaultValue: "Export Health Report PDF"),
                    systemImage: "doc.richtext"
                )
                Spacer()
                if !appState.allowsPremiumAccess {
                    Text(L10n.string("1 free export", defaultValue: "1 free export"))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("settings.health_report.row")
    }
}

private struct SettingsImportResultView: View {
    @Environment(\.dismiss) private var dismiss

    let result: SettingsView.ImportResultPresentation

    private var visibleIssues: [SettingsDataImportService.ImportIssue] {
        Array(result.issues.prefix(5))
    }

    private var hiddenIssueCount: Int {
        max(result.issues.count - visibleIssues.count, 0)
    }

    var body: some View {
        NavigationStack {
            Group {
                if AppTheme.usesImmersivePresentation {
                    lunarImportResultContent
                } else {
                    standardImportResultList
                }
            }
            .navigationTitle(result.title)
            .navigationBarTitleDisplayMode(AppTheme.usesImmersivePresentation ? .inline : .automatic)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Done", defaultValue: "Done")) {
                        dismiss()
                    }
                }
            }
            .lunarSettingsSecondaryNavigation()
        }
    }

    private var standardImportResultList: some View {
        List {
            Section {
                Text(result.channelTitle)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                Text(result.summary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L10n.string("Import Counts", defaultValue: "Import Counts")) {
                LabeledContent(L10n.string("Inserted", defaultValue: "Inserted"), value: String(result.changeCounts.inserted))
                LabeledContent(L10n.string("Updated", defaultValue: "Updated"), value: String(result.changeCounts.updated))
                LabeledContent(L10n.string("Skipped", defaultValue: "Skipped"), value: String(result.changeCounts.skipped))
                LabeledContent(L10n.string("Rejected", defaultValue: "Rejected"), value: String(result.changeCounts.rejected))
            }

            Section(L10n.string("Example Issues", defaultValue: "Example Issues")) {
                ForEach(Array(visibleIssues.enumerated()), id: \.offset) { _, issue in
                    Text(issue.message)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if hiddenIssueCount > 0 {
                    Text(
                        L10n.format(
                            "And %lld more issues...",
                            defaultValue: "And %lld more issues...",
                            hiddenIssueCount
                        )
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("screen.settings.import_result")
    }

    private var lunarImportResultContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                lunarImportHeader
                lunarImportCountsCard

                if !visibleIssues.isEmpty {
                    lunarImportIssuesCard
                }
            }
            .padding(AppTheme.spacing16)
            .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.premiumEditorBackground.ignoresSafeArea())
        .tint(AppTheme.premiumEditorAccentColor)
        .accessibilityIdentifier("screen.settings.import_result")
    }

    private var lunarImportHeader: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: visibleIssues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(visibleIssues.isEmpty ? AppTheme.premiumEditorAccentColor : AppTheme.premiumEditorSecondaryAccentColor)
                .frame(width: 42, height: 42)
                .background(Circle().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.78)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(result.channelTitle)
                    .appFont(.caption, weight: .semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)
                Text(result.summary)
                    .appFont(.body)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing12)
        .lunarSettingsCard()
        .accessibilityIdentifier("settings.import_result.lunar.header")
    }

    private var lunarImportCountsCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(L10n.string("Import Counts", defaultValue: "Import Counts"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.spacing8) {
                ForEach(Array(lunarImportCounts.enumerated()), id: \.offset) { _, count in
                    lunarImportCountCell(count)
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarSettingsCard()
        .accessibilityIdentifier("settings.import_result.lunar.counts")
    }

    private var lunarImportIssuesCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(L10n.string("Example Issues", defaultValue: "Example Issues"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            ForEach(Array(visibleIssues.enumerated()), id: \.offset) { _, issue in
                Text(issue.message)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(AppTheme.spacing8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.premiumEditorSurface.opacity(0.72))
                    )
            }

            if hiddenIssueCount > 0 {
                Text(
                    L10n.format(
                        "And %lld more issues...",
                        defaultValue: "And %lld more issues...",
                        hiddenIssueCount
                    )
                )
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(AppTheme.spacing12)
        .lunarSettingsCard()
        .accessibilityIdentifier("settings.import_result.lunar.issues")
    }

    private var lunarImportCounts: [(title: String, value: Int, tint: Color)] {
        [
            (L10n.string("Inserted", defaultValue: "Inserted"), result.changeCounts.inserted, AppTheme.premiumEditorAccentColor),
            (L10n.string("Updated", defaultValue: "Updated"), result.changeCounts.updated, AppTheme.lavenderAccent),
            (L10n.string("Skipped", defaultValue: "Skipped"), result.changeCounts.skipped, AppTheme.premiumEditorSecondaryAccentColor),
            (L10n.string("Rejected", defaultValue: "Rejected"), result.changeCounts.rejected, AppTheme.premiumEditorWarningAccentColor),
        ]
    }

    private func lunarImportCountCell(_ count: (title: String, value: Int, tint: Color)) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text(count.title)
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            Text(String(count.value))
                .appHeadingFont(.title2, weight: .regular)
                .foregroundStyle(count.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(count.tint.opacity(0.28), lineWidth: 0.8)
        )
    }
}

private struct SettingsCSVImportGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if AppTheme.usesImmersivePresentation {
                    lunarGuideContent
                } else {
                    standardGuideList
                }
            }
            .navigationTitle(L10n.string("CSV Import Guide", defaultValue: "CSV Import Guide"))
            .navigationBarTitleDisplayMode(AppTheme.usesImmersivePresentation ? .inline : .automatic)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Done", defaultValue: "Done")) {
                        dismiss()
                    }
                }
            }
            .lunarSettingsSecondaryNavigation()
        }
    }

    private var standardGuideList: some View {
        List {
            Section {
                Text(
                    L10n.string(
                        "Use the CSV template for imports. Each row must set record_type, and unused columns can be left blank.",
                        defaultValue: "Use the CSV template for imports. Each row must set record_type, and unused columns can be left blank."
                    )
                )
                Text(
                    L10n.string(
                        "Export Data (CSV) creates a readable report. Import External Data (CSV) expects the template columns shown here.",
                        defaultValue: "Export Data (CSV) creates a readable report. Import External Data (CSV) expects the template columns shown here."
                    )
                )
                .foregroundStyle(.secondary)
            }
            .appFont(.caption)

            Section(L10n.string("Supported Record Types", defaultValue: "Supported Record Types")) {
                Text(verbatim: SettingsExternalCSVSchema.RecordType.allCases.map(\.rawValue).joined(separator: ", "))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section(L10n.string("Format Rules", defaultValue: "Format Rules")) {
                ForEach(SettingsExternalCSVSchema.formatRules) { rule in
                    Text(L10n.string(rule.key, defaultValue: rule.defaultValue))
                        .appFont(.caption)
                }
            }

            ForEach(SettingsExternalCSVSchema.recordDefinitions) { definition in
                Section {
                    fieldsBlock(
                        title: L10n.string("Required fields", defaultValue: "Required fields"),
                        value: definition.requiredFields.map(\.rawValue).joined(separator: ", ")
                    )
                    fieldsBlock(
                        title: L10n.string("Optional fields", defaultValue: "Optional fields"),
                        value: definition.optionalFields.map(\.rawValue).joined(separator: ", ")
                    )

                    let acceptedValueColumns = definition.acceptedValueColumns.filter { $0 != .recordType }
                    if !acceptedValueColumns.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(L10n.string("Accepted values", defaultValue: "Accepted values"))
                                .appFont(.caption, weight: .semibold)

                            ForEach(acceptedValueColumns, id: \.self) { column in
                                if let values = SettingsExternalCSVSchema.acceptedValues(for: column) {
                                    Text(verbatim: "\(column.rawValue): \(values.joined(separator: ", "))")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    if
                        let noteKey = definition.noteKey,
                        let noteDefaultValue = definition.noteDefaultValue
                    {
                        Text(L10n.string(noteKey, defaultValue: noteDefaultValue))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(verbatim: definition.type.rawValue)
                        .font(.subheadline.monospaced())
                }
            }
        }
        .accessibilityIdentifier("screen.settings.csv_import_guide")
    }

    private var lunarGuideContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                lunarGuideIntro
                lunarSupportedTypesCard
                lunarFormatRulesCard

                ForEach(SettingsExternalCSVSchema.recordDefinitions) { definition in
                    lunarRecordDefinitionCard(definition)
                }
            }
            .padding(AppTheme.spacing16)
            .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.premiumEditorBackground.ignoresSafeArea())
        .tint(AppTheme.premiumEditorAccentColor)
        .accessibilityIdentifier("screen.settings.csv_import_guide")
    }

    private var lunarGuideIntro: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: "tablecells.badge.ellipsis")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                .frame(width: 42, height: 42)
                .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("Prepare a clean import", defaultValue: "Prepare a clean import"))
                    .appHeadingFont(.title3, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                Text(
                    L10n.string(
                        "Use the CSV template for imports. Each row must set record_type, and unused columns can be left blank.",
                        defaultValue: "Use the CSV template for imports. Each row must set record_type, and unused columns can be left blank."
                    )
                )
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                Text(
                    L10n.string(
                        "Export Data (CSV) creates a readable report. Import External Data (CSV) expects the template columns shown here.",
                        defaultValue: "Export Data (CSV) creates a readable report. Import External Data (CSV) expects the template columns shown here."
                    )
                )
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing12)
        .lunarSettingsCard()
        .accessibilityIdentifier("settings.csv_guide.lunar.intro")
    }

    private var lunarSupportedTypesCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(L10n.string("Supported Record Types", defaultValue: "Supported Record Types"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
            Text(verbatim: SettingsExternalCSVSchema.RecordType.allCases.map(\.rawValue).joined(separator: ", "))
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.premiumEditorAccentColor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(AppTheme.spacing12)
        .lunarSettingsCard()
        .accessibilityIdentifier("settings.csv_guide.lunar.types")
    }

    private var lunarFormatRulesCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(L10n.string("Format Rules", defaultValue: "Format Rules"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            ForEach(SettingsExternalCSVSchema.formatRules) { rule in
                Label {
                    Text(L10n.string(rule.key, defaultValue: rule.defaultValue))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarSettingsCard()
        .accessibilityIdentifier("settings.csv_guide.lunar.rules")
    }

    private func lunarRecordDefinitionCard(_ definition: SettingsExternalCSVSchema.RecordDefinition) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(verbatim: definition.type.rawValue)
                .font(.subheadline.monospaced().weight(.semibold))
                .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)

            lunarFieldsBlock(
                title: L10n.string("Required fields", defaultValue: "Required fields"),
                value: definition.requiredFields.map(\.rawValue).joined(separator: ", ")
            )
            lunarFieldsBlock(
                title: L10n.string("Optional fields", defaultValue: "Optional fields"),
                value: definition.optionalFields.map(\.rawValue).joined(separator: ", ")
            )

            let acceptedValueColumns = definition.acceptedValueColumns.filter { $0 != .recordType }
            if !acceptedValueColumns.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(L10n.string("Accepted values", defaultValue: "Accepted values"))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)

                    ForEach(acceptedValueColumns, id: \.self) { column in
                        if let values = SettingsExternalCSVSchema.acceptedValues(for: column) {
                            Text(verbatim: "\(column.rawValue): \(values.joined(separator: ", "))")
                                .font(.caption.monospaced())
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if
                let noteKey = definition.noteKey,
                let noteDefaultValue = definition.noteDefaultValue
            {
                Text(L10n.string(noteKey, defaultValue: noteDefaultValue))
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing12)
        .lunarSettingsCard()
    }

    @ViewBuilder
    private func fieldsBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text(title)
                .appFont(.caption, weight: .semibold)
            Text(verbatim: value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func lunarFieldsBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text(title)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
            Text(verbatim: value)
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.premiumEditorSurface.opacity(0.72))
        )
    }
}

private struct SettingsActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct DailyJournalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDate = Date()
    @State private var noteText = ""
    @State private var currentPainLevel0To10: Int?
    @State private var saveError: String?
    @State private var savedToggle = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Text(L10n.string("Your space", defaultValue: "Your space"))
                            .appHeadingFont(.title2, weight: .regular)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(prompt)
                            .appFont(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DatePicker(
                        L10n.string("Journal date", defaultValue: "Journal date"),
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("journal.date")

                    TextEditor(text: $noteText)
                        .appFont(.body)
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(minHeight: 220)
                        .scrollContentBackground(.hidden)
                        .padding(AppTheme.spacing12)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                                .fill(AppTheme.usesImmersivePresentation ? AppTheme.premiumEditorRaisedSurface.opacity(0.78) : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                                .stroke(AppTheme.usesImmersivePresentation ? AppTheme.premiumEditorBorder.opacity(0.6) : AppTheme.cardBorder, lineWidth: 0.8)
                        )
                        .accessibilityIdentifier("journal.private_note")

                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .appFont(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button {
                        save()
                    } label: {
                        Text(L10n.string("Save journal entry", defaultValue: "Save journal entry"))
                            .appFont(.headline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.spacing12)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                                    .fill(AppTheme.usesImmersivePresentation ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.accentColor))
                            )
                            .foregroundStyle(AppTheme.usesImmersivePresentation ? AppTheme.premiumEditorCTAForeground : .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("journal.save")
                }
                .padding(AppTheme.spacing16)
                .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
            }
            .background(AppTheme.usesImmersivePresentation ? AppTheme.premiumEditorBackground.ignoresSafeArea() : AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(L10n.string("Journal", defaultValue: "Journal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Done", defaultValue: "Done")) {
                        dismiss()
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: savedToggle)
        .onAppear(perform: loadEntry)
        .onChange(of: selectedDate) { _, _ in
            loadEntry()
        }
    }

    private var prompt: String {
        L10n.string("What do you need today? Write freely, reflect, and release.", defaultValue: "What do you need today? Write freely, reflect, and release.")
    }

    private func loadEntry() {
        do {
            let log = try DailyLogService(modelContext: modelContext).fetchLog(on: selectedDate)
            noteText = log?.privateNote ?? ""
            currentPainLevel0To10 = log?.painLevel0To10
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func save() {
        do {
            try DailyLogService(modelContext: modelContext).saveDailyCheckIn(
                date: selectedDate,
                painLevel0To10: currentPainLevel0To10,
                privateNote: noteText
            )
            savedToggle.toggle()
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct AppLanguageSelectionView: View {
    @Binding var selection: AppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if AppTheme.usesImmersivePresentation {
                lunarLanguageContent
            } else {
                standardLanguageList
            }
        }
        .navigationTitle(L10n.string("App Language", defaultValue: "App Language"))
        .navigationBarTitleDisplayMode(AppTheme.usesImmersivePresentation ? .inline : .automatic)
        .lunarSettingsSecondaryNavigation()
    }

    private var standardLanguageList: some View {
        List {
            ForEach(AppLanguage.allCases) { language in
                languageButton(for: language)
            }
        }
        .accessibilityIdentifier("screen.settings.app_language")
    }

    private var lunarLanguageContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                HStack(alignment: .top, spacing: AppTheme.spacing12) {
                    Image(systemName: "globe")
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Text(L10n.string("Choose your app language", defaultValue: "Choose your app language"))
                            .appHeadingFont(.title3, weight: .regular)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(
                            L10n.string(
                                "Language changes apply immediately. Some system surfaces update the next time they appear.",
                                defaultValue: "Language changes apply immediately. Some system surfaces update the next time they appear."
                            )
                        )
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(AppTheme.spacing12)
                .lunarSettingsCard()
                .accessibilityIdentifier("settings.app_language.lunar.header")

                VStack(spacing: AppTheme.spacing8) {
                    ForEach(AppLanguage.allCases) { language in
                        languageButton(for: language)
                            .padding(AppTheme.spacing12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.premiumEditorRaisedSurface.opacity(selection == language ? 0.94 : 0.72))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        selection == language
                                        ? AppTheme.premiumEditorBorderGradient
                                        : LinearGradient(
                                            colors: [AppTheme.premiumEditorBorder.opacity(0.52)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 0.9
                                    )
                            )
                    }
                }
            }
            .padding(AppTheme.spacing16)
            .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
        }
        .background(AppTheme.premiumEditorBackground.ignoresSafeArea())
        .tint(AppTheme.premiumEditorAccentColor)
        .accessibilityIdentifier("screen.settings.app_language")
    }

    private func languageButton(for language: AppLanguage) -> some View {
        Button {
            selection = language
            dismiss()
        } label: {
            HStack(spacing: AppTheme.spacing12) {
                Text(language.displayName)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer()
                if selection == language {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppTheme.usesImmersivePresentation ? AppTheme.premiumEditorAccentColor : AppTheme.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.app_language.option.\(language.rawValue)")
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .environment(AppLockManager())
        .environment(AppearancePreferences.shared)
}
