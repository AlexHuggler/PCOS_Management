import StoreKit
import SwiftUI
import SwiftData
import os

struct TodayView: View {
    private enum QuickLogAlert: Identifiable {
        case error(String)
        case confirmNewCycle(FlowIntensity, Int)

        var id: String {
            switch self {
            case .error(let message):
                "error-\(message)"
            case .confirmNewCycle(let intensity, let gapDays):
                "confirm-\(intensity.rawValue)-\(gapDays)"
            }
        }
    }

    private enum TodayHeroState: Equatable {
        case welcome
        case currentCycle(dayCount: Int)

        init(currentCycleDayCount: Int?) {
            if let currentCycleDayCount {
                self = .currentCycle(dayCount: currentCycleDayCount)
            } else {
                self = .welcome
            }
        }

        var renderIdentity: String {
            switch self {
            case .welcome:
                "welcome"
            case .currentCycle(let dayCount):
                "current-cycle-\(dayCount)"
            }
        }

        var logValue: String {
            switch self {
            case .welcome:
                "welcome"
            case .currentCycle(let dayCount):
                "currentCycle(\(dayCount))"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
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
    @State private var quickLogCountdown: Int = 0
    @State private var fetchError: String?
    @State private var quickLogErrorMessage: String?
    @State private var lastQuickLogUndoSnapshot: CycleLogUndoSnapshot?
    @State private var streakDays: Int = 0
    @State private var todaysReadings: [BloodSugarReading] = []
    @State private var todaysSupplementLogs: [SupplementLog] = []
    @State private var todaysMeals: [MealEntry] = []
    @State private var todaysDailyLog: DailyLog?
    @State private var pregnancyViewModel: PregnancyViewModel?
    @State private var quickLogAlert: QuickLogAlert?
    @State private var heroState: TodayHeroState = .welcome
    @State private var hasResolvedInitialHeroState = false

    var body: some View {
        NavigationStack {
            ZStack {
                BotanicalScreenBackground(style: .dense)

                ScrollView {
                    VStack(spacing: AppTheme.spacing16) {
                        // Cycle status card
                        cycleStatusCard

                        // Logging streak
                        streakBadge

                        // Quick period log inline
                        if appState.lifecycleMode != .pregnant {
                            quickPeriodLogRow
                        }

                        positiveActionsSection

                        healthContextSection

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
                    // Keep the last summary cards fully tappable above the tab bar.
                    .padding(.bottom, AppTheme.spacing32 * 2)
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
                        .padding(.bottom, AppTheme.isBotanicalJournal ? 126 : AppTheme.spacing32)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.today")
            .navigationTitle(
                L10n.string("Today", defaultValue: "Today")
            )
            .sensoryFeedback(.selection, trigger: quickLogFlow)
            .sensoryFeedback(.selection, trigger: showingLogPeriod)
            .sensoryFeedback(.selection, trigger: showingLogSymptoms)
            .alert(item: $quickLogAlert) { alert in
                switch alert {
                case .error(let message):
                    return Alert(
                        title: Text(L10n.string("Couldn't Save", defaultValue: "Couldn't Save")),
                        message: Text(message),
                        dismissButton: .cancel(Text(L10n.string("OK", defaultValue: "OK")))
                    )
                case .confirmNewCycle(let intensity, let gapDays):
                    return Alert(
                        title: Text(L10n.string("Start a new cycle?", defaultValue: "Start a new cycle?")),
                        message: Text(
                            L10n.format(
                                "This quick log starts %lld days after your last tracked period day. Confirm to reset your current cycle count and start a new cycle today.",
                                defaultValue: "This quick log starts %lld days after your last tracked period day. Confirm to reset your current cycle count and start a new cycle today.",
                                Int64(gapDays)
                            )
                        ),
                        primaryButton: .default(Text(L10n.string("Confirm New Cycle", defaultValue: "Confirm New Cycle"))) {
                            performQuickLog(intensity: intensity, startingNewCycle: true)
                        },
                        secondaryButton: .cancel(Text(L10n.string("Keep Current Cycle", defaultValue: "Keep Current Cycle")))
                    )
                }
            }
            .sheet(isPresented: $showingLogPeriod, onDismiss: {
                viewModel?.loadData()
                refreshStreak()
                refreshSummaryData()
            }) {
                CycleLogView()
            }
            .sheet(isPresented: $showingLogSymptoms, onDismiss: {
                viewModel?.loadData()
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
                MealLogView(entryPoint: .today)
            }
            .onChange(of: showingLogMeal) { _, isPresented in
                Logger.meals.info("TodayView meal log sheet state changed: \(isPresented, privacy: .public)")
            }
            .onChange(of: viewModel?.currentCycleDayCount) { _, _ in
                syncHeroState(reason: hasResolvedInitialHeroState ? "cycle_day_count_change" : "initial_resolution")
            }
            .onChange(of: appState.lifecycleMode) { _, _ in
                syncHeroState(reason: "lifecycle_mode_change")
            }
            .onAppear {
                let isInitialLoad = viewModel == nil
                if viewModel == nil {
                    Logger.ui.debug(
                        "TodayView initial load started. lifecycleMode=\(appState.lifecycleMode.rawValue, privacy: .public)"
                    )
                    let vm = CycleViewModel(modelContext: modelContext)
                    vm.loadData()
                    syncHeroState(reason: "initial_load", currentCycleDayCount: vm.currentCycleDayCount)
                    viewModel = vm
                } else {
                    syncHeroState(reason: "reappear")
                }
                if pregnancyViewModel == nil {
                    let pvm = PregnancyViewModel(modelContext: modelContext)
                    pvm.loadData()
                    pregnancyViewModel = pvm
                }
                refreshTodaysSymptoms()
                refreshStreak()
                refreshSummaryData()
                showNextHintIfNeeded()

                if !isInitialLoad {
                    Logger.ui.debug(
                        "TodayView reappeared with lifecycleMode=\(appState.lifecycleMode.rawValue, privacy: .public) heroState=\(heroState.logValue, privacy: .public)"
                    )
                }
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
        do {
            todaysDailyLog = try DailyLogService(modelContext: modelContext).fetchLog()
        } catch {
            Logger.database.error("Failed to fetch today's daily log: \(error.localizedDescription)")
            todaysDailyLog = nil
        }
    }

    // MARK: - Subviews

    private var cycleStatusCard: some View {
        Group {
            switch appState.lifecycleMode {
            case .pregnant, .postpartum:
                PregnancyDashboardCard(
                    gestationalText: pregnancyViewModel?.gestationalDisplayText,
                    postpartumDayCount: pregnancyViewModel?.postpartumDayCount,
                    lifecycleMode: appState.lifecycleMode
                )
            case .cycling:
                cycleHeroCard
            }
        }
    }

    private var cycleHeroCard: some View {
        VStack(spacing: AppTheme.spacing12) {
            BotanicalOrnamentalDivider(width: 220)
            renderCycleHeroContent(for: heroState)
            BotanicalOrnamentalDivider(width: 180)
        }
        .id(heroState.renderIdentity)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing32)
        .cardStyle(cornerRadius: AppTheme.largeCardCornerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.hero.container")
    }

    @ViewBuilder
    private func renderCycleHeroContent(for heroState: TodayHeroState) -> some View {
        switch heroState {
        case .welcome:
            Text(
                L10n.string("Welcome", defaultValue: "Welcome")
            )
                .appHeadingFont(.title, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today.hero.welcome_title")

            Text(personalizedWelcomeText)
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today.hero.welcome_body")

        case .currentCycle(let dayCount):
            VStack(spacing: AppTheme.spacing8) {
                Text(
                    L10n.format(
                        "Cycle day %lld",
                        defaultValue: "Cycle day %lld",
                        dayCount
                    )
                )
                    .appHeadingFont(.largeTitle, weight: .regular)
                    .foregroundStyle(AppTheme.accentColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.hero.current_cycle_label")

                Text(
                    L10n.string(
                        "Cycle day counts from your last period start, not days bleeding.",
                        defaultValue: "Cycle day counts from your last period start, not days bleeding."
                    )
                )
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var streakBadge: some View {
        if streakDays > 1 {
            HStack(spacing: AppTheme.spacing8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, value: streakDays >= 7)
                Text(
                    L10n.inflected(
                        LocalizedStringResource(
                            "^[\(streakDays) day](inflect: true) logging streak",
                            comment: "Badge showing the user's current logging streak in days."
                        )
                    )
                )
                    .appFont(.subheadline, weight: .medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing8)
        }
    }

    private var quickActionsSection: some View {
        HStack(spacing: AppTheme.spacing12) {
            if appState.lifecycleMode != .pregnant {
                QuickActionButton(
                    title: L10n.string("Log Period", defaultValue: "Log Period"),
                    systemImage: "drop.fill",
                    botanicalAssetName: "botanical-glucose-drop",
                    color: AppTheme.coralAccent
                ) {
                    openLogger(.period)
                }
            }

            QuickActionButton(
                title: L10n.string("Log Symptoms", defaultValue: "Log Symptoms"),
                systemImage: "list.bullet.clipboard",
                botanicalAssetName: "botanical-calendar-illustration",
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
                .appFont(.caption)
                .foregroundStyle(.orange)
                .padding()
            }

            if !todaysSymptoms.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(
                        L10n.string(
                            "Today's Symptoms",
                            defaultValue: "Today's Symptoms"
                        )
                    )
                        .appFont(.headline)

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
            return L10n.string(
                "Log your period to start tracking your cycle",
                defaultValue: "Log your period to start tracking your cycle"
            )
        case (.understandSymptoms, .moodEnergy?):
            return L10n.string(
                "Log how you're feeling to start finding patterns",
                defaultValue: "Log how you're feeling to start finding patterns"
            )
        case (.understandSymptoms, .skinHair?):
            return L10n.string(
                "Log skin and hair changes to start spotting patterns",
                defaultValue: "Log skin and hair changes to start spotting patterns"
            )
        case (.understandSymptoms, .painCramps?):
            return L10n.string(
                "Log symptoms to start tracking pain patterns",
                defaultValue: "Log symptoms to start tracking pain patterns"
            )
        case (.understandSymptoms, _):
            return L10n.string(
                "Log symptoms to start finding patterns",
                defaultValue: "Log symptoms to start finding patterns"
            )
        case (nil, _):
            return L10n.string(
                "Start tracking by logging your period",
                defaultValue: "Start tracking by logging your period"
            )
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
        } else if viewModel?.hasActionablePrediction == true,
                  profile.shouldShowHint(OnboardingProfile.hintFirstPrediction) {
            showHint(
                id: OnboardingProfile.hintFirstPrediction,
                message: L10n.string(
                    "Your first period estimate is here! It'll get more accurate as you log more cycles.",
                    defaultValue: "Your first period estimate is here! It'll get more accurate as you log more cycles."
                )
            )
            ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, requestReview: requestReview)
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
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.coralAccent)

                Text(L10n.string("Are you bleeding today?", defaultValue: "Are you bleeding today?"))
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }

            Button {
                quickLogNoPeriod()
            } label: {
                HStack(spacing: AppTheme.spacing8) {
                    Image(systemName: quickLogFlow == FlowIntensity.none ? "checkmark.circle.fill" : "circle")
                    Text(L10n.string("No period today", defaultValue: "No period today"))
                        .appFont(.subheadline, weight: .semibold)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, AppTheme.spacing12)
                .padding(.vertical, AppTheme.spacing8)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                        .fill(quickLogFlow == FlowIntensity.none ? AppTheme.sage.opacity(0.18) : AppTheme.sage.opacity(0.1))
                )
                .foregroundStyle(AppTheme.sage)
            }
            .buttonStyle(.plain)

            HStack(spacing: AppTheme.spacing8) {
                ForEach([FlowIntensity.spotting, .light, .medium, .heavy], id: \.self) { intensity in
                    Button {
                        quickLogPeriod(intensity: intensity)
                    } label: {
                        Text(intensity.displayName)
                            .appFont(.caption, weight: .medium)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
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
                .appFont(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            // Undo banner with countdown
            if let flow = quickLogFlow {
                HStack {
                    if flow == .none {
                        Text(
                            L10n.string(
                                "Marked no period today",
                                defaultValue: "Marked no period today"
                            )
                        )
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(
                            L10n.format(
                                "Logged %@ flow for today",
                                defaultValue: "Logged %@ flow for today",
                                flow.displayName
                            )
                        )
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if quickLogCountdown > 0 {
                        Text("\(quickLogCountdown)s")
                            .appFont(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .contentTransition(.numericText())
                    }
                    Button {
                        undoQuickLog()
                    } label: {
                        Text(L10n.string("Undo", defaultValue: "Undo"))
                            .appFont(.caption, weight: .semibold)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.quick_period_log")
    }

    private func quickLogPeriod(intensity: FlowIntensity) {
        guard let viewModel else { return }
        quickLogErrorMessage = nil
        let transition = viewModel.evaluatePeriodTransition(startDate: Date())

        if case .requiresNewCycleConfirmation(_, let gapDays) = transition {
            quickLogAlert = .confirmNewCycle(intensity, gapDays)
            return
        }

        performQuickLog(intensity: intensity, startingNewCycle: false)
    }

    private func quickLogNoPeriod() {
        guard let viewModel else { return }

        do {
            let result = try viewModel.logNoPeriodToday()
            if result.savedDates.isEmpty {
                quickLogErrorMessage = L10n.string(
                    "Log your latest period start first, then you can mark non-bleeding days in that cycle.",
                    defaultValue: "Log your latest period start first, then you can mark non-bleeding days in that cycle."
                )
                return
            }

            lastQuickLogUndoSnapshot = result.undoSnapshot
            quickLogErrorMessage = nil
            quickLogFlow = FlowIntensity.none
            showQuickLogSaved.toggle()
            refreshStreak()
            quickLogResetTask?.cancel()
            quickLogCountdown = 6
            quickLogResetTask = Task {
                for _ in 0..<6 {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    withAnimation(.linear(duration: 0.2)) {
                        quickLogCountdown -= 1
                    }
                }
                guard !Task.isCancelled else { return }
                quickLogFlow = nil
                lastQuickLogUndoSnapshot = nil
            }
        } catch {
            Logger.database.error("Failed to quick-log no-period day: \(error.localizedDescription)")
            quickLogErrorMessage = L10n.string(
                "Couldn't save no-period day. Please try again.",
                defaultValue: "Couldn't save no-period day. Please try again."
            )
            quickLogAlert = .error(quickLogErrorMessage ?? "")
        }
    }

    private func undoQuickLog() {
        guard let viewModel, let lastQuickLogUndoSnapshot else { return }

        do {
            try viewModel.undoPeriodSave(using: lastQuickLogUndoSnapshot)
        } catch {
            Logger.database.error("Failed to undo quick log: \(error.localizedDescription)")
            quickLogAlert = .error(
                L10n.string(
                    "Couldn't undo quick log right now.",
                    defaultValue: "Couldn't undo quick log right now."
                )
            )
        }
        quickLogResetTask?.cancel()
        quickLogFlow = nil
        self.lastQuickLogUndoSnapshot = nil
        quickLogCountdown = 0
        refreshStreak()
    }

    private func performQuickLog(intensity: FlowIntensity, startingNewCycle: Bool) {
        guard let viewModel else { return }

        do {
            let result = try viewModel.savePeriodDay(
                date: Date(),
                flowIntensity: intensity,
                notes: "",
                startingNewCycle: startingNewCycle
            )

            lastQuickLogUndoSnapshot = result.undoSnapshot
            quickLogErrorMessage = nil
            UserDefaults.standard.set(intensity.rawValue, forKey: "cycle.lastFlowIntensity")
            quickLogFlow = intensity
            showQuickLogSaved.toggle()
            refreshStreak()
            refreshSummaryData()
            quickLogResetTask?.cancel()
            quickLogCountdown = 6
            quickLogResetTask = Task {
                for _ in 0..<6 {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    withAnimation(.linear(duration: 0.2)) {
                        quickLogCountdown -= 1
                    }
                }
                guard !Task.isCancelled else { return }
                quickLogFlow = nil
                lastQuickLogUndoSnapshot = nil
            }
        } catch {
            Logger.database.error("Failed to quick-log period day: \(error.localizedDescription)")
            quickLogErrorMessage = L10n.string(
                "Couldn't save quick log. Please try again.",
                defaultValue: "Couldn't save quick log. Please try again."
            )
            quickLogAlert = .error(quickLogErrorMessage ?? "")
        }
    }

    private var positiveActionsSection: some View {
        let completedActions = todaysDailyLog?.sortedPositiveActions ?? []

        return VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(spacing: AppTheme.spacing8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(AppTheme.sage)
                Text(L10n.string("Positive actions", defaultValue: "Positive actions"))
                    .appFont(.headline)
                Spacer()
            }

            Text(
                completedActions.isEmpty
                    ? L10n.string(
                        "Track what helped today, not only what felt hard.",
                        defaultValue: "Track what helped today, not only what felt hard."
                    )
                    : L10n.string(
                        "Great consistency - this helps build a clearer PCOS pattern over time.",
                        defaultValue: "Great consistency - this helps build a clearer PCOS pattern over time."
                    )
            )
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: AppTheme.spacing8) {
                ForEach(PositiveActionType.allCases) { action in
                    let isCompleted = todaysDailyLog?.hasPositiveAction(action) == true
                    Button {
                        togglePositiveAction(action)
                    } label: {
                        Label(action.displayName, systemImage: action.systemImage)
                            .appFont(.caption, weight: .semibold)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, AppTheme.spacing8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isCompleted ? AppTheme.sage.opacity(0.18) : Color(.tertiarySystemFill))
                            )
                            .foregroundStyle(isCompleted ? AppTheme.sage : AppTheme.primaryText)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(Array(completedActions.prefix(2))) { action in
                Label(action.encouragement, systemImage: "sparkle")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityIdentifier("today.positive_actions")
    }

    @ViewBuilder
    private var healthContextSection: some View {
        if let todaysDailyLog, todaysDailyLog.hasHealthContext {
            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                HStack(spacing: AppTheme.spacing8) {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(AppTheme.coralAccent)
                    Text(L10n.string("Apple Health context", defaultValue: "Apple Health context"))
                        .appFont(.headline)
                    Spacer()
                }

                Text(
                    L10n.string(
                        "Synced Health data appears here on Today and stays on this device.",
                        defaultValue: "Synced Health data appears here on Today and stays on this device."
                    )
                )
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: AppTheme.spacing8) {
                    if let sleepHours = todaysDailyLog.sleepHours {
                        healthContextRow(
                            title: L10n.string("Sleep", defaultValue: "Sleep"),
                            value: L10n.format("%.1f hr", defaultValue: "%.1f hr", sleepHours),
                            systemImage: "bed.double.fill"
                        )
                    }

                    if let activeMinutes = todaysDailyLog.activeMinutes {
                        healthContextRow(
                            title: L10n.string("Activity", defaultValue: "Activity"),
                            value: L10n.format("%lld min", defaultValue: "%lld min", Int64(activeMinutes)),
                            systemImage: "figure.walk"
                        )
                    }

                    if let restingHeartRateBPM = todaysDailyLog.restingHeartRateBPM {
                        healthContextRow(
                            title: L10n.string("Resting heart rate", defaultValue: "Resting heart rate"),
                            value: L10n.format("%lld bpm", defaultValue: "%lld bpm", Int64(restingHeartRateBPM.rounded())),
                            systemImage: "heart.fill"
                        )
                    }

                    if let weight = todaysDailyLog.weight {
                        healthContextRow(
                            title: L10n.string("Weight", defaultValue: "Weight"),
                            value: L10n.format("%.1f lb", defaultValue: "%.1f lb", weight),
                            systemImage: "scalemass"
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .accessibilityIdentifier("today.health_context")
        }
    }

    private func healthContextRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: AppTheme.spacing8) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(AppTheme.accentColor)
            Text(title)
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
        }
    }

    private func togglePositiveAction(_ action: PositiveActionType) {
        do {
            todaysDailyLog = try DailyLogService(modelContext: modelContext).togglePositiveAction(action)
        } catch {
            Logger.database.error("Failed to toggle positive action: \(error.localizedDescription)")
            quickLogAlert = .error(
                L10n.string(
                    "Couldn't save that action right now.",
                    defaultValue: "Couldn't save that action right now."
                )
            )
        }
    }

    @ViewBuilder
    private var bloodSugarSummarySection: some View {
        if !todaysReadings.isEmpty {
            Button {
                openLogger(.bloodSugar)
            } label: {
                HStack(spacing: AppTheme.spacing12) {
                    BotanicalIllustrationBadge(
                        assetName: "botanical-glucose-drop",
                        systemImage: "drop.triangle.fill",
                        color: .orange,
                        size: 46
                    )
                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(L10n.string("Blood Sugar", defaultValue: "Blood Sugar"))
                            .appFont(.headline)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(
                            L10n.inflected(
                                LocalizedStringResource(
                                    "^[\(todaysReadings.count) reading](inflect: true) today",
                                    comment: "Summary showing how many blood sugar readings were logged today."
                                )
                            )
                        )
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if let latest = todaysReadings.first {
                        Text("\(Int(latest.glucoseValue)) mg/dL")
                            .appFont(.subheadline, weight: .medium)
                            .foregroundStyle(latest.glucoseValue > 140 ? .orange : AppTheme.accentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .cardStyle()
            }
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
                    BotanicalIllustrationBadge(
                        assetName: "botanical-supplement-jar",
                        systemImage: "pills.fill",
                        color: AppTheme.accentColor,
                        size: 46
                    )
                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(L10n.string("Supplements", defaultValue: "Supplements"))
                            .appFont(.headline)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(
                            L10n.format(
                                "%lld of %lld taken today",
                                defaultValue: "%lld of %lld taken today",
                                takenCount,
                                todaysSupplementLogs.count
                            )
                        )
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .cardStyle()
            }
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
                    BotanicalIllustrationBadge(
                        assetName: "botanical-meal-bowl",
                        systemImage: "fork.knife",
                        color: AppTheme.sage,
                        size: 46
                    )
                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(L10n.string("Meals", defaultValue: "Meals"))
                            .appFont(.headline)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(
                            L10n.inflected(
                                LocalizedStringResource(
                                    "^[\(todaysMeals.count) meal](inflect: true) logged today",
                                    comment: "Summary showing how many meals were logged today."
                                )
                            )
                        )
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .cardStyle()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.meal_summary.open_log")
        }
    }

    private var predictionSection: some View {
        Group {
            if appState.lifecycleMode == .pregnant {
                EmptyView()
            } else if appState.lifecycleMode == .postpartum, let postpartumText = viewModel?.postpartumPredictionText {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label {
                        Text(L10n.string("Cycle Recovery", defaultValue: "Cycle Recovery"))
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.accentColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(postpartumText)
                        .appFont(.subheadline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            } else if let predictionText = viewModel?.predictionPrimaryText {
                let sectionTitle = viewModel?.hasActionablePrediction == true
                    ? L10n.string("Period Estimate", defaultValue: "Period Estimate")
                    : L10n.string("Estimate Update", defaultValue: "Estimate Update")
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label {
                        Text(sectionTitle)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                        .appFont(.headline)
                        .foregroundStyle(AppTheme.coralAccent)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(predictionText)
                        .appFont(.subheadline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let secondaryText = viewModel?.predictionSecondaryText {
                        Text(secondaryText)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        case .ovulation:
            break
        case .symptoms:
            showingLogSymptoms = true
        case .bloodSugar:
            guard appState.allowsPremiumAccess else {
                appState.presentPremiumPaywall()
                return
            }
            showingLogBloodSugar = true
        case .supplements:
            guard appState.allowsPremiumAccess else {
                appState.presentPremiumPaywall()
                return
            }
            showingLogSupplements = true
        case .meal:
            Logger.meals.info("TodayView requested meal log.")
            guard appState.allowsPremiumAccess else {
                Logger.meals.notice("TodayView blocked meal log behind premium access.")
                appState.presentPremiumPaywall()
                return
            }
            showingLogMeal = true
            Logger.meals.info("TodayView presenting meal log sheet.")
        case .photo:
            break
        }
    }

    private func syncHeroState(reason: String, currentCycleDayCount: Int? = nil) {
        guard appState.lifecycleMode == .cycling else { return }

        let nextHeroState = TodayHeroState(
            currentCycleDayCount: currentCycleDayCount ?? viewModel?.currentCycleDayCount
        )

        if !hasResolvedInitialHeroState {
            let dayCountLogValue = (currentCycleDayCount ?? viewModel?.currentCycleDayCount)
                .map(String.init) ?? "nil"
            Logger.ui.debug(
                "Today hero first appearance resolved. hasCurrentCycle=\(nextHeroState != .welcome, privacy: .public) dayCount=\(dayCountLogValue, privacy: .public) reason=\(reason, privacy: .public)"
            )
        }

        guard heroState != nextHeroState else {
            if !hasResolvedInitialHeroState {
                Logger.ui.debug(
                    "Today hero state resolved after load without transition. state=\(nextHeroState.logValue, privacy: .public) reason=\(reason, privacy: .public)"
                )
                hasResolvedInitialHeroState = true
            }
            return
        }

        let previousHeroState = heroState
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            heroState = nextHeroState
        }

        if hasResolvedInitialHeroState {
            Logger.ui.debug(
                "Today hero state changed after initial render. previous=\(previousHeroState.logValue, privacy: .public) next=\(nextHeroState.logValue, privacy: .public) reason=\(reason, privacy: .public)"
            )
        } else {
            Logger.ui.debug(
                "Today hero state resolved after load. previous=\(previousHeroState.logValue, privacy: .public) next=\(nextHeroState.logValue, privacy: .public) reason=\(reason, privacy: .public)"
            )
            hasResolvedInitialHeroState = true
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: String
    let systemImage: String
    var botanicalAssetName: String? = nil
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.spacing8) {
                BotanicalIllustrationBadge(
                    assetName: botanicalAssetName,
                    systemImage: systemImage,
                    color: color,
                    size: 48
                )
                Text(title)
                    .appFont(.caption, weight: .medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                    .fill(
                        AppTheme.isBotanicalJournal
                            ? AppTheme.botanicalCreamAltRGB.color.opacity(0.74)
                            : color.opacity(AppTheme.opacityLight)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(AppTheme.isBotanicalJournal ? 0.18 : 0), lineWidth: 0.8)
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
                .appFont(.caption)
            Text(severityLabel)
                .appFont(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(severityColor.opacity(0.15))
        )
        .foregroundStyle(severityColor)
        .accessibilityLabel(
            L10n.format(
                "%@, severity %lld of 5, %@",
                defaultValue: "%@, severity %lld of 5, %@",
                name,
                severity,
                severityLabel
            )
        )
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
