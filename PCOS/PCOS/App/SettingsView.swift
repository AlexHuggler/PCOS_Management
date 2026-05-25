import SwiftUI
import SwiftData
import UniformTypeIdentifiers
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

    @State private var showDeleteConfirmation = false
    @State private var pendingJSONImportSource: PendingJSONImportSource?
    @State private var activeFileImportRequest: SettingsFileImportRequest?
    @State private var activeSheet: SettingsSheet?
    @State private var importResult: ImportResultPresentation?
    @State private var showImportConfirmation = false
    @State private var lastImportSummary: SettingsDataImportService.ImportSummary?
    @State private var operationError: String?
    @State private var deleteSuccessToggle = false
    @State private var exportSuccessToggle = false
    @State private var importSuccessToggle = false
    @State private var showingPregnancyActivation = false
    @State private var showingPregnancyEnd = false
    @State private var pregnancyViewModel: PregnancyViewModel?

#if DEBUG
    @State private var debugTools = SettingsDebugToolsState()
    @State private var debugTapCount = 0
    @State private var showDebugSections = false
#endif

    var body: some View {
        NavigationStack {
            List {
                if appState.showsSubscriptionUI {
                    Section(L10n.string("Account", defaultValue: "Account")) {
                        NavigationLink {
                            PaywallView()
                        } label: {
                            HStack {
                                Label(L10n.string("Subscription", defaultValue: "Subscription"), systemImage: "star.circle")
                                Spacer()
                                Text(
                                    appState.isPremium
                                        ? L10n.string("Premium", defaultValue: "Premium")
                                        : L10n.string("Free", defaultValue: "Free")
                                )
                                    .foregroundStyle(.secondary)
                            }
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

                    Picker(
                        L10n.string("Color Theme", defaultValue: "Color Theme"),
                        selection: Binding(
                            get: { appearancePreferences.themeOption },
                            set: { appearancePreferences.setThemeOption($0) }
                        )
                    ) {
                        ForEach(ThemeOption.allCases) { theme in
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

                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        if appearancePreferences.themeOption == .botanicalJournal {
                            BotanicalPosterHeader(
                                title: L10n.string("Botanical Journal", defaultValue: "Botanical Journal"),
                                subtitle: L10n.string("Warm cream paper, watercolor botanicals, and Cormorant Garamond headings.", defaultValue: "Warm cream paper, watercolor botanicals, and Cormorant Garamond headings."),
                                dividerStyle: .ornamental
                            )
                            .padding(.vertical, AppTheme.spacing8)
                            .cardStyle(cornerRadius: AppTheme.largeCardCornerRadius)
                        } else {
                            Text(L10n.string("Preview", defaultValue: "Preview"))
                                .appHeadingFont(.headline, weight: .regular)
                                .foregroundStyle(AppTheme.primaryText)
                        }
                        Text(L10n.string(
                            "Theme and font changes apply across the app right away. PDF exports keep their current report styling.",
                            defaultValue: "Theme and font changes apply across the app right away. PDF exports keep their current report styling."
                        ))
                            .appFont(.subheadline)
                        Text(appearancePreferences.themeOption.isHighContrast
                             ? L10n.string("High-contrast mode uses stronger color separation for readability.", defaultValue: "High-contrast mode uses stronger color separation for readability.")
                             : L10n.string("Choose the palette that feels most like yours.", defaultValue: "Choose the palette that feels most like yours."))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, AppTheme.spacing8)
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
                        activeSheet = .csvImportGuide
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
                    Link(destination: URL(string: "https://cyclebalance.app/privacy")!) {
                        Label(L10n.string("Privacy Policy", defaultValue: "Privacy Policy"), systemImage: "hand.raised")
                    }

                    Link(destination: URL(string: "https://cyclebalance.app/terms")!) {
                        Label(L10n.string("Terms of Service", defaultValue: "Terms of Service"), systemImage: "doc.text")
                    }

                    Link(destination: URL(string: "mailto:feedback@cyclebalance.app")!) {
                        Label(L10n.string("Get in Touch with the Dev Team ⚡!", defaultValue: "Get in Touch with the Dev Team ⚡!"), systemImage: "envelope")
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
            .navigationTitle(L10n.string("Settings", defaultValue: "Settings"))
            .scrollContentBackground(.hidden)
            .background(AppTheme.warmNeutral)
            .sensoryFeedback(.warning, trigger: showDeleteConfirmation)
            .sensoryFeedback(.success, trigger: deleteSuccessToggle)
            .sensoryFeedback(.success, trigger: exportSuccessToggle)
            .sensoryFeedback(.success, trigger: importSuccessToggle)
            .sheet(item: $importResult) { result in
                SettingsImportResultView(result: result)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .csvImportGuide:
                    SettingsCSVImportGuideView()
                case .share(let payload):
                    SettingsActivityShareSheet(url: payload.url)
                }
            }
            .sheet(isPresented: $showingPregnancyActivation, onDismiss: {
                pregnancyViewModel?.loadData()
            }) {
                PregnancyActivationView()
            }
            .sheet(isPresented: $showingPregnancyEnd, onDismiss: {
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
            .navigationTitle(result.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Done", defaultValue: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct SettingsCSVImportGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
            .navigationTitle(L10n.string("CSV Import Guide", defaultValue: "CSV Import Guide"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Done", defaultValue: "Done")) {
                        dismiss()
                    }
                }
            }
        }
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
}

private struct SettingsActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct AppLanguageSelectionView: View {
    @Binding var selection: AppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    selection = language
                    dismiss()
                } label: {
                    HStack {
                        Text(language.displayName)
                        Spacer()
                        if selection == language {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppTheme.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.app_language.option.\(language.rawValue)")
            }
        }
        .navigationTitle(L10n.string("App Language", defaultValue: "App Language"))
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .environment(AppLockManager())
        .environment(AppearancePreferences.shared)
}
