import Foundation
import SwiftData
import Testing
@testable import PCOS

// Focused tests for the v1 target journey: onboarding personalization, the tap-first check-in,
// first-pattern progress, the day-3 Premium card, paywall routing and privacy-safe analytics.

@Suite("Journey v1: onboarding personalization")
struct OnboardingPersonalizationPlanTests {
    @Test("No answers fall back to the default pinned symptoms and free shortcuts")
    func emptyAnswersUseDefaults() {
        let plan = OnboardingPersonalizationPlan.make(topics: [], experience: nil)
        #expect(plan.pinnedSymptoms == [.fatigue, .acne, .bloating])
        #expect(plan.favoriteActions == [.period, .symptoms])
        #expect(plan.visibleCards == [.cycle, .health, .observation, .symptoms])
        #expect(plan.informationDetail == .simple)
        #expect(!plan.healthCategories.contains(.glucose))
    }

    @Test("Focus topics pin related symptoms, capped at four, in the order chosen")
    func topicsPinSymptoms() {
        let plan = OnboardingPersonalizationPlan.make(topics: [.moodEnergy, .skinHair, .painCramps], experience: .newlyDiagnosed)
        #expect(plan.pinnedSymptoms == [.fatigue, .moodSwings, .acne, .shedding])
        #expect(plan.pinnedSymptoms.count <= OnboardingPersonalizationPlan.maxPinnedSymptoms)
    }

    @Test("Default shortcuts never include a Premium logger")
    func shortcutsAreFree() {
        for topics in [[], [OnboardingFocusTopic.bloodSugar], [.cravingsDigestion, .sleep], OnboardingFocusTopic.allCases] {
            let plan = OnboardingPersonalizationPlan.make(topics: topics, experience: nil)
            #expect(plan.favoriteActions.allSatisfy { !$0.requiresPremium })
        }
        #expect(TrackingSelection().favoriteActions.allSatisfy { !$0.requiresPremium })
    }

    @Test("Irregular periods keep cycle context first; sleep keeps Apple Health near the top")
    func cardOrderFollowsTopics() {
        let periods = OnboardingPersonalizationPlan.make(topics: [.irregularPeriods], experience: nil)
        #expect(periods.visibleCards.first == .cycle)
        #expect(periods.favoriteActions.first == .period)

        let skin = OnboardingPersonalizationPlan.make(topics: [.skinHair], experience: nil)
        #expect(skin.visibleCards.first == .observation)
        #expect(skin.favoriteActions.first == .symptoms)

        let sleep = OnboardingPersonalizationPlan.make(topics: [.sleep], experience: nil)
        #expect(sleep.visibleCards.firstIndex(of: .health)! < sleep.visibleCards.firstIndex(of: .observation)!)
    }

    @Test("Managing for a while sets Detailed explanations")
    func experienceSetsDetail() {
        #expect(OnboardingPersonalizationPlan.make(topics: [], experience: .experienced).informationDetail == .detailed)
        #expect(OnboardingPersonalizationPlan.make(topics: [], experience: .exploring).informationDetail == .simple)
    }

    @Test("Apple Health pre-checks Sleep, Movement and Cycle; Glucose only when chosen")
    func healthPreselection() {
        #expect(OnboardingHealthChoice.defaultSelection(for: []) == [.sleep, .movement, .cycle])
        #expect(OnboardingHealthChoice.defaultSelection(for: [.bloodSugar]).contains(.glucose))
        #expect(OnboardingHealthChoice.categories(for: [.cycle]) == [.cycle, .symptoms])
        #expect(OnboardingHealthChoice.categories(for: [.sleep, .movement]) == [.sleep, .activity])
        let plan = OnboardingPersonalizationPlan.make(topics: [.bloodSugar], experience: nil)
        #expect(plan.healthCategories.contains(.glucose))
    }

    @Test("Focus topics round-trip through defaults and map onto legacy focus areas")
    func topicsPersist() throws {
        let name = "JourneyV1.topics.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        OnboardingFocusTopic.store([.sleep, .skinHair], defaults: defaults)
        #expect(OnboardingFocusTopic.stored(defaults: defaults) == [.sleep, .skinHair])
        #expect(OnboardingFocusTopic.cravingsDigestion.symptomFocusArea == .digestionWeight)
        #expect(OnboardingFocusTopic.sleep.symptomFocusArea == nil)
    }

