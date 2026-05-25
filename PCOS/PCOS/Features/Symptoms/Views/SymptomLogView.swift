import StoreKit
import SwiftUI
import SwiftData
import os

struct SymptomLogView: View {
    var initialCategory: SymptomCategory? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var viewModel: SymptomViewModel?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var activeAlert: ActiveAlert?
    @State private var dirtyTracker: FormDirtyTracker<FormSnapshot>?
    @State private var suggestionsExpanded = true

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
                                            updateSeverity(newSeverity, for: symptomType, source: "grid")
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
            .navigationTitle(L10n.string("Log Symptoms", defaultValue: "Log Symptoms"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.symptom_log")
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
                        SymptomHistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
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
            .onAppear {
                let vm = SymptomViewModel(modelContext: modelContext)
                if let initialCategory,
                   UserDefaults.standard.string(forKey: "symptom.selectedCategory") == nil {
                    vm.selectedCategory = initialCategory
                }
                vm.prefillTodaysSymptoms()
                vm.reloadSupportingData()
                viewModel = vm
                dirtyTracker = FormDirtyTracker(initial: snapshot(for: vm))
#if DEBUG
                let initialCategoryName = vm.selectedCategory?.rawValue ?? "all"
                Logger.symptoms.debug(
                    "Symptom log sheet opened initial_category=\(initialCategoryName, privacy: .public)"
                )
                Logger.symptomsSignposter.emitEvent("SymptomLogSheetOpen")
#endif
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
                    title: L10n.string("All", defaultValue: "All"),
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
                    copyYesterdaysSymptoms()
                } label: {
                    HStack(spacing: AppTheme.spacing12) {
                        Image(systemName: "arrow.counterclockwise")
                            .appFont(.title3)
                            .foregroundStyle(AppTheme.accentColor)

                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(L10n.string("Same as yesterday", defaultValue: "Same as yesterday"))
                                .appFont(.subheadline, weight: .semibold)
                            Text(
                                L10n.inflected(
                                    LocalizedStringResource(
                                        "^[\(vm.yesterdaySymptomCount) symptom](inflect: true)",
                                        comment: "Subtitle showing how many symptoms were copied from yesterday."
                                    )
                                )
                            )
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .appFont(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .cardStyle()
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(flexibility: .soft), trigger: vm.selectionCount)
            }

            // Combined suggestions section
            if let vm = viewModel, vm.selectionCount == 0 {
                let allSuggestions = combinedSuggestions
                if !allSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                suggestionsExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Text(L10n.string("Suggestions", defaultValue: "Suggestions"))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: suggestionsExpanded ? "chevron.up" : "chevron.down")
                                    .appFont(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        if suggestionsExpanded {
                            FlowLayout(spacing: AppTheme.spacing8) {
                                ForEach(allSuggestions) { type in
                                    ChipButton(
                                        title: type.displayName,
                                        systemImage: type.systemImage,
                                        color: periodFocusedQuickSymptoms.contains(type) ? AppTheme.coralAccent : AppTheme.accentColor
                                    ) {
                                        updateSeverity(2, for: type, source: "suggestion")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Compact row when symptoms are already selected
            HStack(spacing: AppTheme.spacing12) {
                if let vm = viewModel, vm.selectionCount > 0 || vm.yesterdaySymptomCount == 0 {
                    Button {
                        copyYesterdaysSymptoms()
                    } label: {
                        Label(yesterdayButtonLabel, systemImage: "arrow.counterclockwise")
                            .appFont(.subheadline)
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
                        Text(L10n.string("Clear all", defaultValue: "Clear all"))
                            .appFont(.subheadline)
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
                    Text(
                        L10n.inflected(
                            LocalizedStringResource(
                                "^[\(count) symptom](inflect: true) selected",
                                comment: "Footer text showing how many symptoms are currently selected."
                            )
                        )
                    )
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                } else {
                    Text(L10n.string("Tap a symptom to get started", defaultValue: "Tap a symptom to get started"))
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    saveSymptoms()
                } label: {
                    Text(L10n.string("Save", defaultValue: "Save"))
                        .appFont(.headline)
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
                .accessibilityIdentifier("symptom_log.save_button")
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
            return String(
                localized: "Same as yesterday (\(count))",
                comment: "Compact button label for copying the same symptoms as the previous day."
            )
        }
        return L10n.string("Same as yesterday", defaultValue: "Same as yesterday")
    }

    private var periodFocusedQuickSymptoms: [SymptomType] {
        guard initialCategory == .pain else { return [] }
        guard viewModel?.selectedCategory == .pain else { return [] }
        return [.cramps, .pelvicPain, .backPain, .nausea]
    }

    private var combinedSuggestions: [SymptomType] {
        var result: [SymptomType] = []
        result.append(contentsOf: periodFocusedQuickSymptoms)
        if let vm = viewModel {
            for type in vm.suggestedSymptoms where !result.contains(type) {
                result.append(type)
            }
        }
        return result
    }

    private func saveSymptoms() {
        guard let viewModel else { return }

        do {
            try viewModel.saveSymptoms()
            saveCoordinator.showSuccessAndDismiss {
                dismiss()
            }
            ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, requestReview: requestReview)
        } catch {
            saveCoordinator.showErrorFeedback()
            activeAlert = .error(
                String(
                    localized: "Could not save symptoms: \(error.localizedDescription)",
                    comment: "Error shown when symptom entries cannot be saved."
                )
            )
        }
    }

    private func copyYesterdaysSymptoms() {
        viewModel?.copyYesterdaysSymptoms()

#if DEBUG
        Logger.symptoms.debug("Copied yesterday's symptom selections into the current form")
        Logger.symptomsSignposter.emitEvent("SymptomCopyYesterday")
#endif
    }

    private func updateSeverity(_ newSeverity: Int, for symptomType: SymptomType, source: String) {
        guard let viewModel else { return }

        let previousSeverity = viewModel.severity(for: symptomType)
        guard previousSeverity != newSeverity else { return }

        viewModel.setSeverity(newSeverity, for: symptomType)

#if DEBUG
        Logger.symptoms.debug(
            "Symptom severity changed source=\(source, privacy: .public) type=\(symptomType.rawValue, privacy: .public) from=\(previousSeverity, privacy: .public) to=\(newSeverity, privacy: .public)"
        )
        Logger.symptomsSignposter.emitEvent("SymptomSeverityChange")
#endif
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
                .appFont(.subheadline, weight: isSelected ? .semibold : .regular)
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
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(Color(.tertiarySystemFill).opacity(0.5))
        )
        .opacity(isAnimating ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

#Preview {
    SymptomLogView()
        .environment(AppState())
        .modelContainer(for: SymptomEntry.self, inMemory: true)
}
