import Foundation
import os
#if canImport(TelemetryDeck)
import TelemetryDeck
#endif

// MARK: - Events

/// Where a daily check-in was saved. UI location only — never what was recorded.
enum CheckInSource: String, Sendable {
    case onboarding
    case today
    case sheet
}

/// Which offer a completed purchase used.
enum PurchaseOfferKind: String, Sendable {
    case none
    case intro
    case exitOffer = "exit_offer"
}

enum RestoreOutcome: String, Sendable {
    case restored
    case nothingToRestore = "nothing_to_restore"
    case failed
}

/// Privacy-preserving funnel events (docs: apps/_shared/ANALYTICS_SCHEMA.md and the Figma spec cards).
///
/// HEALTH DATA RULE: properties may only contain UI step identifiers, counts, booleans,
/// durations and App Store product identifiers. Never add symptom, cycle, mood, food,
/// Apple Health values, diagnosis status or chosen health topics. The associated values
/// below are deliberately typed so that free-form health text cannot be passed in.
enum AnalyticsEvent: Equatable, Sendable {
    // Onboarding (A2–A7)
    case onboardingStarted
    case onboardingStepViewed(stepID: String, index: Int)
    case onboardingStepCompleted(stepID: String, skipped: Bool)
    /// A3. Only whether a stage was chosen — the stage itself is diagnosis information.
    case onboardingStage(answered: Bool)
    /// A4. Only how many areas were chosen — the areas themselves are health topics.
    case onboardingFocus(areaCount: Int)
    case onboardingCompleted(durationSeconds: Int, restoredFromBackup: Bool)
    /// A6.
    case notificationPermission(granted: Bool)
    /// A7. Count of requested read categories, and whether the system sheet finished.
    case healthConnected(categoryCount: Int, completed: Bool)

    // Activation and engagement
    case firstCheckinSaved(source: CheckInSource)
    case checkinSaved(source: CheckInSource)
    case limitReached(feature: String, count: Int)
    case premiumCardDismissed

    // Monetization
    case paywallViewed(source: String)
    case planSelected(plan: String)
    case purchaseStarted(productID: String)
    case purchaseCompleted(productID: String, offer: PurchaseOfferKind)
    case purchaseCancelled(productID: String)
    case purchasePending(productID: String)
    case purchaseFailed(code: String)
    case paywallDismissed(source: String, secondsVisible: Int, attemptedPurchase: Bool)
    case restoreCompleted(result: RestoreOutcome)
    case purchaseResumedAction(action: String)
    case manageSubscriptionOpened
    case exitOfferViewed(source: String, discountPercent: Int)
    case exitOfferDismissed(secondsVisible: Int, attemptedPurchase: Bool)

    var name: String {
        switch self {
        case .onboardingStarted: "onboarding_started"
        case .onboardingStepViewed: "onboarding_step_viewed"
        case .onboardingStepCompleted: "onboarding_step_completed"
        case .onboardingStage: "onboarding_stage"
        case .onboardingFocus: "onboarding_focus"
        case .onboardingCompleted: "onboarding_completed"
        case .notificationPermission: "notification_permission"
        case .healthConnected: "health_connected"
        case .firstCheckinSaved: "first_checkin_saved"
        case .checkinSaved: "checkin_saved"
        case .limitReached: "limit_reached"
        case .premiumCardDismissed: "premium_card_dismissed"
        case .paywallViewed: "paywall_viewed"
        case .planSelected: "plan_selected"
        case .purchaseStarted: "purchase_started"
        case .purchaseCompleted: "purchase_completed"
        case .purchaseCancelled: "purchase_cancelled"
        case .purchasePending: "purchase_pending"
        case .purchaseFailed: "purchase_failed"
        case .paywallDismissed: "paywall_dismissed"
        case .restoreCompleted: "restore_completed"
        case .purchaseResumedAction: "purchase_resumed_action"
        case .manageSubscriptionOpened: "manage_subscription_opened"
        case .exitOfferViewed: "exit_offer_viewed"
        case .exitOfferDismissed: "exit_offer_dismissed"
        }
    }

    var properties: [String: String] {
        switch self {
        case .onboardingStarted, .premiumCardDismissed, .manageSubscriptionOpened:
            [:]
        case let .onboardingStepViewed(stepID, index):
            ["step_id": stepID, "index": String(index)]
        case let .onboardingStepCompleted(stepID, skipped):
            ["step_id": stepID, "skipped": String(skipped)]
        case let .onboardingStage(answered):
            ["answered": String(answered)]
        case let .onboardingFocus(areaCount):
            ["areas_count": String(areaCount)]
        case let .onboardingCompleted(durationSeconds, restoredFromBackup):
            ["duration_s": String(durationSeconds), "restored_from_backup": String(restoredFromBackup)]
        case let .notificationPermission(granted):
            ["type": "notifications", "granted": String(granted)]
        case let .healthConnected(categoryCount, completed):
            ["type": "health", "categories_count": String(categoryCount), "completed": String(completed)]
        case let .firstCheckinSaved(source), let .checkinSaved(source):
            ["source": source.rawValue]
        case let .limitReached(feature, count):
            ["feature": feature, "count": String(count)]
        case let .paywallViewed(source):
            ["source": source, "placement": source]
        case let .planSelected(plan):
            ["plan": plan, "package": plan]
        case let .purchaseStarted(productID), let .purchaseCancelled(productID), let .purchasePending(productID):
            ["product_id": productID]
        case let .purchaseCompleted(productID, offer):
            ["product_id": productID, "offer": offer.rawValue]
        case let .purchaseFailed(code):
            ["code": code]
        case let .paywallDismissed(source, secondsVisible, attemptedPurchase):
            ["source": source, "seconds_visible": String(secondsVisible), "attempted_purchase": String(attemptedPurchase)]
        case let .restoreCompleted(result):
            ["result": result.rawValue]
        case let .purchaseResumedAction(action):
            ["action": action]
        case let .exitOfferViewed(source, discountPercent):
            ["source": source, "discount_pct": String(discountPercent)]
        case let .exitOfferDismissed(secondsVisible, attemptedPurchase):
            ["seconds_visible": String(secondsVisible), "attempted_purchase": String(attemptedPurchase)]
        }
    }
}

