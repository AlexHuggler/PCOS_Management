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
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var showingPersonalization = false
    @State private var trackingPreferences = TrackingPreferences.shared
    @State private var recentHealthLogs: [DailyLog] = []
    @State private var healthOwnership: [HealthKitFieldOwnership] = []
    @State private var healthSources: [HealthKitImportedSampleRecord] = []
    @State private var quickCheckIn = QuickCheckInInput()
    @State private var checkInDays = 0
    @State private var lastCheckInBeforeToday: Date?
    @State private var showCheckInSaved = false
    @State private var activeLogger: LoggerShortcut?
    @AppStorage(PremiumNudgePolicy.dismissedKey) private var premiumCardDismissed = false

    var body: some View {
        NavigationStack {
            companionSurface
                .sheet(isPresented: $showingPersonalization) {
                    NavigationStack { PersonalizationView() }
                }
                .sheet(isPresented: $showingLogSymptoms, onDismiss: { refreshToday() }) {
                    SymptomLogView()
                }
                // A8: shortcuts and resumed Premium actions open in place on Today (no tab jump).
                .sheet(item: $activeLogger, onDismiss: {
                    refreshToday()
                    consumeTodayLogger()
                }) { shortcut in
                    todayLoggerDestination(shortcut)
                }
                .sheet(isPresented: $showingPeriodEndSheet, onDismiss: { refreshToday() }) {
                    if let viewModel, let state = viewModel.currentPeriodState {
                        PeriodEndSheet(periodState: state, onSave: { date, reference in
                            try viewModel.markPeriodEnded(on: date, referenceDate: reference)
                        }, onSaved: { refreshToday() })
                    }
                }
                .alert(item: $quickLogAlert) { alert in
                    switch alert {
                    case .error(let message):
                        Alert(title: Text(L10n.string("Couldn't Save", defaultValue: "Couldn't Save")), message: Text(message), dismissButton: .cancel(Text(L10n.string("OK", defaultValue: "OK"))))
                    case .confirmNewCycle:
                        Alert(title: Text(L10n.string("Log Period", defaultValue: "Log Period")), dismissButton: .cancel())
                    }
                }
                .onAppear {
                    loadTodayIfNeeded()
                    consumeTodayLogger()
                }
                .onChange(of: appState.pendingLoggerShortcut) { _, _ in consumeTodayLogger() }
                .onChange(of: appState.selectedTab) { _, _ in consumeTodayLogger() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { refreshToday() } }
                .onChange(of: appState.lifecycleMode) { _, _ in refreshToday() }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshToday() }
                .onReceive(NotificationCenter.default.publisher(for: InsightRefreshCoordinator.notificationName)) { _ in refreshToday() }
                .onReceive(NotificationCenter.default.publisher(for: .healthKitDidCommit)) { _ in refreshToday() }
        }
    }

    private var companionSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                companionGreeting
                companionCheckIn
                patternProgressCard
                companionFavorites
                if showsPremiumCard { premiumNudgeCard }
                ForEach(orderedCompanionCards) { card in companionCard(card) }
                NavigationLink { CycleDetailView() } label: {
                    Label(L10n.string("Your cycle history", defaultValue: "Your cycle history"), systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                }
            }
            .padding()
            .padding(.bottom, 16)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .refreshable { refreshToday() }
        .navigationTitle(L10n.string("Today", defaultValue: "Today"))
        // The greeting is the page heading (A8), so the bar title stays small.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppTheme.preferredColorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingPersonalization = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel(L10n.string("Make it yours", defaultValue: "Make it yours"))
                    .accessibilityIdentifier("today.personalization")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.today")
    }

    private var orderedCompanionCards: [TodayCard] {
        trackingPreferences.visibleCards
    }

    private func loadTodayIfNeeded() {
        if viewModel == nil { viewModel = CycleViewModel(modelContext: modelContext) }
        if pregnancyViewModel == nil { pregnancyViewModel = PregnancyViewModel(modelContext: modelContext) }
        refreshToday()
    }

    private func refreshToday() {
        viewModel?.loadData()
        pregnancyViewModel?.loadData()
        refreshTodaysSymptoms()
        refreshStreak()
        refreshSummaryData()
        refreshQuickCheckIn()
    }

    private func refreshQuickCheckIn() {
        let summary = CheckInProgress.summary(modelContext: modelContext)
        checkInDays = summary.days
        lastCheckInBeforeToday = summary.lastBeforeToday
        do {
            quickCheckIn = try QuickCheckInService(modelContext: modelContext).load()
        } catch {
            Logger.database.error("Failed to load today's check-in: \(error.localizedDescription)")
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
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date >= cutoff }, sortBy: [SortDescriptor(\.date, order: .reverse)])
            recentHealthLogs = try modelContext.fetch(descriptor)
            healthOwnership = try modelContext.fetch(FetchDescriptor<HealthKitFieldOwnership>())
            healthSources = try modelContext.fetch(FetchDescriptor<HealthKitImportedSampleRecord>(predicate: #Predicate { $0.startDate >= cutoff }))
        } catch {
            recentHealthLogs = []
            healthOwnership = []
            healthSources = []
        }
        do {
            topAhaMoment = try AhaMomentService(modelContext: modelContext)
                .topMoment(isPremium: appState.allowsPremiumAccess)
        } catch {
            Logger.database.error("Failed to refresh aha moment: \(error.localizedDescription)")
            topAhaMoment = nil
        }
    }

    /// A8: "Good evening, Maya" with the date and, when known, the cycle day.
    private var companionGreeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingTitle)
                .appHeadingFont(.title, weight: .bold)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("today.greeting")
            Text(greetingSubtitle)
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if isReturningAfterGap {
                Text(welcomeBackText)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityIdentifier("today.welcome_back")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Back after a few days away: welcome her back and say nothing was reset (no streak guilt).
    private var isReturningAfterGap: Bool {
        CheckInProgress.isReturningAfterGap(
            lastCheckInBeforeToday: lastCheckInBeforeToday,
            hasCheckedInToday: hasCheckIn || showCheckInSaved
        )
    }

    private var welcomeBackText: String {
        if let name = appState.onboardingProfile.preferredDisplayName {
            return L10n.format(
                "Welcome back, %@. Your earlier check-ins still count.",
                defaultValue: "Welcome back, %@. Your earlier check-ins still count.",
                name
            )
        }
        return L10n.string(
            "Welcome back. Your earlier check-ins still count.",
            defaultValue: "Welcome back. Your earlier check-ins still count."
        )
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = appState.onboardingProfile.preferredDisplayName
        switch (hour, name) {
        case (5..<12, let name?): return L10n.format("Good morning, %@", defaultValue: "Good morning, %@", name)
        case (12..<17, let name?): return L10n.format("Good afternoon, %@", defaultValue: "Good afternoon, %@", name)
        case (_, let name?): return L10n.format("Good evening, %@", defaultValue: "Good evening, %@", name)
        case (5..<12, nil): return L10n.string("Good morning", defaultValue: "Good morning")
        case (12..<17, nil): return L10n.string("Good afternoon", defaultValue: "Good afternoon")
        default: return L10n.string("Good evening", defaultValue: "Good evening")
        }
    }

    private var greetingSubtitle: String {
        let date = Date.now.formatted(Date.FormatStyle().weekday(.wide).month(.wide).day().locale(appState.renderLocale))
        guard appState.lifecycleMode == .cycling, let day = viewModel?.currentCycleDayCount else { return date }
        return L10n.format("%@ · Cycle day %lld", defaultValue: "%@ · Cycle day %lld", date, Int64(day))
    }

    @ViewBuilder
    private var companionCycleContext: some View {
        if appState.lifecycleMode != .cycling {
            cycleStatusCard
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .foregroundStyle(AppTheme.accentColor)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    if let day = viewModel?.currentCycleDayCount {
                        Text(L10n.format("Cycle day %lld", defaultValue: "Cycle day %lld", Int64(day)))
                            .appFont(.headline)
                        Text(L10n.string("Counted from your last recorded period start.", defaultValue: "Counted from your last recorded period start."))
                            .appFont(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(L10n.string("Your timeline starts with you", defaultValue: "Your timeline starts with you"))
                            .appFont(.headline)
                        Text(L10n.string("You can check in without recording a period.", defaultValue: "You can check in without recording a period."))
                            .appFont(.caption).foregroundStyle(.secondary)
                    }
                    if trackingPreferences.informationDetail == .detailed, let ended = currentPeriodEndedText {
                        Text(ended).appFont(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if canShowPeriodEndAction {
                    Button { showingPeriodEndSheet = true } label: {
                        Text(L10n.string("End period", defaultValue: "End period"))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(16)
            .premiumCardDecoration()
        }
    }

    private var hasCheckIn: Bool {
        guard let log = todaysDailyLog else { return !todaysSymptoms.isEmpty }
        return log.moodRawValue != nil || log.symptomsReviewed || log.energyLevel != nil || log.stressLevel != nil || log.painLevel0To10 != nil || log.waterOz != nil || !(log.privateNote ?? "").isEmpty || !todaysSymptoms.isEmpty
    }

    /// Up to three pinned symptoms as quick chips (from onboarding A4 or Personalization).
    private var quickSymptoms: [SymptomType] {
        let pinned = trackingPreferences.pinnedSymptomRawValues.compactMap(SymptomType.init(rawValue:))
        let source = pinned.isEmpty ? OnboardingPersonalizationPlan.defaultPinnedSymptoms : pinned
        return Array(source.prefix(3))
    }

    /// A8 inline check-in: the same component as onboarding (A5). Each tap saves straight away;
    /// tapping a selected severity again clears it; "More details" opens the full check-in.
    private var companionCheckIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("How are you feeling?", defaultValue: "How are you feeling?"))
                    .appHeadingFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if showCheckInSaved || hasCheckIn {
                    Label(L10n.string("Saved", defaultValue: "Saved"), systemImage: "checkmark.circle.fill")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.accentColor)
                        .accessibilityIdentifier("today.checkin.saved")
                }
            }
            QuickCheckInPanel(
                input: quickCheckIn,
                symptoms: quickSymptoms,
                moodMinHeight: 52,
                // "Nothing to report" would clear the day's symptoms, so it is only offered while
                // none are logged; it never deletes something she entered elsewhere.
                showsNothingToReport: quickCheckIn.nothingToReport || todaysSymptoms.isEmpty,
                onMood: { mood in
                    var input = QuickCheckInInput()
                    input.mood = mood
                    saveQuickCheckIn(input)
                },
                onSeverity: { symptom, severity in
                    if quickCheckIn.severities[symptom] == severity {
                        clearQuickSymptom(symptom)
                    } else {
                        var input = QuickCheckInInput()
                        input.severities[symptom] = severity
                        saveQuickCheckIn(input)
                    }
                },
                onNothingToReport: toggleNothingToReport
            )
            Button { showingLogSymptoms = true } label: {
                Text(L10n.string("More details", defaultValue: "More details"))
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.accentColor)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.checkin")
        }
        .padding(16)
        .premiumCardDecoration()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.checkin_card")
    }

    /// A8: "3 of 7 toward your first pattern". Missed days are fine; there are no streaks here.
    private var patternProgressCard: some View {
        let target = CheckInProgress.firstPatternTarget
        let completed = CheckInProgress.displayed(checkInDays)
        return HStack(alignment: .center, spacing: 14) {
            PatternProgressRing(completed: completed, target: target)
            VStack(alignment: .leading, spacing: 4) {
                if completed >= target {
                    Text(L10n.string("Your first pattern is ready", defaultValue: "Your first pattern is ready"))
                        .appFont(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { appState.selectTab(.insights) } label: {
                        Text(L10n.string("See what's connected", defaultValue: "See what's connected"))
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(AppTheme.accentColor)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.progress.insights")
                } else {
                    // The ring already reads "3 of 7 check-ins toward your first pattern" to VoiceOver.
                    Text(L10n.format("%lld of %lld toward your first pattern", defaultValue: "%lld of %lld toward your first pattern", Int64(completed), Int64(target)))
                        .appFont(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                    Text(L10n.string("Each check-in adds to your first pattern. Missed days are fine.", defaultValue: "Each check-in adds to your first pattern. Missed days are fine."))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .premiumCardDecoration()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.pattern_progress")
    }

    private var companionFavorites: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { favoriteButtons }
            VStack(spacing: 8) { favoriteButtons }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Your shortcuts", defaultValue: "Your shortcuts"))
    }

    private var favoriteButtons: some View {
        ForEach(trackingPreferences.favoriteActions.filter { $0.isVisible(in: appState.lifecycleMode, showFertility: trackingPreferences.showFertility) }) { shortcut in
            Button { openLogger(shortcut) } label: {
                VStack(spacing: 8) {
                    Image(systemName: shortcut.systemImage)
                        .font(.title3)
                        .foregroundStyle(AppTheme.accentColor)
                        .accessibilityHidden(true)
                    Text(shortcut.title).appFont(.subheadline, weight: .medium)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                    if shortcut.requiresPremium && !appState.allowsPremiumAccess {
                        Text(L10n.string("Premium", defaultValue: "Premium"))
                            .appFont(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .padding(12)
                .premiumCardDecoration()
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.primaryText)
            .accessibilityIdentifier("today.favorite.\(shortcut.rawValue)")
        }
    }

    // MARK: - Premium card (after day 3, dismissible)

    private var showsPremiumCard: Bool {
        PremiumNudgePolicy.shouldShow(
            checkInDays: checkInDays,
            hasPremiumAccess: appState.allowsPremiumAccess,
            showsSubscriptionUI: appState.showsSubscriptionUI,
            dismissed: premiumCardDismissed
        )
    }

    private var premiumNudgeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "fork.knife")
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(AppTheme.coralAccent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous).fill(AppTheme.cardBackground))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Curious how meals affect your energy?", defaultValue: "Curious how meals affect your energy?"))
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    appState.requestLogger(.meal, host: .today, source: "today_premium_card")
                } label: {
                    Text(L10n.string("Try meal logging", defaultValue: "Try meal logging"))
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.coralAccent)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.premium_card.open")
            }
            Spacer(minLength: 0)
            Button {
                premiumCardDismissed = true
                AppAnalytics.shared.track(.premiumCardDismissed)
            } label: {
                Image(systemName: "xmark")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("Dismiss tip", defaultValue: "Dismiss tip"))
            .accessibilityIdentifier("today.premium_card.dismiss")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .fill(AppTheme.coralAccent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .stroke(AppTheme.coralAccent.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.premium_card")
    }

    // MARK: - Inline check-in actions

    private func saveQuickCheckIn(_ input: QuickCheckInInput) {
        do {
            try QuickCheckInService(modelContext: modelContext).save(input)
            CheckInAnalytics.recordSave(source: .today)
            showCheckInSaved = true
            refreshToday()
        } catch {
            Logger.database.error("Failed to save inline check-in: \(error.localizedDescription)")
            quickLogAlert = .error(L10n.string(
                "Your check-in was not saved. Please check your entries and try again.",
                defaultValue: "Your check-in was not saved. Please check your entries and try again."
            ))
        }
    }

    private func toggleNothingToReport() {
        guard quickCheckIn.nothingToReport else {
            var input = QuickCheckInInput()
            input.nothingToReport = true
            saveQuickCheckIn(input)
            return
        }
        do {
            try QuickCheckInService(modelContext: modelContext).clearNothingToReport()
            refreshToday()
        } catch {
            Logger.database.error("Failed to clear Nothing to report: \(error.localizedDescription)")
            quickLogAlert = .error(L10n.string(
                "Your check-in was not saved. Please check your entries and try again.",
                defaultValue: "Your check-in was not saved. Please check your entries and try again."
            ))
        }
    }

    private func clearQuickSymptom(_ symptom: SymptomType) {
        do {
            try QuickCheckInService(modelContext: modelContext).clearSymptom(symptom)
            refreshToday()
        } catch {
            Logger.database.error("Failed to clear inline symptom: \(error.localizedDescription)")
            quickLogAlert = .error(L10n.string(
                "Your check-in was not saved. Please check your entries and try again.",
                defaultValue: "Your check-in was not saved. Please check your entries and try again."
            ))
        }
    }

    // MARK: - Loggers opened in place

    private func consumeTodayLogger() {
        guard activeLogger == nil, let shortcut = appState.consumePendingLogger(host: .today) else { return }
        UserEntryDefaultsStore.shared.lastLoggerShortcut = shortcut
        activeLogger = shortcut
    }

    @ViewBuilder
    private func todayLoggerDestination(_ shortcut: LoggerShortcut) -> some View {
        switch shortcut {
        case .period: CycleLogView()
        case .ovulation: OvulationLogView()
        case .symptoms: SymptomLogView()
        case .bloodSugar: BloodSugarLogView()
        case .supplements: SupplementLogView()
        case .meal: MealLogView(entryPoint: .today)
        case .photo: PhotoGalleryView()
        }
    }

    @ViewBuilder
    private func companionCard(_ card: TodayCard) -> some View {
        switch card {
        case .cycle: companionCycleContext
        case .health: companionHealth
        case .observation:
            if let topAhaMoment { AhaMomentCard(moment: topAhaMoment) }
        case .symptoms: todaysSymptomsSection
        case .meals: mealSummarySection
        case .supplements: supplementSummarySection
        case .glucose: bloodSugarSummarySection
        case .actions: positiveActionsSection
        }
    }

    private var companionHealth: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.string("Your health context", defaultValue: "Your health context"), systemImage: "heart.text.square")
                    .appFont(.headline)
                Spacer()
                NavigationLink { HealthKitSettingsView() } label: {
                    Image(systemName: "arrow.up.right")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.string("Apple Health settings", defaultValue: "Apple Health settings"))
            }
            let fields = ["sleepHours", "activeMinutes", "restingHeartRateBPM"] + (trackingPreferences.showWeight ? ["weight"] : [])
            let hasValues = fields.contains { field in recentHealthLogs.contains { HealthKitFieldOwnership.value(field: field, log: $0) != nil } }
            if hasValues {
                ForEach(fields, id: \.self) { field in
                    if let log = recentHealthLogs.first(where: { HealthKitFieldOwnership.value(field: field, log: $0) != nil }),
                       let value = HealthKitFieldOwnership.value(field: field, log: log) {
                        companionHealthRow(field: field, value: value, log: log)
                    }
                }
            } else {
                Text(L10n.string("Bring in sleep and activity from Apple Health, when you choose.", defaultValue: "Bring in sleep and activity from Apple Health, when you choose."))
                    .appFont(.subheadline).foregroundStyle(.secondary)
                NavigationLink(L10n.string("Choose Health data", defaultValue: "Choose Health data")) { HealthKitSettingsView() }
            }
        }
        .padding(20)
        .premiumCardDecoration()
        .accessibilityIdentifier("today.health_context")
    }

    private func companionHealthRow(field: String, value: Double, log: DailyLog) -> some View {
        let owner = healthOwnership.first { $0.recordID == log.id && $0.field == field }
        let imported = owner != nil && owner?.isManual == false
        let identifierSuffix = ["weight": "BodyMass", "sleepHours": "SleepAnalysis", "activeMinutes": "AppleExerciseTime", "restingHeartRateBPM": "RestingHeartRate"][field] ?? ""
        let sources = healthSources.filter { $0.derivedRecordID == log.id && $0.healthKitIdentifier.hasSuffix(identifierSuffix) }
        let sourceNames = Set(sources.map(\.sourceLabel)).sorted().joined(separator: ", ")
        let title: String
        let formatted: String
        switch field {
        case "sleepHours":
            title = L10n.string("Sleep", defaultValue: "Sleep")
            formatted = L10n.format("%.1f hr", defaultValue: "%.1f hr", value)
        case "activeMinutes":
            title = L10n.string("Activity", defaultValue: "Activity")
            formatted = L10n.format("%lld min", defaultValue: "%lld min", Int64(value))
        case "weight":
            title = L10n.string("Weight", defaultValue: "Weight")
            formatted = trackingPreferences.bodyMeasurementStyle == .metric
                ? L10n.format("%.1f kg", defaultValue: "%.1f kg", trackingPreferences.bodyMeasurementStyle.weight(fromPounds: value))
                : L10n.format("%.1f lb", defaultValue: "%.1f lb", value)
        default:
            title = L10n.string("Resting heart rate", defaultValue: "Resting heart rate")
            formatted = L10n.format("%lld bpm", defaultValue: "%lld bpm", Int64(value))
        }
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).appFont(.subheadline)
                Spacer()
                Text(formatted).appFont(.subheadline, weight: .semibold).monospacedDigit()
            }
            HStack(spacing: 4) {
                Text(imported ? L10n.string("Apple Health", defaultValue: "Apple Health") : L10n.string("Recorded", defaultValue: "Recorded"))
                Text("·")
                Text(log.date, format: .dateTime.month(.abbreviated).day())
            }
            .appFont(.caption).foregroundStyle(.secondary)
            if imported && trackingPreferences.informationDetail == .detailed {
                if !sourceNames.isEmpty { Text(sourceNames).appFont(.caption).foregroundStyle(.secondary) }
                if let updated = sources.map(\.importedAt).max() {
                    Text(L10n.format("Imported %@", defaultValue: "Imported %@", updated.formatted(date: .abbreviated, time: .shortened)))
                        .appFont(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
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
                    .padding(AppTheme.spacing20)
                    .premiumCardDecoration(cornerRadius: AppTheme.largeCardCornerRadius)
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
                    .fixedSize(horizontal: false, vertical: true)

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
            .overlay(
                Circle()
                    .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 1)
                    .padding(-3.5)
                    .opacity(0.7)
            )
            .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.32), radius: 18, y: 6)
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
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(dayCount)")
                    .appHeadingFont(.largeTitle, weight: .regular)
                    .font(AppTheme.headingFont(.largeTitle, weight: .regular))
                    .scaleEffect(1.46)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
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
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: AppTheme.spacing4) {
                    Text(L10n.string("Next period", defaultValue: "Next period"))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(viewModel?.predictionCountdownText() ?? lunarPredictionHeadline)
                        .appHeadingFont(.title2, weight: .regular)
                        .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let secondary = lunarPredictionDetailText {
                        HStack(spacing: AppTheme.spacing4) {
                            Text(secondary)
                                .appFont(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            if viewModel?.hasActionablePrediction == true {
                                Button {
                                    showingPredictionInfo = true
                                } label: {
                                    Image(systemName: "info.circle")
                                        .appFont(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
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
                            .fixedSize(horizontal: false, vertical: true)
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
        .padding(AppTheme.spacing20)
        .premiumCardDecoration()
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
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.softGoldAccent)
                Text(
                    L10n.inflected(
                        LocalizedStringResource(
                            "^[\(streakDays) day](inflect: true) logging streak",
                            comment: "Badge showing the user's current logging streak in days."
                        )
                    )
                )
                    .appFont(.caption, weight: .medium)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, AppTheme.spacing12)
            .padding(.vertical, AppTheme.spacing8)
            .background(Capsule().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.6)))
            .overlay(Capsule().stroke(AppTheme.premiumEditorBorder.opacity(0.5), lineWidth: 0.8))
            .frame(maxWidth: .infinity)
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
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)

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
                .padding(AppTheme.spacing20)
                .premiumCardDecoration()
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
        .padding(AppTheme.spacing20)
        .premiumCardDecoration()
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
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
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
        .padding(AppTheme.spacing20)
        .premiumCardDecoration()
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
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
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
            .padding(AppTheme.spacing20)
            .premiumCardDecoration()
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
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
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
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.spacing20)
                .contentShape(Rectangle())
                .premiumCardDecoration()
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
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
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
                .padding(AppTheme.spacing20)
                .contentShape(Rectangle())
                .premiumCardDecoration()
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
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
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
                .padding(AppTheme.spacing20)
                .contentShape(Rectangle())
                .premiumCardDecoration()
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
                            .foregroundStyle(AppTheme.primaryText)
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppTheme.accentColor)
                    }
                    .appFont(.headline, weight: .semibold)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(postpartumText)
                        .appFont(.subheadline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.spacing20)
                .premiumCardDecoration()
            } else if !AppTheme.usesImmersiveHomeShell, let predictionText = viewModel?.predictionPrimaryText {
                let sectionTitle = viewModel?.hasActionablePrediction == true
                    ? L10n.string("Period Estimate", defaultValue: "Period Estimate")
                    : L10n.string("Estimate Update", defaultValue: "Estimate Update")
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Label {
                        Text(sectionTitle)
                            .foregroundStyle(AppTheme.primaryText)
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppTheme.coralAccent)
                    }
                        .appFont(.headline, weight: .semibold)
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
                .padding(AppTheme.spacing20)
                .premiumCardDecoration()
            }
        }
    }

    private func openLogger(_ shortcut: LoggerShortcut) {
        appState.requestLogger(shortcut, host: .today, source: "today_\(shortcut.rawValue)")
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
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
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
                    .fill(item.color.opacity(0.14))
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
                Image(systemName: item.systemImage)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(item.color)
            }
            .frame(width: 42, height: 42)

            Text(item.title)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.value)
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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
            Task { @MainActor in
                // Yield a frame so the reset above commits on its own tick;
                // otherwise the same-tick false -> true change coalesces on
                // re-appearance and the replay sweep doesn't animate.
                await Task.yield()
                withAnimation(.easeOut(duration: 1.1)) { sweepDone = true }
                // Odd repeat count ends the presentation expanded, matching the
                // model value, so there is no snap before the settle ease-out.
                withAnimation(.easeInOut(duration: 0.75).repeatCount(3, autoreverses: true).delay(1.1)) {
                    bloomBreathing = true
                }
            }
            // Settle back to rest after the breaths (sweep 1.1 + 3 x 0.75 = 3.35).
            settleTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) { bloomBreathing = false }
            }
        case .alive:
            sweepDone = false
            Task { @MainActor in
                // Same frame yield as .subtle so the replay sweep animates.
                await Task.yield()
                withAnimation(.easeOut(duration: 1.1)) { sweepDone = true }
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(1.1)) {
                    bloomBreathing = true
                }
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    aliveShimmer = true
                }
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
                    .fixedSize(horizontal: false, vertical: true)
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
