import StoreKit
import SwiftData
import SwiftUI

/// Checks engagement conditions and triggers the native App Store review prompt
/// at high-value completion moments. Prompts at most once per install.
///
/// Trigger points:
/// - 7+ day logging streak (after any log save)
/// - First AI-generated insight appears
@MainActor
struct ReviewPromptService {

    private static let promptedKey = "onboarding.hasPromptedForReview"

    /// Call after a successful log save (period, symptom, blood sugar, etc.).
    /// Checks streak length and insight count; if eligible, triggers the native
    /// review prompt after a short delay so save feedback finishes first.
    static func requestReviewIfEligible(
        modelContext: ModelContext,
        requestReview: RequestReviewAction
    ) {
        guard !UserDefaults.standard.bool(forKey: promptedKey) else { return }
        guard isEligible(modelContext: modelContext) else { return }

        UserDefaults.standard.set(true, forKey: promptedKey)

        // Delay so the save-success overlay completes before the system sheet appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            requestReview()
        }
    }

    private static func isEligible(modelContext: ModelContext) -> Bool {
        let streak = StreakService(modelContext: modelContext).currentStreak()
        if streak >= 7 { return true }

        let insightCount = (try? modelContext.fetchCount(FetchDescriptor<Insight>())) ?? 0
        if insightCount >= 1 { return true }

        return false
    }
}
