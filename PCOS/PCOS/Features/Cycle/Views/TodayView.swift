import SwiftUI
import SwiftData
import os

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var viewModel: CycleViewModel?
    @State private var symptomViewModel: SymptomViewModel?
    @State private var showingLogPeriod = false
    @State private var showingLogSymptoms = false
    @State private var showingLogBloodSugar = false
    @State private var showingLogSupplements = false
    @State private var showingLogMeal = false
    @State private var todaysSymptoms: [SymptomEntry] = []
    @State private var activeHint: String?
    @State private var activeHintID: String?
    @State private var quickLogFlow: FlowIntensity?
    @State private var showQuickLogSaved = false
    @State private var quickLogResetTask: Task<Void, Never>?
    @State private var fetchError: String?
    @State private var quickLogErrorMessage: String?
    @State private var lastQuickLogEntryID: PersistentIdentifier?
    @State private var streakDays: Int = 0
    @State private var todaysReadings: [BloodSugarReading] = []
    @State private var todaysSupplementLogs: [SupplementLog] = []
    @State private var todaysMeals: [MealEntry] = []

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.warmNeutral.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.spacing16) {
                        // Cycle status card
                        cycleStatusCard

                        // Logging streak
                        streakBadge

                        // Quick period log inline
                        quickPeriodLogRow

                        // Quick actions
                        quickActionsSection

                        // Today's logged symptoms
                        todaysSymptomsSection

                        // Blood sugar summary
                        bloodSugarSummarySection

                        // Supplement summary
                        supplementSummarySection

                        // Meal summary
                        mealSummarySection

                        // Prediction card
                        predictionSection
                    }
                    .padding()
                }
                .refreshable {
                    await Task.yield()
                    viewModel?.loadData()
                    refreshTodaysSymptoms()
                    refreshStreak()
                    refreshSummaryData()
                }

                // Post-onboarding contextual hint
                if let hint = activeHint {
                    VStack {
                        Spacer()
                        TooltipOverlay(message: hint) {
                            dismissActiveHint()
                        }
                        .padding(.horizontal, AppTheme.spacing24)
                        .padding(.bottom, AppTheme.spacing32)
                    }
                }
            }
            .navigationTitle("Today")
            .sensoryFeedback(.selection, trigger: quickLogFlow)
            .sensoryFeedback(.selection, trigger: showingLogPeriod)
            .sensoryFeedback(.selection, trigger: showingLogSymptoms)
            .sheet(isPresented: $showingLogPeriod, onDismiss: {
                viewModel?.loadData()
                refreshStreak()
                refreshSummaryData()
            }) {
                CycleLogView()
            }
            .sheet(isPresented: $showingLogSymptoms, onDismiss: {
                refreshTodaysSymptoms()
                refreshStreak()
                refreshSummaryData()
            }) {
                SymptomLogView()
            }
            .sheet(isPresented: $showingLogBloodSugar, onDismiss: {
                refreshSummaryData()
            }) {
                BloodSugarLogView()
            }
            .sheet(isPresented: $showingLogSupplements, onDismiss: {
                refreshSummaryData()
            }) {
                SupplementLogView()
            }
            .sheet(isPresented: $showingLogMeal, onDismiss: {
                refreshSummaryData()
            }) {
                MealLogView()
            }
            .onAppear {
                if viewModel == nil {
                    let vm = CycleViewModel(modelContext: modelContext)
                    vm.loadData()
                    viewModel = vm
                }
                refreshTodaysSymptoms()
                refreshStreak()
                refreshSummaryData()
                showNextHintIfNeeded()
            }
        }
    }

    private func refreshTodaysSymptoms() {
        if symptomViewModel == nil {
            symptomViewModel = SymptomViewModel(modelContext: modelContext)
        }
        todaysSymptoms = symptomViewModel?.fetchTodaysSymptoms() ?? []
        fetchError = nil
    }

    private func refreshStreak() {
        let service = StreakService(modelContext: modelContext)
        streakDays = service.currentStreak()
    }

    private func refreshSummaryData() {
        let bsVM = BloodSugarViewModel(modelContext: modelContext)
        todaysReadings = bsVM.fetchTodaysReadings()
        let suppVM = SupplementViewModel(modelContext: modelContext)
        todaysSupplementLogs = suppVM.fetchTodaysLogs()
        let mealVM = MealViewModel(modelContext: modelContext)
        todaysMeals = mealVM.fetchTodaysMeals()
    }

    // MARK: - Subviews

    private var cycleStatusCard: some View {
        VStack(spacing: AppTheme.spacing12) {
            if let dayCount = viewModel?.currentCycleDayCount {
                Text("Day \(dayCount)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.accentColor)
                    .contentTransition(.numericText())
                Text("of current cycle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Welcome")
                    .font(.title)
                    .fontWeight(.semibold)
                Text(personalizedWelcomeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing32)
        .cardStyle(cornerRadius: 20)
        .animation(.easeInOut(duration: 0.3), value: viewModel?.currentCycleDayCount)
    }

    @ViewBuilder
    private var streakBadge: some View {
        if streakDays > 1 {
            HStack(spacing: AppTheme.spacing8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, value: streakDays >= 7)
                Text("\(streakDays)-day logging streak")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing8)
        }
    }

    private var quickActionsSection: some View {
        HStack(spacing: AppTheme.spacing12) {
            QuickActionButton(
                title: "Log Period",
                systemImage: "drop.fill",
                color: AppTheme.coralAccent
            ) {
                openLogger(.period)
            }

            QuickActionButton(
                title: "Log Symptoms",
                systemImage: "list.bullet.clipboard",
                color: AppTheme.accentColor
            ) {
                openLogger(.symptoms)
            }
        }
    }

    private var todaysSymptomsSection: some View {
        Group {
            if let fetchError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(fetchError)
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .padding()
            }

            if !todaysSymptoms.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text("Today's Symptoms")
                        .font(.headline)

                    FlowLayout(spacing: AppTheme.spacing8) {
                        ForEach(todaysSymptoms) { symptom in
                            SymptomChip(
                                name: symptom.symptomType.displayName,
                                severity: symptom.severity
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    private var personalizedWelcomeText: String {
        let profile = appState.onboardingProfile
        switch (profile.primaryGoal, profile.symptomFocusAreas.first) {
        case (.trackCycles, _):
            return "Log your period to start tracking your cycle"
        case (.understandSymptoms, .moodEnergy?):
            return "Log how you're feeling to start finding patterns"
        case (.understandSymptoms, .skinHair?):
            return "Log skin and hair changes to start spotting patterns"
        case (.understandSymptoms, .painCramps?):
            return "Log symptoms to start tracking pain patterns"
        case (.understandSymptoms, _):
            return "Log symptoms to start finding patterns"
        case (nil, _):
            return "Start tracking by logging your period"
        }
    }

    // MARK: - Hint Sequencing

    private func showNextHintIfNeeded() {
        let profile = appState.onboardingProfile
        guard appState.hasCompletedOnboarding else { return }

        // Priority order: quick log intro → calendar → symptoms → first prediction
        if profile.shouldShowHint(OnboardingProfile.hintQuickLogIntro) {
            showHint(id: OnboardingProfile.hintQuickLogIntro, message: profile.quickLogHintMessage)
        } else if profile.shouldShowHint(OnboardingProfile.hintCalendarTab) {
            showHint(id: OnboardingProfile.hintCalendarTab, message: profile.calendarHintMessage)
        } else if todaysSymptoms.isEmpty,
                  profile.shouldShowHint(OnboardingProfile.hintLogSymptoms) {
            showHint(id: OnboardingProfile.hintLogSymptoms, message: profile.symptomHintMessage)
        } else if viewModel?.prediction != nil,
                  profile.shouldShowHint(OnboardingProfile.hintFirstPrediction) {
            showHint(
                id: OnboardingProfile.hintFirstPrediction,
                message: "Your first period estimate is here! It'll get more accurate as you log more cycles."
            )
        }
    }

    private func showHint(id: String, message: String) {
        activeHintID = id
        withAnimation(.easeInOut(duration: 0.3)) {
            activeHint = message
        }
    }

    private func dismissActiveHint() {
        if let hintID = activeHintID {
            appState.onboardingProfile.dismissHint(hintID)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            activeHint = nil
            activeHintID = nil
        }
    }

    private var quickPeriodLogRow: some View {
        VStack(spacing: AppTheme.spacing8) {
            HStack(spacing: AppTheme.spacing12) {
                Image(systemName: "drop.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.coralAccent)

                Text("Period today?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                ForEach([FlowIntensity.light, .medium, .heavy], id: \.self) { intensity in
                    Button {
                        quickLogPeriod(intensity: intensity)
                    } label: {
                        Text(intensity.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(quickLogFlow == intensity
                                          ? AppTheme.coralAccent
                                          : AppTheme.coralAccent.opacity(0.12))
                            )
                            .foregroundStyle(quickLogFlow == intensity ? .white : AppTheme.coralAccent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let quickLogErrorMessage {
                HStack(spacing: AppTheme.spacing8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(quickLogErrorMessage)
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Undo banner
            if let flow = quickLogFlow {
                HStack {
                    Text("Logged \(flow.displayName) flow for today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        undoQuickLog()
                    } label: {
                        Text("Undo")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.coralAccent)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
        .sensoryFeedback(.success, trigger: showQuickLogSaved)
        .animation(.easeInOut(duration: 0.25), value: quickLogFlow)
    }

    private func quickLogPeriod(intensity: FlowIntensity) {
        guard let viewModel else { return }
        quickLogErrorMessage = nil
        viewModel.selectedDate = Date()
        viewModel.selectedFlowIntensity = intensity
        viewModel.periodNotes = ""

        do {
            lastQuickLogEntryID = try viewModel.logPeriodDay()

            UserDefaults.standard.set(intensity.rawValue, forKey: "cycle.lastFlowIntensity")
            quickLogFlow = intensity
            showQuickLogSaved.toggle()
            quickLogResetTask?.cancel()
            quickLogResetTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                quickLogFlow = nil
                lastQuickLogEntryID = nil
            }
        } catch {
            Logger.database.error("Failed to quick-log period day: \(error.localizedDescription)")
            quickLogErrorMessage = "Couldn't save quick log. Please try again."
        }
    }

    private func undoQuickLog() {
        guard let entryID = lastQuickLogEntryID else { return }
        if let entry = modelContext.model(for: entryID) as? CycleEntry {
            modelContext.delete(entry)
            do {
                try modelContext.save()
            } catch {
                Logger.database.error("Failed to undo quick log: \(error.localizedDescription)")
            }
        }
        quickLogResetTask?.cancel()
        quickLogFlow = nil
        lastQuickLogEntryID = nil
        viewModel?.loadData()
    }

    @ViewBuilder
    private var bloodSugarSummarySection: some View {
        if !todaysReadings.isEmpty {
            Button {
                openLogger(.bloodSugar)
            } label: {
                HStack(spacing: AppTheme.spacing12) {
                    Image(systemName: "drop.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text("Blood Sugar")
                            .font(.headline)
                        Text("\(todaysReadings.count) reading\(todaysReadings.count == 1 ? "" : "s") today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let latest = todaysReadings.first {
                        Text("\(Int(latest.glucoseValue)) mg/dL")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(latest.glucoseValue > 140 ? .orange : AppTheme.accentColor)
                    }
                }
            }
            .cardStyle()
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var supplementSummarySection: some View {
        if !todaysSupplementLogs.isEmpty {
            let takenCount = todaysSupplementLogs.filter(\.taken).count
            Button {
                openLogger(.supplements)
            } label: {
                HStack(spacing: AppTheme.spacing12) {
                    Image(systemName: "pills.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accentColor)
                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text("Supplements")
                            .font(.headline)
                        Text("\(takenCount) of \(todaysSupplementLogs.count) taken today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .cardStyle()
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var mealSummarySection: some View {
        if !todaysMeals.isEmpty {
            Button {
                openLogger(.meal)
            } label: {
                HStack(spacing: AppTheme.spacing12) {
                    Image(systemName: "fork.knife")
                        .font(.title3)
                        .foregroundStyle(AppTheme.sage)
                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text("Meals")
                            .font(.headline)
                        Text("\(todaysMeals.count) meal\(todaysMeals.count == 1 ? "" : "s") logged today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .cardStyle()
            .buttonStyle(.plain)
        }
    }

    private var predictionSection: some View {
        Group {
            if let predictionText = viewModel?.predictionRangeText {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label("Period Estimate", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(AppTheme.coralAccent)
                    Text(predictionText)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    private func openLogger(_ shortcut: LoggerShortcut) {
        UserEntryDefaultsStore.shared.lastLoggerShortcut = shortcut
        switch shortcut {
        case .period:
            showingLogPeriod = true
        case .symptoms:
            showingLogSymptoms = true
        case .bloodSugar:
            showingLogBloodSugar = true
        case .supplements:
            showingLogSupplements = true
        case .meal:
            showingLogMeal = true
        case .photo:
            break
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.spacing8) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.12))
            )
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Symptom Chip

struct SymptomChip: View {
    let name: String
    let severity: Int

    var body: some View {
        HStack(spacing: AppTheme.spacing4) {
            Text(name)
                .font(.caption)
            Text(severityLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(severityColor.opacity(0.15))
        )
        .foregroundStyle(severityColor)
        .accessibilityLabel("\(name), severity \(severity) of 5, \(severityLabel)")
    }

    private var severityLabel: String {
        guard severity >= 1 && severity <= 5 else { return "" }
        return SeverityPicker.labels[severity - 1]
    }

    private var severityColor: Color {
        switch severity {
        case 1: .green
        case 2: AppTheme.accentColor
        case 3: .orange
        case 4, 5: AppTheme.coralAccent
        default: .secondary
        }
    }
}

#Preview {
    TodayView()
        .environment(AppState())
        .modelContainer(for: [
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
            Insight.self,
            BloodSugarReading.self,
            SupplementLog.self,
            MealEntry.self,
            HairPhotoEntry.self,
            DailyLog.self,
        ], inMemory: true)
}
