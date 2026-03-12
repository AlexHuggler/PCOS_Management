import Foundation
import SwiftData

@MainActor
struct SymptomCorrelationInsightAnalyzer {
    let fetcher: InsightDataFetcher

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
        let completedCycles = cycles.filter { $0.lengthDays != nil && !$0.isPredicted }

        if !completedCycles.isEmpty {
            // Map symptoms to approximate cycle phases
            var phaseSymptoms: [CyclePhase: [SymptomEntry]] = [:]
            for phase in CyclePhase.allCases {
                phaseSymptoms[phase] = []
            }

            for symptom in symptoms {
                if let phase = approximatePhase(for: symptom.date, cycles: completedCycles) {
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
                    title: "Symptoms peak during \(worst.0.displayName) phase",
                    content: "Your most intense symptoms occur during the \(worst.0.displayName.lowercased()) "
                        + "phase, with an average severity of \(String(format: "%.1f", worst.1))/5. "
                        + "Common symptoms in this phase: \(topTypes.joined(separator: ", ")).",
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
                    title: "\(topPair.key) often appear together",
                    content: "These symptoms co-occur on \(percentage)% of your tracked days "
                        + "(\(topPair.value) out of \(totalDays) days). Understanding symptom clusters "
                        + "can help you and your provider target treatments more effectively.",
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
                    let direction = diff > 0 ? "increasing" : "decreasing"
                    let sentiment = diff > 0 ? "worsening" : "improving"
                    let confidence = min(0.3 + abs(diff) * 0.15, 0.70)

                    let trendInsight = Insight(
                        insightType: .symptomCorrelation,
                        title: "Symptom severity is \(direction)",
                        content: "Your average symptom severity has been \(sentiment) recently "
                            + "(from \(String(format: "%.1f", firstAvg)) to \(String(format: "%.1f", secondAvg)) "
                            + "out of 5). \(diff > 0 ? "Consider reviewing recent changes to your routine." : "Keep up what you're doing!")",
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

    /// Approximate cycle phase for a given date based on completed cycles.
    private func approximatePhase(for date: Date, cycles: [Cycle]) -> CyclePhase? {
        let calendar = Calendar.current

        // Find which cycle this date falls in.
        for cycle in cycles {
            guard let lengthDays = cycle.lengthDays else { continue }
            let cycleStart = calendar.startOfDay(for: cycle.startDate)
            guard let cycleEnd = calendar.date(byAdding: .day, value: lengthDays, to: cycleStart) else { continue }

            let dateStart = calendar.startOfDay(for: date)
            guard dateStart >= cycleStart, dateStart < cycleEnd else { continue }

            let dayInCycle = calendar.dateComponents([.day], from: cycleStart, to: dateStart).day ?? 0

            // Approximate phase based on typical distribution
            // Menstrual: days 1-5, Follicular: days 6-13, Ovulatory: days 14-16, Luteal: rest
            if dayInCycle < 5 {
                return .menstrual
            } else if dayInCycle < 13 {
                return .follicular
            } else if dayInCycle < 16 {
                return .ovulatory
            } else {
                return .luteal
            }
        }

        return nil
    }
}
