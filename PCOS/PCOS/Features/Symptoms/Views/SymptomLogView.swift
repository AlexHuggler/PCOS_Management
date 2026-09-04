import StoreKit
import SwiftUI
import SwiftData
import os

struct SymptomLogView: View {
    var initialCategory: SymptomCategory? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var viewModel: SymptomViewModel?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var activeAlert: ActiveAlert?
    @State private var dirtyTracker: FormDirtyTracker<FormSnapshot>?
    @State private var suggestionsExpanded = true
    @State private var lunarExpandedSymptoms = false
    @State private var lunarMoodSelection = LunarMoodOption.good
    @State private var lunarFlowLevel = 0.54
    @State private var lunarPainLevel = 4.0
    @State private var lunarEnergyLevel = 6.0
    @State private var initialLunarEnergyLevel = 6.0
    @State private var lunarWeightText = ""
    @State private var initialLunarWeightText = ""
    @State private var lunarStressLevel = 3.0
    @State private var lunarWaterOz = 0.0
    @State private var lunarNote = ""
    @State private var initialDailyPainLevel0To10: Int?
    @State private var initialLunarStressLevel = 3.0
    @State private var initialLunarWaterOz = 0.0

    private struct FormSnapshot: Equatable {
        var selectedCategory: SymptomCategory?
        var severities: [SymptomType: Int]
        var notes: [SymptomType: String]
        var logDate: Date
        var lunarMoodSelection: LunarMoodOption
        var lunarFlowLevel: Double
        var lunarPainLevel: Double
        var lunarEnergyLevel: Double
        var lunarStressLevel: Double
        var lunarWaterOz: Double
        var lunarWeightText: String
        var lunarNote: String
    }

    private enum ActiveAlert: Identifiable {
        case cancel
        case error(String)

        var id: String {
            switch self {
            case .cancel: "cancel"
            case .error: "error"
            }
        }
    }

