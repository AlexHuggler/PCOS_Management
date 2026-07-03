import SwiftUI
import SwiftData

struct BloodSugarLogView: View {
    let prefillContext: GlucosePrefillContext?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: BloodSugarViewModel?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var activeAlert: ActiveAlert?
    @State private var dirtyTracker: FormDirtyTracker<FormSnapshot>?
    @State private var errorHapticTrigger = false
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case glucose
        case mealContext
        case notes
    }

    private struct FormSnapshot: Equatable {
        var glucoseValueText: String
        var readingType: GlucoseReadingType
        var mealContext: String
        var notes: String
        var readingDate: Date
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

    init(prefillContext: GlucosePrefillContext? = nil) {
        self.prefillContext = prefillContext
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if AppTheme.usesPremiumEditorStyling {
                        lunarBloodSugarContent(viewModel: viewModel)
                    } else {
                        standardBloodSugarContent(viewModel: viewModel)
                    }
                } else {
                    loadingContent
                }
            }
            .accessibilityIdentifier("screen.blood_sugar_log")
            .background {
                if AppTheme.usesPremiumEditorStyling {
                    AppTheme.premiumEditorBackground
                        .ignoresSafeArea()
                }
            }
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Log Blood Sugar", defaultValue: "Log Blood Sugar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .principal) {
                        Text(L10n.string("Blood sugar", defaultValue: "Blood sugar"))
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
                        BloodSugarHistoryView()
                    } label: {
                        Label(L10n.string("History", defaultValue: "History"), systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("blood_sugar_log.history_button")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .glucose {
                        Button(L10n.string("Next", defaultValue: "Next")) {
                            focusedField = .mealContext
                        }
                    } else if focusedField == .mealContext {
                        Button(L10n.string("Next", defaultValue: "Next")) {
                            focusedField = .notes
                        }
                    }
                    Spacer()
                    Button(L10n.string("Done", defaultValue: "Done")) {
                        focusedField = nil
                    }
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
            .sensoryFeedback(.error, trigger: errorHapticTrigger)
            .onAppear {
                initializeViewModelIfNeeded()
            }
            .onDisappear {
                saveCoordinator.cancelPending()
            }
        }
        .premiumGated()
    }

    private func standardBloodSugarContent(viewModel: BloodSugarViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppTheme.spacing16) {
                    inlineHistoryShortcut
                    glucoseSection(viewModel: viewModel)
                    readingTypeSection(viewModel: viewModel)
                    mealContextSection(viewModel: viewModel)
                    dateSection(viewModel: viewModel)
                    notesSection(viewModel: viewModel)
                }
                .padding()
            }

            saveBar
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppTheme.spacing16) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonListRow()
                            .cardStyle()
                    }
                    SkeletonChart()
                }
                .padding()
            }

            saveBar
        }
    }

    private var inlineHistoryShortcut: some View {
        NavigationLink {
            BloodSugarHistoryView()
        } label: {
            HStack(spacing: AppTheme.spacing12) {
                Image(systemName: "clock.arrow.circlepath")
                    .appFont(.title3)
                    .foregroundStyle(AppTheme.accentColor)

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(L10n.string("View History & Trends", defaultValue: "View History & Trends"))
                        .appFont(.headline)
                        .foregroundStyle(.primary)

                    Text(
                        L10n.string(
                            "Review past readings and recent patterns",
                            defaultValue: "Review past readings and recent patterns"
                        )
                    )
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("blood_sugar_log.inline_history_button")
    }

    private func glucoseSection(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Glucose Value")
                .appFont(.headline)

            HStack(spacing: AppTheme.spacing8) {
                TextField("Enter value", text: Binding(
                    get: { viewModel.glucoseValueText },
                    set: { viewModel.glucoseValueText = $0 }
                ))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .glucose)
                .accessibilityIdentifier("blood_sugar_log.glucose_value")
                .onChange(of: viewModel.glucoseValueText) { _, newValue in
                    // Auto-advance when user enters a valid 3+ digit glucose value
                    let digits = newValue.filter(\.isNumber)
                    if digits.count >= 3, viewModel.isValidGlucose {
                        focusedField = .mealContext
                    }
                }

                Text("mg/dL")
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.glucoseValueText.isEmpty && !viewModel.isValidGlucose {
                Text("Value must be between 40 and 600 mg/dL")
                    .appFont(.caption)
                    .foregroundStyle(.red)
            }

            // Range reference hints
            VStack(alignment: .leading, spacing: 2) {
                Text("Fasting: 70–100 mg/dL normal")
                Text("Post-meal: under 140 mg/dL typical")
            }
            .appFont(.caption2)
            .foregroundStyle(.tertiary)
        }
        .cardStyle()
    }

    private func readingTypeSection(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Reading Type")
                .appFont(.headline)

            Picker("Reading Type", selection: Binding(
                get: { viewModel.readingType },
                set: { viewModel.readingType = $0 }
            )) {
                ForEach(GlucoseReadingType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("blood_sugar_log.reading_type")
        }
        .cardStyle()
        .sensoryFeedback(.selection, trigger: viewModel.readingType)
    }

    private func mealContextSection(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Meal Context")
                .appFont(.headline)

            Text(
                L10n.string(
                    "Pair this reading with a meal or snack if you can.",
                    defaultValue: "Pair this reading with a meal or snack if you can."
                )
            )
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("e.g., After breakfast", text: Binding(
                get: { viewModel.mealContext },
                set: { viewModel.mealContext = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .submitLabel(.next)
            .focused($focusedField, equals: .mealContext)
            .accessibilityIdentifier("blood_sugar_log.meal_context")
            .onSubmit {
                focusedField = .notes
            }

            if !viewModel.mealContextSuggestions.isEmpty {
                Text("Quick context")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacing8) {
                        ForEach(viewModel.mealContextSuggestions, id: \.self) { suggestion in
                            ChipButton(title: suggestion, color: AppTheme.accentColor) {
                                viewModel.applyMealContextSuggestion(suggestion)
                            }
                        }
                    }
                }
            }

            Text(L10n.string("Optional", defaultValue: "Optional"))
                .appFont(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardStyle()
    }

    private func dateSection(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(L10n.string("Date & Time", defaultValue: "Date & Time"))
                .appFont(.headline)

            DatePicker(
                "Reading date",
                selection: Binding(
                    get: { viewModel.readingDate },
                    set: { viewModel.readingDate = $0 }
                ),
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .accessibilityIdentifier("blood_sugar_log.date")
        }
        .cardStyle()
    }

    private func notesSection(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(L10n.string("Notes", defaultValue: "Notes"))
                .appFont(.headline)

            TextField("Any additional notes", text: Binding(
                get: { viewModel.notes },
                set: { viewModel.notes = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)
            .focused($focusedField, equals: .notes)
            .accessibilityIdentifier("blood_sugar_log.notes")

            if !viewModel.noteSuggestions.isEmpty {
                Text("Quick notes")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: AppTheme.spacing8) {
                    ForEach(viewModel.noteSuggestions, id: \.self) { suggestion in
                        ChipButton(title: suggestion, isSelected: viewModel.isNoteSuggestionSelected(suggestion), color: AppTheme.sage) {
                            viewModel.toggleNoteSuggestion(suggestion)
                        }
                    }
                }
            }

            Text(L10n.string("Optional", defaultValue: "Optional"))
                .appFont(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardStyle()
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if let viewModel, viewModel.isValidGlucose {
                    Text("Ready to save")
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("blood_sugar_log.save_ready")
                } else {
                    Text("Enter a glucose value to save")
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("blood_sugar_log.save_prompt")
                }

                Spacer()

                Button {
                    saveReading()
                } label: {
                    Text("Save")
                        .appFont(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(viewModel?.isValidGlucose == true
                                      ? AppTheme.coralAccent
                                      : Color.gray.opacity(0.3))
                        )
                        .foregroundStyle(.white)
                }
                .disabled(viewModel?.isValidGlucose != true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.string("Save", defaultValue: "Save"))
                .accessibilityIdentifier("blood_sugar_log.save_button")
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private var hasUnsavedChanges: Bool {
        guard let viewModel, let dirtyTracker else { return false }
        return dirtyTracker.isDirty(current: snapshot(for: viewModel))
    }

    private func initializeViewModelIfNeeded() {
        guard viewModel == nil else { return }
        let vm = BloodSugarViewModel(modelContext: modelContext, prefillContext: prefillContext)
        viewModel = vm
        dirtyTracker = FormDirtyTracker(initial: snapshot(for: vm))
    }

    private func saveReading() {
        guard let viewModel else { return }

        do {
            try viewModel.saveReading()

            if var dirtyTracker {
                dirtyTracker.reset(to: snapshot(for: viewModel))
                self.dirtyTracker = dirtyTracker
            } else {
                dirtyTracker = FormDirtyTracker(initial: snapshot(for: viewModel))
            }

            saveCoordinator.showSuccessTransient()
            focusedField = .glucose
        } catch {
            saveCoordinator.showErrorFeedback()
            errorHapticTrigger.toggle()
            activeAlert = .error(
                String(
                    localized: "Could not save reading: \(error.localizedDescription)",
                    comment: "Error shown when a blood sugar reading cannot be saved."
                )
            )
        }
    }

    private func snapshot(for viewModel: BloodSugarViewModel) -> FormSnapshot {
        FormSnapshot(
            glucoseValueText: viewModel.glucoseValueText,
            readingType: viewModel.readingType,
            mealContext: viewModel.mealContext,
            notes: viewModel.notes,
            readingDate: viewModel.readingDate
        )
    }
}

private extension BloodSugarLogView {
    var lunarTwoColumnGrid: [GridItem] {
        [
            GridItem(.flexible(), spacing: AppTheme.spacing8),
            GridItem(.flexible(), spacing: AppTheme.spacing8),
        ]
    }

    func lunarBloodSugarContent(viewModel: BloodSugarViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                lunarHeader
                lunarHistoryShortcut
                lunarGlucoseCard(viewModel: viewModel)
                lunarReadingTypeCard(viewModel: viewModel)
                lunarMealContextCard(viewModel: viewModel)
                lunarDateCard(viewModel: viewModel)
                lunarNotesCard(viewModel: viewModel)
                lunarPatternCard(viewModel: viewModel)
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
        .accessibilityIdentifier("blood_sugar_log.lunar.surface")
    }

    var lunarHeader: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing12) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("Log glucose gently", defaultValue: "Log glucose gently"))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(L10n.string("Pair readings with meals, energy, and symptoms to find useful patterns over time.", defaultValue: "Pair readings with meals, energy, and symptoms to find useful patterns over time."))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.spacing8)

            ZStack {
                Circle()
                    .fill(AppTheme.premiumEditorAccentGradient)
                Image(systemName: "drop.triangle.fill")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            }
            .frame(width: 52, height: 52)
            .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.24), radius: 16, y: 8)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_log.lunar.header")
    }

    var lunarHistoryShortcut: some View {
        VStack(spacing: 0) {
            NavigationLink {
                BloodSugarHistoryView()
            } label: {
                HStack(spacing: AppTheme.spacing12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.premiumEditorAccentColor.opacity(0.16))
                        Image(systemName: "chart.xyaxis.line")
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.premiumEditorAccentColor)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(L10n.string("History & trends", defaultValue: "History & trends"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)

                        Text(L10n.string("Review recent readings, spikes, and cycle context.", defaultValue: "Review recent readings, spikes, and cycle context."))
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                }
                .padding(AppTheme.spacing12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .lunarBloodSugarCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("blood_sugar_log.inline_history_button")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_log.lunar.history")
    }

    func lunarGlucoseCard(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack {
                Label(L10n.string("Glucose reading", defaultValue: "Glucose reading"), systemImage: "waveform.path.ecg")
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text(glucoseStatusText(for: viewModel))
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(glucoseStatusColor(for: viewModel))
            }

            HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing8) {
                TextField("112", text: Binding(
                    get: { viewModel.glucoseValueText },
                    set: { viewModel.glucoseValueText = $0 }
                ))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .glucose)
                .submitLabel(.next)
                .padding(.horizontal, AppTheme.spacing12)
                .padding(.vertical, AppTheme.spacing8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(viewModel.isValidGlucose || viewModel.glucoseValueText.isEmpty ? AppTheme.premiumEditorBorder.opacity(0.58) : AppTheme.premiumEditorWarningAccentColor.opacity(0.8), lineWidth: 0.9)
                )
                .accessibilityIdentifier("blood_sugar_log.glucose_value")
                .onChange(of: viewModel.glucoseValueText) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits.count >= 3, viewModel.isValidGlucose {
                        focusedField = .mealContext
                    }
                }

                Text("mg/dL")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            if !viewModel.glucoseValueText.isEmpty && !viewModel.isValidGlucose {
                Text(L10n.string("Value must be between 40 and 600 mg/dL.", defaultValue: "Value must be between 40 and 600 mg/dL."))
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
            }

            FlowLayout(spacing: AppTheme.spacing8) {
                lunarReferenceChip(title: L10n.string("Fasting 70-100", defaultValue: "Fasting 70-100"), accent: AppTheme.premiumEditorAccentColor)
                lunarReferenceChip(title: L10n.string("Post-meal < 140", defaultValue: "Post-meal < 140"), accent: AppTheme.sage)
                lunarReferenceChip(title: L10n.string("Elevated 140+", defaultValue: "Elevated 140+"), accent: AppTheme.premiumEditorSecondaryAccentColor)
            }

            Text(L10n.string("Use your clinician's targets if they differ from these general reference ranges.", defaultValue: "Use your clinician's targets if they differ from these general reference ranges."))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing12)
        .lunarBloodSugarCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_log.lunar.glucose")
    }

    func lunarReadingTypeCard(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Reading type", defaultValue: "Reading type"), systemImage: "clock")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            LazyVGrid(columns: lunarTwoColumnGrid, spacing: AppTheme.spacing8) {
                ForEach(GlucoseReadingType.allCases) { type in
                    Button {
                        viewModel.readingType = type
                    } label: {
                        lunarTypePill(
                            title: type.displayName,
                            icon: readingTypeIcon(for: type),
                            isSelected: viewModel.readingType == type,
                            accent: readingTypeAccent(for: type)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(viewModel.readingType == type ? .isSelected : [])
                    .accessibilityIdentifier("blood_sugar_log.lunar.reading_type.\(type.rawValue)")
                }
            }

            Text(L10n.string("Choose the closest context. Estimates are useful even when timing is approximate.", defaultValue: "Choose the closest context. Estimates are useful even when timing is approximate."))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(AppTheme.spacing12)
        .lunarBloodSugarCard()
        .sensoryFeedback(.selection, trigger: viewModel.readingType)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_log.lunar.reading_type")
        .background(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("blood_sugar_log.reading_type")
        }
    }

    func lunarMealContextCard(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Meal context", defaultValue: "Meal context"), systemImage: "fork.knife")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            TextField("e.g., After breakfast", text: Binding(
                get: { viewModel.mealContext },
                set: { viewModel.mealContext = $0 }
            ), axis: .vertical)
            .appFont(.body)
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(2...4)
            .focused($focusedField, equals: .mealContext)
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
            .accessibilityIdentifier("blood_sugar_log.meal_context")
            .onSubmit {
                focusedField = .notes
            }

            if !viewModel.mealContextSuggestions.isEmpty {
                FlowLayout(spacing: AppTheme.spacing8) {
                    ForEach(viewModel.mealContextSuggestions.prefix(8), id: \.self) { suggestion in
                        Button {
                            viewModel.applyMealContextSuggestion(suggestion)
                        } label: {
                            lunarTextChip(
                                title: suggestion,
                                isSelected: viewModel.mealContext == suggestion,
                                accent: AppTheme.premiumEditorAccentColor
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(L10n.string("Optional. A short note like after lunch or before bed can make patterns easier to read.", defaultValue: "Optional. A short note like after lunch or before bed can make patterns easier to read."))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing12)
        .lunarBloodSugarCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_log.lunar.meal_context")
    }

    func lunarDateCard(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Reading date", defaultValue: "Reading date"), systemImage: "calendar")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            DatePicker(
                "Reading date",
                selection: Binding(
                    get: { viewModel.readingDate },
                    set: { viewModel.readingDate = $0 }
                ),
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .tint(AppTheme.premiumEditorAccentColor)
            .foregroundStyle(AppTheme.primaryText)
            .accessibilityIdentifier("blood_sugar_log.date")
        }
        .padding(AppTheme.spacing12)
        .lunarBloodSugarCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_log.lunar.date")
    }

    func lunarNotesCard(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Notes", defaultValue: "Notes"), systemImage: "text.bubble")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            TextField("Any additional notes", text: Binding(
                get: { viewModel.notes },
                set: { viewModel.notes = $0 }
            ), axis: .vertical)
            .appFont(.body)
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(3...6)
            .focused($focusedField, equals: .notes)
            .submitLabel(.done)
            .padding(AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
            )
            .accessibilityIdentifier("blood_sugar_log.notes")

            if !viewModel.noteSuggestions.isEmpty {
                FlowLayout(spacing: AppTheme.spacing8) {
                    ForEach(viewModel.noteSuggestions, id: \.self) { suggestion in
                        Button {
                            viewModel.toggleNoteSuggestion(suggestion)
                        } label: {
                            lunarTextChip(
                                title: suggestion,
                                isSelected: viewModel.isNoteSuggestionSelected(suggestion),
                                accent: AppTheme.lavenderAccent
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(L10n.string("Optional. Add symptoms, stress, sleep, movement, or anything that may help later.", defaultValue: "Optional. Add symptoms, stress, sleep, movement, or anything that may help later."))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing12)
        .lunarBloodSugarCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_log.lunar.notes")
    }

    func lunarPatternCard(viewModel: BloodSugarViewModel) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: "sparkles")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("Pattern building", defaultValue: "Pattern building"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Text(L10n.string("A few paired readings can help connect meals, cycle phase, energy, and symptoms without judging any single number.", defaultValue: "A few paired readings can help connect meals, cycle phase, energy, and symptoms without judging any single number."))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing12)
        .lunarBloodSugarCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_log.lunar.pattern")
    }

    func lunarSavePanel(viewModel: BloodSugarViewModel) -> some View {
        VStack(spacing: AppTheme.spacing8) {
            Button(action: saveReading) {
                Text(L10n.string("Save reading", defaultValue: "Save reading"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(viewModel.isValidGlucose ? AppTheme.premiumEditorCTAForeground : AppTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing16)
                    .background(
                        Capsule()
                            .fill(viewModel.isValidGlucose ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.premiumEditorBorder.opacity(0.9)))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isValidGlucose)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.string("Save reading", defaultValue: "Save reading"))
            .accessibilityIdentifier("blood_sugar_log.save_button")

            Text(viewModel.isValidGlucose
                 ? L10n.string("Private by default. Edit readings anytime.", defaultValue: "Private by default. Edit readings anytime.")
                 : L10n.string("Enter a glucose value to save.", defaultValue: "Enter a glucose value to save."))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityIdentifier(viewModel.isValidGlucose ? "blood_sugar_log.save_ready" : "blood_sugar_log.save_prompt")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blood_sugar_log.lunar.save_button")
    }

    func lunarTypePill(title: String, icon: String, isSelected: Bool, accent: Color) -> some View {
        HStack(spacing: AppTheme.spacing8) {
            Image(systemName: icon)
                .appFont(.caption, weight: .semibold)
            Text(title)
                .appFont(.caption, weight: isSelected ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .foregroundStyle(isSelected ? AppTheme.premiumEditorCTAForeground : accent)
        .background(
            Capsule()
                .fill(isSelected ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.premiumEditorRaisedSurface.opacity(0.72)))
        )
        .overlay(
            Capsule()
                .stroke(isSelected ? accent.opacity(0.42) : AppTheme.premiumEditorBorder.opacity(0.56), lineWidth: 0.8)
        )
    }

    func lunarTextChip(title: String, isSelected: Bool, accent: Color) -> some View {
        Text(title)
            .appFont(.caption, weight: isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? AppTheme.premiumEditorCTAForeground : accent)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, AppTheme.spacing12)
            .padding(.vertical, AppTheme.spacing8)
            .background(
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.premiumEditorSurface.opacity(0.88)))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? accent.opacity(0.42) : AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
            )
    }

    func lunarReferenceChip(title: String, accent: Color) -> some View {
        Text(title)
            .appFont(.caption, weight: .semibold)
            .foregroundStyle(accent)
            .padding(.horizontal, AppTheme.spacing12)
            .padding(.vertical, AppTheme.spacing8)
            .background(Capsule().fill(accent.opacity(0.12)))
            .overlay(Capsule().stroke(accent.opacity(0.34), lineWidth: 0.8))
    }

    func glucoseStatusText(for viewModel: BloodSugarViewModel) -> String {
        guard let value = Double(viewModel.glucoseValueText), viewModel.isValidGlucose else {
            return viewModel.glucoseValueText.isEmpty
                ? L10n.string("Not logged", defaultValue: "Not logged")
                : L10n.string("Check value", defaultValue: "Check value")
        }

        switch value {
        case ..<70:
            return L10n.string("Low range", defaultValue: "Low range")
        case 70..<140:
            return L10n.string("In range", defaultValue: "In range")
        case 140..<180:
            return L10n.string("Elevated", defaultValue: "Elevated")
        default:
            return L10n.string("High", defaultValue: "High")
        }
    }

    func glucoseStatusColor(for viewModel: BloodSugarViewModel) -> Color {
        guard let value = Double(viewModel.glucoseValueText), viewModel.isValidGlucose else {
            return viewModel.glucoseValueText.isEmpty ? AppTheme.secondaryText : AppTheme.premiumEditorWarningAccentColor
        }

        switch value {
        case ..<70:
            return AppTheme.lavenderAccent
        case 70..<140:
            return AppTheme.premiumEditorAccentColor
        case 140..<180:
            return AppTheme.premiumEditorSecondaryAccentColor
        default:
            return AppTheme.premiumEditorWarningAccentColor
        }
    }

    func readingTypeIcon(for type: GlucoseReadingType) -> String {
        switch type {
        case .fasting:
            return "sunrise.fill"
        case .beforeMeal:
            return "fork.knife.circle"
        case .afterMeal:
            return "chart.line.uptrend.xyaxis"
        case .random:
            return "sparkles"
        }
    }

    func readingTypeAccent(for type: GlucoseReadingType) -> Color {
        switch type {
        case .fasting:
            return AppTheme.premiumEditorSecondaryAccentColor
        case .beforeMeal:
            return AppTheme.premiumEditorAccentColor
        case .afterMeal:
            return AppTheme.sage
        case .random:
            return AppTheme.lavenderAccent
        }
    }
}

private extension View {
    func lunarBloodSugarCard() -> some View {
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
        .shadow(color: AppTheme.cardShadowColor.opacity(AppTheme.usesPremiumEditorStyling ? 1.0 : 0.8), radius: 14, y: 8)
    }
}

#Preview {
    BloodSugarLogView()
        .modelContainer(for: BloodSugarReading.self, inMemory: true)
}
