import SwiftUI
import SwiftData

struct CycleLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    private let suggestionProvider = SuggestionProvider()
    @State private var viewModel: CycleViewModel?
    @State private var selectedDate = Date()
    @State private var selectedFlow: FlowIntensity = {
        if let raw = UserDefaults.standard.string(forKey: "cycle.lastFlowIntensity"),
           let intensity = FlowIntensity(rawValue: raw) {
            return intensity
        }
        return .medium
    }()
    @State private var notes = ""
    @State private var activeAlert: ActiveAlert?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var dirtyTracker: FormDirtyTracker<FormSnapshot>?

    var initialDate: Date?

    private struct FormSnapshot: Equatable {
        var selectedDate: Date
        var selectedFlow: FlowIntensity
        var notes: String
    }

    private enum ActiveAlert: Identifiable {
        case cancel
        case skip
        case error(String)

        var id: String {
            switch self {
            case .cancel: "cancel"
            case .skip: "skip"
            case .error: "error"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker(
                        "Period date",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .tint(AppTheme.accentColor)
                }

                Section("Flow Intensity") {
                    FlowIntensityPicker(selection: $selectedFlow)
                }

                Section("Notes") {
                    TextField("e.g., clotting, mood changes, spotting duration...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.sentences)

                    if !periodNoteSuggestions.isEmpty {
                        Text("Quick notes for \(selectedFlow.displayName.lowercased()) flow")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppTheme.spacing8) {
                                ForEach(periodNoteSuggestions, id: \.self) { suggestion in
                                    let isSelected = QuickNoteComposer.isSelected(suggestion, in: notes)
                                    Button {
                                        notes = QuickNoteComposer.toggled(suggestion, in: notes)
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
                                                .fill(
                                                    isSelected
                                                    ? flowColor(for: selectedFlow).opacity(0.22)
                                                    : flowColor(for: selectedFlow).opacity(0.12)
                                                )
                                        )
                                        .foregroundStyle(flowColor(for: selectedFlow))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    Button {
                        logPeriod()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Log Period Day", systemImage: "drop.fill")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .tint(AppTheme.coralAccent)

                    Button {
                        activeAlert = .skip
                    } label: {
                        HStack {
                            Spacer()
                            Text("I skipped a period")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Log Period")
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
                case .skip:
                    return Alert(
                        title: Text("Skip this period?"),
                        message: Text("This will close your current cycle and start a new one from today. This action cannot be undone."),
                        primaryButton: .destructive(Text("Skip Period")) { skipPeriod() },
                        secondaryButton: .cancel(Text("Cancel"))
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
                if viewModel == nil {
                    viewModel = CycleViewModel(modelContext: modelContext)
                }
                if let initialDate {
                    selectedDate = initialDate
                }
                dirtyTracker = FormDirtyTracker(initial: snapshot)
            }
            .onDisappear {
                saveCoordinator.cancelPending()
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        guard let dirtyTracker else { return false }
        return dirtyTracker.isDirty(current: snapshot)
    }

    private var snapshot: FormSnapshot {
        FormSnapshot(
            selectedDate: selectedDate,
            selectedFlow: selectedFlow,
            notes: notes
        )
    }

    private var periodNoteSuggestions: [String] {
        guard selectedFlow != .none else { return [] }
        return suggestionProvider.periodNoteSuggestions(
            flowIntensity: selectedFlow,
            query: noteSuggestionQuery,
            limit: 8
        )
    }

    private var noteSuggestionQuery: String {
        let baseSuggestions = suggestionProvider.periodNoteSuggestions(
            flowIntensity: selectedFlow,
            query: "",
            limit: 20
        )

        let segments = notes.split(separator: ",", omittingEmptySubsequences: false)
        guard let lastSegment = segments.last else {
            return notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let candidate = String(lastSegment).trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.contains(",") {
            return candidate
        }

        if baseSuggestions.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
            return ""
        }
        return candidate
    }

    private func logPeriod() {
        guard let viewModel else { return }
        viewModel.selectedDate = selectedDate
        viewModel.selectedFlowIntensity = selectedFlow
        viewModel.periodNotes = notes

        do {
            try viewModel.logPeriodDay()
            recordPeriodNoteSuggestions()
            UserDefaults.standard.set(selectedFlow.rawValue, forKey: "cycle.lastFlowIntensity")
            saveCoordinator.showSuccessAndDismiss {
                dismiss()
            }
        } catch {
            saveCoordinator.showErrorHaptic()
            activeAlert = .error("Could not log period: \(error.localizedDescription)")
        }
    }

    private func skipPeriod() {
        guard let viewModel else { return }

        do {
            try viewModel.logSkippedPeriod()
            saveCoordinator.showSuccessAndDismiss {
                dismiss()
            }
        } catch {
            saveCoordinator.showErrorHaptic()
            activeAlert = .error("Could not skip period: \(error.localizedDescription)")
        }
    }

    private func recordPeriodNoteSuggestions() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNotes.isEmpty, selectedFlow != .none else { return }

        let noteTokens = QuickNoteComposer.tokens(from: trimmedNotes)
        if noteTokens.count > 1 {
            for token in noteTokens {
                suggestionProvider.recordPeriodNote(token, flowIntensity: selectedFlow)
            }
        } else {
            suggestionProvider.recordPeriodNote(trimmedNotes, flowIntensity: selectedFlow)
        }
    }

    private func flowColor(for intensity: FlowIntensity) -> Color {
        switch intensity {
        case .spotting:
            AppTheme.flowSpotting
        case .light:
            AppTheme.flowLight
        case .medium:
            AppTheme.flowMedium
        case .heavy:
            AppTheme.flowHeavy
        case .none:
            .secondary
        }
    }
}

#Preview {
    CycleLogView()
        .modelContainer(for: [CycleEntry.self, Cycle.self], inMemory: true)
}
