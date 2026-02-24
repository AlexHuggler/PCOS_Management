import SwiftUI
import SwiftData

struct CycleLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CycleViewModel?

    @State private var selectedDate = Date()
    @State private var selectedFlow: FlowIntensity = .medium
    @State private var notes = ""
    @State private var showSkipConfirmation = false
    @State private var showSavedFeedback = false
    @State private var saveError: String?

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
                    TextField("How are you feeling?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
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
                        showSkipConfirmation = true
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
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Skip Period?", isPresented: $showSkipConfirmation) {
                Button("Skip Period", role: .destructive) {
                    skipPeriod()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will close your current cycle and start a new one from today. This action cannot be undone.")
            }
            .overlay {
                if showSavedFeedback {
                    SavedFeedbackOverlay()
                }
            }
            .alert("Save Failed", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "An unknown error occurred.")
            }
            .onAppear {
                viewModel = CycleViewModel(modelContext: modelContext)
            }
        }
    }

    private func logPeriod() {
        guard let viewModel else { return }
        viewModel.selectedDate = selectedDate
        viewModel.selectedFlowIntensity = selectedFlow
        viewModel.periodNotes = notes

        do {
            try viewModel.logPeriodDay()
            showSavedFeedback = true
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                dismiss()
            }
        } catch {
            saveError = "Could not log period: \(error.localizedDescription)"
        }
    }

    private func skipPeriod() {
        guard let viewModel else { return }

        do {
            try viewModel.logSkippedPeriod()
            showSavedFeedback = true
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                dismiss()
            }
        } catch {
            saveError = "Could not skip period: \(error.localizedDescription)"
        }
    }
}

#Preview {
    CycleLogView()
        .modelContainer(for: [CycleEntry.self, Cycle.self], inMemory: true)
}