    @Test("Onboarding timing reports seconds since the first start")
    func onboardingDuration() throws {
        let name = "JourneyV1.timing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        OnboardingTiming.markStarted(now: start, defaults: defaults)
        OnboardingTiming.markStarted(now: start.addingTimeInterval(500), defaults: defaults)
        #expect(OnboardingTiming.durationSeconds(now: start.addingTimeInterval(75), defaults: defaults) == 75)
    }
}

@Suite("Journey v1: tap-first check-in")
struct QuickCheckInTests {
    @Test("Three-step severity stores on the 1-5 scale and reads back to the nearest step")
    func severityMapping() {
        #expect(QuickSeverity.allCases.map(\.rawValue) == [1, 3, 5])
        #expect(QuickSeverity(storedSeverity: 2) == .mild)
        #expect(QuickSeverity(storedSeverity: 3) == .moderate)
        #expect(QuickSeverity(storedSeverity: 4) == .strong)
        #expect(QuickSeverity(storedSeverity: 0) == nil)
    }

    @Test("Toggling a severity selects, switches and clears; Nothing to report clears symptoms")
    func toggles() {
        var input = QuickCheckInInput()
        #expect(input.isEmpty)
        input.toggle(.mild, for: .fatigue)
        #expect(input.severities[.fatigue] == .mild)
        input.toggle(.strong, for: .fatigue)
        #expect(input.severities[.fatigue] == .strong)
        input.toggle(.strong, for: .fatigue)
        #expect(input.severities[.fatigue] == nil)
        input.toggle(.moderate, for: .acne)
        input.toggleNothingToReport()
        #expect(input.nothingToReport)
        #expect(input.severities.isEmpty)
        input.toggle(.mild, for: .bloating)
        #expect(!input.nothingToReport)
    }

    @Test("A typical first check-in takes fewer than six taps")
    func underSixTaps() {
        var input = QuickCheckInInput()
        input.mood = .okay
        input.toggle(.moderate, for: .fatigue)
        input.toggle(.mild, for: .acne)
        #expect(input.tapCount + 1 < 6) // plus the Save tap
    }

    @Test("Applying keeps the day's other symptoms and marks symptoms reviewed")
    func applyingMerges() {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var loaded = DailyCheckInDraft(date: date)
        loaded.symptoms = .set([.cramps: 2])
        loaded.rememberLoadedSymptoms()

        var input = QuickCheckInInput()
        input.mood = .good
        input.severities[.acne] = .strong
        let edited = input.applying(to: loaded)
        #expect(edited.mood == .set(.good))
        #expect(edited.symptoms.value == [.cramps: 2, .acne: 5])
        #expect(edited.symptomsReviewed)

        var nothing = QuickCheckInInput()
        nothing.nothingToReport = true
        let cleared = nothing.applying(to: loaded)
        #expect(cleared.symptoms == .clear)
        #expect(cleared.symptomsReviewed)
    }

    @Test("Saving, loading and clearing through the check-in service")
    @MainActor
    func serviceRoundTrip() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = QuickCheckInService(modelContext: context)
        let today = Date()
        #expect(CheckInProgress.checkInDayCount(modelContext: context) == 0)

        var input = QuickCheckInInput()
        input.mood = .low
        input.severities = [.fatigue: .moderate, .bloating: .mild]
        try service.save(input, on: today)

        let loaded = try service.load(on: today)
        #expect(loaded.mood == .low)
        #expect(loaded.severities == [.fatigue: .moderate, .bloating: .mild])
        #expect(CheckInProgress.checkInDayCount(modelContext: context) == 1)

        try service.clearSymptom(.bloating, on: today)
        #expect(try service.load(on: today).severities == [.fatigue: .moderate])
        #expect(try service.load(on: today).mood == .low)
    }

    @Test("Nothing to report can be undone on Today without touching logged symptoms")
    @MainActor
    func nothingToReportUndo() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = QuickCheckInService(modelContext: context)
        let today = Date()

        var nothing = QuickCheckInInput()
        nothing.nothingToReport = true
        try service.save(nothing, on: today)
        #expect(try service.load(on: today).nothingToReport)

        try service.clearNothingToReport(on: today)
        #expect(try service.load(on: today).nothingToReport == false)

        // With a symptom logged, clearing "nothing to report" is a no-op.
        var symptom = QuickCheckInInput()
        symptom.severities = [.fatigue: .strong]
        try service.save(symptom, on: today)
        try service.clearNothingToReport(on: today)
        #expect(try service.load(on: today).severities == [.fatigue: .strong])
    }
}