    private enum LunarMoodOption: String, CaseIterable, Identifiable {
        case great
        case good
        case okay
        case low
        case awful

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
            case .awful:
                L10n.string("Awful", defaultValue: "Awful")
            }
        }

        var systemImage: String {
            switch self {
            case .great: "sun.max.fill"
            case .good: "cloud.sun.fill"
            case .okay: "cloud.fill"
            case .low: "cloud.rain.fill"
            case .awful: "bolt.fill"
            }
        }

        var color: Color {
            switch self {
            case .great: AppTheme.softGoldAccent
            case .good: AppTheme.premiumEditorAccentColor
            case .okay: AppTheme.lavenderAccent
            case .low: AppTheme.sage
            case .awful: AppTheme.premiumEditorWarningAccentColor
            }
        }
    }

    private struct LunarWeekDay: Identifiable {
        let id: Date
        let weekday: String
        let day: String
        let isSelected: Bool
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if AppTheme.usesPremiumEditorStyling {
                    lunarSymptomLogContent
                } else {
                    categoryFilterBar
                    standardSymptomLogContent
                    saveBar
                }
            }
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Log Symptoms", defaultValue: "Log Symptoms"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.symptom_log")
            .background {
                if AppTheme.usesPremiumEditorStyling {
                    AppTheme.premiumEditorBackground
                } else {
                    BotanicalScreenBackground(style: .quiet)
                }
            }
            .toolbar {
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .principal) {
                        Text(L10n.string("Log symptoms", defaultValue: "Log symptoms"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                            .accessibilityIdentifier("symptom_log.lunar.header")
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if hasUnsavedChanges {
                            activeAlert = .cancel
                        } else {
                            dismiss()
                        }
                    } label: {
                        if AppTheme.usesPremiumEditorStyling {
                            Image(systemName: "xmark")
                        } else {
                            Text(L10n.string("Cancel", defaultValue: "Cancel"))
                        }
                    }
                    .accessibilityLabel(L10n.string("Cancel", defaultValue: "Cancel"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SymptomHistoryView()
                    } label: {
                        if AppTheme.usesPremiumEditorStyling {
                            Image(systemName: "moon.stars.fill")
                                .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                        } else {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    .accessibilityLabel(L10n.string("History", defaultValue: "History"))
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .cancel:
                    return Alert(
                        title: Text("Discard changes?"),
                        message: Text("You have unsaved changes that will be lost."),
                        primaryButton: .destructive(Text("Discard")) { dismiss() },
                        secondaryButton: .cancel(Text("Keep Editing"))
                    )
                case .error(let message):
                    return Alert(
                        title: Text("Could not Save"),
                        message: Text(message),
                        dismissButton: .cancel(Text("OK"))
                    )
                }
            }
            .overlay {
                if saveCoordinator.isShowingSavedFeedback {
                    SavedFeedbackOverlay()
                }
            }
            .onAppear {
                let vm = SymptomViewModel(modelContext: modelContext)
                if let initialCategory,
                   UserDefaults.standard.string(forKey: "symptom.selectedCategory") == nil {
                    vm.selectedCategory = initialCategory
                }
                vm.prefillTodaysSymptoms()
                vm.reloadSupportingData()
                configureLunarState(from: vm)
                viewModel = vm
                dirtyTracker = FormDirtyTracker(initial: snapshot(for: vm))
#if DEBUG
                let initialCategoryName = vm.selectedCategory?.rawValue ?? "all"
                Logger.symptoms.debug(
                    "Symptom log sheet opened initial_category=\(initialCategoryName, privacy: .public)"
                )
                Logger.symptomsSignposter.emitEvent("SymptomLogSheetOpen")
#endif
            }
            .onDisappear {
                saveCoordinator.cancelPending()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var standardSymptomLogContent: some View {
        if let viewModel {
            ScrollView {
                VStack(spacing: AppTheme.spacing16) {
                    // Quick actions row
                    quickActionsRow

                    // Symptom grid — 2 columns for better touch targets
                    LazyVGrid(
                        columns: symptomGridColumns,
                        spacing: AppTheme.spacing12
                    ) {
                        ForEach(viewModel.visibleSymptomTypes) { symptomType in
                            SymptomGridItem(
                                symptomType: symptomType,
                                severity: viewModel.severity(for: symptomType),
                                onSeverityChange: { newSeverity in
                                    updateSeverity(newSeverity, for: symptomType, source: "grid")
                                }
                            )
                        }
                    }
                }
                .padding()
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: symptomGridColumns,
                    spacing: AppTheme.spacing12
                ) {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonCard()
                    }
                }
                .padding()
            }
        }
    }

    private var symptomGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: AppTheme.spacing12),
            GridItem(.flexible(), spacing: AppTheme.spacing12),
        ]
    }

    private var lunarSymptomLogContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                lunarDateStrip

                if viewModel == nil {
                    lunarSkeletonPanel
                } else {
                    lunarMoodSection
                    lunarSymptomChipSection

                    if lunarExpandedSymptoms {
                        categoryFilterBar
                        LazyVGrid(
                            columns: symptomGridColumns,
                            spacing: AppTheme.spacing12
                        ) {
                            ForEach(viewModel?.visibleSymptomTypes ?? []) { symptomType in
                                SymptomGridItem(
                                    symptomType: symptomType,
                                    severity: viewModel?.severity(for: symptomType) ?? 0,
                                    onSeverityChange: { newSeverity in
                                        updateSeverity(newSeverity, for: symptomType, source: "lunar_grid")
                                    }
                                )
                            }
                        }
                    }

                    lunarMetricSection
                    lunarNotesSection
                    lunarSaveButton
                }
            }
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.top, AppTheme.spacing8)
            .padding(.bottom, AppTheme.spacing24)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.premiumEditorBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("symptom_log.lunar.surface")
    }

    private var lunarDateStrip: some View {
        VStack(spacing: AppTheme.spacing8) {
            HStack(spacing: 0) {
                ForEach(lunarWeekDays) { day in
                    VStack(spacing: AppTheme.spacing4) {
                        Text(day.weekday)
                            .appFont(.caption2, weight: .semibold)
                            .foregroundStyle(AppTheme.secondaryText)
                            .textCase(.uppercase)

                        Text(day.day)
                            .appFont(.subheadline, weight: day.isSelected ? .semibold : .regular)
                            .foregroundStyle(day.isSelected ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
                            .frame(width: 38, height: 38)
                            .background(
                                Circle()
                                    .fill(day.isSelected ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(Color.clear))
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()
                .overlay(AppTheme.premiumEditorBorder.opacity(0.62))
        }
        .accessibilityIdentifier("symptom_log.lunar.date_strip")
    }

    private var lunarMoodSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(L10n.string("How are you feeling?", defaultValue: "How are you feeling?"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityIdentifier("symptom_log.lunar.mood_section")

            HStack(spacing: AppTheme.spacing8) {
                ForEach(LunarMoodOption.allCases) { mood in
                    Button {
                        selectLunarMood(mood)
                    } label: {
                        VStack(spacing: AppTheme.spacing8) {
                            Image(systemName: mood.systemImage)
                                .appFont(.title3, weight: .semibold)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(mood.color, AppTheme.premiumEditorSecondaryAccentColor)
                                .frame(height: 30)

                            Text(mood.title)
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 86)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                                .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                                .stroke(
                                    mood == lunarMoodSelection ? AppTheme.premiumEditorBorderGradient : LinearGradient(colors: [AppTheme.premiumEditorBorder.opacity(0.58)], startPoint: .leading, endPoint: .trailing),
                                    lineWidth: mood == lunarMoodSelection ? 1.3 : 0.8
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("symptom_log.lunar.mood.\(mood.rawValue)")
                }
            }
        }
    }

    private var lunarSymptomChipSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(L10n.string("Select symptoms", defaultValue: "Select symptoms"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityIdentifier("symptom_log.lunar.symptom_chips")

            FlowLayout(spacing: AppTheme.spacing8) {
                ForEach(lunarPrioritySymptoms) { symptomType in
                    lunarSymptomChip(symptomType)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        lunarExpandedSymptoms.toggle()
                    }
                } label: {
                    Label(
                        lunarExpandedSymptoms
                            ? L10n.string("Hide symptoms", defaultValue: "Hide symptoms")
                            : L10n.string("Add symptom", defaultValue: "Add symptom"),
                        systemImage: lunarExpandedSymptoms ? "minus" : "plus"
                    )
                    .appFont(.subheadline)
                    .padding(.horizontal, AppTheme.spacing16)
                    .padding(.vertical, AppTheme.spacing8)
                    .background(Capsule().fill(AppTheme.premiumEditorSurface.opacity(0.86)))
                    .overlay(Capsule().stroke(AppTheme.premiumEditorBorder.opacity(0.62), lineWidth: 0.8))
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("symptom_log.lunar.add_symptom")
            }
        }
    }

    private func lunarSymptomChip(_ symptomType: SymptomType) -> some View {
        let severity = viewModel?.severity(for: symptomType) ?? 0
        let isSelected = severity > 0

        return Button {
            updateSeverity(isSelected ? 0 : max(severity, 2), for: symptomType, source: "lunar_chip")
        } label: {
            Text(lunarSymptomDisplayName(for: symptomType))
                .appFont(.subheadline, weight: isSelected ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, AppTheme.spacing16)
                .padding(.vertical, AppTheme.spacing8)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.premiumEditorRaisedSurface.opacity(0.96) : AppTheme.premiumEditorSurface.opacity(0.9))
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? AppTheme.premiumEditorBorderGradient : LinearGradient(colors: [AppTheme.premiumEditorBorder.opacity(0.58)], startPoint: .leading, endPoint: .trailing), lineWidth: isSelected ? 1.1 : 0.8)
                )
                .foregroundStyle(isSelected ? AppTheme.premiumEditorAccentColor : AppTheme.primaryText)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lunarSymptomDisplayName(for: symptomType))
        .accessibilityValue(isSelected ? L10n.string("Selected", defaultValue: "Selected") : L10n.string("Not selected", defaultValue: "Not selected"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("symptom_log.lunar.chip.\(symptomType.rawValue)")
    }

    private var lunarMetricSection: some View {
        VStack(spacing: AppTheme.spacing16) {
            LunarMetricSlider(
                icon: "drop.fill",
                title: L10n.string("Flow", defaultValue: "Flow"),
                valueLabel: lunarFlowLabel,
                value: $lunarFlowLevel,
                range: 0...1,
                step: 0.25,
                tint: AppTheme.premiumEditorAccentColor,
                accessibilityIdentifier: "symptom_log.lunar.slider.flow"
            )

            LunarMetricSlider(
                icon: "bolt.fill",
                title: L10n.string("Pain level", defaultValue: "Pain level"),
                valueLabel: L10n.format("%lld / 10", defaultValue: "%lld / 10", Int64(lunarPainLevel.rounded())),
                value: $lunarPainLevel,
                range: 0...10,
                step: 1,
                tint: AppTheme.premiumEditorSecondaryAccentColor,
                accessibilityIdentifier: "symptom_log.lunar.slider.pain"
            )
            .onChange(of: lunarPainLevel) { _, newValue in
                updateSeverity(Int((newValue / 2).rounded()), for: .cramps, source: "lunar_pain_slider")
            }

            LunarMetricSlider(
                icon: "waveform.path.ecg",
                title: L10n.string("Energy level", defaultValue: "Energy level"),
                valueLabel: L10n.format("%lld / 10", defaultValue: "%lld / 10", Int64(lunarEnergyLevel.rounded())),
                value: $lunarEnergyLevel,
                range: 1...10,
                step: 1,
                tint: AppTheme.premiumEditorAccentColor,
                accessibilityIdentifier: "symptom_log.lunar.slider.energy"
            )
            .onChange(of: lunarEnergyLevel) { _, newValue in
                let severity = newValue <= 5 ? max(1, min(5, Int(((6 - newValue) / 1.2).rounded()))) : 0
                updateSeverity(severity, for: .energyCrash, source: "lunar_energy_slider")
            }

            LunarMetricSlider(
                icon: "brain.head.profile",
                title: L10n.string("Stress", defaultValue: "Stress"),
                valueLabel: L10n.format("%lld / 5", defaultValue: "%lld / 5", Int64(lunarStressLevel.rounded())),
                value: $lunarStressLevel,
                range: 1...5,
                step: 1,
                tint: AppTheme.premiumEditorSecondaryAccentColor,
                accessibilityIdentifier: "symptom_log.lunar.slider.stress"
            )

            LunarMetricSlider(
                icon: "drop.circle",
                title: L10n.string("Water", defaultValue: "Water"),
                valueLabel: L10n.format("%lld oz", defaultValue: "%lld oz", Int64(lunarWaterOz.rounded())),
                value: $lunarWaterOz,
                range: 0...96,
                step: 8,
                tint: AppTheme.premiumEditorAccentColor,
                accessibilityIdentifier: "symptom_log.lunar.slider.water"
            )

            HStack(spacing: AppTheme.spacing12) {
                Image(systemName: "scalemass")
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)
                    .accessibilityHidden(true)
                Text(L10n.string("Weight", defaultValue: "Weight"))
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Spacer(minLength: AppTheme.spacing8)
                TextField(L10n.string("Optional", defaultValue: "Optional"), text: $lunarWeightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 96)
                    .accessibilityLabel(L10n.string("Weight", defaultValue: "Weight"))
                    .accessibilityIdentifier("symptom_log.lunar.weight")
                Text(WeightDisplay.unitSymbol(locale: L10n.locale()))
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, AppTheme.spacing4)
        }
    }

    /// Weight typed in the locale's unit, converted to kilograms for storage.
    private var parsedLunarWeightKilograms: Double? {
        let normalized = lunarWeightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized), value > 0 else { return nil }
        return WeightDisplay.kilograms(fromDisplayValue: value, locale: L10n.locale())
    }

    private var lunarNotesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(L10n.string("Notes (optional)", defaultValue: "Notes (optional)"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            TextEditor(text: $lunarNote)
                .appFont(.body)
                .foregroundStyle(AppTheme.primaryText)
                .frame(minHeight: 86)
                .scrollContentBackground(.hidden)
                .padding(AppTheme.spacing12)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                        .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                        .stroke(AppTheme.premiumEditorBorder.opacity(0.62), lineWidth: 0.8)
                )
                .accessibilityIdentifier("symptom_log.lunar.notes")
        }
    }

    private var lunarSaveButton: some View {
        Button {
            saveSymptoms()
        } label: {
            Text(L10n.string("Save today's log", defaultValue: "Save today's log"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacing16)
                    .background(
                        Capsule()
                            .fill(lunarCanSave ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.premiumEditorBorder.opacity(0.9)))
                    )
        }
        .buttonStyle(.plain)
        .disabled(!lunarCanSave)
        .accessibilityIdentifier("symptom_log.save_button")
    }

    private var lunarSkeletonPanel: some View {
        VStack(spacing: AppTheme.spacing12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius)
                    .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.7))
                    .frame(height: 72)
            }
        }
        .accessibilityIdentifier("symptom_log.lunar.loading")
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacing8) {
                CategoryChip(
                    title: L10n.string("All", defaultValue: "All"),
                    isSelected: viewModel?.selectedCategory == nil
                ) {
                    viewModel?.selectedCategory = nil
                }

                ForEach(SymptomCategory.allCases) { category in
                    CategoryChip(
                        title: category.displayName,
                        isSelected: viewModel?.selectedCategory == category
                    ) {
                        viewModel?.selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, AppTheme.spacing8)
        }
        .background(AppTheme.groupedBackground)
    }

    private var quickActionsRow: some View {
        VStack(spacing: AppTheme.spacing12) {
            // Prominent "Same as yesterday" card when yesterday has data and nothing selected yet
            if let vm = viewModel, vm.yesterdaySymptomCount > 0, vm.selectionCount == 0 {
                Button {
                    copyYesterdaysSymptoms()
                } label: {
                    HStack(spacing: AppTheme.spacing12) {
                        Image(systemName: "arrow.counterclockwise")
                            .appFont(.title3)
                            .foregroundStyle(AppTheme.accentColor)

                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(L10n.string("Same as yesterday", defaultValue: "Same as yesterday"))
                                .appFont(.subheadline, weight: .semibold)
                            Text(
                                L10n.inflected(
                                    LocalizedStringResource(
                                        "^[\(vm.yesterdaySymptomCount) symptom](inflect: true)",
                                        comment: "Subtitle showing how many symptoms were copied from yesterday."
                                    )
                                )
                            )
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .appFont(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .cardStyle()
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(flexibility: .soft), trigger: vm.selectionCount)
            }

            // Combined suggestions section
            if let vm = viewModel, vm.selectionCount == 0 {
                let allSuggestions = combinedSuggestions
                if !allSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                suggestionsExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Text(L10n.string("Suggestions", defaultValue: "Suggestions"))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: suggestionsExpanded ? "chevron.up" : "chevron.down")
                                    .appFont(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        if suggestionsExpanded {
                            FlowLayout(spacing: AppTheme.spacing8) {
                                ForEach(allSuggestions) { type in
                                    ChipButton(
                                        title: type.displayName,
                                        systemImage: type.systemImage,
                                        color: periodFocusedQuickSymptoms.contains(type) ? AppTheme.coralAccent : AppTheme.accentColor
                                    ) {
                                        updateSeverity(2, for: type, source: "suggestion")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Compact row when symptoms are already selected
            HStack(spacing: AppTheme.spacing12) {
                if let vm = viewModel, vm.selectionCount > 0 || vm.yesterdaySymptomCount == 0 {
                    Button {
                        copyYesterdaysSymptoms()
                    } label: {
                        Label(yesterdayButtonLabel, systemImage: "arrow.counterclockwise")
                            .appFont(.subheadline)
                            .padding(.horizontal, AppTheme.spacing16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(AppTheme.accentColor.opacity(0.12))
                            )
                            .foregroundStyle(AppTheme.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel?.yesterdaySymptomCount == 0)
                    .opacity(viewModel?.yesterdaySymptomCount == 0 ? 0.5 : 1)
                }

                Spacer()

                if let count = viewModel?.selectionCount, count > 0 {
                    Button {
                        viewModel?.reset()
                    } label: {
                        Text(L10n.string("Clear all", defaultValue: "Clear all"))
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if let count = viewModel?.selectionCount, count > 0 {
                    Text(
                        L10n.inflected(
                            LocalizedStringResource(
                                "^[\(count) symptom](inflect: true) selected",
                                comment: "Footer text showing how many symptoms are currently selected."
                            )
                        )
                    )
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                } else {
                    Text(L10n.string("Tap a symptom to get started", defaultValue: "Tap a symptom to get started"))
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    saveSymptoms()
                } label: {
                    Text(L10n.string("Save", defaultValue: "Save"))
                        .appFont(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(saveButtonBackground)
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("symptom_log.save_button")
                .disabled(viewModel?.hasSelections != true)
            }
            .padding()
        }
        .background(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground : Color(.systemBackground))
    }

    @ViewBuilder
    private var saveButtonBackground: some View {
        if viewModel?.hasSelections == true, AppTheme.usesPremiumEditorStyling {
            Capsule().fill(AppTheme.premiumEditorAccentGradient)
        } else {
            Capsule()
                .fill(viewModel?.hasSelections == true
                      ? AppTheme.accentColor
                      : Color.gray.opacity(0.3))
        }
    }

    private var hasUnsavedChanges: Bool {
        guard let viewModel, let dirtyTracker else { return false }
        return dirtyTracker.isDirty(current: snapshot(for: viewModel))
    }

    private var yesterdayButtonLabel: String {
        if let count = viewModel?.yesterdaySymptomCount, count > 0 {
            return String(
                localized: "Same as yesterday (\(count))",
                comment: "Compact button label for copying the same symptoms as the previous day."
            )
        }
        return L10n.string("Same as yesterday", defaultValue: "Same as yesterday")
    }

    private var periodFocusedQuickSymptoms: [SymptomType] {
        guard initialCategory == .pain else { return [] }
        guard viewModel?.selectedCategory == .pain else { return [] }
        return [.cramps, .pelvicPain, .backPain, .nausea]
    }

    private var combinedSuggestions: [SymptomType] {
        var result: [SymptomType] = []
        result.append(contentsOf: periodFocusedQuickSymptoms)
        if let vm = viewModel {
            for type in vm.suggestedSymptoms where !result.contains(type) {
                result.append(type)
            }
        }
        return result
    }

    private var lunarPrioritySymptoms: [SymptomType] {
        [
            .cramps,
            .bloating,
            .headache,
            .fatigue,
            .acne,
            .breastTenderness,
            .backPain,
            .nausea,
            .irritable,
        ]
    }

    private var lunarWeekDays: [LunarWeekDay] {
        let calendar = Calendar.autoupdatingCurrent
        let selectedDate = viewModel?.logDate ?? Date()
        let startDate = calendar.date(byAdding: .day, value: -2, to: selectedDate) ?? selectedDate
        let formatter = DateFormatter()
        formatter.locale = L10n.locale()
        formatter.dateFormat = "EEE"

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }

            return LunarWeekDay(
                id: calendar.startOfDay(for: date),
                weekday: formatter.string(from: date).uppercased(with: formatter.locale),
                day: String(calendar.component(.day, from: date)),
                isSelected: calendar.isDate(date, inSameDayAs: selectedDate)
            )
        }
    }

    private var lunarFlowLabel: String {
        switch lunarFlowLevel {
        case ..<0.2:
            return L10n.string("None", defaultValue: "None")
        case ..<0.45:
            return L10n.string("Light", defaultValue: "Light")
        case ..<0.7:
            return L10n.string("Medium", defaultValue: "Medium")
        default:
            return L10n.string("Heavy", defaultValue: "Heavy")
        }
    }

    private var lunarCanSave: Bool {
        guard AppTheme.usesPremiumEditorStyling else {
            return viewModel?.hasSelections == true
        }

        guard viewModel != nil else { return false }
        if viewModel?.hasSelections == true { return true }
        if !lunarNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if lunarStressLevel != initialLunarStressLevel { return true }
        if lunarWaterOz != initialLunarWaterOz { return true }
        if lunarWeightText != initialLunarWeightText, parsedLunarWeightKilograms != nil { return true }
        if lunarEnergyLevel != initialLunarEnergyLevel { return true }

        let painLevel = Int(lunarPainLevel.rounded())
        return initialDailyPainLevel0To10.map { $0 != painLevel } ?? true
    }

    private func saveSymptoms() {
        guard let viewModel else { return }

        do {
            applyLunarNoteToSelectedSymptoms()
            if AppTheme.usesPremiumEditorStyling {
                try DailyLogService(modelContext: modelContext).saveDailyCheckIn(
                    date: viewModel.logDate,
                    painLevel0To10: Int(lunarPainLevel.rounded()),
                    privateNote: lunarNote,
                    stressLevel: lunarStressLevel == initialLunarStressLevel ? nil : Int(lunarStressLevel.rounded()),
                    waterOz: lunarWaterOz == initialLunarWaterOz ? nil : Int(lunarWaterOz.rounded()),
                    energyLevel: lunarEnergyLevel == initialLunarEnergyLevel ? nil : max(1, min(5, Int((lunarEnergyLevel / 2).rounded()))),
                    weightKg: lunarWeightText == initialLunarWeightText ? nil : parsedLunarWeightKilograms
                )
            }
            try viewModel.saveSymptoms()
            saveCoordinator.showSuccessAndDismiss {
                dismiss()
            }
            ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, moment: .logSaved, requestReview: requestReview)
        } catch {
            saveCoordinator.showErrorFeedback()
            activeAlert = .error(
                String(
                    localized: "Could not save symptoms: \(error.localizedDescription)",
                    comment: "Error shown when symptom entries cannot be saved."
                )
            )
        }
    }

    private func configureLunarState(from viewModel: SymptomViewModel) {
        lunarMoodSelection = inferredLunarMood(from: viewModel)
        let dailyLog = try? DailyLogService(modelContext: modelContext).fetchLog(on: viewModel.logDate)
        initialDailyPainLevel0To10 = dailyLog?.painLevel0To10

        let painSeverity = [
            viewModel.severity(for: .cramps),
            viewModel.severity(for: .pelvicPain),
            viewModel.severity(for: .backPain),
        ].max() ?? 0
        lunarPainLevel = Double(dailyLog?.painLevel0To10 ?? painSeverity * 2)

        let energyCrashSeverity = viewModel.severity(for: .energyCrash)
        lunarEnergyLevel = energyCrashSeverity > 0
            ? Double(max(1, 10 - (energyCrashSeverity * 2)))
            : 6
        initialLunarEnergyLevel = lunarEnergyLevel
        lunarWeightText = dailyLog?.weight.map {
            L10n.decimal(WeightDisplay.displayValue(kilograms: $0, locale: L10n.locale()), fractionDigits: 1)
        } ?? ""
        initialLunarWeightText = lunarWeightText

        lunarStressLevel = Double(dailyLog?.stressLevel ?? 3)
        initialLunarStressLevel = lunarStressLevel
        lunarWaterOz = Double(dailyLog?.waterOz ?? 0)
        initialLunarWaterOz = lunarWaterOz

        lunarNote = dailyLog?.privateNote ?? viewModel.symptomNotes.values.sorted().first ?? ""
    }

    private func inferredLunarMood(from viewModel: SymptomViewModel) -> LunarMoodOption {
        let moodSeverity = [
            viewModel.severity(for: .irritable),
            viewModel.severity(for: .anxious),
            viewModel.severity(for: .depressed),
            viewModel.severity(for: .moodSwings),
        ].max() ?? 0

        if moodSeverity >= 4 {
            return .awful
        } else if moodSeverity >= 2 {
            return .low
        } else if viewModel.severity(for: .fatigue) > 0 || viewModel.severity(for: .energyCrash) > 0 {
            return .okay
        }

        return .good
    }

    private func selectLunarMood(_ mood: LunarMoodOption) {
        lunarMoodSelection = mood

        switch mood {
        case .great, .good:
            break
        case .okay:
            updateSeverity(max(viewModel?.severity(for: .fatigue) ?? 0, 1), for: .fatigue, source: "lunar_mood")
        case .low:
            updateSeverity(max(viewModel?.severity(for: .depressed) ?? 0, 2), for: .depressed, source: "lunar_mood")
        case .awful:
            updateSeverity(max(viewModel?.severity(for: .irritable) ?? 0, 4), for: .irritable, source: "lunar_mood")
        }
    }

    private func lunarSymptomDisplayName(for symptomType: SymptomType) -> String {
        switch symptomType {
        case .breastTenderness:
            return L10n.string("Tender breasts", defaultValue: "Tender breasts")
        default:
            return symptomType.displayName
        }
    }

    private func applyLunarNoteToSelectedSymptoms() {
        guard AppTheme.usesPremiumEditorStyling else { return }
        guard let viewModel else { return }

        let trimmedNote = lunarNote.trimmingCharacters(in: .whitespacesAndNewlines)
        for symptomType in viewModel.symptomSeverities.keys {
            if trimmedNote.isEmpty {
                viewModel.symptomNotes.removeValue(forKey: symptomType)
            } else {
                viewModel.symptomNotes[symptomType] = trimmedNote
            }
        }
    }

    private func copyYesterdaysSymptoms() {
        viewModel?.copyYesterdaysSymptoms()

#if DEBUG
        Logger.symptoms.debug("Copied yesterday's symptom selections into the current form")
        Logger.symptomsSignposter.emitEvent("SymptomCopyYesterday")
#endif
    }

    private func updateSeverity(_ newSeverity: Int, for symptomType: SymptomType, source: String) {
        guard let viewModel else { return }

        let previousSeverity = viewModel.severity(for: symptomType)
        guard previousSeverity != newSeverity else { return }

        viewModel.setSeverity(newSeverity, for: symptomType)

#if DEBUG
        Logger.symptoms.debug(
            "Symptom severity changed source=\(source, privacy: .public) type=\(symptomType.rawValue, privacy: .public) from=\(previousSeverity, privacy: .public) to=\(newSeverity, privacy: .public)"
        )
        Logger.symptomsSignposter.emitEvent("SymptomSeverityChange")
#endif
    }

    private func snapshot(for viewModel: SymptomViewModel) -> FormSnapshot {
        FormSnapshot(
            selectedCategory: viewModel.selectedCategory,
            severities: viewModel.symptomSeverities,
            notes: viewModel.symptomNotes,
            logDate: viewModel.logDate,
            lunarMoodSelection: lunarMoodSelection,
            lunarFlowLevel: lunarFlowLevel,
            lunarPainLevel: lunarPainLevel,
            lunarEnergyLevel: lunarEnergyLevel,
            lunarStressLevel: lunarStressLevel,
            lunarWaterOz: lunarWaterOz,
            lunarWeightText: lunarWeightText,
            lunarNote: lunarNote
        )
    }
}

private struct LunarMetricSlider: View {
    let icon: String
    let title: String
    let valueLabel: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            HStack(spacing: AppTheme.spacing8) {
                Image(systemName: icon)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(tint)
                    .frame(width: 22)

                Text(title)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text(valueLabel)
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Slider(value: $value, in: range, step: step)
                .tint(tint)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(.vertical, AppTheme.spacing4)
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(.subheadline, weight: isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(chipFill)
                )
                .overlay(chipBorder)
                .foregroundStyle(chipForeground)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var chipFill: Color {
        if isSelected, AppTheme.usesPremiumEditorStyling {
            AppTheme.premiumEditorRaisedSurface.opacity(0.96)
        } else if isSelected {
            AppTheme.accentColor
        } else if AppTheme.usesPremiumEditorStyling {
            AppTheme.premiumEditorSurface.opacity(0.9)
        } else {
            Color(.tertiarySystemFill)
        }
    }

    private var chipForeground: Color {
        if isSelected, AppTheme.usesPremiumEditorStyling {
            AppTheme.premiumEditorAccentColor
        } else if isSelected {
            .white
        } else {
            AppTheme.primaryText
        }
    }

    @ViewBuilder
    private var chipBorder: some View {
        if isSelected, AppTheme.usesPremiumEditorStyling {
            Capsule().strokeBorder(AppTheme.premiumEditorBorderGradient, lineWidth: 1)
        } else {
            Capsule().strokeBorder(Color.clear, lineWidth: 0)
        }
    }
}

// MARK: - Skeleton Card

private struct SkeletonCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: AppTheme.spacing8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 32, height: 32)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 12)
                .padding(.horizontal, AppTheme.spacing8)

            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 18, height: 18)
                }
            }
        }
        .padding(.vertical, AppTheme.spacing12)
        .padding(.horizontal, AppTheme.spacing8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(Color(.tertiarySystemFill).opacity(0.5))
        )
        .opacity(isAnimating ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

#Preview {
    SymptomLogView()
        .environment(AppState())
        .modelContainer(for: SymptomEntry.self, inMemory: true)
}
