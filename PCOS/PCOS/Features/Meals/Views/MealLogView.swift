import SwiftUI
import SwiftData
import PhotosUI
import os
#if canImport(VisionKit)
import VisionKit
import Vision
#endif

enum MealLogEntryPoint: String, Sendable {
    case trackingHub = "tracking_hub"
    case today = "today"
    case direct = "direct"
}

enum MealLogInitialDestination: Sendable {
    case form
    case barcode
    case afterMealContext
}

private func localizedNutritionSourceLabel(_ sourceLabel: String) -> String {
    L10n.string(sourceLabel, defaultValue: sourceLabel)
}

struct MealLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let entryPoint: MealLogEntryPoint
    @State private var viewModel: MealViewModel?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var activeAlert: ActiveAlert?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var dirtyTracker: FormDirtyTracker<FormSnapshot>?
    @State private var recentMealSuggestions: [RecentMealReuseSuggestion] = []
    @State private var mealGlucoseReadiness: MealGlucoseReadiness?
    @State private var showingBarcodeImport = false
    @State private var showingMealScan = false
    @State private var launchBarcodeAfterMealScan = false
    @State private var pendingInitialDestination: MealLogInitialDestination?
    @FocusState private var focusedField: FocusedField?

    init(
        entryPoint: MealLogEntryPoint,
        initialDestination: MealLogInitialDestination = .form
    ) {
        self.entryPoint = entryPoint
        _pendingInitialDestination = State(initialValue: initialDestination)
    }

    private enum FocusedField: Hashable {
        case description
        case carbs
        case protein
        case fat
        case notes
        case postMealNote
    }

    private struct FormSnapshot: Equatable {
        var mealType: MealType
        var mealDescription: String
        var glycemicImpact: GlycemicImpact
        var carbsText: String
        var proteinText: String
        var fatText: String
        var photoData: Data?
        var notes: String
        var selectedTemplateID: String?
        var postMealSymptomSeverity: Int
        var postMealSymptomNote: String
        var mealDate: Date
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

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if AppTheme.usesPremiumEditorStyling {
                        lunarMealLogContent(viewModel: viewModel)
                    } else {
                        standardMealLogForm(viewModel: viewModel)
                    }
                } else {
                    mealLogLoadingView
                }
            }
            .accessibilityIdentifier("screen.meal_log")
            .background {
                if AppTheme.usesPremiumEditorStyling {
                    AppTheme.premiumEditorBackground
                        .ignoresSafeArea()
                }
                mealLogLayoutDebugProbe
            }
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Log Meal", defaultValue: "Log Meal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .principal) {
                        Text(L10n.string("Meal log", defaultValue: "Meal log"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
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
                        MealHistoryView()
                    } label: {
                        if AppTheme.usesPremiumEditorStyling {
                            Image(systemName: "clock.arrow.circlepath")
                        } else {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    .accessibilityLabel(L10n.string("History", defaultValue: "History"))
                    .accessibilityIdentifier("meal_log.history_button")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .description {
                        Button(L10n.string("Next", defaultValue: "Next")) { focusedField = .carbs }
                    } else if focusedField == .carbs {
                        Button(L10n.string("Next", defaultValue: "Next")) { focusedField = .protein }
                    } else if focusedField == .protein {
                        Button(L10n.string("Next", defaultValue: "Next")) { focusedField = .fat }
                    } else if focusedField == .fat {
                        Button(L10n.string("Next", defaultValue: "Next")) { focusedField = .notes }
                    } else if focusedField == .notes {
                        Button(L10n.string("Next", defaultValue: "Next")) { focusedField = .postMealNote }
                    }
                    Spacer()
                    Button(L10n.string("Done", defaultValue: "Done")) { focusedField = nil }
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .sheet(isPresented: $showingBarcodeImport) {
                if let viewModel {
                    BarcodeMealImportSheet(modelContext: modelContext) { candidate in
                        viewModel.applyNutritionCandidate(candidate)
                    }
                }
            }
            .sheet(isPresented: $showingMealScan, onDismiss: {
                guard launchBarcodeAfterMealScan else { return }
                launchBarcodeAfterMealScan = false
                showingBarcodeImport = true
            }) {
                if let viewModel {
                    MealScanFlowView(
                        mealType: viewModel.mealType,
                        onChooseBarcode: {
                            launchBarcodeAfterMealScan = true
                            showingMealScan = false
                        },
                        onChooseManual: {
                            showingMealScan = false
                        },
                        onAddContext: {
                            showingMealScan = false
                            focusedField = .postMealNote
                        }
                    )
                }
            }
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
            .sensoryFeedback(.success, trigger: saveCoordinator.isShowingSavedFeedback)
            .onAppear {
                Logger.meals.info("MealLogView appeared from \(entryPoint.rawValue, privacy: .public)")
                initializeMealViewModelIfNeeded()
                consumeInitialDestinationIfNeeded()
                refreshRoadmapContext()
            }
            .onDisappear {
                Logger.meals.info("MealLogView disappeared from \(entryPoint.rawValue, privacy: .public)")
                saveCoordinator.cancelPending()
            }
        }
        .accessibilityIdentifier("screen.meal_log")
        .premiumGated()
    }

    private var mealLogLoadingView: some View {
        ProgressView()
            .tint(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : AppTheme.sage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground : Color.clear)
            .onAppear {
                initializeMealViewModelIfNeeded()
                consumeInitialDestinationIfNeeded()
                refreshRoadmapContext()
            }
            .accessibilityIdentifier("meal_log.loading")
    }

    @ViewBuilder
    private func standardMealLogForm(viewModel: MealViewModel) -> some View {
        Form {
            mealTypeSection(viewModel: viewModel)
            descriptionSection(viewModel: viewModel)
            barcodeImportSection(viewModel: viewModel)
            recentMealReuseSection(viewModel: viewModel)
            mealTemplateSection(viewModel: viewModel)
            swapSuggestionsSection(viewModel: viewModel)
            mealGlucoseReadinessSection(viewModel: viewModel)

            Section {
                HStack(spacing: AppTheme.spacing8) {
                    GIButton(
                        impact: .low,
                        label: "Low",
                        examples: "Vegetables, legumes, nuts",
                        color: .green,
                        isSelected: viewModel.glycemicImpact == .low
                    ) {
                        viewModel.glycemicImpact = .low
                    }

                    GIButton(
                        impact: .medium,
                        label: "Med",
                        examples: "Rice, whole wheat, fruits",
                        color: .orange,
                        isSelected: viewModel.glycemicImpact == .medium
                    ) {
                        viewModel.glycemicImpact = .medium
                    }

                    GIButton(
                        impact: .high,
                        label: "High",
                        examples: "White bread, sugary foods",
                        color: AppTheme.coralAccent,
                        isSelected: viewModel.glycemicImpact == .high
                    ) {
                        viewModel.glycemicImpact = .high
                    }
                }
                .listRowInsets(EdgeInsets(
                    top: AppTheme.spacing8,
                    leading: AppTheme.spacing16,
                    bottom: AppTheme.spacing8,
                    trailing: AppTheme.spacing16
                ))
            } header: {
                Text("Glycemic Impact")
            }

            Section {
                VStack(spacing: AppTheme.spacing12) {
                    macroInputRow(
                        title: "Carbs",
                        value: Binding(
                            get: { viewModel.carbsText },
                            set: { viewModel.carbsText = $0 }
                        ),
                        options: ["15", "30", "45", "60"],
                        focused: .carbs
                    )

                    macroInputRow(
                        title: "Protein",
                        value: Binding(
                            get: { viewModel.proteinText },
                            set: { viewModel.proteinText = $0 }
                        ),
                        options: ["10", "20", "30", "40"],
                        focused: .protein
                    )

                    macroInputRow(
                        title: "Fat",
                        value: Binding(
                            get: { viewModel.fatText },
                            set: { viewModel.fatText = $0 }
                        ),
                        options: ["10", "20", "30", "40"],
                        focused: .fat
                    )
                }
            } header: {
                Text("Macros (Optional)")
            }

            Section {
                mealPhotoPicker(viewModel: viewModel)
            } header: {
                Text("Photo (Optional)")
            }

            notesSection(viewModel: viewModel)
            postMealFeedbackSection(viewModel: viewModel)

            Section {
                DatePicker(
                    "Meal Date",
                    selection: Binding(
                        get: { viewModel.mealDate },
                        set: { viewModel.mealDate = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Section {
                Button {
                    saveMeal()
                } label: {
                    Text("Save Meal")
                        .appFont(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(viewModel.isValid
                                      ? AppTheme.sage
                                      : Color.gray.opacity(0.3))
                        )
                        .foregroundStyle(.white)
                }
                .disabled(!viewModel.isValid)
                .accessibilityIdentifier("meal_log.save_button")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    private func lunarMealLogContent(viewModel: MealViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                lunarMealHeader
                lunarMealTypeCard(viewModel: viewModel)
                lunarDescriptionCard(viewModel: viewModel)
                lunarImportActionsCard
                lunarGlycemicImpactCard(viewModel: viewModel)
                lunarMacrosCard(viewModel: viewModel)
                lunarPhotoCard(viewModel: viewModel)
                lunarNotesCard(viewModel: viewModel)
                lunarAfterMealCard(viewModel: viewModel)
                lunarDateCard(viewModel: viewModel)
                lunarReadinessCard(viewModel: viewModel)
            }
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.top, AppTheme.spacing8)
            .padding(.bottom, 112)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.premiumEditorBackground)
        .safeAreaInset(edge: .bottom) {
            lunarSavePanel(viewModel: viewModel)
                .padding(.horizontal, AppTheme.spacing16)
                .padding(.top, AppTheme.spacing8)
                .padding(.bottom, AppTheme.spacing8)
                .background(AppTheme.premiumEditorBackground.opacity(0.96))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.surface")
    }

    private var lunarMealHeader: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing12) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("Log a meal", defaultValue: "Log a meal"))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .accessibilityIdentifier("meal_log.lunar.header")

                Text(L10n.string("Connect food with energy, cravings, skin, and glucose patterns over time.", defaultValue: "Connect food with energy, cravings, skin, and glucose patterns over time."))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.spacing8)

            ZStack {
                Circle()
                    .fill(AppTheme.premiumEditorAccentGradient)
                Image(systemName: "fork.knife")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            }
            .frame(width: 52, height: 52)
            .shadow(color: AppTheme.premiumEditorSecondaryAccentColor.opacity(0.22), radius: 16, y: 8)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.header")
    }

    private func lunarMealTypeCard(viewModel: MealViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Meal type", defaultValue: "Meal type"), systemImage: "clock")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            LazyVGrid(columns: lunarTwoColumnGrid, spacing: AppTheme.spacing8) {
                ForEach(MealType.allCases) { type in
                    Button {
                        viewModel.mealType = type
                        viewModel.selectedTemplateID = nil
                    } label: {
                        lunarPillLabel(
                            title: type.displayName,
                            icon: type.systemImage,
                            isSelected: viewModel.mealType == type,
                            accent: mealTypeAccent(for: type)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(viewModel.mealType == type ? .isSelected : [])
                    .accessibilityIdentifier("meal_log.lunar.meal_type.\(type.rawValue)")
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarMealCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.meal_type")
    }

    private func lunarDescriptionCard(viewModel: MealViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("What did you eat?", defaultValue: "What did you eat?"), systemImage: "sparkles")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            TextField("What did you eat?", text: Binding(
                get: { viewModel.mealDescription },
                set: {
                    viewModel.mealDescription = $0
                    if viewModel.selectedTemplateID != nil {
                        viewModel.selectedTemplateID = nil
                    }
                }
            ), axis: .vertical)
            .appFont(.body)
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(2...4)
            .focused($focusedField, equals: .description)
            .submitLabel(.next)
            .padding(AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
            )
            .accessibilityIdentifier("meal_log.description")
            .onSubmit {
                focusedField = .carbs
            }

            lunarMealDescriptionSuggestions(viewModel: viewModel)
            lunarRecentMeals(viewModel: viewModel)
            lunarMealTemplates(viewModel: viewModel)
            lunarSwapSuggestions(viewModel: viewModel)
        }
        .padding(AppTheme.spacing12)
        .lunarMealCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.description")
    }

    private var lunarImportActionsCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Add nutrition", defaultValue: "Add nutrition"), systemImage: "plus.circle")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            VStack(spacing: AppTheme.spacing8) {
                if MealScanFeatureFlags.current.enableMealScanV2 {
                    Button {
                        openMealScanIfAvailable()
                    } label: {
                        lunarNutritionActionRow(
                            title: L10n.string("Photo estimate", defaultValue: "Photo estimate"),
                            subtitle: L10n.string("Estimate foods and portions", defaultValue: "Estimate foods and portions"),
                            icon: "camera.viewfinder",
                            accent: AppTheme.premiumEditorAccentColor
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("meal_log.photo_estimate_button")
                }

                Button {
                    showingBarcodeImport = true
                } label: {
                    lunarNutritionActionRow(
                        title: L10n.string("Scan barcode", defaultValue: "Scan barcode"),
                        subtitle: L10n.string("Look up packaged food", defaultValue: "Look up packaged food"),
                        icon: "barcode.viewfinder",
                        accent: AppTheme.premiumEditorSecondaryAccentColor
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("meal_log.scan_barcode_button")

                Button {
                    focusManualNutritionEntry()
                } label: {
                    lunarNutritionActionRow(
                        title: L10n.string("Enter manually", defaultValue: "Enter manually"),
                        subtitle: L10n.string("Type nutrition details", defaultValue: "Type nutrition details"),
                        icon: "square.and.pencil",
                        accent: AppTheme.premiumEditorWarningAccentColor
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("meal_log.manual_nutrition_button")
            }
        }
        .padding(AppTheme.spacing12)
        .lunarMealCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.quick_actions")
    }

    private func lunarNutritionActionRow(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color
    ) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accent.opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(title)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.spacing8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, AppTheme.spacing12)
        .padding(.vertical, AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder.opacity(0.56), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
    }

    private func lunarGlycemicImpactCard(viewModel: MealViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack {
                Label(L10n.string("Glycemic impact", defaultValue: "Glycemic impact"), systemImage: "chart.line.uptrend.xyaxis")
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text(viewModel.glycemicImpact.displayName)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(glycemicColor(for: viewModel.glycemicImpact))
            }

            HStack(spacing: AppTheme.spacing8) {
                ForEach(GlycemicImpact.allCases) { impact in
                    Button {
                        viewModel.glycemicImpact = impact
                    } label: {
                        VStack(spacing: AppTheme.spacing8) {
                            Image(systemName: glycemicIcon(for: impact))
                                .appFont(.headline, weight: .semibold)
                                .foregroundStyle(glycemicColor(for: impact))

                            Text(lunarShortGlycemicTitle(for: impact))
                                .appFont(.caption, weight: viewModel.glycemicImpact == impact ? .semibold : .regular)
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 82)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.premiumEditorRaisedSurface.opacity(viewModel.glycemicImpact == impact ? 0.96 : 0.64))
                        )
                        .overlay(
                            Group {
                                if viewModel.glycemicImpact == impact {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(AppTheme.premiumEditorBorderGradient, lineWidth: 1)
                                } else {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(AppTheme.premiumEditorBorder.opacity(0.5), lineWidth: 0.8)
                                }
                            }
                        )
                        .foregroundStyle(viewModel.glycemicImpact == impact ? AppTheme.primaryText : AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(viewModel.glycemicImpact == impact ? .isSelected : [])
                    .accessibilityIdentifier("meal_log.lunar.gi.\(impact.rawValue)")
                }
            }

            Text(L10n.string("Use an estimate if you are unsure. The pattern matters more than perfection.", defaultValue: "Use an estimate if you are unsure. The pattern matters more than perfection."))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(AppTheme.spacing12)
        .lunarMealCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.glycemic_impact")
    }

    private func lunarMacrosCard(viewModel: MealViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Macros (optional)", defaultValue: "Macros (optional)"), systemImage: "number")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            lunarMacroRow(
                title: "Carbs",
                value: Binding(
                    get: { viewModel.carbsText },
                    set: { viewModel.carbsText = $0 }
                ),
                options: ["15", "30", "45", "60"],
                focused: .carbs,
                accent: AppTheme.premiumEditorSecondaryAccentColor,
                identifier: "meal_log.lunar.macro.carbs"
            )

            lunarMacroRow(
                title: "Protein",
                value: Binding(
                    get: { viewModel.proteinText },
                    set: { viewModel.proteinText = $0 }
                ),
                options: ["10", "20", "30", "40"],
                focused: .protein,
                accent: AppTheme.premiumEditorAccentColor,
                identifier: "meal_log.lunar.macro.protein"
            )

            lunarMacroRow(
                title: "Fat",
                value: Binding(
                    get: { viewModel.fatText },
                    set: { viewModel.fatText = $0 }
                ),
                options: ["10", "20", "30", "40"],
                focused: .fat,
                accent: AppTheme.lavenderAccent,
                identifier: "meal_log.lunar.macro.fat"
            )
        }
        .padding(AppTheme.spacing12)
        .lunarMealCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.macros")
    }

    private func lunarPhotoCard(viewModel: MealViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Photo (optional)", defaultValue: "Photo (optional)"), systemImage: "camera")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            mealPhotoPicker(viewModel: viewModel)
        }
        .padding(AppTheme.spacing12)
        .lunarMealCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.photo")
    }

    private func lunarNotesCard(viewModel: MealViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Notes", defaultValue: "Notes"), systemImage: "text.bubble")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            TextField("Any additional notes...", text: Binding(
                get: { viewModel.notes },
                set: { viewModel.notes = $0 }
            ), axis: .vertical)
            .appFont(.body)
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(3...6)
            .focused($focusedField, equals: .notes)
            .padding(AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
            )

            if !viewModel.mealNoteSuggestions.isEmpty {
                FlowLayout(spacing: AppTheme.spacing8) {
                    ForEach(viewModel.mealNoteSuggestions, id: \.self) { suggestion in
                        Button {
                            viewModel.toggleMealNoteSuggestion(suggestion)
                        } label: {
                            lunarTextChip(
                                title: suggestion,
                                isSelected: viewModel.isMealNoteSelected(suggestion),
                                accent: AppTheme.lavenderAccent
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarMealCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.notes")
    }

    private func lunarAfterMealCard(viewModel: MealViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("After-meal check-in", defaultValue: "After-meal check-in"), systemImage: "heart.text.square")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            Text(L10n.string("Use this after eating to connect meals with energy, cravings, bloating, or skin changes.", defaultValue: "Use this after eating to connect meals with energy, cravings, bloating, or skin changes."))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppTheme.spacing8) {
                ForEach(1...5, id: \.self) { severity in
                    Button {
                        viewModel.postMealSymptomSeverity = severity
                    } label: {
                        Text("\(severity)")
                            .appFont(.caption, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                Circle()
                                    .fill(
                                        viewModel.postMealSymptomSeverity == severity
                                            ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient)
                                            : AnyShapeStyle(AppTheme.premiumEditorSurface.opacity(0.88))
                                    )
                            )
                            .foregroundStyle(viewModel.postMealSymptomSeverity == severity ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("meal_log.lunar.checkin.\(severity)")
                }
            }

            TextField(
                L10n.string("e.g., steady energy, hungry soon, bloated later", defaultValue: "e.g., steady energy, hungry soon, bloated later"),
                text: Binding(
                    get: { viewModel.postMealSymptomNote },
                    set: { viewModel.postMealSymptomNote = $0 }
                ),
                axis: .vertical
            )
            .appFont(.body)
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(2...4)
            .focused($focusedField, equals: .postMealNote)
            .padding(AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
            )
        }
        .padding(AppTheme.spacing12)
        .lunarMealCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.checkin")
    }

    private func lunarDateCard(viewModel: MealViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Meal date", defaultValue: "Meal date"), systemImage: "calendar")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            DatePicker(
                "Meal Date",
                selection: Binding(
                    get: { viewModel.mealDate },
                    set: { viewModel.mealDate = $0 }
                ),
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .tint(AppTheme.premiumEditorAccentColor)
            .foregroundStyle(AppTheme.primaryText)
            .accessibilityIdentifier("meal_log.lunar.date")
        }
        .padding(AppTheme.spacing12)
        .lunarMealCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.date_card")
    }

    private func lunarReadinessCard(viewModel: MealViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                Image(systemName: mealGlucoseReadiness.map { readinessIcon(for: $0.state) } ?? "chart.xyaxis.line")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                    .frame(width: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(mealGlucoseReadiness.map { readinessTitle(for: $0.state) } ?? L10n.string("Pattern building", defaultValue: "Pattern building"))
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)

                    Text(mealGlucoseReadiness?.message ?? L10n.string("Meals become more useful when paired with energy, cravings, and glucose notes.", defaultValue: "Meals become more useful when paired with energy, cravings, and glucose notes."))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let readiness = mealGlucoseReadiness {
                HStack(spacing: AppTheme.spacing8) {
                    lunarReadinessMetric("\(readiness.mealCount)", label: L10n.string("meals", defaultValue: "meals"))
                    lunarReadinessMetric("\(readiness.pairedReadingCount)", label: L10n.string("paired", defaultValue: "paired"))
                    lunarReadinessMetric("\(readiness.postMealFeedbackCount)", label: L10n.string("check-ins", defaultValue: "check-ins"))
                }
            }

            if !viewModel.mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NavigationLink {
                    BloodSugarLogView(
                        prefillContext: GlucosePrefillContext(
                            mealContext: "After \(viewModel.mealDescription)",
                            readingType: .afterMeal,
                            readingDate: Date()
                        )
                    )
                } label: {
                    Label(
                        L10n.string("Log after-meal glucose", defaultValue: "Log after-meal glucose"),
                        systemImage: "drop.fill"
                    )
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarMealCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.readiness")
    }

    private func lunarSavePanel(viewModel: MealViewModel) -> some View {
        VStack(spacing: AppTheme.spacing8) {
            Button(action: saveMeal) {
                Text(L10n.string("Save meal", defaultValue: "Save meal"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(viewModel.isValid ? AppTheme.premiumEditorCTAForeground : AppTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing16)
                    .background(
                        Capsule()
                            .fill(viewModel.isValid ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.premiumEditorBorder.opacity(0.9)))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isValid)
            .accessibilityIdentifier("meal_log.save_button")

            Text(L10n.string("Private by default. Edit meals anytime.", defaultValue: "Private by default. Edit meals anytime."))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_log.lunar.save_button")
    }

    @ViewBuilder
    private func lunarMealDescriptionSuggestions(viewModel: MealViewModel) -> some View {
        let suggestions = viewModel.mealDescriptionSuggestions
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(viewModel.hasMealDescriptionQuery ? "Suggestions" : "Quick options")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)

                FlowLayout(spacing: AppTheme.spacing8) {
                    ForEach(suggestions.prefix(8), id: \.self) { suggestion in
                        Button {
                            viewModel.applyMealDescriptionSuggestion(suggestion)
                        } label: {
                            lunarTextChip(
                                title: suggestion,
                                isSelected: viewModel.mealDescription == suggestion,
                                accent: AppTheme.premiumEditorAccentColor
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lunarRecentMeals(viewModel: MealViewModel) -> some View {
        if !recentMealSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("Recent meals", defaultValue: "Recent meals"))
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)

                FlowLayout(spacing: AppTheme.spacing8) {
                    ForEach(recentMealSuggestions) { suggestion in
                        Button {
                            viewModel.applyRecentMeal(suggestion)
                        } label: {
                            lunarTextChip(
                                title: suggestion.mealDescription,
                                isSelected: false,
                                accent: AppTheme.premiumEditorSecondaryAccentColor,
                                icon: "arrow.clockwise"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lunarMealTemplates(viewModel: MealViewModel) -> some View {
        let templates = viewModel.mealTemplates
        if !templates.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("PCOS-friendly templates", defaultValue: "PCOS-friendly templates"))
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacing8) {
                        ForEach(templates) { template in
                            let isSelected = template.id == viewModel.selectedTemplateID
                            Button {
                                viewModel.applyMealTemplate(template)
                            } label: {
                                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                    Text(template.title)
                                        .appFont(.caption, weight: .semibold)
                                        .lineLimit(2)
                                    Text(template.glycemicImpact.displayName)
                                        .appFont(.caption2)
                                        .foregroundStyle(glycemicColor(for: template.glycemicImpact))
                                }
                                .frame(width: 142, alignment: .leading)
                                .padding(AppTheme.spacing8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(AppTheme.premiumEditorRaisedSurface.opacity(isSelected ? 0.96 : 0.64))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(isSelected ? AppTheme.premiumEditorAccentColor.opacity(0.8) : AppTheme.premiumEditorBorder.opacity(0.5), lineWidth: 0.8)
                                )
                                .foregroundStyle(AppTheme.primaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func lunarSwapSuggestions(viewModel: MealViewModel) -> some View {
        let swaps = viewModel.swapSuggestions
        if !swaps.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("Recommended swaps", defaultValue: "Recommended swaps"))
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)

                ForEach(swaps.prefix(3), id: \.self) { swap in
                    HStack(alignment: .top, spacing: AppTheme.spacing8) {
                        Image(systemName: "arrow.triangle.swap")
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(AppTheme.premiumEditorAccentColor)
                            .padding(.top, 2)

                        Text(swap)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(AppTheme.spacing8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.premiumEditorSurface.opacity(0.72))
                    )
                }
            }
        }
    }

    private func lunarMacroRow(
        title: String,
        value: Binding<String>,
        options: [String],
        focused: FocusedField,
        accent: Color,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            HStack {
                Text("\(title) (g)")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                TextField("0", text: value)
                    .appFont(.headline, weight: .semibold)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 84)
                    .focused($focusedField, equals: focused)
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(.horizontal, AppTheme.spacing12)
                    .padding(.vertical, AppTheme.spacing8)
                    .background(
                        Capsule()
                            .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.74))
                    )
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.premiumEditorBorder.opacity(0.54), lineWidth: 0.8)
                    )
                    .accessibilityIdentifier(identifier)
            }

            FlowLayout(spacing: AppTheme.spacing8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        value.wrappedValue = option
                    } label: {
                        lunarTextChip(
                            title: "\(option)g",
                            isSelected: value.wrappedValue == option,
                            accent: accent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func mealPhotoPicker(viewModel: MealViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            let selectedPhotoData = viewModel.photoData
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images
            ) {
                HStack(spacing: AppTheme.spacing12) {
                    if let photoData = selectedPhotoData,
                       let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorSurface.opacity(0.88) : Color(.tertiarySystemFill))
                            Image(systemName: "camera")
                                .appFont(.headline, weight: .semibold)
                                .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : AppTheme.sage)
                        }
                        .frame(width: 52, height: 52)
                    }

                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(selectedPhotoData == nil ? L10n.string("Add photo", defaultValue: "Add photo") : L10n.string("Replace photo", defaultValue: "Replace photo"))
                            .appFont(.subheadline, weight: .semibold)
                        Text(L10n.string("Optional context for future reflections.", defaultValue: "Optional context for future reflections."))
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Spacer()
                }
                .foregroundStyle(AppTheme.primaryText)
                .padding(AppTheme.usesPremiumEditorStyling ? AppTheme.spacing12 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorRaisedSurface.opacity(0.72) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBorder.opacity(0.58) : Color.clear, lineWidth: 0.8)
                )
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task { @MainActor in
                    do {
                        guard let data = try await newItem.loadTransferable(type: Data.self) else {
                            return
                        }
                        viewModel.photoData = data
                    } catch {
                        saveCoordinator.showErrorFeedback()
                        activeAlert = .error(
                            String(
                                localized: "Could not import photo: \(error.localizedDescription)",
                                comment: "Error shown when importing a meal photo fails."
                            )
                        )
                    }
                }
            }

            if selectedPhotoData != nil {
                Button(L10n.string("Remove photo", defaultValue: "Remove photo")) {
                    viewModel.photoData = nil
                    selectedPhotoItem = nil
                }
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorWarningAccentColor : .red)
            }
        }
    }

    private func lunarPillLabel(title: String, icon: String, isSelected: Bool, accent: Color) -> some View {
        HStack(spacing: AppTheme.spacing8) {
            Image(systemName: icon)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(accent)
                .frame(width: 18)

            Text(title)
                .appFont(.caption, weight: isSelected ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing8)
        .padding(.horizontal, AppTheme.spacing8)
        .background(
            Capsule()
                .fill(isSelected ? AppTheme.premiumEditorRaisedSurface.opacity(0.96) : AppTheme.premiumEditorSurface.opacity(0.88))
        )
        .overlay(
            Group {
                if isSelected {
                    Capsule().strokeBorder(AppTheme.premiumEditorBorderGradient, lineWidth: 1)
                } else {
                    Capsule().strokeBorder(AppTheme.premiumEditorBorder.opacity(0.5), lineWidth: 0.8)
                }
            }
        )
        .foregroundStyle(isSelected ? AppTheme.premiumEditorAccentColor : AppTheme.primaryText)
    }

    private func lunarTextChip(
        title: String,
        isSelected: Bool,
        accent: Color,
        icon: String? = nil
    ) -> some View {
        HStack(spacing: AppTheme.spacing4) {
            if let icon {
                Image(systemName: icon)
                    .appFont(.caption2, weight: .semibold)
                    .foregroundStyle(accent)
            }

            Text(title)
                .appFont(.caption, weight: isSelected ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, AppTheme.spacing12)
        .padding(.vertical, AppTheme.spacing8)
        .background(
            Capsule()
                .fill(isSelected ? AppTheme.premiumEditorRaisedSurface.opacity(0.96) : AppTheme.premiumEditorSurface.opacity(0.88))
        )
        .overlay(
            Group {
                if isSelected {
                    Capsule().strokeBorder(AppTheme.premiumEditorBorderGradient, lineWidth: 1)
                } else {
                    Capsule().strokeBorder(AppTheme.premiumEditorBorder.opacity(0.5), lineWidth: 0.8)
                }
            }
        )
        .foregroundStyle(isSelected ? accent : AppTheme.primaryText)
    }

    private func lunarActionTile(title: String, subtitle: String, icon: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Image(systemName: icon)
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(accent)

            Text(title)
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(subtitle)
                .appFont(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
        )
    }

    private func lunarReadinessMetric(_ value: String, label: String) -> some View {
        VStack(spacing: AppTheme.spacing4) {
            Text(value)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
            Text(label)
                .appFont(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.premiumEditorSurface.opacity(0.86))
        )
    }

    private var lunarTwoColumnGrid: [GridItem] {
        [
            GridItem(.flexible(minimum: 0), spacing: AppTheme.spacing8),
            GridItem(.flexible(minimum: 0), spacing: AppTheme.spacing8)
        ]
    }

    private func mealTypeAccent(for type: MealType) -> Color {
        switch type {
        case .breakfast:
            AppTheme.softGoldAccent
        case .lunch:
            AppTheme.premiumEditorAccentColor
        case .dinner:
            AppTheme.lavenderAccent
        case .snack:
            AppTheme.premiumEditorSecondaryAccentColor
        }
    }

    private func glycemicColor(for impact: GlycemicImpact) -> Color {
        switch impact {
        case .low:
            AppTheme.premiumEditorAccentColor
        case .medium:
            AppTheme.premiumEditorSecondaryAccentColor
        case .high:
            AppTheme.premiumEditorWarningAccentColor
        }
    }

    private func glycemicIcon(for impact: GlycemicImpact) -> String {
        switch impact {
        case .low:
            "leaf"
        case .medium:
            "circle.lefthalf.filled"
        case .high:
            "bolt.fill"
        }
    }

    private func lunarShortGlycemicTitle(for impact: GlycemicImpact) -> String {
        switch impact {
        case .low:
            L10n.string("Low", defaultValue: "Low")
        case .medium:
            L10n.string("Medium", defaultValue: "Medium")
        case .high:
            L10n.string("High", defaultValue: "High")
        }
    }

    private func openMealScanIfAvailable() {
        guard MealScanFeatureFlags.current.enableMealScanV2 else {
            Logger.meals.info("AI meal scan is disabled for this release.")
            return
        }

        showingMealScan = true
    }

    @ViewBuilder
    private func barcodeImportSection(viewModel: MealViewModel) -> some View {
        Section {
            if MealScanFeatureFlags.current.enableMealScanV2 {
                Button {
                    openMealScanIfAvailable()
                } label: {
                    Label(
                        L10n.string("Photo estimate", defaultValue: "Photo estimate"),
                        systemImage: "camera.viewfinder"
                    )
                }
                .accessibilityIdentifier("meal_log.photo_estimate_button")
            }

            Button {
                showingBarcodeImport = true
            } label: {
                Label(
                    L10n.string("Scan barcode", defaultValue: "Scan barcode"),
                    systemImage: "barcode.viewfinder"
                )
            }
            .accessibilityIdentifier("meal_log.scan_barcode_button")

            Button {
                focusManualNutritionEntry()
            } label: {
                Label(
                    L10n.string("Enter manually", defaultValue: "Enter manually"),
                    systemImage: "square.and.pencil"
                )
            }
            .accessibilityIdentifier("meal_log.manual_nutrition_button")

            if let summary = viewModel.pendingNutritionImportSummary {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(localizedNutritionSourceLabel(summary.sourceLabel), systemImage: "checkmark.seal.fill")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.sage)

                    Text(summary.productName)
                        .appFont(.subheadline, weight: .semibold)

                    if let brandName = summary.brandName {
                        Text(brandName)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let servingText = summary.servingText {
                        Text(servingText)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: summary.completeness, total: 1)
                        .tint(AppTheme.sage)
                }
                .accessibilityIdentifier("meal_log.nutrition_import_summary")
            }
        } header: {
            Text(L10n.string("Add nutrition", defaultValue: "Add nutrition"))
        } footer: {
            Text(L10n.string(
                "Every option stays editable until you save the meal.",
                defaultValue: "Every option stays editable until you save the meal."
            ))
        }
    }

    @ViewBuilder
    private func recentMealReuseSection(viewModel: MealViewModel) -> some View {
        if !recentMealSuggestions.isEmpty {
            Section {
                FlowLayout(spacing: AppTheme.spacing8) {
                    ForEach(recentMealSuggestions) { suggestion in
                        Button {
                            viewModel.applyRecentMeal(suggestion)
                        } label: {
                            Label(suggestion.mealDescription, systemImage: "arrow.clockwise")
                                .appFont(.caption, weight: .semibold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, AppTheme.spacing8)
                                .background(
                                    Capsule()
                                        .fill(AppTheme.sage.opacity(AppTheme.opacityLight))
                                )
                                .foregroundStyle(AppTheme.sage)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text(L10n.string("Recent Meals", defaultValue: "Recent Meals"))
            } footer: {
                Text(L10n.string(
                    "Reuse meals you log often, then adjust anything that changed.",
                    defaultValue: "Reuse meals you log often, then adjust anything that changed."
                ))
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        guard let viewModel, let dirtyTracker else { return false }
        return dirtyTracker.isDirty(current: snapshot(for: viewModel))
    }

    private func initializeMealViewModelIfNeeded() {
        guard viewModel == nil else { return }
        Logger.meals.info("MealLogView initializing view model from \(entryPoint.rawValue, privacy: .public)")
        let vm = MealViewModel(modelContext: modelContext)
        viewModel = vm
        dirtyTracker = FormDirtyTracker(initial: snapshot(for: vm))
    }

    private func consumeInitialDestinationIfNeeded() {
        guard viewModel != nil, let destination = pendingInitialDestination else { return }
        pendingInitialDestination = nil

        switch destination {
        case .form:
            break
        case .barcode:
            showingBarcodeImport = true
        case .afterMealContext:
            focusedField = .postMealNote
        }
    }

    private func mealTypeSection(viewModel: MealViewModel) -> some View {
        Section {
            Picker("Meal Type", selection: Binding(
                get: { viewModel.mealType },
                set: {
                    viewModel.mealType = $0
                    viewModel.selectedTemplateID = nil
                }
            )) {
                ForEach(MealType.allCases) { type in
                    Label(type.displayName, systemImage: type.systemImage)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
        .sensoryFeedback(.selection, trigger: viewModel.mealType)
    }

    @ViewBuilder
    private func mealTemplateSection(viewModel: MealViewModel) -> some View {
        let templates = viewModel.mealTemplates
        if !templates.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text("PCOS-friendly templates")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: AppTheme.spacing8) {
                        ForEach(templates) { template in
                            let isSelected = template.id == viewModel.selectedTemplateID
                            Button {
                                viewModel.applyMealTemplate(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.title)
                                        .appFont(.caption, weight: .semibold)
                                    Text(template.glycemicImpact.displayName)
                                        .appFont(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                        .fill(isSelected ? AppTheme.sage.opacity(AppTheme.opacityMedium) : AppTheme.sage.opacity(AppTheme.opacityLight))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                        .stroke(isSelected ? AppTheme.sage : .clear, lineWidth: 1.5)
                                )
                                .foregroundStyle(AppTheme.sage)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("Meal Templates")
            }
        }
    }

    private func descriptionSection(viewModel: MealViewModel) -> some View {
        Section {
            TextField("What did you eat?", text: Binding(
                get: { viewModel.mealDescription },
                set: {
                    viewModel.mealDescription = $0
                    if viewModel.selectedTemplateID != nil {
                        viewModel.selectedTemplateID = nil
                    }
                }
            ))
            .focused($focusedField, equals: .description)
            .submitLabel(.next)
            .accessibilityIdentifier("meal_log.description")
            .onSubmit {
                focusedField = .carbs
            }

            mealDescriptionSuggestionsView(viewModel: viewModel)
        } header: {
            Text("Description")
        }
    }

    @ViewBuilder
    private func swapSuggestionsSection(viewModel: MealViewModel) -> some View {
        let swaps = viewModel.swapSuggestions
        if !swaps.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text("Recommended swaps")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(swaps, id: \.self) { swap in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.triangle.swap")
                                .appFont(.caption)
                                .foregroundStyle(AppTheme.accentColor)
                                .padding(.top, 2)
                            Text(swap)
                                .appFont(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Swap Suggestions")
            }
        }
    }

    @ViewBuilder
    private func mealGlucoseReadinessSection(viewModel: MealViewModel) -> some View {
        if let readiness = mealGlucoseReadiness {
            Section {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(readinessTitle(for: readiness.state), systemImage: readinessIcon(for: readiness.state))
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(readinessColor(for: readiness.state))

                    Text(readiness.message)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: AppTheme.spacing8) {
                        readinessMetric("\(readiness.mealCount)", label: "meals")
                        readinessMetric("\(readiness.pairedReadingCount)", label: "paired readings")
                        readinessMetric("\(readiness.postMealFeedbackCount)", label: "check-ins")
                    }

                    if !viewModel.mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        NavigationLink {
                            BloodSugarLogView(
                                prefillContext: GlucosePrefillContext(
                                    mealContext: "After \(viewModel.mealDescription)",
                                    readingType: .afterMeal,
                                    readingDate: Date()
                                )
                            )
                        } label: {
                            Label(
                                L10n.string("Log after-meal glucose", defaultValue: "Log after-meal glucose"),
                                systemImage: "drop.fill"
                            )
                        }
                    }
                }
            } header: {
                Text(L10n.string("Meal + Glucose Readiness", defaultValue: "Meal + Glucose Readiness"))
            }
        }
    }

    @ViewBuilder
    private func mealDescriptionSuggestionsView(viewModel: MealViewModel) -> some View {
        let suggestions = viewModel.mealDescriptionSuggestions
        if !suggestions.isEmpty {
            if viewModel.hasMealDescriptionQuery {
                autocompleteSuggestionsView(suggestions: suggestions) { suggestion in
                    viewModel.applyMealDescriptionSuggestion(suggestion)
                }
            } else {
                quickDescriptionSuggestionsView(suggestions: suggestions) { suggestion in
                    viewModel.applyMealDescriptionSuggestion(suggestion)
                }
            }
        }
    }

    private func autocompleteSuggestionsView(
        suggestions: [String],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Autocomplete")
                .appFont(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        HStack {
                            Text(suggestion)
                                .appFont(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .appFont(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, AppTheme.spacing12)
                        .padding(.vertical, AppTheme.spacing8)
                    }
                    .buttonStyle(.plain)

                    if index < suggestions.count - 1 {
                        Divider()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(Color.secondary.opacity(AppTheme.opacityLight), lineWidth: 1)
            )
        }
    }

    private func quickDescriptionSuggestionsView(
        suggestions: [String],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Quick options")
                .appFont(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: AppTheme.spacing8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    ChipButton(title: suggestion, color: AppTheme.sage) {
                        onSelect(suggestion)
                    }
                }
            }
        }
    }

    private func notesSection(viewModel: MealViewModel) -> some View {
        Section {
            TextField("Any additional notes...", text: Binding(
                get: { viewModel.notes },
                set: { viewModel.notes = $0 }
            ), axis: .vertical)
            .lineLimit(3...6)
            .focused($focusedField, equals: .notes)

            if !viewModel.mealNoteSuggestions.isEmpty {
                Text("Quick notes")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: AppTheme.spacing8) {
                    ForEach(viewModel.mealNoteSuggestions, id: \.self) { suggestion in
                        ChipButton(title: suggestion, isSelected: viewModel.isMealNoteSelected(suggestion), color: AppTheme.accentColor) {
                            viewModel.toggleMealNoteSuggestion(suggestion)
                        }
                    }
                }
            }
        } header: {
            Text(L10n.string("Notes", defaultValue: "Notes"))
        }
    }

    private func postMealFeedbackSection(viewModel: MealViewModel) -> some View {
        Section {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(
                    L10n.string(
                        "Use this after eating to connect meals with energy, cravings, bloating, or skin changes.",
                        defaultValue: "Use this after eating to connect meals with energy, cravings, bloating, or skin changes."
                    )
                )
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: AppTheme.spacing8) {
                    ForEach(1...5, id: \.self) { severity in
                        Button {
                            viewModel.postMealSymptomSeverity = severity
                        } label: {
                            Text("\(severity)")
                                .appFont(.caption, weight: .semibold)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(
                                            viewModel.postMealSymptomSeverity == severity
                                                ? AppTheme.coralAccent.opacity(0.22)
                                                : Color(.tertiarySystemFill)
                                        )
                                )
                                .foregroundStyle(
                                    viewModel.postMealSymptomSeverity == severity
                                        ? AppTheme.coralAccent
                                        : .secondary
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        viewModel.postMealSymptomSeverity = 0
                    } label: {
                        Text(L10n.string("Clear", defaultValue: "Clear"))
                            .appFont(.caption, weight: .semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, AppTheme.spacing8)
                            .background(
                                Capsule()
                                    .fill(Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                }

                TextField(
                    L10n.string(
                        "e.g., steady energy, hungry soon, bloated later",
                        defaultValue: "e.g., steady energy, hungry soon, bloated later"
                    ),
                    text: Binding(
                        get: { viewModel.postMealSymptomNote },
                        set: { viewModel.postMealSymptomNote = $0 }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...4)
                .focused($focusedField, equals: .postMealNote)
            }
        } header: {
            Text(L10n.string("After-meal check-in", defaultValue: "After-meal check-in"))
        }
    }

    private func macroInputRow(
        title: String,
        value: Binding<String>,
        options: [String],
        focused: FocusedField
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            HStack {
                Text("\(title) (g)")
                    .appFont(.subheadline, weight: .medium)

                Spacer()

                TextField("0", text: value)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .focused($focusedField, equals: focused)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacing8) {
                    ForEach(options, id: \.self) { option in
                        ChipButton(title: "\(option)g", color: AppTheme.sage) {
                            value.wrappedValue = option
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func saveMeal() {
        do {
            try viewModel?.saveMeal()
            refreshRoadmapContext()
            saveCoordinator.showSuccessAndDismiss {
                dismiss()
            }
        } catch {
            saveCoordinator.showErrorFeedback()
            activeAlert = .error(
                String(
                    localized: "Could not save meal: \(error.localizedDescription)",
                    comment: "Error shown when a meal entry cannot be saved."
                )
            )
        }
    }

    private func focusManualNutritionEntry() {
        if viewModel?.mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            focusedField = .description
        } else {
            focusedField = .carbs
        }
    }

    private func refreshRoadmapContext() {
        do {
            let service = MealGlucoseContextService(modelContext: modelContext)
            recentMealSuggestions = try service.recentMealReuseSuggestions(limit: 4)
            mealGlucoseReadiness = try service.readiness(days: 14)
        } catch {
            Logger.meals.error("Failed to refresh meal roadmap context: \(error.localizedDescription)")
        }
    }

    private func readinessTitle(for state: MealGlucoseReadiness.State) -> String {
        switch state {
        case .notReady:
            L10n.string("Start pairing", defaultValue: "Start pairing")
        case .building:
            L10n.string("Pattern building", defaultValue: "Pattern building")
        case .ready:
            L10n.string("Ready for reflection", defaultValue: "Ready for reflection")
        }
    }

    private func readinessIcon(for state: MealGlucoseReadiness.State) -> String {
        switch state {
        case .notReady:
            "circle.dashed"
        case .building:
            "chart.xyaxis.line"
        case .ready:
            "checkmark.seal.fill"
        }
    }

    private func readinessColor(for state: MealGlucoseReadiness.State) -> Color {
        switch state {
        case .notReady:
            .secondary
        case .building:
            AppTheme.coralAccent
        case .ready:
            AppTheme.sage
        }
    }

    private func readinessMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .appFont(.caption, weight: .semibold)
            Text(label)
                .appFont(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private func snapshot(for viewModel: MealViewModel) -> FormSnapshot {
        FormSnapshot(
            mealType: viewModel.mealType,
            mealDescription: viewModel.mealDescription,
            glycemicImpact: viewModel.glycemicImpact,
            carbsText: viewModel.carbsText,
            proteinText: viewModel.proteinText,
            fatText: viewModel.fatText,
            photoData: viewModel.photoData,
            notes: viewModel.notes,
            selectedTemplateID: viewModel.selectedTemplateID,
            postMealSymptomSeverity: viewModel.postMealSymptomSeverity,
            postMealSymptomNote: viewModel.postMealSymptomNote,
            mealDate: viewModel.mealDate
        )
    }

    @ViewBuilder
    private var mealLogLayoutDebugProbe: some View {
#if DEBUG
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    logInvalidMealLogLayoutIfNeeded(geometry.size, reason: "appear")
                }
                .onChange(of: geometry.size) { _, newSize in
                    logInvalidMealLogLayoutIfNeeded(newSize, reason: "resize")
                }
        }
#else
        EmptyView()
#endif
    }

#if DEBUG
    private func logInvalidMealLogLayoutIfNeeded(_ size: CGSize, reason: String) {
        guard !size.width.isFinite || !size.height.isFinite || size.width < 0 || size.height < 0 else { return }
        Logger.ui.debug(
            "MealLogView observed invalid root layout size. reason=\(reason, privacy: .public) width=\(size.width, privacy: .public) height=\(size.height, privacy: .public)"
        )
    }
#endif
}

private extension View {
    func lunarMealCard() -> some View {
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
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 8)
    }
}

private struct GIButton: View {
    let impact: GlycemicImpact
    let label: String
    let examples: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.spacing4) {
                Text(label)
                    .appFont(.subheadline, weight: .semibold)

                Text(examples)
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing8)
            .padding(.horizontal, AppTheme.spacing4)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .fill(isSelected ? color.opacity(0.2) : Color(.tertiarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

private struct BarcodeMealImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let modelContext: ModelContext
    let onUseCandidate: (FoodProductCandidate) -> Void

    @State private var barcodeText = ""
    @State private var lookupError: String?
    @State private var isLookingUp = false
    @State private var candidate: FoodProductCandidate?
    @State private var hasAcknowledgedConsent = UserDefaults.standard.bool(forKey: BarcodeMealImportSheet.consentDefaultsKey)
    @State private var lastScannedBarcode: String?

    private static let consentDefaultsKey = "nutrition.barcodeLookupConsentAcknowledged"

    var body: some View {
        NavigationStack {
            Form {
                if !hasAcknowledgedConsent {
                    Section {
                        Text(
                            L10n.string(
                                "UPC codes are sent to Open Food Facts for a keyless product lookup. You can review and edit the result before adding it to this meal.",
                                defaultValue: "UPC codes are sent to Open Food Facts for a keyless product lookup. You can review and edit the result before adding it to this meal."
                            )
                        )
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            UserDefaults.standard.set(true, forKey: Self.consentDefaultsKey)
                            hasAcknowledgedConsent = true
                        } label: {
                            Label("Continue", systemImage: "checkmark.shield")
                        }
                        .accessibilityIdentifier("meal_log.barcode_consent_continue")
                    }
                } else {
                    scannerSection
                    manualEntrySection
                    resultSection
                }
            }
            .navigationTitle("Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scannerSection: some View {
        Section {
#if canImport(VisionKit)
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                BarcodeDataScannerView { barcode in
                    guard lastScannedBarcode != barcode else { return }
                    lastScannedBarcode = barcode
                    barcodeText = barcode
                    Task {
                        await lookup(barcode)
                    }
                }
                .frame(minHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                .accessibilityIdentifier("meal_log.barcode_scanner")
            } else {
                Label("Scanner unavailable on this device", systemImage: "camera.viewfinder")
                    .foregroundStyle(.secondary)
            }
#else
            Label("Scanner unavailable on this device", systemImage: "camera.viewfinder")
                .foregroundStyle(.secondary)
#endif
        } header: {
            Text("Scan")
        }
    }

    private var manualEntrySection: some View {
        Section {
            TextField("UPC or EAN", text: $barcodeText)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .accessibilityIdentifier("meal_log.manual_barcode_field")

            Button {
                Task {
                    await lookup(barcodeText)
                }
            } label: {
                if isLookingUp {
                    ProgressView()
                } else {
                    Label("Look up barcode", systemImage: "magnifyingglass")
                }
            }
            .disabled(isLookingUp || OpenFoodFactsLookupService.cleanedBarcode(barcodeText).isEmpty)
            .accessibilityIdentifier("meal_log.lookup_barcode_button")

            if let lookupError {
                Label(lookupError, systemImage: "exclamationmark.triangle.fill")
                    .appFont(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Manual Entry")
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let candidate {
            Section {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label(localizedNutritionSourceLabel(candidate.sourceLabel), systemImage: "checkmark.seal")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.sage)

                    Text(candidate.productName)
                        .appFont(.headline)

                    if let brandName = candidate.brandName {
                        Text(brandName)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let servingText = candidate.servingText {
                        Text(servingText)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        nutritionPreview("Carbs", value: candidate.carbsGrams, suffix: "g")
                        nutritionPreview("Protein", value: candidate.proteinGrams, suffix: "g")
                        nutritionPreview("Fiber", value: candidate.fiberGrams, suffix: "g")
                    }

                    ProgressView(value: candidate.completeness, total: 1)
                        .tint(AppTheme.sage)

                    Button {
                        onUseCandidate(candidate)
                        dismiss()
                    } label: {
                        Label("Use in meal draft", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.sage)
                    .accessibilityIdentifier("meal_log.use_barcode_result_button")
                }
            } header: {
                Text("Review Result")
            }
        }
    }

    private func nutritionPreview(_ title: String, value: Double?, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appFont(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { "\(L10n.decimal($0, fractionDigits: 0))\(suffix)" } ?? "-")
                .appFont(.caption, weight: .semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func lookup(_ barcode: String) async {
        let cleanedBarcode = OpenFoodFactsLookupService.cleanedBarcode(barcode)
        guard !cleanedBarcode.isEmpty else {
            lookupError = FoodLookupError.invalidBarcode.localizedDescription
            return
        }

        isLookingUp = true
        lookupError = nil
        defer { isLookingUp = false }

        do {
            candidate = try await BarcodeProductLookupCoordinator(modelContext: modelContext)
                .lookupBarcode(cleanedBarcode)
        } catch {
            lookupError = error.localizedDescription
        }
    }
}

#if canImport(VisionKit)
private struct BarcodeDataScannerView: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcode: onBarcode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcode: (String) -> Void

        init(onBarcode: @escaping (String) -> Void) {
            self.onBarcode = onBarcode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            handle(items: addedItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            handle(items: updatedItems)
        }

        private func handle(items: [RecognizedItem]) {
            for item in items {
                if case let .barcode(barcode) = item,
                   let value = barcode.payloadStringValue,
                   !value.isEmpty {
                    onBarcode(value)
                    return
                }
            }
        }
    }
}
#endif

#Preview {
    MealLogView(entryPoint: .direct)
        .modelContainer(for: [
            MealEntry.self,
            MealScanFoodItem.self,
            MealScanNutritionSummary.self,
            MealScanMetadata.self,
            NutritionImportRecord.self,
            MealScanRepeatCacheRecord.self,
        ], inMemory: true)
}