@Suite("Journey v1: first-pattern progress and the Premium card")
struct CheckInProgressTests {
    @Test("Progress counts distinct days and caps at seven")
    func distinctDays() {
        // Fixed time zone: the base date is 23:13 in US Pacific (PDT), so base + 1 h would fall on
        // the next day there with the device's time zone.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let dates = [base, base.addingTimeInterval(3600), base.addingTimeInterval(86_400 * 2)]
        #expect(CheckInProgress.distinctDays(dates, calendar: calendar) == 2)
        #expect(CheckInProgress.displayed(3) == 3)
        #expect(CheckInProgress.displayed(12) == CheckInProgress.firstPatternTarget)
        #expect(CheckInProgress.displayed(-1) == 0)
        #expect(CheckInProgress.fraction(7) == 1)
    }

    @Test("Welcome back appears after a gap of 3+ days, only before today's check-in")
    func returnAfterGap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let day: TimeInterval = 86_400
        #expect(!CheckInProgress.isReturningAfterGap(lastCheckInBeforeToday: nil, hasCheckedInToday: false, now: now, calendar: calendar))
        #expect(!CheckInProgress.isReturningAfterGap(lastCheckInBeforeToday: now - day, hasCheckedInToday: false, now: now, calendar: calendar))
        #expect(!CheckInProgress.isReturningAfterGap(lastCheckInBeforeToday: now - 2 * day, hasCheckedInToday: false, now: now, calendar: calendar))
        #expect(CheckInProgress.isReturningAfterGap(lastCheckInBeforeToday: now - 3 * day, hasCheckedInToday: false, now: now, calendar: calendar))
        #expect(!CheckInProgress.isReturningAfterGap(lastCheckInBeforeToday: now - 10 * day, hasCheckedInToday: true, now: now, calendar: calendar))
    }

    @Test("The latest check-in before today ignores today's records")
    func latestDayBeforeToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let day: TimeInterval = 86_400
        let dates = [now, now - 5 * day, now - 4 * day]
        #expect(CheckInProgress.latestDay(before: now, in: dates, calendar: calendar) == calendar.startOfDay(for: now - 4 * day))
        #expect(CheckInProgress.latestDay(before: now, in: [now], calendar: calendar) == nil)
    }

    @Test("Mood dots use one hue in five distinct tints, strongest for Great")
    func moodTints() {
        let opacities = DailyMood.allCases.map(\.dotOpacity)
        #expect(Set(opacities).count == DailyMood.allCases.count)
        #expect(opacities == opacities.sorted(by: >))
        #expect(opacities.allSatisfy { $0 > 0 && $0 <= 1 })
    }

    @Test("Premium card only from day 3, never for subscribers, and stays dismissed")
    func premiumNudge() {
        #expect(!PremiumNudgePolicy.shouldShow(checkInDays: 2, hasPremiumAccess: false, showsSubscriptionUI: true, dismissed: false))
        #expect(PremiumNudgePolicy.shouldShow(checkInDays: 3, hasPremiumAccess: false, showsSubscriptionUI: true, dismissed: false))
        #expect(!PremiumNudgePolicy.shouldShow(checkInDays: 9, hasPremiumAccess: true, showsSubscriptionUI: true, dismissed: false))
        #expect(!PremiumNudgePolicy.shouldShow(checkInDays: 9, hasPremiumAccess: false, showsSubscriptionUI: true, dismissed: true))
        #expect(!PremiumNudgePolicy.shouldShow(checkInDays: 9, hasPremiumAccess: false, showsSubscriptionUI: false, dismissed: false))
    }
}

