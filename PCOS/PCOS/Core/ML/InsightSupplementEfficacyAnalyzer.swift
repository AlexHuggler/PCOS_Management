import Foundation
import SwiftData

@MainActor
struct SupplementEfficacyInsightAnalyzer {
    let fetcher: InsightDataFetcher

    /// Emits quantitative-only supplement efficacy insights:
    /// 1) symptom severity deltas on taken vs missed days
    /// 2) cycle length deltas in >80% adherence cycles vs lower-adherence cycles
    func analyze() throws -> [Insight] {
        let supplementDescriptor = FetchDescriptor<SupplementLog>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let supplements: [SupplementLog] = try fetcher.fetch(supplementDescriptor, stage: .supplementEfficacy)

        guard supplements.count >= 14 else { return [] }

        let calendar = Calendar.current
        let earliestSupplement = supplements.first?.date ?? Date()
        let symptomDescriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate<SymptomEntry> { $0.date >= earliestSupplement },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let symptoms: [SymptomEntry] = try fetcher.fetch(
            symptomDescriptor,
            stage: .supplementEfficacySymptoms
        )

        let cycleDescriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        let cycles: [Cycle] = try fetcher.fetch(
            cycleDescriptor,
            stage: .supplementEfficacyCycles
        )

        var insights: [Insight] = []

        let completedCycles = cycles.compactMap { cycle -> CompletedSupplementCycle? in
            guard !cycle.isPredicted,
                  let cycleLength = cycle.manualCycleLengthOverrideDays ?? cycle.lengthDays,
                  cycleLength > 0
            else {
                return nil
            }

            let startDate = calendar.startOfDay(for: cycle.startDate)
            let endDate = cycle.endDate
                .map { calendar.startOfDay(for: $0) }
                ?? calendar.date(byAdding: .day, value: cycleLength, to: startDate)

            guard let endDate else { return nil }

            return CompletedSupplementCycle(
                startDate: startDate,
                endDate: endDate,
                lengthDays: cycleLength
            )
        }

        let byName = Dictionary(grouping: supplements, by: \.supplementName)
        let symptomsByDay = Dictionary(grouping: symptoms) { calendar.startOfDay(for: $0.date) }

        for (name, logs) in byName {
            let takenDays = Set(logs.filter(\.taken).map { calendar.startOfDay(for: $0.date) })
            let missedDays = Set(logs.filter { !$0.taken }.map { calendar.startOfDay(for: $0.date) })

            if !symptoms.isEmpty, takenDays.count >= 6, missedDays.count >= 4 {
                let takenSeverities = takenDays.compactMap { day -> Double? in
                    guard let daySymptoms = symptomsByDay[day], !daySymptoms.isEmpty else { return nil }
                    return Double(daySymptoms.map(\.severity).reduce(0, +)) / Double(daySymptoms.count)
                }
                let missedSeverities = missedDays.compactMap { day -> Double? in
                    guard let daySymptoms = symptomsByDay[day], !daySymptoms.isEmpty else { return nil }
                    return Double(daySymptoms.map(\.severity).reduce(0, +)) / Double(daySymptoms.count)
                }

                if takenSeverities.count >= 4, missedSeverities.count >= 4 {
                    let takenAvg = takenSeverities.reduce(0, +) / Double(takenSeverities.count)
                    let missedAvg = missedSeverities.reduce(0, +) / Double(missedSeverities.count)
                    let delta = missedAvg - takenAvg

                    if abs(delta) >= 0.4 {
                        let confidence = min(
                            0.88,
                            max(
                                0.45,
                                0.50
                                    + (Double(min(takenSeverities.count, missedSeverities.count)) * 0.03)
                                    + (abs(delta) * 0.06)
                            )
                        )

                        let directionalText = delta > 0
                            ? L10n.string("lower", defaultValue: "lower")
                            : L10n.string("higher", defaultValue: "higher")

                        let diffWord = InsightNarrativeHelpers.differenceWord(delta)

                        let friendlyContent = delta > 0
                            ? L10n.format(
                                "On days you took %@, your symptoms tended to feel %@ milder than on days you skipped it. That makes consistency worth watching over the next few weeks.",
                                defaultValue: "On days you took %@, your symptoms tended to feel %@ milder than on days you skipped it. That makes consistency worth watching over the next few weeks.",
                                name,
                                diffWord
                            )
                            : L10n.format(
                                "Your symptoms didn't seem to improve on days you took %@. This doesn't necessarily mean it's not helping — it may take longer, or other factors may be at play.",
                                defaultValue: "Your symptoms didn't seem to improve on days you took %@. This doesn't necessarily mean it's not helping — it may take longer, or other factors may be at play.",
                                name
                            )

                        insights.append(
                            Insight(
                                insightType: .supplementEfficacy,
                                title: L10n.format(
                                    "%@: symptom severity delta",
                                    defaultValue: "%@: symptom severity delta",
                                    name
                                ),
                                content: friendlyContent,
                                scientificContent: L10n.format(
                                    "Your average symptom severity was %@/5 on days you took %@, compared to %@/5 on days you missed it — symptoms were %@ when you took it.",
                                    defaultValue: "Your average symptom severity was %@/5 on days you took %@, compared to %@/5 on days you missed it — symptoms were %@ when you took it.",
                                    L10n.decimal(takenAvg),
                                    name,
                                    L10n.decimal(missedAvg),
                                    directionalText
                                ),
                                confidence: confidence,
                                dataPointsUsed: takenSeverities.count + missedSeverities.count,
                                actionable: delta <= 0
                            )
                        )
                    }
                }
            }

            let adherenceByCycle: [(lengthDays: Int, adherencePercent: Double)] = completedCycles.compactMap { cycle in
                let cycleLogs = logs.filter { log in
                    let logDate = calendar.startOfDay(for: log.date)
                    return logDate >= cycle.startDate && logDate <= cycle.endDate
                }

                guard !cycleLogs.isEmpty else { return nil }

                let takenCount = cycleLogs.filter(\.taken).count
                let adherence = (Double(takenCount) / Double(cycleLogs.count)) * 100
                return (cycle.lengthDays, adherence)
            }

            let highAdherenceCycleLengths = adherenceByCycle
                .filter { $0.adherencePercent >= 80 }
                .map(\.lengthDays)
            let lowerAdherenceCycleLengths = adherenceByCycle
                .filter { $0.adherencePercent < 80 }
                .map(\.lengthDays)

            guard highAdherenceCycleLengths.count >= 2, lowerAdherenceCycleLengths.count >= 2 else { continue }

            let highAverage = average(highAdherenceCycleLengths.map(Double.init))
            let lowAverage = average(lowerAdherenceCycleLengths.map(Double.init))
            let cycleDelta = lowAverage - highAverage

            guard abs(cycleDelta) >= 2 else { continue }

            let cycleConfidence = min(
                0.90,
                max(
                    0.48,
                    0.52
                        + (Double(min(highAdherenceCycleLengths.count, lowerAdherenceCycleLengths.count)) * 0.04)
                        + (abs(cycleDelta) * 0.02)
                )
            )

            let directionalWord = cycleDelta > 0
                ? L10n.string("shorter", defaultValue: "shorter")
                : L10n.string("longer", defaultValue: "longer")

            let friendlyCycleContent = cycleDelta > 0
                ? L10n.format(
                    "In months when you were consistent with %@, your cycles tended to be shorter. That makes adherence worth tracking for a bit longer to see if the pattern holds.",
                    defaultValue: "In months when you were consistent with %@, your cycles tended to be shorter. That makes adherence worth tracking for a bit longer to see if the pattern holds.",
                    name
                )
                : L10n.format(
                    "In months when you were consistent with %@, your cycles ran a bit longer. That is useful to keep watching before drawing any big conclusions.",
                    defaultValue: "In months when you were consistent with %@, your cycles ran a bit longer. That is useful to keep watching before drawing any big conclusions.",
                    name
                )

            insights.append(
                Insight(
                    insightType: .supplementEfficacy,
                    title: L10n.format(
                        "Cycle length shift with %@ adherence",
                        defaultValue: "Cycle length shift with %@ adherence",
                        name
                    ),
                    content: friendlyCycleContent,
                    scientificContent: L10n.format(
                        "Your cycles were about %@ days %@ in months when you consistently took %@ (%@ vs %@ days on average).",
                        defaultValue: "Your cycles were about %@ days %@ in months when you consistently took %@ (%@ vs %@ days on average).",
                        L10n.decimal(abs(cycleDelta)),
                        directionalWord,
                        name,
                        L10n.decimal(highAverage),
                        L10n.decimal(lowAverage)
                    ),
                    confidence: cycleConfidence,
                    dataPointsUsed: highAdherenceCycleLengths.count + lowerAdherenceCycleLengths.count,
                    actionable: true
                )
            )
        }

        return insights
    }

    private func average(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }
}

private struct CompletedSupplementCycle {
    let startDate: Date
    let endDate: Date
    let lengthDays: Int
}
