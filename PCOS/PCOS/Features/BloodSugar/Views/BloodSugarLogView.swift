import SwiftUI
import SwiftData

struct BloodSugarLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: BloodSugarViewModel?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var activeAlert: ActiveAlert?
    @State private var dirtyTracker: FormDirtyTracker<FormSnapshot>?
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let viewModel {
                    ScrollView {
                        VStack(spacing: AppTheme.spacing16) {
                            glucoseSection(viewModel: viewModel)
                            readingTypeSection(viewModel: viewModel)
                            mealContextSection(viewModel: viewModel)
                            dateSection(viewModel: viewModel)
                            notesSection(viewModel: viewModel)
                        }
                        .padding()
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                saveBar
            }
            .navigationTitle("Log Blood Sugar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .glucose {
                        Button("Next") {
                            focusedField = .mealContext
                        }
                    } else if focusedField == .mealContext {
                        Button("Next") {
                            focusedField = .notes
                        }
                    }
                    Spacer()
                    Button("Done") {
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
            .sensoryFeedback(.warning, trigger: activeAlert?.id)
            .overlay {
                if saveCoordinator.isShowingSavedFeedback {
                    SavedFeedbackOverlay()
                }
            }
            .onAppear {
                let vm = BloodSugarViewModel(modelContext: modelContext)
                viewModel = vm
                dirtyTracker = FormDirtyTracker(initial: snapshot(for: vm))
            }
            .onDisappear {
                saveCoordinator.cancelPending()
            }
        }
        .premiumGated()
    }

    private func glucoseSection(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Glucose Value")
                .font(.headline)

            HStack(spacing: AppTheme.spacing8) {
                TextField("Enter value", text: Binding(
                    get: { viewModel.glucoseValueText },
                    set: { viewModel.glucoseValueText = $0 }
                ))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .glucose)

                Text("mg/dL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.glucoseValueText.isEmpty && !viewModel.isValidGlucose {
                Text("Value must be between 40 and 600 mg/dL")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .cardStyle()
    }

    private func readingTypeSection(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Reading Type")
                .font(.headline)

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
    }

    private func mealContextSection(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Meal Context")
                .font(.headline)

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
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacing8) {
                        ForEach(viewModel.mealContextSuggestions, id: \.self) { suggestion in
                            Button {
                                viewModel.applyMealContextSuggestion(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(AppTheme.accentColor.opacity(0.12))
                                    )
                                    .foregroundStyle(AppTheme.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text("Optional")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardStyle()
    }

    private func dateSection(viewModel: BloodSugarViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Date & Time")
                .font(.headline)

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
            Text("Notes")
                .font(.headline)

            TextField("Any additional notes", text: Binding(
                get: { viewModel.notes },
                set: { viewModel.notes = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)
            .focused($focusedField, equals: .notes)

            if !viewModel.noteSuggestions.isEmpty {
                Text("Quick notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacing8) {
                        ForEach(viewModel.noteSuggestions, id: \.self) { suggestion in
                            let isSelected = viewModel.isNoteSuggestionSelected(suggestion)
                            Button {
                                viewModel.toggleNoteSuggestion(suggestion)
                            } label: {
                                HStack(spacing: 4) {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.caption2)
                                    }
                                    Text(suggestion)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? AppTheme.sage.opacity(0.26) : AppTheme.sage.opacity(0.18))
                                )
                                .foregroundStyle(AppTheme.sage)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text("Optional")
                .font(.caption)
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enter a glucose value to save")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    saveReading()
                } label: {
                    Text("Save")
                        .font(.headline)
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
        do {
            try viewModel?.saveReading()
            saveCoordinator.showSuccessAndDismiss {
                dismiss()
            }
        } catch {
            saveCoordinator.showErrorHaptic()
            activeAlert = .error("Could not save reading: \(error.localizedDescription)")
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