@Suite("Journey v1: paywall routing", .serialized)
@MainActor
struct JourneyPaywallRoutingTests {
    private func makeState() -> (AppState, UserDefaults, String) {
        let suiteName = "JourneyPaywallRoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let state = AppState(
            defaults: defaults,
            launchArguments: [],
            appStoreReceiptURL: URL(fileURLWithPath: "/tmp/receipt"),
            isDebugBuild: true
        )
        state.hasCompletedOnboarding = true
        return (state, defaults, suiteName)
    }

    @Test("Closing a paywall started on Today leaves the user on Today (B1)")
    func closeReturnsToToday() {
        let (state, defaults, suite) = makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        state.selectTab(.today)
        state.requestLogger(.meal, host: .today, source: "today_premium_card")
        #expect(state.showPremiumPaywall)
        #expect(state.selectedTab == .today)
        #expect(state.premiumPaywallReason == .meal)
        #expect(state.premiumPaywallSource == "today_premium_card")
        state.finishPremiumPaywall()
        #expect(state.selectedTab == .today)
        #expect(state.consumePendingLogger(host: .today) == nil)
    }

    @Test("A purchase continues the started logger on the tab it began on (A12)")
    func purchaseResumesOnToday() {
        let (state, defaults, suite) = makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        state.selectTab(.today)
        state.requestLogger(.meal, host: .today)
        #expect(state.deferredLogger == .meal)
        state.isPremium = true
        state.finishPremiumPaywall()
        #expect(state.selectedTab == .today)
        #expect(state.consumePendingLogger() == nil)
        #expect(state.consumePendingLogger(host: .today) == .meal)
        #expect(state.consumePendingLogger(host: .today) == nil)
    }

    @Test("Free shortcuts on Today open in place without a tab jump")
    func freeShortcutStaysOnToday() {
        let (state, defaults, suite) = makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        state.selectTab(.today)
        state.requestLogger(.period, host: .today)
        #expect(!state.showPremiumPaywall)
        #expect(state.selectedTab == .today)
        #expect(state.consumePendingLogger(host: .today) == .period)
    }

    @Test("No path shows a subscriber the paywall (B2)")
    func subscribersNeverSeePaywall() {
        let (state, defaults, suite) = makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        state.isPremium = true
        state.presentPremiumPaywall(reason: .settings, source: "settings")
        #expect(!state.showPremiumPaywall)
        state.requestLogger(.meal, host: .today)
        #expect(!state.showPremiumPaywall)
    }

    @Test("Each Premium logger maps to its contextual headline")
    func reasonsPerLogger() {
        #expect(PremiumPaywallReason.forLogger(.meal) == .meal)
        #expect(PremiumPaywallReason.forLogger(.bloodSugar) == .glucose)
        #expect(PremiumPaywallReason.forLogger(.supplements) == .supplements)
        #expect(PremiumPaywallReason.forLogger(.photo) == .photo)
    }
}

@Suite("Journey v1: plan text")
@MainActor // SubscriptionManager product IDs are main-actor isolated in the app module.
struct JourneyPlanTextTests {
    @Test("Single-unit periods read '/month' and '/year'; analytics plan names are generic")
    func perPeriodText() {
        let monthly = BillingProduct(
            id: SubscriptionManager.monthlyProductID,
            displayName: "CycleBalance Premium Monthly",
            displayPrice: "$9.99",
            price: Decimal(string: "9.99")!,
            subscriptionPeriod: BillingPeriod(unit: .month, value: 1)
        )
        let yearly = BillingProduct(
            id: SubscriptionManager.yearlyProductID,
            displayName: "CycleBalance Premium Yearly",
            displayPrice: "$79.99",
            price: Decimal(string: "79.99")!,
            subscriptionPeriod: BillingPeriod(unit: .year, value: 1),
            localizedPricePerMonth: "$6.66"
        )
        #expect(monthly.displayPricePerPeriod(language: .en) == "$9.99/month")
        #expect(yearly.displayPricePerPeriod(language: .en) == "$79.99/year")
        #expect(yearly.planTitle(language: .en) == "Yearly")
        #expect(monthly.analyticsPlanName == "monthly")
        #expect(yearly.analyticsPlanName == "yearly")
    }
}

@Suite("Journey v1: privacy-preserving analytics", .serialized)
@MainActor
struct JourneyAnalyticsTests {
    final class RecordingSink: AnalyticsSink {
        var events: [(name: String, properties: [String: String])] = []
        func send(_ name: String, properties: [String: String]) {
            events.append((name, properties))
        }
    }

    /// Only UI facts may leave the device: step IDs, counts, booleans, durations, sources and
    /// product identifiers. Never symptom, cycle, mood, food or Health values.
    private let allowedKeys: Set<String> = [
        "step_id", "index", "skipped", "answered", "areas_count", "duration_s", "restored_from_backup",
        "type", "granted", "categories_count", "completed", "source", "feature", "count", "placement",
        "plan", "package", "product_id", "offer", "code", "seconds_visible", "attempted_purchase",
        "result", "action",
    ]

