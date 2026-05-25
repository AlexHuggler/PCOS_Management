import Foundation
import SwiftData

@MainActor
struct SymptomCorrelationInsightAnalyzer {
    let fetcher: InsightDataFetcher
    private let phaseInferencePolicy = CyclePhaseInferencePolicy()

    /// Analyzes symptom patterns across cycle phases, severity trends, and co-occurrences.
    /// Requires at least 14 days of symptom data.
    func analyze() throws -> [Insight] {
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let symptomDescriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { $0.date >= fourteenDaysAgo },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let symptoms: [SymptomEntry] = try fetcher.fetch(symptomDescriptor, stage: .symptomCorrelations)

        guard symptoms.count >= 5 else { return [] }

        // Check that symptoms span at least 14 distinct days
        let calendar = Calendar.current
        let distinctDays = Set(symptoms.map { calendar.startOfDay(for: $0.date) })
        guard distinctDays.count >= 14 else { return [] }

        var insights: [Insight] = []

        // --- Phase-based symptom analysis ---
        let cycleDescriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        let cycles: [Cycle] = try fetcher.fetch(cycleDescriptor, stage: .symptomCorrelationCycles)
        let completedCycles = cycles.filter { !$0.isPredicted && ($0.manualCycleLengthOverrideDays != nil || $0.lengthDays != nil) }

        if !completedCycles.isEmpty {
            // Map symptoms to approximate cycle phases
            var phaseSymptoms: [CyclePhase: [SymptomEntry]] = [:]
            for phase in CyclePhase.allCases {
                phaseSymptoms[phase] = []
            }

            for symptom in symptoms {
                if let phase = phaseInferencePolicy.approximatePhase(
                    for: symptom.date,
                    cycles: completedCycles,
                    calendar: calendar
                ) {
                    phaseSymptoms[phase, default: []].append(symptom)
                }
            }

            // Find the phase with the highest average severity
            var phaseAverages: [(CyclePhase, Double, Int)] = []
            for (phase, entries) in phaseSymptoms where !entries.isEmpty {
                let avgSeverity = Double(entries.map(\.severity).reduce(0, +)) / Double(entries.count)
                phaseAverages.append((phase, avgSeverity, entries.count))
            }

            if let worst = phaseAverages.max(by: { $0.1 < $1.1 }), worst.1 >= 2.5, worst.2 >= 3 {
                // Find top symptom types in the worst phase
                let worstPhaseSymptoms = phaseSymptoms[worst.0] ?? []
                let typeCounts = Dictionary(grouping: worstPhaseSymptoms, by: \.symptomType)
                let topTypes = typeCounts
                    .sorted { $0.value.count > $1.value.count }
                    .prefix(3)
                    .map { $0.key.displayName }

                let confidence = min(0.35 + Double(worst.2) * 0.03, 0.80)
                let phaseInsight = Insight(
                    insightType: .symptomCorrelation,
                    title: L10n.format(
                        "Symptoms peak during %@ phase",
                        defaultValue: "Symptoms peak during %@ phase",
                        worst.0.displayName
                    ),
                    content: L10n.format(
                        "Your symptoms tend to be strongest during your %@ phase — especially %@. Knowing this pattern means you can plan gentler days or extra self-care during that time.",
                        defaultValue: "Your symptoms tend to be strongest during your %@ phase — especially %@. Knowing this pattern means you can plan gentler days or extra self-care during that time.",
                        worst.0.displayName,
                        topTypes.joined(separator: ", ")
                    ),
                    scientificContent: L10n.format(
                        "Your most intense symptoms occur during the %@ phase, with an average severity of %@/5. Common symptoms in this phase: %@.",
                        defaultValue: "Your most intense symptoms occur during the %@ phase, with an average severity of %@/5. Common symptoms in this phase: %@.",
                        worst.0.displayName,
                        L10n.decimal(worst.1),
                        topTypes.joined(separator: ", ")
                    ),
                    confidence: confidence,
                    dataPointsUsed: symptoms.count,
                    actionable: true,
                    relatedSymptoms: topTypes
                )
                insights.append(phaseInsight)
            }
        }

        // --- Co-occurring symptoms (same day) ---
        let byDay = Dictionary(grouping: symptoms) { calendar.startOfDay(for: $0.date) }
        var pairCounts: [String: Int] = [:]
        for (_, daySymptoms) in byDay {
            let types = Array(Set(daySymptoms.map(\.symptomType))).sorted { $0.rawValue < $1.rawValue }
            guard types.count >= 2 else { continue }
            for i in 0..<types.count {
                for j in (i + 1)..<types.count {
                    let key = "\(types[i].displayName) & \(types[j].displayName)"
                    pairCounts[key, default: 0] += 1
                }
            }
        }

        let totalDays = byDay.count
        if let topPair = pairCounts.max(by: { $0.value < $1.value }),
           topPair.value >= 3,
           totalDays > 0 {
            let coOccurrenceRate = Double(topPair.value) / Double(totalDays)
            if coOccurrenceRate >= 0.3 {
                let percentage = Int(coOccurrenceRate * 100)
                let confidence = min(0.35 + coOccurrenceRate * 0.4, 0.80)
                let pairInsight = Insight(
                    insightType: .symptomCorrelation,
                    title: L10n.format(
                        "%@ often appear together",
                        defaultValue: "%@ often appear together",
                        topPair.key
                    ),
                    content: L10n.string(
                        "These two symptoms seem to travel together — they show up on the same days quite often. Mentioning this to your provider could help find treatments that address both.",
                        defaultValue: "These two symptoms seem to travel together — they show up on the same days quite often. Mentioning this to your provider could help find treatments that address both."
                    ),
                    scientificContent: L10n.format(
                        "These symptoms appeared together on %lld%% of your tracked days. Understanding which symptoms cluster can help you and your provider target treatments.",
                        defaultValue: "These symptoms appeared together on %lld%% of your tracked days. Understanding which symptoms cluster can help you and your provider target treatments.",
                        percentage
                    ),
                    confidence: confidence,
                    dataPointsUsed: symptoms.count,
                    actionable: true,
                    relatedSymptoms: topPair.key.components(separatedBy: " & ")
                )
                insights.append(pairInsight)
            }
        }

        // --- Severity trend (improving/worsening) ---
        if distinctDays.count >= 14 {
            let sortedDays = distinctDays.sorted()
            let midpoint = sortedDays.count / 2
            let firstHalfDays = Set(sortedDays.prefix(midpoint))
            let secondHalfDays = Set(sortedDays.suffix(from: midpoint))

            let firstHalf = symptoms.filter { firstHalfDays.contains(calendar.startOfDay(for: $0.date)) }
            let secondHalf = symptoms.filter { secondHalfDays.contains(calendar.startOfDay(for: $0.date)) }

            if !firstHalf.isEmpty && !secondHalf.isEmpty {
                let firstAvg = Double(firstHalf.map(\.severity).reduce(0, +)) / Double(firstHalf.count)
                let secondAvg = Double(secondHalf.map(\.severity).reduce(0, +)) / Double(secondHalf.count)
                let diff = secondAvg - firstAvg

                if abs(diff) >= 0.5 {
                    let confidence = min(0.3 + abs(diff) * 0.15, 0.70)

                    let friendlyTrendContent = diff > 0
                        ? L10n.string(
                            "Your symptoms have been trending a bit harder recently. It might help to think about what's changed — sleep, stress, diet, or activity — and see if something stands out.",
                            defaultValue: "Your symptoms have been trending a bit harder recently. It might help to think about what's changed — sleep, stress, diet, or activity — and see if something stands out."
                        )
                        : L10n.string(
                            "Your symptoms have been easing up recently — whatever you've been doing seems to be working. Keep going!",
                            defaultValue: "Your symptoms have been easing up recently — whatever you've been doing seems to be working. Keep going!"
                        )

                    let trendInsight = Insight(
                        insightType: .symptomCorrelation,
                        title: L10n.string(
                            diff > 0
                                ? "Symptom severity is increasing"
                                : "Symptom severity is decreasing",
                            defaultValue: diff > 0
                                ? "Symptom severity is increasing"
                                : "Symptom severity is decreasing"
                        ),
                        content: friendlyTrendContent,
                        scientificContent: L10n.format(
                            diff > 0
                                ? "Your average symptom severity has been worsening recently (from %@ to %@ out of 5). Consider reviewing recent changes to your routine."
                                : "Your average symptom severity has been improving recently (from %@ to %@ out of 5). Keep up what you're doing!",
                            defaultValue: diff > 0
                                ? "Your average symptom severity has been worsening recently (from %@ to %@ out of 5). Consider reviewing recent changes to your routine."
                                : "Your average symptom severity has been improving recently (from %@ to %@ out of 5). Keep up what you're doing!",
                            L10n.decimal(firstAvg),
                            L10n.decimal(secondAvg)
                        ),
                        confidence: confidence,
                        dataPointsUsed: symptoms.count,
                        actionable: diff > 0
                    )
                    insights.append(trendInsight)
                }
            }
        }

        return insights
    }
}
