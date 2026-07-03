import StoreKit
import SwiftUI
import SwiftData
import UIKit

struct ReportConfigView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
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
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : localized("Export PDF", defaultValue: "Export PDF"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(localized("Close", defaultValue: "Close"))
                    }
                    ToolbarItem(placement: .principal) {
                        Text(localized("Export PDF", defaultValue: "Export PDF"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }
            }
            .lunarReportNavigationBackground()
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
        if AppTheme.usesPremiumEditorStyling {
            lunarReportForm(viewModel: viewModel)
        } else {
            standardReportForm(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func standardReportForm(viewModel: ReportViewModel) -> some View {
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

    private func lunarReportForm(viewModel: ReportViewModel) -> some View {
        let hasSelectedData = viewModel.hasDataForSelectedSections

        return ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                lunarReportHeader(viewModel: viewModel, hasSelectedData: hasSelectedData)
                lunarDateRangeCard(viewModel: viewModel)
                lunarPresetCard(viewModel: viewModel)
                lunarSectionToggleCard(viewModel: viewModel)

                if viewModel.includeHairPhotos {
                    lunarPhotoComparisonCard(viewModel: viewModel)
                }

                if !hasSelectedData {
                    lunarEmptyRangeCard(viewModel: viewModel)
                }

                lunarExportCard(viewModel: viewModel, hasSelectedData: hasSelectedData)
            }
            .padding(AppTheme.spacing16)
            .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.premiumEditorBackground.ignoresSafeArea())
        .tint(AppTheme.premiumEditorAccentColor)
        .sensoryFeedback(.selection, trigger: sectionToggleHaptic)
        .accessibilityIdentifier("screen.report_config")
    }

    private func lunarReportHeader(viewModel: ReportViewModel, hasSelectedData: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(localized("Prepare a doctor-ready PDF", defaultValue: "Prepare a doctor-ready PDF"))
                        .appFont(.largeTitle, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("report.lunar.header")

                    Text(localized(
                        "Choose the context that matters most and export it in a calm, reviewable format.",
                        defaultValue: "Choose the context that matters most and export it in a calm, reviewable format."
                    ))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacing8)

                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                    .shadow(color: AppTheme.premiumEditorSecondaryAccentColor.opacity(0.24), radius: 16, y: 8)
            }

            HStack(spacing: AppTheme.spacing8) {
                lunarReportSummaryPill(
                    title: localized("Sections", defaultValue: "Sections"),
                    value: "\(selectedReportSectionCount(viewModel))",
                    systemImage: "checklist"
                )
                lunarReportSummaryPill(
                    title: localized("Photos", defaultValue: "Photos"),
                    value: viewModel.includeHairPhotos ? localized("On", defaultValue: "On") : localized("Off", defaultValue: "Off"),
                    systemImage: "photo.stack.fill"
                )
                lunarReportSummaryPill(
                    title: localized("Data", defaultValue: "Data"),
                    value: hasSelectedData ? localized("Ready", defaultValue: "Ready") : localized("Adjust", defaultValue: "Adjust"),
                    systemImage: hasSelectedData ? "sparkles" : "calendar.badge.exclamationmark"
                )
            }
        }
        .padding(AppTheme.spacing16)
        .lunarReportCard()
    }

    private func lunarDateRangeCard(viewModel: ReportViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarReportSectionHeader(
                localized("Date Range", defaultValue: "Date Range"),
                systemImage: "calendar"
            )

            DatePicker(
                selection: Bindable(viewModel).startDate,
                in: ...viewModel.endDate,
                displayedComponents: .date
            ) {
                Text(localized("Start Date", defaultValue: "Start Date"))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(AppTheme.premiumEditorAccentColor)

            Divider()
                .overlay(AppTheme.premiumEditorBorder.opacity(0.52))

            DatePicker(
                selection: Bindable(viewModel).endDate,
                in: viewModel.startDate...,
                displayedComponents: .date
            ) {
                Text(localized("End Date", defaultValue: "End Date"))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(AppTheme.premiumEditorAccentColor)
        }
        .padding(AppTheme.spacing16)
        .lunarReportCard()
        .accessibilityIdentifier("report.lunar.range")
    }

    private func lunarPresetCard(viewModel: ReportViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarReportSectionHeader(
                localized("Presets", defaultValue: "Presets"),
                systemImage: "wand.and.stars"
            )

            lunarPresetButton(
                title: localized("Full Report", defaultValue: "Full Report"),
                subtitle: localized("Cycles, symptoms, meals, glucose, photos, insights, and pregnancy context.", defaultValue: "Cycles, symptoms, meals, glucose, photos, insights, and pregnancy context."),
                systemImage: "doc.richtext",
                isSelected: isFullReport(viewModel)
            ) {
                applyPreset(.full, viewModel: viewModel)
            }

            lunarPresetButton(
                title: localized("Quick Summary", defaultValue: "Quick Summary"),
                subtitle: localized("Cycles, symptoms, and insights for a lighter appointment prep.", defaultValue: "Cycles, symptoms, and insights for a lighter appointment prep."),
                systemImage: "doc.text",
                isSelected: isQuickSummary(viewModel)
            ) {
                applyPreset(.quick, viewModel: viewModel)
            }
        }
        .padding(AppTheme.spacing16)
        .lunarReportCard()
        .accessibilityIdentifier("report.lunar.presets")
    }

    private func lunarSectionToggleCard(viewModel: ReportViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarReportSectionHeader(
                localized("Customize Sections", defaultValue: "Customize Sections"),
                systemImage: "slider.horizontal.3"
            )

            lunarReportToggle(title: localized("Cycles", defaultValue: "Cycles"), systemImage: "moonphase.waxing.crescent", isOn: Bindable(viewModel).includeCycles)
            lunarReportToggle(title: localized("Symptoms", defaultValue: "Symptoms"), systemImage: "heart.text.square", isOn: Bindable(viewModel).includeSymptoms)
            lunarReportToggle(title: localized("Blood Sugar", defaultValue: "Blood Sugar"), systemImage: "drop.triangle", isOn: Bindable(viewModel).includeBloodSugar)
            lunarReportToggle(title: localized("Supplements", defaultValue: "Supplements"), systemImage: "pills", isOn: Bindable(viewModel).includeSupplements)
            lunarReportToggle(title: localized("Meals", defaultValue: "Meals"), systemImage: "fork.knife", isOn: Bindable(viewModel).includeMeals)
            lunarReportToggle(title: localized("Weight Trend", defaultValue: "Weight Trend"), systemImage: "chart.line.uptrend.xyaxis", isOn: Bindable(viewModel).includeWeightTrend)
            lunarReportToggle(title: localized("Hair Photo Grid", defaultValue: "Hair Photo Grid"), systemImage: "photo.on.rectangle.angled", isOn: Bindable(viewModel).includeHairPhotos)
            lunarReportToggle(title: localized("Insights", defaultValue: "Insights"), systemImage: "sparkles", isOn: Bindable(viewModel).includeInsights)
            lunarReportToggle(title: localized("Pregnancy", defaultValue: "Pregnancy"), systemImage: "figure.and.child.holdinghands", isOn: Bindable(viewModel).includePregnancy)
        }
        .padding(AppTheme.spacing16)
        .lunarReportCard()
        .accessibilityIdentifier("report.lunar.sections")
        .onChange(of: viewModel.includeCycles) { _, _ in sectionToggleHaptic.toggle() }
        .onChange(of: viewModel.includeSymptoms) { _, _ in sectionToggleHaptic.toggle() }
        .onChange(of: viewModel.includeBloodSugar) { _, _ in sectionToggleHaptic.toggle() }
        .onChange(of: viewModel.includeSupplements) { _, _ in sectionToggleHaptic.toggle() }
        .onChange(of: viewModel.includeMeals) { _, _ in sectionToggleHaptic.toggle() }
        .onChange(of: viewModel.includeWeightTrend) { _, _ in sectionToggleHaptic.toggle() }
        .onChange(of: viewModel.includeHairPhotos) { _, _ in sectionToggleHaptic.toggle() }
        .onChange(of: viewModel.includeInsights) { _, _ in sectionToggleHaptic.toggle() }
        .onChange(of: viewModel.includePregnancy) { _, _ in sectionToggleHaptic.toggle() }
    }

    private func lunarPhotoComparisonCard(viewModel: ReportViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            lunarReportSectionHeader(
                localized("Photo Comparison Format", defaultValue: "Photo Comparison Format"),
                systemImage: "rectangle.split.2x1"
            )

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

            Text(comparisonStyleDescription(viewModel.photoComparisonStyle))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing16)
        .lunarReportCard()
        .accessibilityIdentifier("report.lunar.photo_format")
    }

    private func lunarEmptyRangeCard(viewModel: ReportViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(
                localized("No report data in this range", defaultValue: "No report data in this range"),
                systemImage: "doc.text.magnifyingglass"
            )
            .appFont(.headline, weight: .semibold)
            .foregroundStyle(AppTheme.primaryText)

            Text(localized(
                "Choose a wider date range or include sections with logged data before exporting.",
                defaultValue: "Choose a wider date range or include sections with logged data before exporting."
            ))
            .appFont(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                useLastNinetyDays(viewModel: viewModel)
            } label: {
                Label(
                    localized("Use Last 90 Days", defaultValue: "Use Last 90 Days"),
                    systemImage: "calendar.badge.clock"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.premiumEditorAccentColor)
            .accessibilityIdentifier("report.empty_range.expand_range")
        }
        .padding(AppTheme.spacing16)
        .lunarReportCard()
        .accessibilityIdentifier("report.empty_range")
    }

    private func lunarExportCard(viewModel: ReportViewModel, hasSelectedData: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            if !appState.allowsPremiumAccess {
                Text(freeExportMessage)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.isGenerating {
                HStack(spacing: AppTheme.spacing12) {
                    ProgressView()
                        .tint(AppTheme.premiumEditorAccentColor)
                    Text(localized("Generating report...", defaultValue: "Generating report..."))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("report.lunar.generating")
            } else {
                Button {
                    exportReport(viewModel: viewModel)
                } label: {
                    HStack(spacing: AppTheme.spacing8) {
                        Image(systemName: "square.and.arrow.up")
                        Text(localized("Export PDF", defaultValue: "Export PDF"))
                        Spacer(minLength: 0)
                    }
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.spacing16)
                    .padding(.vertical, AppTheme.spacing12)
                    .background(Capsule().fill(AppTheme.premiumEditorAccentGradient))
                    .shadow(color: AppTheme.premiumEditorSecondaryAccentColor.opacity(0.2), radius: 16, y: 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(localized("Export PDF", defaultValue: "Export PDF"))
                    .accessibilityIdentifier("report.export")
                }
                .buttonStyle(.plain)
                .disabled(!hasSelectedData)
                .opacity(hasSelectedData ? 1 : 0.48)
                .accessibilityIdentifier("report.export")

                if viewModel.hasGeneratedReport {
                    lunarExportStatusCard(viewModel: viewModel)
                }

                if viewModel.hasGeneratedReport || viewModel.hasPendingConfigurationChanges {
                    Button {
                        regenerateReport(viewModel: viewModel)
                    } label: {
                        Label(localized("Regenerate Report", defaultValue: "Regenerate Report"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tint(AppTheme.premiumEditorAccentColor)
                    .disabled(!hasSelectedData)
                    .accessibilityIdentifier("report.regenerate")
                }
            }
        }
        .padding(AppTheme.spacing16)
        .lunarReportCard()
        .accessibilityIdentifier("report.lunar.export")
    }

    private func lunarExportStatusCard(viewModel: ReportViewModel) -> some View {
        let isStale = viewModel.hasPendingConfigurationChanges
        let statusID = isStale ? "report.lunar.export_stale" : "report.lunar.share_ready"
        let title = isStale
            ? localized("Fresh PDF needed", defaultValue: "Fresh PDF needed")
            : localized("PDF ready", defaultValue: "PDF ready")
        let detail = isStale
            ? localized(
                "Your report settings changed. Export PDF to generate a fresh file before sharing.",
                defaultValue: "Your report settings changed. Export PDF to generate a fresh file before sharing."
            )
            : localized(
                "Your latest PDF is ready to share again without generating a new file.",
                defaultValue: "Your latest PDF is ready to share again without generating a new file."
            )
        let iconName = isStale ? "arrow.clockwise.circle.fill" : "checkmark.seal.fill"
        let tint = isStale ? AppTheme.premiumEditorSecondaryAccentColor : AppTheme.premiumEditorAccentColor

        return HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: iconName)
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.13)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(title)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .accessibilityIdentifier(statusID)

                Text(detail)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                .fill(AppTheme.premiumEditorSurface.opacity(0.66))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder.opacity(0.54), lineWidth: 0.8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report.lunar.export_status")
    }

    private func lunarReportSectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .appFont(.headline, weight: .semibold)
            .foregroundStyle(AppTheme.primaryText)
    }

    private func lunarReportSummaryPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: AppTheme.spacing8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.premiumEditorAccentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appFont(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.spacing8)
        .padding(.vertical, AppTheme.spacing8)
        .background(Capsule().fill(AppTheme.premiumEditorSurface.opacity(0.76)))
        .overlay(Capsule().stroke(AppTheme.premiumEditorBorder.opacity(0.56), lineWidth: 0.8))
    }

    private func lunarPresetButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.premiumEditorCTAForeground : AppTheme.premiumEditorAccentColor)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(isSelected ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.premiumEditorAccentColor.opacity(0.12)))
                    )

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(title)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacing8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                }
            }
            .padding(AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                    .fill(AppTheme.premiumEditorSurface.opacity(isSelected ? 0.86 : 0.58))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                    .stroke(isSelected ? AppTheme.premiumEditorBorderGradient : LinearGradient(colors: [AppTheme.premiumEditorBorder.opacity(0.48)], startPoint: .leading, endPoint: .trailing), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func lunarReportToggle(title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage)
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(AppTheme.premiumEditorAccentColor)
        .padding(.vertical, AppTheme.spacing4)
    }

    private func selectedReportSectionCount(_ viewModel: ReportViewModel) -> Int {
        [
            viewModel.includeCycles,
            viewModel.includeSymptoms,
            viewModel.includeBloodSugar,
            viewModel.includeSupplements,
            viewModel.includeMeals,
            viewModel.includeWeightTrend,
            viewModel.includeHairPhotos,
            viewModel.includeInsights,
            viewModel.includePregnancy,
        ].filter { $0 }.count
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
                ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, moment: .reportGenerated, requestReview: requestReview)
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
                ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, moment: .reportGenerated, requestReview: requestReview)
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

private extension View {
    @ViewBuilder
    func lunarReportNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func lunarReportCard(cornerRadius: CGFloat = AppTheme.cornerRadiusLarge) -> some View {
        if AppTheme.usesPremiumEditorStyling {
            background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.85)
            )
            .shadow(color: AppTheme.cardShadowColor, radius: 18, y: 12)
        } else {
            cardStyle(cornerRadius: cornerRadius)
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
