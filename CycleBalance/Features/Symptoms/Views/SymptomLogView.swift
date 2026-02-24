import SwiftUI
import SwiftData

struct SymptomLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SymptomViewModel?
    @State private var showSavedFeedback = false

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
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if showSavedFeedback {
                    SavedFeedbackOverlay()
                }
            }
            .onAppear {
                let vm = SymptomViewModel(modelContext: modelContext)
                vm.prefillTodaysSymptoms()
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
                Label("Same as yesterday", systemImage: "arrow.counterclockwise")
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

    private func saveSymptoms() {
        viewModel?.saveSymptoms()
        showSavedFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
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
