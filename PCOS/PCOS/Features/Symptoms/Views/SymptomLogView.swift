import SwiftUI
import SwiftData

struct SymptomLogView: View {
    var initialCategory: SymptomCategory? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SymptomViewModel?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var activeAlert: ActiveAlert?
    @State private var dirtyTracker: FormDirtyTracker<FormSnapshot>?

    private struct FormSnapshot: Equatable {
        var selectedCategory: SymptomCategory?
        var severities: [SymptomType: Int]
        var notes: [SymptomType: String]
        var logDate: Date
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
                // Category filter
                categoryFilterBar

                // Symptom grid
                if let viewModel {
                    ScrollView {
                        VStack(spacing: AppTheme.spacing16) {
                            // Quick actions row
                            quickActionsRow

                            // Symptom grid — 2 columns for better touch targets
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: AppTheme.spacing12),
                                    GridItem(.flexible(), spacing: AppTheme.spacing12),
                                ],
                                spacing: AppTheme.spacing12
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
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: AppTheme.spacing12),
                                GridItem(.flexible(), spacing: AppTheme.spacing12),
                            ],
                            spacing: AppTheme.spacing12
                        ) {
                            ForEach(0..<6, id: \.self) { _ in
                                SkeletonCard()
                            }
                        }
                        .padding()
                    }
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
                let vm = SymptomViewModel(modelContext: modelContext)
                if let initialCategory,
                   UserDefaults.standard.string(forKey: "symptom.selectedCategory") == nil {
                    vm.selectedCategory = initialCategory
                }
                vm.prefillTodaysSymptoms()
                viewModel = vm
                dirtyTracker = FormDirtyTracker(initial: snapshot(for: vm))
            }
            .onDisappear {
                saveCoordinator.cancelPending()
            }
        }
    }

    // MARK: - Subviews

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacing8) {
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
            .padding(.vertical, AppTheme.spacing8)
        }
        .background(AppTheme.groupedBackground)
    }

    private var quickActionsRow: some View {
        VStack(spacing: AppTheme.spacing12) {
            // Prominent "Same as yesterday" card when yesterday has data and nothing selected yet
            if let vm = viewModel, vm.yesterdaySymptomCount > 0, vm.selectionCount == 0 {
                Button {
                    vm.copyYesterdaysSymptoms()
                } label: {
                    HStack(spacing: AppTheme.spacing12) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accentColor)

                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text("Same as yesterday")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("\(vm.yesterdaySymptomCount) symptom\(vm.yesterdaySymptomCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .cardStyle()
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(flexibility: .soft), trigger: vm.selectionCount)
            }

            if let vm = viewModel,
               vm.selectionCount == 0,
               !periodFocusedQuickSymptoms.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text("Common on period days")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: AppTheme.spacing8) {
                        ForEach(periodFocusedQuickSymptoms) { type in
                            Button {
                                vm.setSeverity(2, for: type)
                            } label: {
                                Label(type.displayName, systemImage: type.systemImage)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(AppTheme.coralAccent.opacity(0.12)))
                                    .foregroundStyle(AppTheme.coralAccent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Frequent symptoms suggestion row
            if let vm = viewModel, vm.selectionCount == 0 {
                let frequent = vm.frequentSymptoms()
                if !frequent.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Text("Frequent this cycle")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: AppTheme.spacing8) {
                            ForEach(frequent) { type in
                                Button {
                                    vm.setSeverity(2, for: type)
                                } label: {
                                    Label(type.displayName, systemImage: type.systemImage)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(AppTheme.accentColor.opacity(0.12)))
                                        .foregroundStyle(AppTheme.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Compact row when symptoms are already selected
            HStack(spacing: AppTheme.spacing12) {
                if let vm = viewModel, vm.selectionCount > 0 || vm.yesterdaySymptomCount == 0 {
                    Button {
                        viewModel?.copyYesterdaysSymptoms()
                    } label: {
                        Label(yesterdayButtonLabel, systemImage: "arrow.counterclockwise")
                            .font(.subheadline)
                            .padding(.horizontal, AppTheme.spacing16)
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
                }

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
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if let count = viewModel?.selectionCount, count > 0 {
                    Text("\(count) symptom\(count == 1 ? "" : "s") selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                } else {
                    Text("Tap a symptom to get started")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
        guard let viewModel, let dirtyTracker else { return false }
        return dirtyTracker.isDirty(current: snapshot(for: viewModel))
    }

    private var yesterdayButtonLabel: String {
        if let count = viewModel?.yesterdaySymptomCount, count > 0 {
            return "Same as yesterday (\(count))"
        }
        return "Same as yesterday"
    }

    private var periodFocusedQuickSymptoms: [SymptomType] {
        guard initialCategory == .pain else { return [] }
        guard viewModel?.selectedCategory == .pain else { return [] }
        return [.cramps, .pelvicPain, .backPain, .nausea]
    }

    private func saveSymptoms() {
        do {
            try viewModel?.saveSymptoms()
            saveCoordinator.showSuccessAndDismiss {
                dismiss()
            }
        } catch {
            saveCoordinator.showErrorHaptic()
            activeAlert = .error("Could not save symptoms: \(error.localizedDescription)")
        }
    }

    private func snapshot(for viewModel: SymptomViewModel) -> FormSnapshot {
        FormSnapshot(
            selectedCategory: viewModel.selectedCategory,
            severities: viewModel.symptomSeverities,
            notes: viewModel.symptomNotes,
            logDate: viewModel.logDate
        )
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
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Skeleton Card

private struct SkeletonCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: AppTheme.spacing8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 32, height: 32)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 12)
                .padding(.horizontal, AppTheme.spacing8)

            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 18, height: 18)
                }
            }
        }
        .padding(.vertical, AppTheme.spacing12)
        .padding(.horizontal, AppTheme.spacing8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemFill).opacity(0.5))
        )
        .opacity(isAnimating ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

#Preview {
    SymptomLogView()
        .modelContainer(for: SymptomEntry.self, inMemory: true)
}
