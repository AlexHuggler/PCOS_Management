import SwiftUI
import SwiftData

struct CycleLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CycleViewModel?

    var initialDate: Date?

    @State private var selectedDate = Date()
    @State private var selectedFlow: FlowIntensity = {
        if let raw = UserDefaults.standard.string(forKey: "cycle.lastFlowIntensity"),
           let intensity = FlowIntensity(rawValue: raw) {
            return intensity
        }
        return .medium
    }()
    @State private var notes = ""
    @State private var showSavedFeedback = false
    @State private var activeAlert: ActiveAlert?
    @State private var dismissTask: Task<Void, Never>?

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
                    Button("Discard", role: .destructive) { dismiss() }
                    Button("Keep Editing", role: .cancel) {}
                case .skip:
                    Button("Skip Period", role: .destructive) { skipPeriod() }
                    Button("Cancel", role: .cancel) {}
                case .error:
                    Button("OK", role: .cancel) {}
                }
            } message: { alert in
                switch alert {
                case .cancel:
                    Text("You have unsaved changes that will be lost.")
                case .skip:
                    Text("This will close your current cycle and start a new one from today. This action cannot be undone.")
                case .error(let message):
                    Text(message)
                }
            }
            .sensoryFeedback(.success, trigger: showSavedFeedback)
            .sensoryFeedback(.warning, trigger: activeAlert?.id)
            .overlay {
                if showSavedFeedback {
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
            }
            .onDisappear {
                dismissTask?.cancel()
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        !notes.isEmpty
    }

    private func logPeriod() {
        guard let viewModel else { return }
        viewModel.selectedDate = selectedDate
        viewModel.selectedFlowIntensity = selectedFlow
        viewModel.periodNotes = notes

        do {
            try viewModel.logPeriodDay()
            UserDefaults.standard.set(selectedFlow.rawValue, forKey: "cycle.lastFlowIntensity")
            showSavedFeedback = true
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                dismiss()
            }
        } catch {
            activeAlert = .error("Could not log period: \(error.localizedDescription)")
        }
    }

    private func skipPeriod() {
        guard let viewModel else { return }

        do {
            try viewModel.logSkippedPeriod()
            showSavedFeedback = true
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                dismiss()
            }
        } catch {
            activeAlert = .error("Could not skip period: \(error.localizedDescription)")
        }
    }
}

#Preview {
    CycleLogView()
        .modelContainer(for: [CycleEntry.self, Cycle.self], inMemory: true)
}
