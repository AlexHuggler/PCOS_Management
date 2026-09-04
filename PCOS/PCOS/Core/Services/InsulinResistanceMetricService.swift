import Foundation

struct InsulinResistanceMetrics {
    let fastingAverage: Double?
    let elevatedReadingRate: Double
    let medianPostMealSpike: Double?
    let lutealVsFollicularDelta: Double?
}

struct CyclePhaseAverage: Identifiable {
    let phase: CyclePhase
    let average: Double
    let count: Int

    var id: String { phase.rawValue }
}

struct PostMealSpikeSample: Identifiable {
    let id: UUID
    let date: Date
    let mealContext: String
    let beforeValue: Double
    let afterValue: Double

    var spike: Double { afterValue - beforeValue }
}

protocol InsulinResistanceMetricCalculating {
    func calculateMetrics(readings: [BloodSugarReading], cycles: [Cycle]) -> InsulinResistanceMetrics
    func cyclePhaseAverages(readings: [BloodSugarReading], cycles: [Cycle]) -> [CyclePhaseAverage]
    func postMealSpikeSamples(readings: [BloodSugarReading]) -> [PostMealSpikeSample]
    func dailyAverages(readings: [BloodSugarReading], days: Int, now: Date) -> [(date: Date, average: Double)]
}

struct InsulinResistanceMetricService: InsulinResistanceMetricCalculating {
    private let calendar = Calendar.current

    func calculateMetrics(readings: [BloodSugarReading], cycles: [Cycle]) -> InsulinResistanceMetrics {
        let fasting = readings.filter { $0.readingType == .fasting }.map(\.glucoseValue)
        let fastingAverage = fasting.isEmpty ? nil : fasting.reduce(0, +) / Double(fasting.count)

        let elevatedCount = readings.filter { $0.glucoseValue >= 140 }.count
        let elevatedRate = readings.isEmpty ? 0 : Double(elevatedCount) / Double(readings.count)

        let spikes = postMealSpikeSamples(readings: readings).map(\.spike).sorted()
        let medianSpike = median(of: spikes)

        let phaseAverages = cyclePhaseAverages(readings: readings, cycles: cycles)
        let follicular = phaseAverages.first { $0.phase == .follicular }?.average
        let luteal = phaseAverages.first { $0.phase == .luteal }?.average
        let phaseDelta: Double? = if let luteal, let follicular { luteal - follicular } else { nil }

        return InsulinResistanceMetrics(
            fastingAverage: fastingAverage,
            elevatedReadingRate: elevatedRate,
            medianPostMealSpike: medianSpike,
            lutealVsFollicularDelta: phaseDelta
        )
    }

    func cyclePhaseAverages(readings: [BloodSugarReading], cycles: [Cycle]) -> [CyclePhaseAverage] {
        var grouped: [CyclePhase: [Double]] = [:]
        for phase in CyclePhase.allCases {
            grouped[phase] = []
        }

        for reading in readings {
            guard let phase = approximatePhase(for: reading.timestamp, cycles: cycles) else { continue }
            grouped[phase, default: []].append(reading.glucoseValue)
        }

        return grouped.compactMap { phase, values in
            guard !values.isEmpty else { return nil }
            let average = values.reduce(0, +) / Double(values.count)
            return CyclePhaseAverage(phase: phase, average: average, count: values.count)
        }
        .sorted { $0.phase.rawValue < $1.phase.rawValue }
    }

    func postMealSpikeSamples(readings: [BloodSugarReading]) -> [PostMealSpikeSample] {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        let before = sorted.filter { $0.readingType == .beforeMeal }
        let after = sorted.filter { $0.readingType == .afterMeal }

        var samples: [PostMealSpikeSample] = []

        for beforeReading in before {
            let day = calendar.startOfDay(for: beforeReading.timestamp)
            let context = normalizedContext(beforeReading.mealContext)

            let candidates = after.filter { candidate in
                guard calendar.startOfDay(for: candidate.timestamp) == day else { return false }
                guard candidate.timestamp > beforeReading.timestamp else { return false }
                guard candidate.timestamp.timeIntervalSince(beforeReading.timestamp) <= 3 * 60 * 60 else { return false }
                return normalizedContext(candidate.mealContext) == context
            }

            guard let match = candidates.first else { continue }

            samples.append(
                PostMealSpikeSample(
                    id: UUID(),
                    date: day,
                    mealContext: context ?? String(localized: "Meal", comment: "Fallback meal context label for post-meal spike samples."),
                    beforeValue: beforeReading.glucoseValue,
                    afterValue: match.glucoseValue
                )
            )
        }

        return samples
    }

    func dailyAverages(readings: [BloodSugarReading], days: Int, now: Date = Date()) -> [(date: Date, average: Double)] {
        guard let earliestDate = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else {
            return []
        }

        let filtered = readings.filter { $0.timestamp >= earliestDate }
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.timestamp) }

        return grouped.map { day, dayReadings in
            let avg = dayReadings.map(\.glucoseValue).reduce(0, +) / Double(dayReadings.count)
            return (date: day, average: avg)
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Private

    /// Phase assignment goes through the app's phase-inference policy so long, unstable or
    /// anovulatory PCOS cycles are never bucketed into standard-cycle phases.
    private func approximatePhase(for date: Date, cycles: [Cycle]) -> CyclePhase? {
        CyclePhaseInferencePolicy().approximatePhase(for: date, cycles: cycles, calendar: calendar)
    }

    private func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }

        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    private func normalizedContext(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
