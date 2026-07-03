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
        if let intensity = UserEntryDefaultsStore.shared.lastFlowIntensity,
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
    @State private var showingPeriodEndSheet = false

    var initialDate: Date?

    var body: some View {
        NavigationStack {
            Group {
                if AppTheme.usesPremiumEditorStyling {
                    lunarCycleLogContent
                } else {
                    standardCycleLogForm
                }
            }
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Log Period", defaultValue: "Log Period"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.cycle_log")
            .background {
                if AppTheme.usesPremiumEditorStyling {
                    AppTheme.premiumEditorBackground
                }
            }
            .toolbar {
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .principal) {
                        Text(L10n.string("Log period", defaultValue: "Log period"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                            .accessibilityIdentifier("cycle_log.lunar.header")
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if hasUnsavedChanges {
                            activeAlert = .cancel
                        } else {
                            dismiss()
                        }
                    } label: {
                        if AppTheme.usesPremiumEditorStyling {
                            Image(systemName: "xmark")
                        } else {
                            Text(L10n.string("Cancel", defaultValue: "Cancel"))
                        }
                    }
                    .accessibilityLabel(L10n.string("Cancel", defaultValue: "Cancel"))
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
            .sheet(isPresented: $showingPeriodEndSheet, onDismiss: {
                viewModel?.loadData()
            }) {
                if let viewModel, let currentPeriodState = viewModel.currentPeriodState {
                    PeriodEndSheet(
                        periodState: currentPeriodState,
                        initialDate: initialDate,
                        onSave: { endDate, referenceDate in
                            try viewModel.markPeriodEnded(on: endDate, referenceDate: referenceDate)
                        },
                        onSaved: {
                            viewModel.loadData()
                        }
                    )
                }
            }
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

    private var standardCycleLogForm: some View {
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

                if canShowPeriodEndAction {
                    Button {
                        showingPeriodEndSheet = true
                    } label: {
                        HStack {
                            Spacer()
                            Label(periodEndButtonTitle, systemImage: "calendar.badge.checkmark")
                                .foregroundStyle(AppTheme.accentColor)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                    }
                    .accessibilityIdentifier("cycle_log.period_end_button")
                }
            }
        }
    }

    private var lunarCycleLogContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                lunarCycleHeader
                lunarModeControl
                lunarDateCard
                lunarFlowCard
                lunarNotesCard
                lunarActionPanel
            }
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.top, AppTheme.spacing8)
            .padding(.bottom, AppTheme.spacing24)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.premiumEditorBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cycle_log.lunar.surface")
    }

    private var lunarCycleHeader: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing12) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("Log your flow", defaultValue: "Log your flow"))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(L10n.string("Flow, timing, and notes for cycles that do not always follow a pattern.", defaultValue: "Flow, timing, and notes for cycles that do not always follow a pattern."))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.spacing8)

            ZStack {
                Circle()
                    .fill(AppTheme.premiumEditorAccentGradient)
                Image(systemName: "drop.fill")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            }
            .frame(width: 52, height: 52)
            .shadow(color: AppTheme.premiumEditorWarningAccentColor.opacity(0.22), radius: 16, y: 8)
            .accessibilityHidden(true)
        }
    }

    private var lunarModeControl: some View {
        HStack(spacing: AppTheme.spacing8) {
            ForEach(LoggingMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        loggingMode = mode
                    }
                } label: {
                    Text(lunarTitle(for: mode))
                        .appFont(.subheadline, weight: loggingMode == mode ? .semibold : .regular)
                        .foregroundStyle(loggingMode == mode ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacing8)
                        .background(
                            Capsule()
                                .fill(loggingMode == mode ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.premiumEditorRaisedSurface.opacity(0.78)))
                        )
                        .overlay(
                            Capsule()
                                .stroke(loggingMode == mode ? AppTheme.premiumEditorAccentColor.opacity(0.48) : AppTheme.premiumEditorBorder.opacity(0.54), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(loggingMode == mode ? .isSelected : [])
                .accessibilityIdentifier("cycle_log.lunar.mode.\(mode.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cycle_log.lunar.mode")
    }

    private var lunarDateCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Date", defaultValue: "Date"), systemImage: "calendar")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            if loggingMode == .singleDay {
                DatePicker(
                    L10n.string("Period date", defaultValue: "Period date"),
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(AppTheme.premiumEditorAccentColor)
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityIdentifier("cycle_log.single_date")
            } else {
                DatePicker(
                    L10n.string("Start date", defaultValue: "Start date"),
                    selection: $rangeStartDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(AppTheme.premiumEditorAccentColor)
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityIdentifier("cycle_log.range_start_date")

                Toggle(
                    L10n.string("Through today", defaultValue: "Through today"),
                    isOn: $rangeEndsToday
                )
                .tint(AppTheme.premiumEditorAccentColor)
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityIdentifier("cycle_log.through_today")

                if !rangeEndsToday {
                    DatePicker(
                        L10n.string("End date", defaultValue: "End date"),
                        selection: $rangeEndDate,
                        in: rangeStartDate...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .tint(AppTheme.premiumEditorAccentColor)
                    .foregroundStyle(AppTheme.primaryText)
                    .accessibilityIdentifier("cycle_log.range_end_date")
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarCycleCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cycle_log.lunar.date_card")
    }

    private var lunarFlowCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack {
                Label(L10n.string("Flow", defaultValue: "Flow"), systemImage: "drop.fill")
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text(selectedFlow.displayName)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(lunarFlowColor(for: selectedFlow))
            }

            HStack(spacing: AppTheme.spacing8) {
                ForEach(lunarFlowOptions) { intensity in
                    Button {
                        selectedFlow = intensity
                    } label: {
                        VStack(spacing: AppTheme.spacing8) {
                            lunarFlowIcon(for: intensity)
                                .frame(height: 30)

                            Text(intensity.displayName)
                                .appFont(.caption, weight: selectedFlow == intensity ? .semibold : .regular)
                                .foregroundStyle(selectedFlow == intensity ? AppTheme.primaryText : AppTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 86)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.premiumEditorRaisedSurface.opacity(selectedFlow == intensity ? 0.94 : 0.64))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    selectedFlow == intensity
                                        ? AppTheme.premiumEditorBorderGradient
                                        : LinearGradient(colors: [AppTheme.premiumEditorBorder.opacity(0.5)], startPoint: .leading, endPoint: .trailing),
                                    lineWidth: selectedFlow == intensity ? 1.1 : 0.8
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.flowAccessibilityLabel(for: intensity))
                    .accessibilityHint(L10n.flowAccessibilityHint(for: intensity))
                    .accessibilityAddTraits(selectedFlow == intensity ? .isSelected : [])
                    .accessibilityIdentifier("cycle_log.lunar.flow.\(intensity.rawValue)")
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarCycleCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cycle_log.lunar.flow_picker")
    }

    private var lunarNotesCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(L10n.string("Notes (optional)", defaultValue: "Notes (optional)"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            TextField(
                L10n.string(
                    "e.g., clotting, mood changes, spotting duration...",
                    defaultValue: "e.g., clotting, mood changes, spotting duration..."
                ),
                text: $notes,
                axis: .vertical
            )
            .appFont(.body)
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(3...6)
            .submitLabel(.done)
            .textInputAutocapitalization(.sentences)
            .padding(AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
            )

            if !periodNoteSuggestions.isEmpty {
                Text(
                    L10n.format(
                        "Quick notes for %@ flow",
                        defaultValue: "Quick notes for %@ flow",
                        selectedFlow.displayName
                    )
                )
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)

                FlowLayout(spacing: AppTheme.spacing8) {
                    ForEach(periodNoteSuggestions, id: \.self) { suggestion in
                        Button {
                            notes = QuickNoteComposer.toggled(suggestion, in: notes)
                        } label: {
                            Text(suggestion)
                                .appFont(.caption, weight: QuickNoteComposer.isSelected(suggestion, in: notes) ? .semibold : .regular)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .padding(.horizontal, AppTheme.spacing12)
                                .padding(.vertical, AppTheme.spacing8)
                                .background(Capsule().fill(AppTheme.premiumEditorSurface.opacity(0.88)))
                                .overlay(Capsule().stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8))
                                .foregroundStyle(QuickNoteComposer.isSelected(suggestion, in: notes) ? AppTheme.premiumEditorAccentColor : AppTheme.primaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarCycleCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cycle_log.lunar.notes")
    }

    private var lunarActionPanel: some View {
        VStack(spacing: AppTheme.spacing12) {
            Button(action: attemptSave) {
                Text(saveButtonTitle)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing16)
                    .background(Capsule().fill(AppTheme.premiumEditorAccentGradient))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cycle_log.save_button")

            if loggingMode == .singleDay {
                Button(action: markNoPeriodDay) {
                    Label(
                        L10n.string("No period on this date", defaultValue: "No period on this date"),
                        systemImage: "checkmark.circle"
                    )
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing12)
                    .background(Capsule().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.78)))
                    .overlay(Capsule().stroke(AppTheme.premiumEditorBorder.opacity(0.54), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cycle_log.no_period_button")
            }

            if canShowPeriodEndAction {
                Button {
                    showingPeriodEndSheet = true
                } label: {
                    Label(periodEndButtonTitle, systemImage: "calendar.badge.checkmark")
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacing12)
                        .background(Capsule().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.78)))
                        .overlay(Capsule().stroke(AppTheme.premiumEditorBorder.opacity(0.54), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cycle_log.period_end_button")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cycle_log.lunar.actions")
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

    private var canShowPeriodEndAction: Bool {
        guard let viewModel else { return false }
        return viewModel.canMarkPeriodEnd && viewModel.currentPeriodState != nil
    }

    private var periodEndButtonTitle: String {
        guard viewModel?.currentPeriodState?.isActive == false else {
            return L10n.string("Mark Period End", defaultValue: "Mark Period End")
        }
        return L10n.string("Edit Period End Date", defaultValue: "Edit Period End Date")
    }

    private var lunarFlowOptions: [FlowIntensity] {
        FlowIntensity.allCases.filter { $0 != .none }
    }

    private func lunarTitle(for mode: LoggingMode) -> String {
        switch mode {
        case .singleDay:
            L10n.string("Single day", defaultValue: "Single day")
        case .dateRange:
            L10n.string("Date range", defaultValue: "Date range")
        }
    }

    @ViewBuilder
    private func lunarFlowIcon(for intensity: FlowIntensity) -> some View {
        switch intensity {
        case .none:
            Image(systemName: "drop")
                .appFont(.body)
                .foregroundStyle(AppTheme.secondaryText)
        case .spotting:
            Image(systemName: "drop.fill")
                .appFont(.caption)
                .foregroundStyle(lunarFlowColor(for: intensity).opacity(0.72))
        case .light:
            Image(systemName: "drop.fill")
                .appFont(.subheadline)
                .foregroundStyle(lunarFlowColor(for: intensity).opacity(0.82))
        case .medium:
            Image(systemName: "drop.fill")
                .appFont(.body, weight: .semibold)
                .foregroundStyle(lunarFlowColor(for: intensity))
        case .heavy:
            HStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .appFont(.caption2, weight: .semibold)
                Image(systemName: "drop.fill")
                    .appFont(.subheadline, weight: .semibold)
            }
            .foregroundStyle(lunarFlowColor(for: intensity))
        }
    }

    private func lunarFlowColor(for intensity: FlowIntensity) -> Color {
        switch intensity {
        case .none:
            AppTheme.secondaryText
        case .spotting:
            AppTheme.roseAccent
        case .light:
            AppTheme.coralAccent
        case .medium:
            AppTheme.premiumEditorSecondaryAccentColor
        case .heavy:
            AppTheme.softGoldAccent
        }
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
            UserEntryDefaultsStore.shared.lastFlowIntensity = request.flowIntensity
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

            ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, moment: .logSaved, requestReview: requestReview)
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
            ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, moment: .logSaved, requestReview: requestReview)
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

private extension View {
    func lunarCycleCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.premiumEditorRaisedSurface.opacity(0.92),
                            AppTheme.premiumEditorSurface.opacity(0.78),
                            AppTheme.premiumEditorBackground.opacity(0.9),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.8)
                .opacity(0.72)
        )
        .shadow(color: AppTheme.cardShadowColor.opacity(AppTheme.usesPremiumEditorStyling ? 1.0 : 0.8), radius: 14, y: 8)
    }
}

#Preview {
    CycleLogView()
        .modelContainer(for: [CycleEntry.self, Cycle.self], inMemory: true)
}

struct PeriodEndSheet: View {
    private enum ActiveAlert: Identifiable {
        case error(String)
        case confirmEarlierEnd(Date)

        var id: String {
            switch self {
            case .error(let message):
                "error-\(message)"
            case .confirmEarlierEnd(let date):
                "confirm-\(date.timeIntervalSinceReferenceDate)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let periodState: CurrentPeriodState
    let initialDate: Date?
    let referenceDate: Date
    let onSave: (Date, Date) throws -> CycleRangeSaveResult
    var onSaved: () -> Void = {}

    @State private var selectedDate: Date
    @State private var activeAlert: ActiveAlert?
    @State private var saveCoordinator = SaveInteractionCoordinator()

    init(
        periodState: CurrentPeriodState,
        initialDate: Date? = nil,
        referenceDate: Date = Date(),
        onSave: @escaping (Date, Date) throws -> CycleRangeSaveResult,
        onSaved: @escaping () -> Void = {}
    ) {
        self.periodState = periodState
        self.initialDate = initialDate
        self.referenceDate = referenceDate
        self.onSave = onSave
        self.onSaved = onSaved

        let defaultDate = PeriodEndSheet.resolvedInitialDate(
            initialDate,
            periodState: periodState,
            referenceDate: referenceDate
        )
        self._selectedDate = State(initialValue: defaultDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        L10n.string("Period End Date", defaultValue: "Period End Date"),
                        selection: $selectedDate,
                        in: selectableDateRange,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .tint(AppTheme.accentColor)
                    .accessibilityIdentifier("period_end.date_picker")

                    Text(
                        L10n.string(
                            "Select the last day you had bleeding so CycleBalance can update your cycle accurately.",
                            defaultValue: "Select the last day you had bleeding so CycleBalance can update your cycle accurately."
                        )
                    )
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    periodSummaryRow(
                        title: L10n.string("Period started", defaultValue: "Period started"),
                        date: periodState.periodStartDate
                    )

                    periodSummaryRow(
                        title: L10n.string("Last bleeding logged", defaultValue: "Last bleeding logged"),
                        date: periodState.lastBleedingDate
                    )

                    if let periodEndedDate = periodState.periodEndedDate {
                        periodSummaryRow(
                            title: L10n.string("Saved period end", defaultValue: "Saved period end"),
                            date: periodEndedDate
                        )
                    }
                }
            }
            .accessibilityIdentifier("period_end.sheet")
            .navigationTitle(L10n.string("Mark Period End", defaultValue: "Mark Period End"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("period_end.cancel_button")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Save", defaultValue: "Save"), action: savePeriodEnd)
                        .accessibilityIdentifier("period_end.save_button")
                }
            }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .error(let message):
                    return Alert(
                        title: Text(L10n.string("Could not Save", defaultValue: "Could not Save")),
                        message: Text(message),
                        dismissButton: .cancel(Text(L10n.string("OK", defaultValue: "OK")))
                    )
                case .confirmEarlierEnd(let endDate):
                    return Alert(
                        title: Text(L10n.string("Update Period End?", defaultValue: "Update Period End?")),
                        message: Text(
                            L10n.string(
                                "Marking this date will change later bleeding logs in this period to no-period days.",
                                defaultValue: "Marking this date will change later bleeding logs in this period to no-period days."
                            )
                        ),
                        primaryButton: .default(Text(L10n.string("Update Period End", defaultValue: "Update Period End"))) {
                            performPeriodEndSave(endDate)
                        },
                        secondaryButton: .cancel(Text(L10n.string("Keep Editing", defaultValue: "Keep Editing")))
                    )
                }
            }
            .overlay {
                if saveCoordinator.isShowingSavedFeedback {
                    SavedFeedbackOverlay()
                }
            }
            .sensoryFeedback(.success, trigger: saveCoordinator.isShowingSavedFeedback)
            .onDisappear {
                saveCoordinator.cancelPending()
            }
        }
    }

    private var selectableDateRange: ClosedRange<Date> {
        let lowerBound = Calendar.current.startOfDay(for: periodState.periodStartDate)
        let referenceDay = Calendar.current.startOfDay(for: min(referenceDate, Date()))
        let upperBound = max(lowerBound, referenceDay)
        return lowerBound...upperBound
    }

    private func periodSummaryRow(title: String, date: Date) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formattedDate(date))
                .foregroundStyle(AppTheme.primaryText)
        }
        .appFont(.subheadline)
    }

    private func savePeriodEnd() {
        if Calendar.current.startOfDay(for: selectedDate) < Calendar.current.startOfDay(for: periodState.lastBleedingDate) {
            activeAlert = .confirmEarlierEnd(selectedDate)
            return
        }

        performPeriodEndSave(selectedDate)
    }

    private func performPeriodEndSave(_ endDate: Date) {
        do {
            _ = try onSave(endDate, referenceDate)
            onSaved()
            saveCoordinator.showSuccessAndDismiss {
                dismiss()
            }
        } catch {
            saveCoordinator.showErrorFeedback()
            activeAlert = .error(
                L10n.format(
                    "Could not mark period end: %@",
                    defaultValue: "Could not mark period end: %@",
                    error.localizedDescription
                )
            )
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func resolvedInitialDate(
        _ initialDate: Date?,
        periodState: CurrentPeriodState,
        referenceDate: Date
    ) -> Date {
        let calendar = Calendar.current
        let lowerBound = calendar.startOfDay(for: periodState.periodStartDate)
        let referenceDay = calendar.startOfDay(for: min(referenceDate, Date()))
        let upperBound = max(lowerBound, referenceDay)

        if let initialDate {
            let candidate = calendar.startOfDay(for: initialDate)
            if candidate >= lowerBound && candidate <= upperBound {
                return candidate
            }
        }

        if let periodEndedDate = periodState.periodEndedDate {
            let candidate = calendar.startOfDay(for: periodEndedDate)
            if candidate >= lowerBound && candidate <= upperBound {
                return candidate
            }
        }

        let suggestedEndDate = calendar.startOfDay(for: periodState.suggestedEndDate)
        if suggestedEndDate >= lowerBound && suggestedEndDate <= upperBound {
            return suggestedEndDate
        }

        return upperBound
    }
}

#Preview("Period End Sheet - Active") {
    PeriodEndSheet(
        periodState: CurrentPeriodState(
            periodStartDate: Date().addingTimeInterval(-4 * 24 * 60 * 60),
            lastBleedingDate: Date(),
            isActive: true,
            suggestedEndDate: Date(),
            periodEndedDate: nil
        ),
        onSave: { _, _ in
            CycleRangeSaveResult(primaryEntryID: nil, savedDates: [], undoSnapshot: nil)
        }
    )
}

#Preview("Period End Sheet - Backdated") {
    PeriodEndSheet(
        periodState: CurrentPeriodState(
            periodStartDate: Date().addingTimeInterval(-6 * 24 * 60 * 60),
            lastBleedingDate: Date().addingTimeInterval(-2 * 24 * 60 * 60),
            isActive: true,
            suggestedEndDate: Date().addingTimeInterval(-2 * 24 * 60 * 60),
            periodEndedDate: nil
        ),
        initialDate: Date().addingTimeInterval(-3 * 24 * 60 * 60),
        onSave: { _, _ in
            CycleRangeSaveResult(primaryEntryID: nil, savedDates: [], undoSnapshot: nil)
        }
    )
}

#Preview("Period End Sheet - Already Ended") {
    PeriodEndSheet(
        periodState: CurrentPeriodState(
            periodStartDate: Date().addingTimeInterval(-8 * 24 * 60 * 60),
            lastBleedingDate: Date().addingTimeInterval(-4 * 24 * 60 * 60),
            isActive: false,
            suggestedEndDate: Date().addingTimeInterval(-4 * 24 * 60 * 60),
            periodEndedDate: Date().addingTimeInterval(-4 * 24 * 60 * 60)
        ),
        onSave: { _, _ in
            CycleRangeSaveResult(primaryEntryID: nil, savedDates: [], undoSnapshot: nil)
        }
    )
}
