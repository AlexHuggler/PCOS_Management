import StoreKit
import SwiftUI
import SwiftData

struct CycleLogView: View {
    private enum LoggingMode: String, CaseIterable, Identifiable {
        case singleDay
        case dateRange

        var id: String { rawValue }
    }

    private struct PendingSaveRequest: Identifiable {
        let id = UUID()
        let startDate: Date
        let endDate: Date
        let flowIntensity: FlowIntensity
        let notes: String
    }

    private struct FormSnapshot: Equatable {
        var loggingMode: LoggingMode
        var selectedDate: Date
        var rangeStartDate: Date
        var rangeEndDate: Date
        var rangeEndsToday: Bool
        var selectedFlow: FlowIntensity
        var notes: String
    }

    private enum ActiveAlert: Identifiable {
        case cancel
        case error(String)
        case confirmNewCycle(PendingSaveRequest, Int)

        var id: String {
            switch self {
            case .cancel:
                "cancel"
            case .error(let message):
                "error-\(message)"
            case .confirmNewCycle(let request, _):
                "confirm-\(request.id.uuidString)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    private let suggestionProvider = SuggestionProvider()

    @State private var viewModel: CycleViewModel?
    @State private var loggingMode: LoggingMode = .singleDay
    @State private var selectedDate = Date()
    @State private var rangeStartDate = Date()
    @State private var rangeEndDate = Date()
    @State private var rangeEndsToday = true
    @State private var selectedFlow: FlowIntensity = {
        if let raw = UserDefaults.standard.string(forKey: "cycle.lastFlowIntensity"),
           let intensity = FlowIntensity(rawValue: raw),
           intensity != FlowIntensity.none {
            return intensity
        }
        return .medium
    }()
    @State private var notes = ""
    @State private var activeAlert: ActiveAlert?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var dirtyTracker: FormDirtyTracker<FormSnapshot>?
    @State private var pendingUndoSnapshot: CycleLogUndoSnapshot?
    @State private var showUndoToast = false

    var initialDate: Date?

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.string("Logging Mode", defaultValue: "Logging Mode")) {
                    Picker(
                        L10n.string("Logging mode", defaultValue: "Logging mode"),
                        selection: $loggingMode
                    ) {
                        Text(L10n.string("Single day", defaultValue: "Single day"))
                            .tag(LoggingMode.singleDay)
                        Text(L10n.string("Date range", defaultValue: "Date range"))
                            .tag(LoggingMode.dateRange)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("cycle_log.logging_mode")
                }

                dateSection

                Section(L10n.string("Flow Intensity", defaultValue: "Flow Intensity")) {
                    FlowIntensityPicker(selection: $selectedFlow)
                }

                Section(L10n.string("Notes", defaultValue: "Notes")) {
                    TextField(
                        L10n.string(
                            "e.g., clotting, mood changes, spotting duration...",
                            defaultValue: "e.g., clotting, mood changes, spotting duration..."
                        ),
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)

                    if !periodNoteSuggestions.isEmpty {
                        Text(
                            L10n.format(
                                "Quick notes for %@ flow",
                                defaultValue: "Quick notes for %@ flow",
                                selectedFlow.displayName
                            )
                        )
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                        FlowLayout(spacing: AppTheme.spacing8) {
                            ForEach(periodNoteSuggestions, id: \.self) { suggestion in
                                ChipButton(
                                    title: suggestion,
                                    isSelected: QuickNoteComposer.isSelected(suggestion, in: notes),
                                    color: flowColor(for: selectedFlow)
                                ) {
                                    notes = QuickNoteComposer.toggled(suggestion, in: notes)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    Button(action: attemptSave) {
                        HStack {
                            Spacer()
                            Label(saveButtonTitle, systemImage: "drop.fill")
                                .appFont(.headline)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                    }
                    .tint(AppTheme.coralAccent)
                    .accessibilityIdentifier("cycle_log.save_button")

                    if loggingMode == .singleDay {
                        Button(action: markNoPeriodDay) {
                            HStack {
                                Spacer()
                                Label(
                                    L10n.string("No period on this date", defaultValue: "No period on this date"),
                                    systemImage: "checkmark.circle"
                                )
                                .foregroundStyle(AppTheme.sage)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                        }
                        .accessibilityIdentifier("cycle_log.no_period_button")
                    }
                }
            }
            .navigationTitle(L10n.string("Log Period", defaultValue: "Log Period"))
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
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .cancel:
                    return Alert(
                        title: Text(L10n.string("Discard changes?", defaultValue: "Discard changes?")),
                        message: Text(L10n.string("You have unsaved changes that will be lost.", defaultValue: "You have unsaved changes that will be lost.")),
                        primaryButton: .destructive(Text(L10n.string("Discard", defaultValue: "Discard"))) { dismiss() },
                        secondaryButton: .cancel(Text(L10n.string("Keep Editing", defaultValue: "Keep Editing")))
                    )
                case .error(let message):
                    return Alert(
                        title: Text(L10n.string("Could not Save", defaultValue: "Could not Save")),
                        message: Text(message),
                        dismissButton: .cancel(Text(L10n.string("OK", defaultValue: "OK")))
                    )
                case .confirmNewCycle(let request, let gapDays):
                    return Alert(
                        title: Text(L10n.string("Start a new cycle?", defaultValue: "Start a new cycle?")),
                        message: Text(
                            L10n.format(
                                "This log starts %lld days after your last tracked period day. Confirm to reset the current cycle count and start a new cycle on %@.",
                                defaultValue: "This log starts %lld days after your last tracked period day. Confirm to reset the current cycle count and start a new cycle on %@.",
                                Int64(gapDays),
                                request.startDate.formatted(date: .abbreviated, time: .omitted)
                            )
                        ),
                        primaryButton: .default(Text(L10n.string("Confirm New Cycle", defaultValue: "Confirm New Cycle"))) {
                            performSave(request, startingNewCycle: true)
                        },
                        secondaryButton: .cancel(Text(L10n.string("Keep Current Cycle", defaultValue: "Keep Current Cycle")))
                    )
                }
            }
            .overlay {
                if saveCoordinator.isShowingSavedFeedback {
                    SavedFeedbackOverlay()
                }
            }
            .overlay(alignment: .bottom) {
                if showUndoToast, pendingUndoSnapshot != nil {
                    UndoToast(
                        message: undoToastMessage,
                        onUndo: undoRangeSave,
                        onExpire: {
                            withAnimation {
                                pendingUndoSnapshot = nil
                                showUndoToast = false
                            }
                        }
                    )
                    .padding()
                }
            }
            .sensoryFeedback(.selection, trigger: selectedFlow)
            .sensoryFeedback(.success, trigger: saveCoordinator.isShowingSavedFeedback)
            .onAppear {
                if viewModel == nil {
                    let newViewModel = CycleViewModel(modelContext: modelContext)
                    newViewModel.loadData()
                    viewModel = newViewModel
                }
                let defaultDate = initialDate ?? Date()
                selectedDate = defaultDate
                rangeStartDate = defaultDate
                rangeEndDate = defaultDate
                dirtyTracker = FormDirtyTracker(initial: snapshot)
            }
            .onChange(of: rangeEndsToday) { _, isEnabled in
                if isEnabled {
                    rangeEndDate = Date()
                }
            }
            .onChange(of: rangeStartDate) { _, newValue in
                if rangeEndDate < newValue {
                    rangeEndDate = newValue
                }
            }
            .onDisappear {
                saveCoordinator.cancelPending()
            }
        }
    }

    @ViewBuilder
    private var dateSection: some View {
        Section(L10n.string("Date", defaultValue: "Date")) {
            if loggingMode == .singleDay {
                DatePicker(
                    L10n.string("Period date", defaultValue: "Period date"),
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(AppTheme.accentColor)
                .accessibilityIdentifier("cycle_log.single_date")
            } else {
                DatePicker(
                    L10n.string("Start date", defaultValue: "Start date"),
                    selection: $rangeStartDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(AppTheme.accentColor)
                .accessibilityIdentifier("cycle_log.range_start_date")

                Toggle(
                    L10n.string("Through today", defaultValue: "Through today"),
                    isOn: $rangeEndsToday
                )
                .accessibilityIdentifier("cycle_log.through_today")

                if !rangeEndsToday {
                    DatePicker(
                        L10n.string("End date", defaultValue: "End date"),
                        selection: $rangeEndDate,
                        in: rangeStartDate...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .tint(AppTheme.accentColor)
                    .accessibilityIdentifier("cycle_log.range_end_date")
                }
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        guard let dirtyTracker else { return false }
        return dirtyTracker.isDirty(current: snapshot)
    }

    private var snapshot: FormSnapshot {
        FormSnapshot(
            loggingMode: loggingMode,
            selectedDate: selectedDate,
            rangeStartDate: rangeStartDate,
            rangeEndDate: rangeEndDate,
            rangeEndsToday: rangeEndsToday,
            selectedFlow: selectedFlow,
            notes: notes
        )
    }

    private var resolvedStartDate: Date {
        loggingMode == .singleDay ? selectedDate : rangeStartDate
    }

    private var resolvedEndDate: Date {
        if loggingMode == .singleDay {
            return selectedDate
        }
        return rangeEndsToday ? Date() : rangeEndDate
    }

    private var saveButtonTitle: String {
        switch loggingMode {
        case .singleDay:
            return L10n.string("Log Period Day", defaultValue: "Log Period Day")
        case .dateRange:
            return L10n.string("Log Period Range", defaultValue: "Log Period Range")
        }
    }

    private var undoToastMessage: String {
        L10n.string(
            "Period range saved. Undo to restore your previous entries.",
            defaultValue: "Period range saved. Undo to restore your previous entries."
        )
    }

    private var periodNoteSuggestions: [String] {
        guard selectedFlow != .none else { return [] }
        let baseSuggestions = suggestionProvider.periodNoteSuggestions(
            flowIntensity: selectedFlow,
            query: "",
            limit: 20
        )
        let filteredSuggestions = suggestionProvider.periodNoteSuggestions(
            flowIntensity: selectedFlow,
            query: QuickNoteComposer.suggestionQuery(in: notes, availableSuggestions: baseSuggestions),
            limit: 8
        )
        return QuickNoteComposer.visibleSuggestions(
            from: filteredSuggestions,
            selectedIn: notes,
            availableSuggestions: baseSuggestions
        )
    }

    private func attemptSave() {
        let request = PendingSaveRequest(
            startDate: resolvedStartDate,
            endDate: resolvedEndDate,
            flowIntensity: selectedFlow,
            notes: notes
        )

        guard let viewModel else { return }
        let transition = viewModel.evaluatePeriodTransition(startDate: request.startDate)

        if case .requiresNewCycleConfirmation(_, let gapDays) = transition {
            activeAlert = .confirmNewCycle(request, gapDays)
            return
        }

        performSave(request, startingNewCycle: false)
    }

    private func performSave(_ request: PendingSaveRequest, startingNewCycle: Bool) {
        guard let viewModel else { return }

        do {
            let result: CycleRangeSaveResult
            if loggingMode == .singleDay {
                result = try viewModel.savePeriodDay(
                    date: request.startDate,
                    flowIntensity: request.flowIntensity,
                    notes: request.notes,
                    startingNewCycle: startingNewCycle
                )
            } else {
                result = try viewModel.savePeriodRange(
                    startDate: request.startDate,
                    endDate: request.endDate,
                    flowIntensity: request.flowIntensity,
                    notes: request.notes,
                    startingNewCycle: startingNewCycle
                )
            }

            recordPeriodNoteSuggestions()
            UserDefaults.standard.set(request.flowIntensity.rawValue, forKey: "cycle.lastFlowIntensity")
            dirtyTracker = FormDirtyTracker(initial: snapshot)

            if loggingMode == .dateRange {
                pendingUndoSnapshot = result.undoSnapshot
                withAnimation {
                    showUndoToast = result.undoSnapshot != nil
                }
                saveCoordinator.showSuccessTransient()
            } else {
                pendingUndoSnapshot = nil
                showUndoToast = false
                saveCoordinator.showSuccessAndDismiss {
                    dismiss()
                }
            }

            ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, requestReview: requestReview)
        } catch {
            saveCoordinator.showErrorFeedback()
            activeAlert = .error(
                String(
                    localized: "Could not log period: \(error.localizedDescription)",
                    comment: "Error shown when a period day cannot be saved."
                )
            )
        }
    }

    private func undoRangeSave() {
        guard let viewModel, let pendingUndoSnapshot else { return }

        do {
            try viewModel.undoPeriodSave(
                using: pendingUndoSnapshot,
                referenceDate: resolvedEndDate
            )
            saveCoordinator.showSuccessTransient()
            withAnimation {
                self.pendingUndoSnapshot = nil
                showUndoToast = false
            }
            dirtyTracker = FormDirtyTracker(initial: snapshot)
        } catch {
            activeAlert = .error(
                String(
                    localized: "Could not undo period range: \(error.localizedDescription)",
                    comment: "Error shown when undoing a period range fails."
                )
            )
        }
    }

    private func markNoPeriodDay() {
        guard let viewModel else { return }

        do {
            let result = try viewModel.saveNoPeriodDay(date: selectedDate)
            if result.savedDates.isEmpty {
                activeAlert = .error(
                    L10n.string(
                        "Log your latest period start first, then you can mark non-bleeding days in that cycle.",
                        defaultValue: "Log your latest period start first, then you can mark non-bleeding days in that cycle."
                    )
                )
                return
            }

            saveCoordinator.showSuccessAndDismiss {
                dismiss()
            }
            ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, requestReview: requestReview)
        } catch {
            saveCoordinator.showErrorFeedback()
            activeAlert = .error(
                L10n.format(
                    "Could not mark no period: %@",
                    defaultValue: "Could not mark no period: %@",
                    error.localizedDescription
                )
            )
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
