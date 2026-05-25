import SwiftUI
import SwiftData
import PhotosUI
import os

enum MealLogEntryPoint: String, Sendable {
    case trackingHub = "tracking_hub"
    case today = "today"
    case direct = "direct"
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
    @FocusState private var focusedField: FocusedField?

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
            Form {
                if let viewModel {
                    mealTypeSection(viewModel: viewModel)
                    descriptionSection(viewModel: viewModel)
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
                        let selectedPhotoData = viewModel.photoData
                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images
                        ) {
                            HStack {
                                if let photoData = selectedPhotoData,
                                   let uiImage = UIImage(data: photoData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Spacer()

                                    Button(L10n.string("Remove", defaultValue: "Remove")) {
                                        viewModel.photoData = nil
                                        selectedPhotoItem = nil
                                    }
                                    .foregroundStyle(.red)
                                } else {
                                    Label("Add Photo", systemImage: "camera")
                                        .foregroundStyle(AppTheme.sage)
                                }
                            }
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
            .accessibilityIdentifier("screen.meal_log")
            .background(mealLogLayoutDebugProbe)
            .navigationTitle(L10n.string("Log Meal", defaultValue: "Log Meal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel", defaultValue: "Cancel")) {
                        if hasUnsavedChanges {
                            activeAlert = .cancel
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MealHistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
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

                if viewModel == nil {
                    Logger.meals.info("MealLogView initializing view model from \(entryPoint.rawValue, privacy: .public)")
                    let vm = MealViewModel(modelContext: modelContext)
                    viewModel = vm
                    dirtyTracker = FormDirtyTracker(initial: snapshot(for: vm))
                }
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

#Preview {
    MealLogView(entryPoint: .direct)
        .modelContainer(for: MealEntry.self, inMemory: true)
}
