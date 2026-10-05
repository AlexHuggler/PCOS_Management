import Foundation
import SwiftData

@MainActor
struct HealthSignalInsightAnalyzer {
    let fetcher: InsightDataFetcher

    private let recentWindowDays = 7
    private let minimumComparableLogs = 14

    func analyze() throws -> [Insight] {
        let dailyLogs: [DailyLog] = try fetcher.fetch(
            FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\.date, order: .forward)]),
            stage: .sleepActivity
        )
        let comparableLogs = dailyLogs.filter(Self.hasRecoverySignal)
        guard comparableLogs.count >= minimumComparableLogs else { return [] }

        let calendar = Calendar.current
        let recentWindow = InsightAnalysisPolicy.window(days: recentWindowDays)
        let baselineStart = calendar.date(byAdding: .day, value: -recentWindowDays, to: recentWindow.start) ?? recentWindow.start
        let recentLogs = comparableLogs.filter { $0.date >= recentWindow.start && $0.date < recentWindow.end }
        let baselineLogs = comparableLogs.filter { $0.date >= baselineStart && $0.date < recentWindow.start }
        guard Set(recentLogs.map { calendar.startOfDay(for: $0.date) }).count >= 5,
              Set(baselineLogs.map { calendar.startOfDay(for: $0.date) }).count >= 5,
              recentLogs.compactMap(\.sleepHours).count >= 5,
              baselineLogs.compactMap(\.sleepHours).count >= 5 else { return [] }

        let earliestDate = baselineLogs.first?.date ?? comparableLogs.first?.date ?? Date()
        let latestDate = recentLogs.last?.date ?? Date()
        let inclusiveEndDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: latestDate)) ?? latestDate

        let symptoms: [SymptomEntry] = try fetcher.fetch(
            FetchDescriptor<SymptomEntry>(
                predicate: #Predicate<SymptomEntry> { symptom in
                    symptom.date >= earliestDate && symptom.date < inclusiveEndDate
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            ),
            stage: .sleepActivitySymptoms
        )

        let healthSignals: [HealthKitImportedSampleRecord] = try fetcher.fetch(
            FetchDescriptor<HealthKitImportedSampleRecord>(
                predicate: #Predicate<HealthKitImportedSampleRecord> { record in
                    record.startDate >= earliestDate && record.startDate < inclusiveEndDate
                },
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            ),
            stage: .healthSignals
        )

        guard let insight = makeRecoveryInsight(
            recentLogs: recentLogs,
            baselineLogs: baselineLogs,
            symptoms: symptoms,
            healthSignals: healthSignals,
            calendar: calendar
        ) else {
            return []
        }
        return [insight]
    }

    private func makeRecoveryInsight(
        recentLogs: [DailyLog],
        baselineLogs: [DailyLog],
        symptoms: [SymptomEntry],
        healthSignals: [HealthKitImportedSampleRecord],
        calendar: Calendar
    ) -> Insight? {
        guard let recentSleep = average(recentLogs.compactMap(\.sleepHours)),
              let baselineSleep = average(baselineLogs.compactMap(\.sleepHours)) else {
            return nil
        }

        let recentRHR = average(recentLogs.compactMap(\.restingHeartRateBPM))
        let baselineRHR = average(baselineLogs.compactMap(\.restingHeartRateBPM))
        let recentEnergy = average(recentLogs.compactMap { $0.energyLevel.map(Double.init) })
        let baselineEnergy = average(baselineLogs.compactMap { $0.energyLevel.map(Double.init) })
        let recentPain = average(recentLogs.compactMap { $0.painLevel0To10.map(Double.init) })
        let baselinePain = average(baselineLogs.compactMap { $0.painLevel0To10.map(Double.init) })

        let baselineStart = calendar.startOfDay(for: baselineLogs.first?.date ?? Date())
        let recentStart = calendar.startOfDay(for: recentLogs.first?.date ?? Date())
        let recentEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: recentLogs.last?.date ?? Date())) ?? Date()
        let baselineSymptoms = symptoms.filter { $0.date >= baselineStart && $0.date < recentStart }
        let recentSymptoms = symptoms.filter { $0.date >= recentStart && $0.date < recentEnd }
        let symptomDays = InsightAnalysisPolicy.symptomObservations(symptoms: symptoms, dailyLogs: baselineLogs + recentLogs, days: InsightAnalysisPolicy.lifestyleDays, calendar: calendar)
        let recentSymptomSeverity = average(symptomDays.filter { $0.date >= recentStart && $0.date < recentEnd }.map(\.value))
        let baselineSymptomSeverity = average(symptomDays.filter { $0.date >= baselineStart && $0.date < recentStart }.map(\.value))

        let sleepDrop = baselineSleep - recentSleep
        let restingHeartRateRise = zipAverages(recentRHR, baselineRHR).map { $0.recent - $0.baseline } ?? 0
        let energyDrop = zipAverages(recentEnergy, baselineEnergy).map { $0.baseline - $0.recent } ?? 0
        let painRise = zipAverages(recentPain, baselinePain).map { $0.recent - $0.baseline } ?? 0
        let symptomRise = zipAverages(recentSymptomSeverity, baselineSymptomSeverity).map { $0.recent - $0.baseline } ?? 0

        let hasShortSleep = recentSleep < 7 && sleepDrop >= 0.75
        let hasRecoveryStrain = restingHeartRateRise >= 4 || energyDrop >= 1 || painRise >= 2 || symptomRise >= 1
        guard hasShortSleep, hasRecoveryStrain else { return nil }

        let topSymptom = topSymptomName(from: recentSymptoms)
        let sourceSummary = sourceSummary(for: healthSignals)
        let sourcePhrase = sourceSummary.isEmpty
            ? L10n.string(
                "your logs",
                defaultValue: "your logs"
            )
            : L10n.format(
                "your logs plus %@ data shared through Apple Health",
                defaultValue: "your logs plus %@ data shared through Apple Health",
                sourceSummary
            )

        let pattern = patternSummary(
            recentSleep: recentSleep,
            baselineSleep: baselineSleep,
            restingHeartRateRise: restingHeartRateRise,
            energyDrop: energyDrop,
            painRise: painRise,
            symptomRise: symptomRise,
            topSymptom: topSymptom
        )

        let content = L10n.format(
            "Pattern: %@ These measures changed together; your records do not establish a cause. Possible next steps: protect a steadier bedtime, choose gentler movement, hydrate, and pair meals with protein or fiber. Best first step: tonight, keep the evening simple and log energy, pain, and symptoms tomorrow so we can see whether the pattern eases.",
            defaultValue: "Pattern: %@ These measures changed together; your records do not establish a cause. Possible next steps: protect a steadier bedtime, choose gentler movement, hydrate, and pair meals with protein or fiber. Best first step: tonight, keep the evening simple and log energy, pain, and symptoms tomorrow so we can see whether the pattern eases.",
            pattern
        )

        let scientificContent = scientificSummary(
            recentSleep: recentSleep,
            baselineSleep: baselineSleep,
            recentRHR: recentRHR,
            baselineRHR: baselineRHR,
            recentEnergy: recentEnergy,
            baselineEnergy: baselineEnergy,
            recentPain: recentPain,
            baselinePain: baselinePain,
            recentSymptomSeverity: recentSymptomSeverity,
            baselineSymptomSeverity: baselineSymptomSeverity,
            sourcePhrase: sourcePhrase,
            healthSignals: healthSignals
        )

        return Insight(
            insightType: .sleepActivity,
            title: L10n.string(
                "Recovery signals may be adding strain",
                defaultValue: "Recovery signals may be adding strain"
            ),
            content: content,
            scientificContent: scientificContent,
            confidence: confidence(
                sleepDrop: sleepDrop,
                restingHeartRateRise: restingHeartRateRise,
                energyDrop: energyDrop,
                painRise: painRise,
                symptomRise: symptomRise,
                sourceCount: healthSignals.count
            ),
            dataPointsUsed: recentLogs.count + baselineLogs.count + recentSymptoms.count + baselineSymptoms.count + healthSignals.count,
            actionable: true,
            relatedSymptoms: topSymptom.map { [$0] } ?? []
        )
    }

    private static func hasRecoverySignal(_ log: DailyLog) -> Bool {
        log.sleepHours != nil
            || log.activeMinutes != nil
            || log.restingHeartRateBPM != nil
            || log.energyLevel != nil
            || log.painLevel0To10 != nil
    }

    private func patternSummary(
        recentSleep: Double,
        baselineSleep: Double,
        restingHeartRateRise: Double,
        energyDrop: Double,
        painRise: Double,
        symptomRise: Double,
        topSymptom: String?
    ) -> String {
        var pieces: [String] = [
            L10n.format(
                "your last week averaged %@ hours of sleep versus %@ before",
                defaultValue: "your last week averaged %@ hours of sleep versus %@ before",
                L10n.decimal(recentSleep),
                L10n.decimal(baselineSleep)
            )
        ]

        if restingHeartRateRise >= 4 {
            pieces.append(
                L10n.format(
                    "resting heart rate was up about %@ bpm",
                    defaultValue: "resting heart rate was up about %@ bpm",
                    L10n.decimal(restingHeartRateRise)
                )
            )
        }
        if energyDrop >= 1 {
            pieces.append(
                L10n.string(
                    "energy was lower",
                    defaultValue: "energy was lower"
                )
            )
        }
        if painRise >= 2 {
            pieces.append(
                L10n.string(
                    "pain was higher",
                    defaultValue: "pain was higher"
                )
            )
        } else if symptomRise >= 1, let topSymptom {
            pieces.append(
                L10n.format(
                    "%@ was higher",
                    defaultValue: "%@ was higher",
                    topSymptom.lowercased()
                )
            )
        }

        return pieces.joined(separator: ", ") + "."
    }

    private func scientificSummary(
        recentSleep: Double,
        baselineSleep: Double,
        recentRHR: Double?,
        baselineRHR: Double?,
        recentEnergy: Double?,
        baselineEnergy: Double?,
        recentPain: Double?,
        baselinePain: Double?,
        recentSymptomSeverity: Double?,
        baselineSymptomSeverity: Double?,
        sourcePhrase: String,
        healthSignals: [HealthKitImportedSampleRecord]
    ) -> String {
        var measurements = [
            L10n.format(
                "sleep %@h vs %@h",
                defaultValue: "sleep %@h vs %@h",
                L10n.decimal(recentSleep),
                L10n.decimal(baselineSleep)
            )
        ]

        if let recentRHR, let baselineRHR {
            measurements.append(
                L10n.format(
                    "resting heart rate %@ vs %@ bpm",
                    defaultValue: "resting heart rate %@ vs %@ bpm",
                    L10n.decimal(recentRHR),
                    L10n.decimal(baselineRHR)
                )
            )
        }
        if let recentEnergy, let baselineEnergy {
            measurements.append(
                L10n.format(
                    "energy %@/5 vs %@/5",
                    defaultValue: "energy %@/5 vs %@/5",
                    L10n.decimal(recentEnergy),
                    L10n.decimal(baselineEnergy)
                )
            )
        }
        if let recentPain, let baselinePain {
            measurements.append(
                L10n.format(
                    "pain %@/10 vs %@/10",
                    defaultValue: "pain %@/10 vs %@/10",
                    L10n.decimal(recentPain),
                    L10n.decimal(baselinePain)
                )
            )
        }
        if let recentSymptomSeverity, let baselineSymptomSeverity {
            measurements.append(
                L10n.format(
                    "symptoms %@/5 vs %@/5",
                    defaultValue: "symptoms %@/5 vs %@/5",
                    L10n.decimal(recentSymptomSeverity),
                    L10n.decimal(baselineSymptomSeverity)
                )
            )
        }

        var context = L10n.format(
            "The recent 7-day window is compared with the prior 7-day baseline using %@: %@. This is a personal pattern check, not a diagnosis, and it can be influenced by cycle timing, stress, illness, medication changes, and sensor availability.",
            defaultValue: "The recent 7-day window is compared with the prior 7-day baseline using %@: %@. This is a personal pattern check, not a diagnosis, and it can be influenced by cycle timing, stress, illness, medication changes, and sensor availability.",
            sourcePhrase,
            measurements.joined(separator: "; ")
        )

        let sourceTypes = sourceTypeSummary(for: healthSignals)
        if !sourceTypes.isEmpty {
            context += " " + L10n.format(
                "Available HealthKit context included %@.",
                defaultValue: "Available HealthKit context included %@.",
                sourceTypes
            )
        }
        return context
    }

    private func confidence(
        sleepDrop: Double,
        restingHeartRateRise: Double,
        energyDrop: Double,
        painRise: Double,
        symptomRise: Double,
        sourceCount: Int
    ) -> Double {
        var score = 0.44
        score += min(max(sleepDrop - 0.75, 0) * 0.06, 0.12)
        score += min(max(restingHeartRateRise - 4, 0) * 0.015, 0.08)
        score += min(max(energyDrop, 0) * 0.035, 0.07)
        score += min(max(painRise, 0) * 0.02, 0.06)
        score += min(max(symptomRise, 0) * 0.025, 0.06)
        if sourceCount > 0 {
            score += 0.04
        }
        return min(score, 0.78)
    }

    private func topSymptomName(from symptoms: [SymptomEntry]) -> String? {
        let grouped = Dictionary(grouping: symptoms, by: \.symptomType)
        return grouped
            .map { type, entries in
                let avg = average(entries.map { Double($0.severity) }) ?? 0
                return (type: type, score: avg, count: entries.count)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.count > rhs.count
                }
                return lhs.score > rhs.score
            }
            .first?
            .type
            .displayName
    }

    private func sourceSummary(for records: [HealthKitImportedSampleRecord]) -> String {
        readableList(
            from: records
                .map(\.sourceLabel)
                .filter { !$0.localizedCaseInsensitiveContains("Apple Health") }
        )
    }

    private func sourceTypeSummary(for records: [HealthKitImportedSampleRecord]) -> String {
        let types = Set(records.compactMap(sourceTypeName(for:)))
        return readableList(from: Array(types).sorted())
    }

    private func sourceTypeName(for record: HealthKitImportedSampleRecord) -> String? {
        let identifier = record.healthKitIdentifier.lowercased()
        if identifier.contains("heartratevariability") || identifier.contains("heart_rate_variability") {
            return L10n.string("heart-rate variability", defaultValue: "heart-rate variability")
        }
        if identifier.contains("restingheartrate") || identifier.contains("resting_heart_rate") {
            return L10n.string("resting heart rate", defaultValue: "resting heart rate")
        }
        if identifier.contains("bodytemperature") || identifier.contains("wristtemperature") {
            return L10n.string("temperature", defaultValue: "temperature")
        }
        if identifier.contains("activeenergy") || identifier.contains("exercisetime") || identifier.contains("stepcount") {
            return L10n.string("activity", defaultValue: "activity")
        }
        if identifier.contains("dietary") || identifier.contains("protein") || identifier.contains("carbohydrate") || identifier.contains("fat") {
            return L10n.string("nutrition", defaultValue: "nutrition")
        }
        return nil
    }

    private func readableList(from values: [String]) -> String {
        let unique = Array(
            Set(
                values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
        .prefix(3)

        switch unique.count {
        case 0:
            return ""
        case 1:
            return String(unique[0])
        case 2:
            return "\(unique[0]) and \(unique[1])"
        default:
            return "\(unique[0]), \(unique[1]), and \(unique[2])"
        }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func zipAverages(_ recent: Double?, _ baseline: Double?) -> (recent: Double, baseline: Double)? {
        guard let recent, let baseline else { return nil }
        return (recent, baseline)
    }
}
