import StoreKit
import SwiftData
import SwiftUI

enum ReviewPromptMoment {
    case logSaved
    case firstInsight
    case reportGenerated
    case photoProgressSaved
}

/// Checks engagement conditions and triggers the native App Store review prompt
/// at high-value completion moments. Prompts at most once per install.
///
/// Trigger points:
/// - 7+ day logging streak (after any log save)
/// - First AI-generated insight appears
@MainActor
struct ReviewPromptService {

    static let promptedDefaultsKey = "onboarding.hasPromptedForReview"

    /// Call after a successful log save (period, symptom, blood sugar, etc.).
    /// Checks streak length and insight count; if eligible, triggers the native
    /// review prompt after a short delay so save feedback finishes first.
    @discardableResult
    static func requestReviewIfEligible(
        modelContext: ModelContext,
        moment: ReviewPromptMoment = .logSaved,
        requestReview: RequestReviewAction
    ) -> Bool {
        requestReviewIfEligible(
            modelContext: modelContext,
            moment: moment,
            defaults: .standard,
            delay: 1.5
        ) {
            requestReview()
        }
    }

    @discardableResult
    static func requestReviewIfEligible(
        modelContext: ModelContext,
        moment: ReviewPromptMoment,
        defaults: UserDefaults,
        delay: TimeInterval,
        requestReview: @escaping () -> Void
    ) -> Bool {
        guard !defaults.bool(forKey: promptedDefaultsKey) else { return false }
        guard isEligible(modelContext: modelContext, moment: moment) else { return false }

        defaults.set(true, forKey: promptedDefaultsKey)

        guard delay > 0 else {
            requestReview()
            return true
        }

        // Delay so the save-success overlay completes before the system sheet appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            requestReview()
        }

        return true
    }

    private static func isEligible(
        modelContext: ModelContext,
        moment: ReviewPromptMoment
    ) -> Bool {
        switch moment {
        case .logSaved:
            StreakService(modelContext: modelContext).currentStreak() >= 7
        case .firstInsight:
            insightCount(in: modelContext) >= 1
        case .reportGenerated, .photoProgressSaved:
            true
        }
    }

    private static func insightCount(in modelContext: ModelContext) -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<Insight>())) ?? 0
    }
}
