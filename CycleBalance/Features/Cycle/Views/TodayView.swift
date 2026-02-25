import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var viewModel: CycleViewModel?
    @State private var symptomViewModel: SymptomViewModel?
    @State private var showingLogPeriod = false
    @State private var showingLogSymptoms = false
    @State private var todaysSymptoms: [SymptomEntry] = []
    @State private var activeHint: String?
    @State private var quickLogFlow: FlowIntensity?
    @State private var showQuickLogSaved = false
    @State private var quickLogResetTask: Task<Void, Never>?
    @State private var fetchError: String?
    @State private var lastQuickLogEntryID: PersistentIdentifier?
    @State private var streakDays: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
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
            }) {
                CycleLogView()
            }
            .sheet(isPresented: $showingLogSymptoms, onDismiss: {
                refreshTodaysSymptoms()
                refreshStreak()
            }) {
                SymptomLogView()
            }
            .onAppear {
                if viewModel == nil {
                    let vm = CycleViewModel(modelContext: modelContext)
                    vm.loadData()
                    viewModel = vm
                }
                refreshTodaysSymptoms()
                refreshStreak()
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
                showingLogPeriod = true
            }

            QuickActionButton(
                title: "Log Symptoms",
                systemImage: "list.bullet.clipboard",
                color: AppTheme.accentColor
            ) {
                showingLogSymptoms = true
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
        switch appState.onboardingProfile.primaryGoal {
        case .trackCycles:
            "Log your period to start tracking your cycle"
        case .understandSymptoms:
            "Log symptoms to start finding patterns"
        case nil:
            "Start tracking by logging your period"
        }
    }

    private func showNextHintIfNeeded() {
        let profile = appState.onboardingProfile
        guard appState.hasCompletedOnboarding else { return }

        if profile.shouldShowHint(OnboardingProfile.hintCalendarTab) {
            withAnimation(.easeInOut(duration: 0.3)) {
                activeHint = "Check the Calendar tab to see your cycle at a glance"
            }
        } else if todaysSymptoms.isEmpty,
                  profile.shouldShowHint(OnboardingProfile.hintLogSymptoms) {
            withAnimation(.easeInOut(duration: 0.3)) {
                activeHint = "Logging symptoms helps find patterns with your cycle"
            }
        }
    }

    private func dismissActiveHint() {
        let profile = appState.onboardingProfile
        if activeHint != nil {
            if profile.shouldShowHint(OnboardingProfile.hintCalendarTab) {
                profile.dismissHint(OnboardingProfile.hintCalendarTab)
            } else if profile.shouldShowHint(OnboardingProfile.hintLogSymptoms) {
                profile.dismissHint(OnboardingProfile.hintLogSymptoms)
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            activeHint = nil
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
        viewModel.selectedDate = Date()
        viewModel.selectedFlowIntensity = intensity
        viewModel.periodNotes = ""

        do {
            try viewModel.logPeriodDay()
            // Store the last entry ID for undo
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let descriptor = FetchDescriptor<CycleEntry>(
                predicate: #Predicate<CycleEntry> { entry in
                    entry.date >= startOfDay && entry.date < endOfDay && entry.isPeriodDay
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            lastQuickLogEntryID = (try? modelContext.fetch(descriptor))?.first?.persistentModelID

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
            // Quick log is best-effort; full form available via sheet
        }
    }

    private func undoQuickLog() {
        guard let entryID = lastQuickLogEntryID else { return }
        if let entry = modelContext.model(for: entryID) as? CycleEntry {
            modelContext.delete(entry)
            try? modelContext.save()
        }
        quickLogResetTask?.cancel()
        quickLogFlow = nil
        lastQuickLogEntryID = nil
        viewModel?.loadData()
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
        ], inMemory: true)
}