// MARK: - Sinks

@MainActor
protocol AnalyticsSink: AnyObject {
    func send(_ name: String, properties: [String: String])
}

/// DEBUG-only sink: writes events to the unified log so funnels can be checked in Console. No network.
@MainActor
final class OSLogAnalyticsSink: AnalyticsSink {
    private let logger = Logger(subsystem: "com.cyclebalance.app", category: "analytics")

    func send(_ name: String, properties: [String: String]) {
        let description = properties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        logger.debug("analytics \(name, privacy: .public) \(description, privacy: .public)")
    }
}

#if canImport(TelemetryDeck)
/// TelemetryDeck sink. Only compiled once the TelemetryDeck package is added, and only created
/// when Info.plist contains a non-empty `TelemetryDeckAppID`. UI-step signals only; no session replay.
@MainActor
final class TelemetryDeckAnalyticsSink: AnalyticsSink {
    static let appIDInfoPlistKey = "TelemetryDeckAppID"

    static func makeFromInfoPlist(bundle: Bundle = .main) -> TelemetryDeckAnalyticsSink? {
        guard let appID = BillingConfiguration.sanitized(bundle.object(forInfoDictionaryKey: appIDInfoPlistKey) as? String) else {
            return nil
        }
        TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: appID))
        return TelemetryDeckAnalyticsSink()
    }

    func send(_ name: String, properties: [String: String]) {
        var parameters = properties
        let userID = parameters.removeValue(forKey: AppAnalytics.distinctIDKey)
        TelemetryDeck.signal(name, parameters: parameters, customUserID: userID)
    }
}
#endif

// MARK: - Facade

/// Single entry point for funnel events. The SDK sink is added later behind `canImport`;
/// until then Release builds send nothing and Debug builds only log locally.
@MainActor
final class AppAnalytics {
    static let shared = AppAnalytics()
    static let distinctIDKey = "rc_app_user_id"

    private let sinks: [any AnalyticsSink]
    private let defaults: UserDefaults
    private let appVersion: String?

    /// RevenueCat app user ID (anonymous), used as the distinct ID so behaviour joins to revenue.
    var distinctID: String?

    init(
        sinks: [any AnalyticsSink]? = nil,
        defaults: UserDefaults = .standard,
        appVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) {
        self.sinks = sinks ?? Self.makeDefaultSinks()
        self.defaults = defaults
        self.appVersion = appVersion
    }

    func track(_ event: AnalyticsEvent) {
        guard !sinks.isEmpty else { return }
        let properties = Self.mergedProperties(for: event, appVersion: appVersion, distinctID: distinctID)
        for sink in sinks {
            sink.send(event.name, properties: properties)
        }
    }

    /// Sends `event` only the first time `onceKey` is used on this device.
    func trackOnce(_ event: AnalyticsEvent, onceKey: String) {
        let key = "analytics.once.\(onceKey)"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        track(event)
    }

    /// Sends `event` at most once per calendar day for `dailyKey`.
    func trackOncePerDay(_ event: AnalyticsEvent, dailyKey: String, now: Date = Date(), calendar: Calendar = .current) {
        let key = "analytics.daily.\(dailyKey)"
        let today = calendar.startOfDay(for: now).timeIntervalSinceReferenceDate
        if let last = defaults.object(forKey: key) as? Double, last == today { return }
        defaults.set(today, forKey: key)
        track(event)
    }

    static func mergedProperties(for event: AnalyticsEvent, appVersion: String?, distinctID: String?) -> [String: String] {
        var properties: [String: String] = [:]
        if let appVersion, !appVersion.isEmpty { properties["app_version"] = appVersion }
        if let distinctID, !distinctID.isEmpty { properties[distinctIDKey] = distinctID }
        properties.merge(event.properties) { _, eventValue in eventValue }
        return properties
    }

    private static func makeDefaultSinks() -> [any AnalyticsSink] {
        var sinks: [any AnalyticsSink] = []
#if DEBUG
        sinks.append(OSLogAnalyticsSink())
#endif
#if canImport(TelemetryDeck)
        if let telemetryDeck = TelemetryDeckAnalyticsSink.makeFromInfoPlist() {
            sinks.append(telemetryDeck)
        }
#endif
        return sinks
    }
}
