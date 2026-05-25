import Foundation

/// Restricts phase inference to shorter, ovulatory, and relatively stable cycles.
/// This avoids presenting standard-cycle phase assumptions for irregular PCOS patterns.
struct CyclePhaseInferencePolicy: Sendable {
    let maximumSupportedCycleLength: Int
    let maximumStandardDeviation: Double

    init(
        maximumSupportedCycleLength: Int = 45,
        maximumStandardDeviation: Double = 7
    ) {
        self.maximumSupportedCycleLength = maximumSupportedCycleLength
        self.maximumStandardDeviation = maximumStandardDeviation
    }

    func approximatePhase(
        for date: Date,
        cycles: [Cycle],
        calendar: Calendar = .current
    ) -> CyclePhase? {
        let normalizedDate = calendar.startOfDay(for: date)
        let completedCycles = cycles.filter { !$0.isPredicted }

        for cycle in completedCycles {
            let cycleStart = calendar.startOfDay(for: cycle.startDate)
            guard let cycleLength = cycle.manualCycleLengthOverrideDays ?? cycle.lengthDays,
                  cycleLength > 0,
                  supportsPhaseInference(for: cycle, within: completedCycles),
                  let cycleEnd = calendar.date(byAdding: .day, value: cycleLength, to: cycleStart),
                  normalizedDate >= cycleStart,
                  normalizedDate < cycleEnd else {
                continue
            }

            let dayInCycle = calendar.dateComponents([.day], from: cycleStart, to: normalizedDate).day ?? 0
            if dayInCycle < 5 { return .menstrual }
            if dayInCycle < 13 { return .follicular }
            if dayInCycle < 16 { return .ovulatory }
            return .luteal
        }

        return nil
    }

    private func supportsPhaseInference(for cycle: Cycle, within cycles: [Cycle]) -> Bool {
        guard cycle.ovulationStatus == .ovulatory,
              let cycleLength = cycle.manualCycleLengthOverrideDays ?? cycle.lengthDays,
              cycleLength <= maximumSupportedCycleLength else {
            return false
        }

        let recentLengths = cycles
            .filter { !$0.isPredicted }
            .compactMap { $0.manualCycleLengthOverrideDays ?? $0.lengthDays }
            .suffix(6)

        guard recentLengths.count >= 3 else {
            return true
        }

        let average = Double(recentLengths.reduce(0, +)) / Double(recentLengths.count)
        let variance = recentLengths
            .map { pow(Double($0) - average, 2) }
            .reduce(0, +) / Double(recentLengths.count - 1)

        return sqrt(variance) <= maximumStandardDeviation
    }
}
