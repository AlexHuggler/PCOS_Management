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
        let calendar = Calendar.current
        let now = Date()

        // Delete insights older than expiration threshold.
        let expirationDate = calendar.date(byAdding: .day, value: -insightExpirationDays, to: now) ?? now
        for existing in existingInsights where existing.generatedDate < expirationDate {
            modelContext.delete(existing)
        }

        // Filter new insights against recent existing ones (same type within window with similar title).
        let deduplicationCutoff = calendar.date(
            byAdding: .day,
            value: -deduplicationWindowDays,
            to: now
        ) ?? now

        let recentExisting = existingInsights.filter { $0.generatedDate >= deduplicationCutoff }

        var deduplicated: [Insight] = []
        for newInsight in newInsights {
            let isDuplicate = recentExisting.contains { existing in
                existing.insightType == newInsight.insightType
                    && titlesAreSimilar(existing.title, newInsight.title)
            }
            if !isDuplicate {
                deduplicated.append(newInsight)
            }
        }

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
