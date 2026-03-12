import Foundation
import SwiftData

@MainActor
struct DietImpactInsightAnalyzer {
    let fetcher: InsightDataFetcher

    /// Analyzes glycemic impact distribution and its relationship to symptom severity.
    /// Requires at least 7 days of meal data.
    func analyze() throws -> [Insight] {
        let mealDescriptor = FetchDescriptor<MealEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let meals: [MealEntry] = try fetcher.fetch(mealDescriptor, stage: .dietImpact)

        guard meals.count >= 7 else { return [] }

        let calendar = Calendar.current
        let mealDays = Set(meals.map { calendar.startOfDay(for: $0.timestamp) })
        guard mealDays.count >= 7 else { return [] }

        var insights: [Insight] = []

        // GI distribution analysis
        let giCounts: [GlycemicImpact: Int] = Dictionary(
            grouping: meals,
            by: \.glycemicImpact
        ).mapValues(\.count)

        let totalMeals = meals.count
        let highGICount = giCounts[.high] ?? 0
        let lowGICount = giCounts[.low] ?? 0
        let highGIRatio = Double(highGICount) / Double(totalMeals)
        let lowGIRatio = Double(lowGICount) / Double(totalMeals)

        // Compare GI impact to next-day symptom severity
        let earliestMeal = meals.first?.timestamp ?? Date()
        let symptomDescriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { $0.date >= earliestMeal },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let symptoms: [SymptomEntry] = try fetcher.fetch(symptomDescriptor, stage: .dietImpactSymptoms)
        let symptomsByDay = Dictionary(grouping: symptoms) { calendar.startOfDay(for: $0.date) }

        // Group meals by day and calculate daily predominant GI
        let mealsByDay = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.timestamp) }
        var highGIDaySeverities: [Double] = []
        var lowGIDaySeverities: [Double] = []

        for (day, dayMeals) in mealsByDay {
            let dayHighCount = dayMeals.filter { $0.glycemicImpact == .high }.count
            let dayLowCount = dayMeals.filter { $0.glycemicImpact == .low }.count

            // Check next day's symptom severity
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
                  let nextDaySymptoms = symptomsByDay[nextDay],
                  !nextDaySymptoms.isEmpty else { continue }

            let nextDayAvgSeverity = Double(nextDaySymptoms.map(\.severity).reduce(0, +))
                / Double(nextDaySymptoms.count)

            if dayHighCount > dayLowCount {
                highGIDaySeverities.append(nextDayAvgSeverity)
            } else if dayLowCount > dayHighCount {
                lowGIDaySeverities.append(nextDayAvgSeverity)
            }
        }

        // Generate diet-symptom correlation insight
        if highGIDaySeverities.count >= 3, lowGIDaySeverities.count >= 3 {
            let highGIAvg = highGIDaySeverities.reduce(0, +) / Double(highGIDaySeverities.count)
            let lowGIAvg = lowGIDaySeverities.reduce(0, +) / Double(lowGIDaySeverities.count)
            let diff = highGIAvg - lowGIAvg

            if diff > 0.5 {
                let confidence = min(0.35 + Double(highGIDaySeverities.count + lowGIDaySeverities.count) * 0.02, 0.75)
                let insight = Insight(
                    insightType: .dietImpact,
                    title: "High-GI meals may worsen symptoms",
                    content: "Days following high-GI meals show an average symptom severity of "
                        + "\(String(format: "%.1f", highGIAvg))/5, compared to \(String(format: "%.1f", lowGIAvg))/5 "
                        + "after low-GI meals. Consider swapping some high-GI foods for lower-GI alternatives.",
                    confidence: confidence,
                    dataPointsUsed: totalMeals,
                    actionable: true
                )
                insights.append(insight)
            }
        }

        // GI balance insight
        if highGIRatio > 0.4 {
            let confidence = min(0.35 + Double(totalMeals) * 0.01, 0.70)
            let insight = Insight(
                insightType: .dietImpact,
                title: "Many of your meals are high-GI",
                content: "\(Int(highGIRatio * 100))% of your logged meals are high glycemic impact. "
                    + "For PCOS management, aiming for more low-GI meals may help with insulin "
                    + "sensitivity and symptom management.",
                confidence: confidence,
                dataPointsUsed: totalMeals,
                actionable: true
            )
            insights.append(insight)
        } else if lowGIRatio > 0.6 {
            let confidence = min(0.4 + Double(totalMeals) * 0.01, 0.75)
            let insight = Insight(
                insightType: .dietImpact,
                title: "Your diet is mostly low-GI",
                content: "\(Int(lowGIRatio * 100))% of your logged meals are low glycemic impact. "
                    + "This is great for PCOS management and insulin sensitivity. Keep it up!",
                confidence: confidence,
                dataPointsUsed: totalMeals,
                actionable: false
            )
            insights.append(insight)
        }

        return insights
    }
}