    private var sampleEvents: [AnalyticsEvent] {
        [
            .onboardingStarted,
            .onboardingStepViewed(stepID: "A5_first_checkin", index: 3),
            .onboardingStepCompleted(stepID: "A4_focus", skipped: false),
            .onboardingStage(answered: true),
            .onboardingFocus(areaCount: 3),
            .onboardingCompleted(durationSeconds: 75, restoredFromBackup: false),
            .notificationPermission(granted: true),
            .healthConnected(categoryCount: 4, completed: true),
            .firstCheckinSaved(source: .onboarding),
            .checkinSaved(source: .today),
            .limitReached(feature: "pdf_report", count: 1),
            .premiumCardDismissed,
            .paywallViewed(source: "today_premium_card"),
            .planSelected(plan: "yearly"),
            .purchaseStarted(productID: "cyclebalance.premium.annual"),
            .purchaseCompleted(productID: "cyclebalance.premium.annual", offer: .none),
            .purchaseCancelled(productID: "cyclebalance.premium.annual"),
            .purchasePending(productID: "cyclebalance.premium.annual"),
            .purchaseFailed(code: "SKErrorDomain#2"),
            .paywallDismissed(source: "settings", secondsVisible: 12, attemptedPurchase: false),
            .restoreCompleted(result: .nothingToRestore),
            .purchaseResumedAction(action: "meal"),
            .manageSubscriptionOpened,
        ]
    }

    @Test("Event names match the Figma spec cards")
    func eventNames() {
        #expect(AnalyticsEvent.onboardingStarted.name == "onboarding_started")
        #expect(AnalyticsEvent.onboardingFocus(areaCount: 1).name == "onboarding_focus")
        #expect(AnalyticsEvent.firstCheckinSaved(source: .onboarding).name == "first_checkin_saved")
        #expect(AnalyticsEvent.notificationPermission(granted: true).name == "notification_permission")
        #expect(AnalyticsEvent.healthConnected(categoryCount: 1, completed: true).name == "health_connected")
        #expect(AnalyticsEvent.checkinSaved(source: .today).name == "checkin_saved")
        #expect(AnalyticsEvent.paywallViewed(source: "x").name == "paywall_viewed")
        #expect(AnalyticsEvent.planSelected(plan: "yearly").name == "plan_selected")
        #expect(AnalyticsEvent.purchaseCompleted(productID: "p", offer: .none).name == "purchase_completed")
        #expect(AnalyticsEvent.purchaseResumedAction(action: "meal").name == "purchase_resumed_action")
        #expect(AnalyticsEvent.manageSubscriptionOpened.name == "manage_subscription_opened")
    }

    @Test("Event properties carry only UI facts")
    func propertiesAreHealthFree() {
        let healthWords = Set(SymptomType.allCases.map(\.rawValue) + DailyMood.allCases.map(\.rawValue)
            + OnboardingFocusTopic.allCases.map(\.rawValue) + PCOSExperience.allCases.map(\.rawValue))
        for event in sampleEvents {
            #expect(Set(event.properties.keys).isSubset(of: allowedKeys), "\(event.name)")
            for value in event.properties.values {
                #expect(!healthWords.contains(value), "\(event.name) leaks \(value)")
            }
        }
        #expect(AnalyticsEvent.checkinSaved(source: .today).properties == ["source": "today"])
        #expect(AnalyticsEvent.onboardingFocus(areaCount: 2).properties == ["areas_count": "2"])
    }

    @Test("The facade adds app version and the RevenueCat user ID, and once-keys fire once")
    func facadeMergesGlobalsAndDeduplicates() throws {
        let name = "JourneyAnalyticsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let sink = RecordingSink()
        let analytics = AppAnalytics(sinks: [sink], defaults: defaults, appVersion: "1.0.5")
        analytics.distinctID = "$RCAnonymousID:abc"

        analytics.track(.paywallViewed(source: "settings"))
        #expect(sink.events.last?.properties["app_version"] == "1.0.5")
        #expect(sink.events.last?.properties[AppAnalytics.distinctIDKey] == "$RCAnonymousID:abc")
        #expect(sink.events.last?.properties["source"] == "settings")

        analytics.trackOnce(.firstCheckinSaved(source: .today), onceKey: "first")
        analytics.trackOnce(.firstCheckinSaved(source: .today), onceKey: "first")
        #expect(sink.events.filter { $0.name == "first_checkin_saved" }.count == 1)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        analytics.trackOncePerDay(.checkinSaved(source: .today), dailyKey: "daily", now: day, calendar: utc)
        analytics.trackOncePerDay(.checkinSaved(source: .sheet), dailyKey: "daily", now: day.addingTimeInterval(60), calendar: utc)
        analytics.trackOncePerDay(.checkinSaved(source: .today), dailyKey: "daily", now: day.addingTimeInterval(86_400 * 2), calendar: utc)
        #expect(sink.events.filter { $0.name == "checkin_saved" }.count == 2)
    }
}
