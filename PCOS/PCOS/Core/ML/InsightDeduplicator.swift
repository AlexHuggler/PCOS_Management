import Foundation
import SwiftData

@MainActor
struct InsightDeduplicator {
    let modelContext: ModelContext
    let deduplicationWindowDays: Int
    let insightExpirationDays: Int

    /// Removes duplicate insights (same type within 7 days with similar title)
    /// and deletes insights older than 90 days.
    func deduplicateAndClean(newInsights: [Insight], existingInsights: [Insight]) -> [Insight] {
        // Each successful run is a complete snapshot. Retract conclusions when their
        // sources disappear or change, even when the replacement has the same title.
        for existing in existingInsights {
            modelContext.delete(existing)
        }
        let deduplicated = newInsights

        // Also deduplicate within the new batch itself.
        var finalInsights: [Insight] = []
        for insight in deduplicated {
            let alreadyAdded = finalInsights.contains { added in
                added.insightType == insight.insightType
                    && titlesAreSimilar(added.title, insight.title)
            }
            if !alreadyAdded {
                finalInsights.append(insight)
            }
        }

        return finalInsights
    }

    /// Check if two insight titles are similar enough to be considered duplicates.
    private func titlesAreSimilar(_ a: String, _ b: String) -> Bool {
        let normalizedA = a.lowercased().trimmingCharacters(in: .whitespaces)
        let normalizedB = b.lowercased().trimmingCharacters(in: .whitespaces)

        if normalizedA == normalizedB { return true }

        // Check if one title starts with the same significant prefix.
        let wordsA = normalizedA.split(separator: " ")
        let wordsB = normalizedB.split(separator: " ")
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return false }

        // If the first 3 significant words match, consider similar.
        let significantA = Array(wordsA.filter { $0.count > 2 }.prefix(3))
        let significantB = Array(wordsB.filter { $0.count > 2 }.prefix(3))

        guard !significantA.isEmpty, !significantB.isEmpty else { return false }
        let matchCount = significantA.filter { significantB.contains($0) }.count
        return matchCount >= min(significantA.count, significantB.count)
    }
}
