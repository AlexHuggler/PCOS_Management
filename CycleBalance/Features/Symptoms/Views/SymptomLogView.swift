import SwiftUI
import SwiftData

struct SymptomLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SymptomViewModel?
    @State private var showSavedFeedback = false
    @State private var showCancelConfirmation = false
    @State private var saveError: String?
    @State private var initialSelectionCount = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter
                categoryFilterBar

                // Symptom grid
                if let viewModel {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Quick actions row
                            quickActionsRow

                            // Symptom grid — 2 columns for better touch targets
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12),
                                ],
                                spacing: 12
                            ) {
                                ForEach(viewModel.visibleSymptomTypes) { symptomType in
                                    SymptomGridItem(
                                        symptomType: symptomType,
                                        severity: viewModel.severity(for: symptomType),
                                        onSeverityChange: { newSeverity in
                                            viewModel.setSeverity(newSeverity, for: symptomType)
                                        }
                                    )
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    Spacer()
                    ProgressView("Loading symptoms...")
                    Spacer()
                }

                // Save button
                saveBar
            }
            .navigationTitle("Log Symptoms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges {
                            showCancelConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .alert("Discard Changes?", isPresented: $showCancelConfirmation) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("You have unsaved changes that will be lost.")
            }
            .sensoryFeedback(.success, trigger: showSavedFeedback)
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
                let vm = SymptomViewModel(modelContext: modelContext)
                vm.prefillTodaysSymptoms()
                initialSelectionCount = vm.selectionCount
                viewModel = vm
            }
        }
    }

    // MARK: - Subviews

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    title: "All",
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
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            Button {
                viewModel?.copyYesterdaysSymptoms()
            } label: {
                Label(yesterdayButtonLabel, systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
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
            .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel?.selectionCount ?? 0)

            Spacer()

            if let count = viewModel?.selectionCount, count > 0 {
                Button {
                    viewModel?.reset()
                } label: {
                    Text("Clear all")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if let count = viewModel?.selectionCount, count > 0 {
                    Text("\(count) symptom\(count == 1 ? "" : "s") selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    saveSymptoms()
                } label: {
                    Text("Save")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(viewModel?.hasSelections == true
                                      ? AppTheme.accentColor
                                      : Color.gray.opacity(0.3))
                        )
                        .foregroundStyle(.white)
                }
                .disabled(viewModel?.hasSelections != true)
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private var hasUnsavedChanges: Bool {
        (viewModel?.selectionCount ?? 0) != initialSelectionCount
    }

    private var yesterdayButtonLabel: String {
        if let count = viewModel?.yesterdaySymptomCount, count > 0 {
            return "Same as yesterday (\(count))"
        }
        return "Same as yesterday"
    }

    private func saveSymptoms() {
        do {
            try viewModel?.saveSymptoms()
            showSavedFeedback = true
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                dismiss()
            }
        } catch {
            saveError = "Could not save symptoms: \(error.localizedDescription)"
        }
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
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.accentColor : Color(.tertiarySystemFill))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

#Preview {
    SymptomLogView()
        .modelContainer(for: SymptomEntry.self, inMemory: true)
}
