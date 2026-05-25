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
            VStack(spacing: 0) {
                if let viewModel {
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
                } else {
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
                }

                saveBar
            }
            .navigationTitle(L10n.string("Log Blood Sugar", defaultValue: "Log Blood Sugar"))
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
                        BloodSugarHistoryView()
                    } label: {
                        Label(L10n.string("History", defaultValue: "History"), systemImage: "clock.arrow.circlepath")
                    }
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
                let vm = BloodSugarViewModel(modelContext: modelContext, prefillContext: prefillContext)
                viewModel = vm
                dirtyTracker = FormDirtyTracker(initial: snapshot(for: vm))
            }
            .onDisappear {
                saveCoordinator.cancelPending()
            }
        }
        .premiumGated()
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
                } else {
                    Text("Enter a glucose value to save")
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
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
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private var hasUnsavedChanges: Bool {
        guard let viewModel, let dirtyTracker else { return false }
        return dirtyTracker.isDirty(current: snapshot(for: viewModel))
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

#Preview {
    BloodSugarLogView()
        .modelContainer(for: BloodSugarReading.self, inMemory: true)
}
