import StoreKit
import SwiftUI
import SwiftData
import UIKit

struct ReportConfigView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Environment(AppState.self) private var appState
    @Environment(ReportAccessPolicy.self) private var reportAccessPolicy
    @State private var viewModel: ReportViewModel?
    @State private var reportGenerated = false
    @State private var sectionToggleHaptic = false
    @State private var sharePayload: SharePayload?

    private enum ActiveAlert: Identifiable {
        case error(String)

        var id: String {
            switch self {
            case .error: "error"
            }
        }
    }

    private struct SharePayload: Identifiable {
        let id = UUID()
        let url: URL
    }

    @State private var activeAlert: ActiveAlert?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    reportForm(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(localized("Export PDF", defaultValue: "Export PDF"))
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .error(let message):
                    return Alert(
                        title: Text(localized("Report Error", defaultValue: "Report Error")),
                        message: Text(message),
                        dismissButton: .cancel(Text(localized("OK", defaultValue: "OK")))
                    )
                }
            }
            .sheet(item: $sharePayload) { payload in
                ReportActivityShareSheet(url: payload.url)
            }
            .sensoryFeedback(.success, trigger: reportGenerated)
            .onAppear {
                if viewModel == nil {
                    viewModel = ReportViewModel(modelContext: modelContext)
                }
                reportAccessPolicy.markReportOpened()
            }
        }
    }

    // MARK: - Report Form

    @ViewBuilder
    private func reportForm(viewModel: ReportViewModel) -> some View {
        let hasSelectedData = viewModel.hasDataForSelectedSections

        List {
            // Date Range
            Section {
                DatePicker(
                    selection: Bindable(viewModel).startDate,
                    in: ...viewModel.endDate,
                    displayedComponents: .date
                ) {
                    Text(localized("Start Date", defaultValue: "Start Date"))
                        .fixedSize(horizontal: false, vertical: true)
                }

                DatePicker(
                    selection: Bindable(viewModel).endDate,
                    in: viewModel.startDate...,
                    displayedComponents: .date
                ) {
                    Text(localized("End Date", defaultValue: "End Date"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(localized("Date Range", defaultValue: "Date Range"))
            }

            // Presets
            Section {
                Button {
                    applyPreset(.full, viewModel: viewModel)
                } label: {
                    HStack(alignment: .top, spacing: AppTheme.spacing8) {
                        Image(systemName: "doc.richtext")
                        Text(localized("Full Report", defaultValue: "Full Report"))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if isFullReport(viewModel) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppTheme.accentColor)
                        }
                    }
                }

                Button {
                    applyPreset(.quick, viewModel: viewModel)
                } label: {
                    HStack(alignment: .top, spacing: AppTheme.spacing8) {
                        Image(systemName: "doc.text")
                        Text(localized("Quick Summary", defaultValue: "Quick Summary"))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if isQuickSummary(viewModel) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppTheme.accentColor)
                        }
                    }
                }
            } header: {
                Text(localized("Presets", defaultValue: "Presets"))
            } footer: {
                Text(localized(
                    "Quick Summary includes cycles, symptoms, and insights only.",
                    defaultValue: "Quick Summary includes cycles, symptoms, and insights only."
                ))
                .fixedSize(horizontal: false, vertical: true)
            }

            // Section Toggles
            Section {
                Toggle(isOn: Bindable(viewModel).includeCycles) {
                    Text(localized("Cycles", defaultValue: "Cycles"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: Bindable(viewModel).includeSymptoms) {
                    Text(localized("Symptoms", defaultValue: "Symptoms"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: Bindable(viewModel).includeBloodSugar) {
                    Text(localized("Blood Sugar", defaultValue: "Blood Sugar"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: Bindable(viewModel).includeSupplements) {
                    Text(localized("Supplements", defaultValue: "Supplements"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: Bindable(viewModel).includeMeals) {
                    Text(localized("Meals", defaultValue: "Meals"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: Bindable(viewModel).includeWeightTrend) {
                    Text(localized("Weight Trend", defaultValue: "Weight Trend"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: Bindable(viewModel).includeHairPhotos) {
                    Text(localized("Hair Photo Grid", defaultValue: "Hair Photo Grid"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: Bindable(viewModel).includeInsights) {
                    Text(localized("Insights", defaultValue: "Insights"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: Bindable(viewModel).includePregnancy) {
                    Text(localized("Pregnancy", defaultValue: "Pregnancy"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(localized("Customize Sections", defaultValue: "Customize Sections"))
            }
            .onChange(of: viewModel.includeCycles) { _, _ in sectionToggleHaptic.toggle() }
            .onChange(of: viewModel.includeSymptoms) { _, _ in sectionToggleHaptic.toggle() }
            .onChange(of: viewModel.includeBloodSugar) { _, _ in sectionToggleHaptic.toggle() }
            .onChange(of: viewModel.includeSupplements) { _, _ in sectionToggleHaptic.toggle() }
            .onChange(of: viewModel.includeMeals) { _, _ in sectionToggleHaptic.toggle() }
            .onChange(of: viewModel.includeWeightTrend) { _, _ in sectionToggleHaptic.toggle() }
            .onChange(of: viewModel.includeHairPhotos) { _, _ in sectionToggleHaptic.toggle() }
            .onChange(of: viewModel.includeInsights) { _, _ in sectionToggleHaptic.toggle() }
            .onChange(of: viewModel.includePregnancy) { _, _ in sectionToggleHaptic.toggle() }

            if viewModel.includeHairPhotos {
                Section {
                    Picker(
                        localized("Comparison Format", defaultValue: "Comparison Format"),
                        selection: Bindable(viewModel).photoComparisonStyle
                    ) {
                        ForEach(ComparisonPhotoPresentationStyle.allCases) { style in
                            Text(comparisonStyleLabel(style))
                                .tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("report.photo_comparison_style")
                } header: {
                    Text(localized("Photo Comparison Format", defaultValue: "Photo Comparison Format"))
                } footer: {
                    Text(comparisonStyleDescription(viewModel.photoComparisonStyle))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !hasSelectedData {
                Section {
                    VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                        Label(
                            localized("No report data in this range", defaultValue: "No report data in this range"),
                            systemImage: "doc.text.magnifyingglass"
                        )
                        .appFont(.headline)
                        .foregroundStyle(.primary)

                        Text(
                            localized(
                                "Choose a wider date range or include sections with logged data before exporting.",
                                defaultValue: "Choose a wider date range or include sections with logged data before exporting."
                            )
                        )
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Button {
                            useLastNinetyDays(viewModel: viewModel)
                        } label: {
                            Label(
                                localized("Use Last 90 Days", defaultValue: "Use Last 90 Days"),
                                systemImage: "calendar.badge.clock"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.sage)
                        .accessibilityIdentifier("report.empty_range.expand_range")
                    }
                    .padding(.vertical, AppTheme.spacing4)
                }
                .accessibilityIdentifier("report.empty_range")
            }

            // Generate / Share
            Section {
                if !appState.allowsPremiumAccess {
                    Text(freeExportMessage)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.isGenerating {
                    HStack(spacing: AppTheme.spacing12) {
                        ProgressView()
                        Text(localized("Generating report...", defaultValue: "Generating report..."))
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Button {
                        exportReport(viewModel: viewModel)
                    } label: {
                        HStack(alignment: .top, spacing: AppTheme.spacing8) {
                            Image(systemName: "square.and.arrow.up")
                            Text(localized("Export PDF", defaultValue: "Export PDF"))
                                .appFont(.headline)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.spacing16)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(AppTheme.coralAccent))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasSelectedData)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("report.export")

                    if viewModel.hasGeneratedReport {
                        Text(
                            viewModel.hasPendingConfigurationChanges
                                ? localized(
                                    "Your report settings changed. Export PDF to generate a fresh file before sharing.",
                                    defaultValue: "Your report settings changed. Export PDF to generate a fresh file before sharing."
                                )
                                : localized(
                                    "Your latest PDF is ready to share again without generating a new file.",
                                    defaultValue: "Your latest PDF is ready to share again without generating a new file."
                                )
                        )
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if viewModel.hasGeneratedReport || viewModel.hasPendingConfigurationChanges {
                        Button {
                            regenerateReport(viewModel: viewModel)
                        } label: {
                            HStack(alignment: .top, spacing: AppTheme.spacing8) {
                                Image(systemName: "arrow.clockwise")
                                Text(localized("Regenerate Report", defaultValue: "Regenerate Report"))
                                    .appFont(.subheadline)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tint(AppTheme.sage)
                        .disabled(!hasSelectedData)
                        .accessibilityIdentifier("report.regenerate")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .tint(AppTheme.sage)
        .sensoryFeedback(.selection, trigger: sectionToggleHaptic)
        .accessibilityIdentifier("screen.report_config")
    }

    // MARK: - Presets

    private enum ReportPreset {
        case full, quick
    }

    private func applyPreset(_ preset: ReportPreset, viewModel: ReportViewModel) {
        switch preset {
        case .full:
            viewModel.includeCycles = true
            viewModel.includeSymptoms = true
            viewModel.includeBloodSugar = true
            viewModel.includeSupplements = true
            viewModel.includeMeals = true
            viewModel.includeWeightTrend = true
            viewModel.includeHairPhotos = true
            viewModel.includeInsights = true
            viewModel.includePregnancy = true
        case .quick:
            viewModel.includeCycles = true
            viewModel.includeSymptoms = true
            viewModel.includeBloodSugar = false
            viewModel.includeSupplements = false
            viewModel.includeMeals = false
            viewModel.includeWeightTrend = false
            viewModel.includeHairPhotos = false
            viewModel.includeInsights = true
            viewModel.includePregnancy = false
        }
        sectionToggleHaptic.toggle()
    }

    private func isFullReport(_ viewModel: ReportViewModel) -> Bool {
        viewModel.includeCycles && viewModel.includeSymptoms &&
        viewModel.includeBloodSugar && viewModel.includeSupplements &&
        viewModel.includeMeals && viewModel.includeWeightTrend &&
        viewModel.includeHairPhotos && viewModel.includeInsights &&
        viewModel.includePregnancy
    }

    private func isQuickSummary(_ viewModel: ReportViewModel) -> Bool {
        viewModel.includeCycles && viewModel.includeSymptoms && viewModel.includeInsights &&
        !viewModel.includeBloodSugar && !viewModel.includeSupplements &&
        !viewModel.includeMeals && !viewModel.includeWeightTrend && !viewModel.includeHairPhotos
    }

    // MARK: - Actions

    private func exportReport(viewModel: ReportViewModel) {
        guard viewModel.hasDataForSelectedSections else {
            activeAlert = .error(emptyRangeExportMessage)
            return
        }

        if let cachedURL = viewModel.generatedPDFURL, !viewModel.hasPendingConfigurationChanges {
            sharePayload = SharePayload(url: cachedURL)
            return
        }

        guard reportAccessPolicy.canGenerateReport(isPremium: appState.allowsPremiumAccess) else {
            appState.presentPremiumPaywall()
            return
        }

        Task {
            let exportResult = await viewModel.prepareExport(appLanguage: language)
            if let error = viewModel.errorMessage {
                activeAlert = .error(error)
                return
            }

            guard let exportResult else { return }

            switch exportResult {
            case .existing(let url):
                sharePayload = SharePayload(url: url)
            case .generated(let url):
                reportAccessPolicy.consumeFreeExportIfNeeded(isPremium: appState.allowsPremiumAccess)
                reportGenerated.toggle()
                sharePayload = SharePayload(url: url)
                ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, requestReview: requestReview)
            }
        }
    }

    private func regenerateReport(viewModel: ReportViewModel) {
        guard viewModel.hasDataForSelectedSections else {
            activeAlert = .error(emptyRangeExportMessage)
            return
        }

        guard reportAccessPolicy.canGenerateReport(isPremium: appState.allowsPremiumAccess) else {
            appState.presentPremiumPaywall()
            return
        }

        Task {
            await viewModel.generateReport(appLanguage: language)
            if let error = viewModel.errorMessage {
                activeAlert = .error(error)
            } else if viewModel.generatedPDFURL != nil {
                reportAccessPolicy.consumeFreeExportIfNeeded(isPremium: appState.allowsPremiumAccess)
                reportGenerated.toggle()
                ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, requestReview: requestReview)
            }
        }
    }

    private func useLastNinetyDays(viewModel: ReportViewModel) {
        let endDate = Date()
        viewModel.endDate = endDate
        viewModel.startDate = Calendar.current.date(byAdding: .day, value: -90, to: endDate) ?? endDate
        sectionToggleHaptic.toggle()
    }

    private var language: AppLanguage {
        appState.selectedAppLanguage
    }

    private var freeExportMessage: String {
        if reportAccessPolicy.hasConsumedFreeExport {
            return localized(
                "Your first free PDF export has already been used. Upgrade to Premium for unlimited report exports.",
                defaultValue: "Your first free PDF export has already been used. Upgrade to Premium for unlimited report exports."
            )
        }

        return localized(
            "Your first PDF export is free. After that, report exports require Premium.",
            defaultValue: "Your first PDF export is free. After that, report exports require Premium."
        )
    }

    private var emptyRangeExportMessage: String {
        localized(
            "No selected report sections have data in this date range. Choose a wider range or include sections with logged data before exporting.",
            defaultValue: "No selected report sections have data in this date range. Choose a wider range or include sections with logged data before exporting."
        )
    }

    private func localized(_ key: String, defaultValue: String? = nil) -> String {
        L10n.string(key, defaultValue: defaultValue, language: language)
    }

    private func comparisonStyleLabel(_ style: ComparisonPhotoPresentationStyle) -> String {
        switch style {
        case .standard:
            localized("Standard", defaultValue: "Standard")
        case .clinical:
            localized("Clinical", defaultValue: "Clinical")
        }
    }

    private func comparisonStyleDescription(_ style: ComparisonPhotoPresentationStyle) -> String {
        switch style {
        case .standard:
            localized(
                "Standard keeps a more compact side-by-side layout for export.",
                defaultValue: "Standard keeps a more compact side-by-side layout for export."
            )
        case .clinical:
            localized(
                "Clinical uses larger aspect-fit slots with clearer spacing for healthcare review.",
                defaultValue: "Clinical uses larger aspect-fit slots with clearer spacing for healthcare review."
            )
        }
    }
}

private struct ReportActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ReportConfigView()
        .modelContainer(
            for: [
                Cycle.self,
                SymptomEntry.self,
                BloodSugarReading.self,
                SupplementLog.self,
                MealEntry.self,
                DailyLog.self,
                HairPhotoEntry.self,
                Insight.self,
            ],
            inMemory: true
        )
        .environment(AppState())
        .environment(ReportAccessPolicy())
}
