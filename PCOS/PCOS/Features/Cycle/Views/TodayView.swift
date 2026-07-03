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

        var isCurrentCycle: Bool {
            if case .currentCycle = self { return true }
            return false
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
    @State private var topAhaMoment: AhaMoment?
    @State private var pregnancyViewModel: PregnancyViewModel?
    @State private var quickLogAlert: QuickLogAlert?
    @State private var heroState: TodayHeroState = .welcome
    @State private var hasResolvedInitialHeroState = false
    @State private var showingPeriodEndSheet = false
    @State private var showingPredictionInfo = false

    var body: some View {
        NavigationStack {
            ZStack {
                BotanicalScreenBackground(style: .dense)

                ScrollView {
                    VStack(spacing: AppTheme.spacing16) {
                        if AppTheme.usesImmersiveHomeShell {
                            lunarTodayHeader
                        }

                        // Cycle status card
                        cycleStatusCard

                        // Logging streak
                        streakBadge

                        if !AppTheme.usesImmersiveHomeShell, let topAhaMoment {
                            AhaMomentCard(moment: topAhaMoment)
                        }

                        if AppTheme.usesImmersiveHomeShell {
                            lunarTodaySnapshotCard

                            if let topAhaMoment {
                                ImmersiveInsightCard(moment: topAhaMoment)
                            }
                        }

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
                    // Keep the last summary cards fully tappable above the custom tab bar.
                    .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
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
                        .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.today")
            .navigationTitle(
                AppTheme.usesImmersiveHomeShell ? "" : L10n.string("Today", defaultValue: "Today")
            )
            .navigationBarTitleDisplayMode(AppTheme.usesImmersiveHomeShell ? .inline : .automatic)
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
            .todayLunarPresentation(isPresented: $showingLogPeriod, onDismiss: {
                viewModel?.loadData()
                refreshStreak()
                refreshSummaryData()
            }) {
                CycleLogView()
            }
            .todayLunarPresentation(isPresented: $showingPeriodEndSheet, onDismiss: {
                viewModel?.loadData()
                refreshStreak()
                refreshSummaryData()
            }) {
                if let viewModel, let currentPeriodState = viewModel.currentPeriodState {
                    PeriodEndSheet(
                        periodState: currentPeriodState,
                        onSave: { endDate, referenceDate in
                            try viewModel.markPeriodEnded(on: endDate, referenceDate: referenceDate)
                        },
                        onSaved: {
                            viewModel.loadData()
                            refreshStreak()
                            refreshSummaryData()
                        }
                    )
                }
            }
            .todayLunarPresentation(isPresented: $showingLogSymptoms, onDismiss: {
                viewModel?.loadData()
                refreshTodaysSymptoms()
                refreshStreak()
                refreshSummaryData()
            }) {
                SymptomLogView()
            }
            .todayLunarPresentation(isPresented: $showingLogBloodSugar, onDismiss: {
                refreshSummaryData()
            }) {
                BloodSugarLogView()
            }
            .todayLunarPresentation(isPresented: $showingLogSupplements, onDismiss: {
                refreshSummaryData()
            }) {
                SupplementLogView()
            }
            .todayLunarPresentation(isPresented: $showingLogMeal, onDismiss: {
                refreshSummaryData()
            }) {
                MealLogView(entryPoint: .today)
            }
            .sheet(isPresented: $showingPredictionInfo) {
                PredictionEstimateInfoSheet(detailText: viewModel?.predictionSecondaryText)
                    .presentationDetents([.medium])
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
        do {
            topAhaMoment = try AhaMomentService(modelContext: modelContext)
                .topMoment(isPremium: appState.allowsPremiumAccess)
        } catch {
            Logger.database.error("Failed to refresh aha moment: \(error.localizedDescription)")
            topAhaMoment = nil
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
        Group {
            if AppTheme.usesImmersiveHomeShell {
                cycleHeroContent
                    .padding(.horizontal, AppTheme.spacing4)
                    .padding(.vertical, AppTheme.spacing12)
            } else {
                cycleHeroContent
                    .padding(.vertical, AppTheme.spacing32)
                    .cardStyle(cornerRadius: AppTheme.largeCardCornerRadius)
            }
        }
        .id(heroState.renderIdentity)
        .frame(maxWidth: .infinity)
        .frame(minHeight: AppTheme.usesImmersiveHomeShell ? 312 : nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.hero.container")
    }

    @ViewBuilder
    private var cycleHeroContent: some View {
        if AppTheme.usesImmersiveHomeShell {
            GeometryReader { proxy in
                let ringDiameter = min(max(proxy.size.width - 56, 238), 296)
                ZStack {
                    LunarCycleHeroRing(
                        progress: cycleHeroRingProgress,
                        isWelcome: !heroState.isCurrentCycle
                    )
                        .frame(width: ringDiameter, height: ringDiameter)
                        .accessibilityHidden(true)

                    renderLunarCycleHeroContent(for: heroState)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 304)
        } else {
            VStack(spacing: AppTheme.spacing12) {
                BotanicalOrnamentalDivider(width: 220)
                renderCycleHeroContent(for: heroState)
                BotanicalOrnamentalDivider(width: 180)
            }
        }
    }

    private var cycleHeroRingProgress: Double {
        guard case .currentCycle(let dayCount) = heroState else {
            return 0
        }

        let expectedCycleLength = viewModel?.currentManualCycleLengthOverride
            ?? viewModel?.statistics.map { Int($0.averageLength.rounded()) }
            ?? 28
        let clampedExpectedCycleLength = min(max(expectedCycleLength, 15), 120)
        return Double(dayCount) / Double(clampedExpectedCycleLength)
    }

    private var lunarTodayHeader: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing12) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(lunarGreetingTitle)
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(L10n.string("You're not alone in this.", defaultValue: "You're not alone in this."))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: AppTheme.spacing12)

            ZStack {
                Circle()
                    .fill(AppTheme.premiumEditorAccentGradient)
                Image(systemName: "moon.stars.fill")
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            }
            .frame(width: 40, height: 40)
            .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.26), radius: 14, y: 6)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, AppTheme.spacing4)
        .accessibilityIdentifier("today.lunar.header")
    }

    private var lunarGreetingTitle: String {
        TodayGreeting.title(
            hour: Calendar.current.component(.hour, from: Date()),
            name: appState.onboardingProfile.preferredDisplayName
        )
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
    private func renderLunarCycleHeroContent(for heroState: TodayHeroState) -> some View {
        switch heroState {
        case .welcome:
            VStack(spacing: AppTheme.spacing8) {
                Text(L10n.string("Cycle day", defaultValue: "Cycle day"))
                    .appFont(.caption, weight: .semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.secondaryText)

                Text(L10n.string("Start", defaultValue: "Start"))
                    .appHeadingFont(.largeTitle, weight: .regular)
                    .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                    .accessibilityIdentifier("today.hero.welcome_title")

                Text(personalizedWelcomeText)
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 210)

        case .currentCycle(let dayCount):
            VStack(spacing: AppTheme.spacing8) {
                Text(L10n.string("Cycle day", defaultValue: "Cycle day"))
                    .appFont(.caption, weight: .semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Text("\(dayCount)")
                    .appHeadingFont(.largeTitle, weight: .regular)
                    .font(AppTheme.headingFont(.largeTitle, weight: .regular))
                    .scaleEffect(1.46)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .padding(.vertical, AppTheme.spacing4)
                    .accessibilityIdentifier("today.hero.current_cycle_label")

                if let phase = viewModel?.currentApproximatePhase {
                    Text(
                        L10n.format(
                            "%@ Phase",
                            defaultValue: "%@ Phase",
                            phase.displayName
                        )
                    )
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                VStack(spacing: AppTheme.spacing4) {
                    Text(L10n.string("Next period", defaultValue: "Next period"))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)

                    Text(viewModel?.predictionCountdownText() ?? lunarPredictionHeadline)
                        .appHeadingFont(.title2, weight: .regular)
                        .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    if let secondary = lunarPredictionDetailText {
                        HStack(spacing: AppTheme.spacing4) {
                            Text(secondary)
                                .appFont(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)

                            if viewModel?.hasActionablePrediction == true {
                                Button {
                                    showingPredictionInfo = true
                                } label: {
                                    Image(systemName: "info.circle")
                                        .appFont(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .accessibilityLabel(
                                    L10n.string("About this estimate", defaultValue: "About this estimate")
                                )
                                .accessibilityIdentifier("today.hero.prediction_info")
                            }
                        }
                    }
                }
                .padding(.top, AppTheme.spacing4)

                Button {
                    openLogger(.period)
                } label: {
                    HStack(spacing: AppTheme.spacing4) {
                        Text(L10n.string("Edit period dates", defaultValue: "Edit period dates"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Image(systemName: "pencil")
                            .imageScale(.small)
                    }
                    .appFont(.caption, weight: .semibold)
                    .padding(.horizontal, AppTheme.spacing12)
                    .padding(.vertical, AppTheme.spacing8)
                    .background(Capsule().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.92)))
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.premiumEditorBorder.opacity(0.72), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.primaryText)
            }
            .frame(maxWidth: 218)
            .offset(y: 2)
        }
    }

    private var lunarPredictionHeadline: String {
        guard let predictionText = viewModel?.predictionPrimaryText else {
            return L10n.string("building with your logs", defaultValue: "building with your logs")
        }

        if predictionText.localizedCaseInsensitiveContains("harder to estimate") {
            return L10n.string("Hard to estimate", defaultValue: "Hard to estimate")
        }

        let prefix = L10n.string(
            "Your period may arrive between ",
            defaultValue: "Your period may arrive between "
        )
        if predictionText.hasPrefix(prefix) {
            return String(predictionText.dropFirst(prefix.count))
        }

        return predictionText
    }

    private var lunarPredictionDetailText: String? {
        guard viewModel?.predictionPrimaryText != nil else {
            return L10n.string("Log a cycle to begin prediction.", defaultValue: "Log a cycle to begin prediction.")
        }

        if viewModel?.hasActionablePrediction == true {
            return viewModel?.predictionMidpointText ?? viewModel?.predictionSecondaryText
        }

        return L10n.string(
            "Keep logging to narrow your future window.",
            defaultValue: "Keep logging to narrow your future window."
        )
    }

    private var lunarTodaySnapshotCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack {
                Text(L10n.string("Today's snapshot", defaultValue: "Today's snapshot"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Button {
                    openLogger(.symptoms)
                } label: {
                    HStack(spacing: AppTheme.spacing4) {
                        Text(L10n.string("View all", defaultValue: "View all"))
                        Image(systemName: "arrow.right")
                    }
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("View all symptoms", defaultValue: "View all symptoms"))
            }

            HStack(spacing: 0) {
                ForEach(lunarSnapshotItems) { item in
                    LunarTodaySnapshotItemView(item: item)
                    if item.id != lunarSnapshotItems.last?.id {
                        Divider()
                            .overlay(AppTheme.premiumEditorBorder.opacity(0.46))
                            .padding(.vertical, AppTheme.spacing8)
                    }
                }
            }
        }
        .padding(AppTheme.spacing16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.largeCardCornerRadius, style: .continuous)
                .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.largeCardCornerRadius, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder.opacity(0.62), lineWidth: 0.8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.lunar.snapshot")
    }

    private var lunarSnapshotItems: [LunarTodaySnapshotItem] {
        [
            LunarTodaySnapshotItem(
                title: lunarTopSymptom.title,
                value: lunarTopSymptom.value,
                systemImage: "camera.macro",
                color: AppTheme.premiumEditorWarningAccentColor
            ),
            LunarTodaySnapshotItem(
                title: L10n.string("Mood", defaultValue: "Mood"),
                value: lunarMoodText,
                systemImage: "cloud.sun.fill",
                color: AppTheme.premiumEditorAccentColor
            ),
            LunarTodaySnapshotItem(
                title: L10n.string("Energy", defaultValue: "Energy"),
                value: lunarEnergyText,
                systemImage: "bolt.fill",
                color: AppTheme.premiumEditorSecondaryAccentColor
            ),
            LunarTodaySnapshotItem(
                title: L10n.string("Sleep", defaultValue: "Sleep"),
                value: lunarSleepText,
                systemImage: "moon.fill",
                color: AppTheme.lavenderAccent
            ),
        ]
    }

    private var lunarTopSymptom: (title: String, value: String) {
        guard let topSymptom = todaysSymptoms.max(by: { $0.severity < $1.severity }) else {
            return (
                title: L10n.string("Symptoms", defaultValue: "Symptoms"),
                value: L10n.string("None yet", defaultValue: "None yet")
            )
        }

        return (
            title: topSymptom.symptomType.displayName,
            value: SeverityPicker.label(for: topSymptom.severity)
        )
    }

    private var lunarMoodText: String {
        if todaysSymptoms.contains(where: { $0.symptomType.category == .mood }) {
            return L10n.string("Tender", defaultValue: "Tender")
        }
        return L10n.string("Calm", defaultValue: "Calm")
    }

    private var lunarEnergyText: String {
        guard let energy = todaysDailyLog?.energyLevel else {
            return L10n.string("Medium", defaultValue: "Medium")
        }
        if energy >= 4 {
            return L10n.string("High", defaultValue: "High")
        } else if energy <= 2 {
            return L10n.string("Low", defaultValue: "Low")
        }
        return L10n.string("Medium", defaultValue: "Medium")
    }

    private var lunarSleepText: String {
        guard let sleepHours = todaysDailyLog?.sleepHours else {
            return L10n.string("No log", defaultValue: "No log")
        }

        let totalMinutes = max(0, Int((sleepHours * 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        guard minutes > 0 else {
            return L10n.format("%lldh", defaultValue: "%lldh", Int64(hours))
        }
        return L10n.format("%lldh %lldm", defaultValue: "%lldh %lldm", Int64(hours), Int64(minutes))
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
            ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, moment: .logSaved, requestReview: requestReview)
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

            if canShowPeriodEndAction {
                Button {
                    showingPeriodEndSheet = true
                } label: {
                    HStack(spacing: AppTheme.spacing8) {
                        Image(systemName: "calendar.badge.checkmark")
                        Text(periodEndButtonTitle)
                            .appFont(.subheadline, weight: .semibold)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.spacing12)
                    .padding(.vertical, AppTheme.spacing8)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                            .fill(AppTheme.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(AppTheme.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.period_end_button")
            }

            if let currentPeriodEndedText {
                HStack(spacing: AppTheme.spacing8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(currentPeriodEndedText)
                        .appFont(.caption, weight: .medium)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .foregroundStyle(AppTheme.sage)
                .accessibilityIdentifier("today.period_end_status")
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

    private var currentPeriodEndedText: String? {
        guard let state = viewModel?.currentPeriodState,
              state.isActive == false,
              let periodEndedDate = state.periodEndedDate
        else { return nil }

        return L10n.format(
            "Period ended %@",
            defaultValue: "Period ended %@",
            formattedPeriodEndDate(periodEndedDate)
        )
    }

    private func formattedPeriodEndDate(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle()
                .locale(L10n.locale())
                .month(.abbreviated)
                .day(.defaultDigits)
        )
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
            UserEntryDefaultsStore.shared.lastFlowIntensity = intensity
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

    private var recommendedPositiveActions: [PositiveActionRecommendation] {
        PositiveActionRecommendationEngine.rankedRecommendations(
            cycleDay: positiveActionCycleDay,
            symptoms: todaysSymptoms,
            completedActions: todaysDailyLog?.positiveActions ?? []
        )
    }

    private var positiveActionCycleDay: Int? {
        guard case .currentCycle(let dayCount) = heroState else {
            return nil
        }
        return dayCount
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

            if !recommendedPositiveActions.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(L10n.string("Recommended for today", defaultValue: "Recommended for today"))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.secondaryText)

                    ForEach(recommendedPositiveActions.prefix(3)) { recommendation in
                        Button {
                            togglePositiveAction(recommendation.action)
                        } label: {
                            HStack(alignment: .top, spacing: AppTheme.spacing8) {
                                Image(systemName: recommendation.action.systemImage)
                                    .appFont(.caption, weight: .semibold)
                                    .foregroundStyle(AppTheme.sage)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(AppTheme.sage.opacity(0.14)))
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                    Text(recommendation.action.displayName)
                                        .appFont(.caption, weight: .semibold)
                                        .foregroundStyle(AppTheme.primaryText)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(recommendation.reason)
                                        .appFont(.caption2)
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: AppTheme.spacing8)

                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppTheme.sage)
                                    .accessibilityHidden(true)
                            }
                            .padding(AppTheme.spacing8)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                                    .fill(AppTheme.sage.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                                    .stroke(AppTheme.sage.opacity(0.18), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(recommendation.action.displayName)
                        .accessibilityHint(recommendation.reason)
                        .accessibilityIdentifier("positive_action.recommendation.\(recommendation.action.rawValue)")
                    }
                }
            }

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

private extension View {
    @ViewBuilder
    func todayLunarPresentation<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if AppTheme.usesImmersivePresentation {
            fullScreenCover(
                isPresented: isPresented,
                onDismiss: onDismiss,
                content: content
            )
        } else {
            sheet(
                isPresented: isPresented,
                onDismiss: onDismiss,
                content: content
            )
        }
    }
}

private struct PredictionEstimateInfoSheet: View {
    let detailText: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppTheme.premiumEditorBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                HStack(alignment: .top) {
                    Text(L10n.string("About this estimate", defaultValue: "About this estimate"))
                        .appHeadingFont(.title3, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .appFont(.title3)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("Close", defaultValue: "Close"))
                }

                if let detailText {
                    Text(detailText)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(
                    L10n.string(
                        "Cycle predictions are ranges, not exact dates. Cycle length can shift from month to month — especially with PCOS — so CycleBalance shows a window and refines it as you log more periods.",
                        defaultValue: "Cycle predictions are ranges, not exact dates. Cycle length can shift from month to month — especially with PCOS — so CycleBalance shows a window and refines it as you log more periods."
                    )
                )
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(AppTheme.spacing24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.prediction_info_sheet")
    }
}

private struct LunarTodaySnapshotItem: Identifiable {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var id: String {
        "\(title)-\(value)-\(systemImage)"
    }
}

private struct LunarTodaySnapshotItemView: View {
    let item: LunarTodaySnapshotItem

    var body: some View {
        VStack(spacing: AppTheme.spacing8) {
            ZStack {
                Circle()
                    .fill(AppTheme.premiumEditorSurface.opacity(0.92))
                Image(systemName: item.systemImage)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(item.color)
            }
            .frame(width: 42, height: 42)

            Text(item.title)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(item.value)
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LunarCycleHeroRing: View {
    let progress: Double
    var isWelcome: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepDone = false
    @State private var bloomBreathing = false
    @State private var aliveShimmer = false
    @State private var settleTask: Task<Void, Never>?

    /// Arc starts at 12 o'clock. Circle paths start at 3 o'clock, so offset -90°.
    private let rotationDegrees = -90.0

    private var motionStyle: RingMotionStyle {
        RingMotionStyle.resolved(reduceMotion: reduceMotion)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ringPalette = AppTheme.cycleHeroRingPalette
            let model = SilkCometRingModel(
                progress: progress,
                isWelcome: isWelcome,
                tailFloorOpacity: ringPalette.tailFloorOpacity
            )
            let lineWidth = max(size * 0.05, 13)
            let trackWidth = max(size * 0.012, 2.5)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = (size - lineWidth) / 2
            let visibleEnd = sweepDone ? model.arcEnd : 0.001
            let shimmerAngle = aliveShimmer ? 4.0 : 0.0
            let tipPoint = point(
                on: center,
                radius: radius,
                trim: model.arcEnd,
                angleOffsetDegrees: shimmerAngle
            )

            ZStack {
                Circle()
                    .stroke(ringPalette.trackGradient, style: StrokeStyle(lineWidth: trackWidth))
                    .padding(lineWidth / 2)
                    .opacity(0.8)

                Circle()
                    .trim(from: 0, to: visibleEnd)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: gradientStops(
                                model: model,
                                ringPalette: ringPalette,
                                lineWidth: lineWidth,
                                radius: radius
                            )),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .padding(lineWidth / 2)
                    .rotationEffect(.degrees(rotationDegrees + shimmerAngle))
                    .shadow(color: ringPalette.tipGlowColor.opacity(0.18), radius: 13, y: 3)

                if model.showsTip {
                    tip(ringPalette: ringPalette, size: size)
                        .position(tipPoint)
                        .opacity(sweepDone ? 1 : 0)
                }
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .onAppear { startMotion() }
        .onDisappear { settleTask?.cancel() }
    }

    private func gradientStops(
        model: SilkCometRingModel,
        ringPalette: CycleHeroRingPalette,
        lineWidth: CGFloat,
        radius: CGFloat
    ) -> [Gradient.Stop] {
        guard !ringPalette.silkColors.isEmpty else { return [] }

        var stops = model.stops.map { stop in
            Gradient.Stop(
                color: ringPalette.silkColors[max(0, min(stop.colorIndex, ringPalette.silkColors.count - 1))]
                    .opacity(stop.opacity),
                location: stop.position
            )
        }

        // Guard the wrap-around: the arc's round start cap bulges just past
        // location 0, where the angular gradient samples positions below 1.0
        // and would repeat the bright tip color, painting a solid half-disc
        // at 12 o'clock. Fade to clear right after the arc end so the tail
        // cap stays invisible; the comet-head overlay covers the tip cap.
        // The guard band spans 1.5x the round cap's angular footprint
        // (lineWidth over the stroke centerline circumference).
        if let tipStop = stops.last, tipStop.location < 1 {
            let capFraction = Double(lineWidth / (2 * .pi * radius))
            let guardBand = max(0.012, capFraction * 1.5)
            let clearTip = tipStop.color.opacity(0)
            stops.append(Gradient.Stop(color: clearTip, location: min(tipStop.location + guardBand, 1)))
            stops.append(Gradient.Stop(color: clearTip, location: 1))
        }
        return stops
    }

    @ViewBuilder
    private func tip(ringPalette: CycleHeroRingPalette, size: CGFloat) -> some View {
        let coreDiameter = max(size * 0.034, 9)
        let bloomDiameter = max(size * 0.16, 40)

        ZStack {
            if ringPalette.showsTipBloom {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                ringPalette.tipGlowColor.opacity(0.55),
                                ringPalette.tipGlowColor.opacity(0.16),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: bloomDiameter / 2
                        )
                    )
                    .frame(width: bloomDiameter, height: bloomDiameter)
                    .scaleEffect(bloomBreathing ? 1.12 : 1)
                    .modifier(GlowBlendModifier(enabled: ringPalette.usesGlowBlend))
            }

            Circle()
                .fill(ringPalette.tipCoreColor)
                .frame(width: coreDiameter, height: coreDiameter)
                .shadow(color: ringPalette.tipGlowColor.opacity(0.7), radius: 5)
        }
    }

    private func startMotion() {
        // Reset to a known rest state (no animation) so re-appearing after a
        // previous run doesn't leave repeatForever animations stuck mid-flight.
        settleTask?.cancel()
        bloomBreathing = false
        aliveShimmer = false

        switch motionStyle {
        case .off:
            sweepDone = true
        case .subtle:
            sweepDone = false
            withAnimation(.easeOut(duration: 1.1)) { sweepDone = true }
            // Odd repeat count ends the presentation expanded, matching the
            // model value, so there is no snap before the settle ease-out.
            withAnimation(.easeInOut(duration: 0.75).repeatCount(3, autoreverses: true).delay(1.1)) {
                bloomBreathing = true
            }
            // Settle back to rest after the breaths (sweep 1.1 + 3 x 0.75 = 3.35).
            settleTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) { bloomBreathing = false }
            }
        case .alive:
            sweepDone = false
            withAnimation(.easeOut(duration: 1.1)) { sweepDone = true }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(1.1)) {
                bloomBreathing = true
            }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                aliveShimmer = true
            }
        }
    }

    private func point(
        on center: CGPoint,
        radius: CGFloat,
        trim: Double,
        angleOffsetDegrees: Double = 0
    ) -> CGPoint {
        let angle = (trim * 360 + rotationDegrees + angleOffsetDegrees) * .pi / 180
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}

private struct GlowBlendModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.blendMode(.plusLighter)
        } else {
            content
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
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.defaultCardCornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(borderOpacity), lineWidth: 0.8)
            )
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    private var backgroundFill: Color {
        if AppTheme.isBotanicalJournal {
            AppTheme.botanicalCreamAltRGB.color.opacity(0.74)
        } else if AppTheme.usesImmersiveHomeShell {
            AppTheme.premiumEditorRaisedSurface.opacity(0.74)
        } else {
            color.opacity(AppTheme.opacityLight)
        }
    }

    private var borderOpacity: Double {
        if AppTheme.isBotanicalJournal {
            0.18
        } else if AppTheme.usesImmersiveHomeShell {
            0.34
        } else {
            0
        }
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
