import Foundation

/// Predicts next period using weighted averages with PCOS-appropriate variance windows.
/// Never assumes cycle regularity. Returns date RANGES, not single days.
struct CyclePredictionEngine: Sendable {

    /// Result of a cycle prediction
    struct Prediction: Sendable {
        let earliestDate: Date
        let latestDate: Date
        let centerDate: Date
        let confidence: Double

        var dateInterval: DateInterval {
            DateInterval(start: earliestDate, end: latestDate)
        }

        var windowDays: Int {
            Calendar.current.dateComponents([.day], from: earliestDate, to: latestDate).day ?? 0
        }
    }

    /// Predict the next period start date range based on cycle history.
    ///
    /// Uses weighted average of the most recent cycles (up to 6), with higher weight
    /// on recent cycles. The prediction window expands based on historical variance,
    /// with a minimum 5-day window for PCOS users.
    ///
    /// - Parameters:
    ///   - cycles: Completed cycles sorted by start date (most recent last)
    ///   - lastPeriodStart: The start date of the current/most recent period
    /// - Returns: A prediction with date range, or nil if insufficient data
    func predictNextPeriod(
        cycles: [Cycle],
        lastPeriodStart: Date
    ) -> Prediction? {
        let completedCycles = cycles.filter { $0.lengthDays != nil && !$0.isPredicted }
        guard !completedCycles.isEmpty else { return nil }

        let recentCycles = Array(completedCycles.suffix(6))
        let lengths = recentCycles.compactMap { $0.lengthDays }
        guard !lengths.isEmpty else { return nil }

        let weightedAverage = calculateWeightedAverage(lengths)
        let variance = calculateVariance(lengths, mean: weightedAverage)
        let standardDeviation = sqrt(variance)

        // Minimum 5-day window, expanding based on cycle irregularity
        let minimumWindowDays = 5.0
        let windowHalf = max(minimumWindowDays / 2.0, standardDeviation * 1.5)

        let calendar = Calendar.current
        let centerDays = Int(round(weightedAverage))
        guard let centerDate = calendar.date(byAdding: .day, value: centerDays, to: lastPeriodStart) else {
            return nil
        }

        let earliestOffset = centerDays - Int(ceil(windowHalf))
        let latestOffset = centerDays + Int(ceil(windowHalf))

        guard let earliestDate = calendar.date(byAdding: .day, value: earliestOffset, to: lastPeriodStart),
              let latestDate = calendar.date(byAdding: .day, value: latestOffset, to: lastPeriodStart) else {
            return nil
        }

        // Confidence decreases with higher variance and fewer data points.
        // Capped at 0.9 — cycle prediction should never claim certainty.
        let dataPointFactor = min(Double(lengths.count) / 6.0, 1.0)
        let varianceFactor = max(0.0, 1.0 - (standardDeviation / 20.0))
        let confidence = min(dataPointFactor * varianceFactor, 0.9)

        return Prediction(
            earliestDate: earliestDate,
            latestDate: latestDate,
            centerDate: centerDate,
            confidence: confidence
        )
    }

    /// Calculate cycle statistics for display.
    func cycleStatistics(cycles: [Cycle]) -> CycleStatistics? {
        let completedCycles = cycles.filter { $0.lengthDays != nil && !$0.isPredicted }
        let lengths = completedCycles.compactMap { $0.lengthDays }
        guard !lengths.isEmpty else { return nil }

        let average = Double(lengths.reduce(0, +)) / Double(lengths.count)
        let shortest = lengths.min() ?? 0
        let longest = lengths.max() ?? 0
        let variance = calculateVariance(lengths.map(Double.init), mean: average)

        return CycleStatistics(
            averageLength: average,
            shortestLength: shortest,
            longestLength: longest,
            standardDeviation: sqrt(variance),
            totalCycles: lengths.count
        )
    }

    // MARK: - Private

    /// Weighted average giving more weight to recent cycles.
    /// Weights: most recent = count, second most recent = count-1, etc.
    private func calculateWeightedAverage(_ lengths: [Int]) -> Double {
        guard !lengths.isEmpty else { return 0 }
        var totalWeight = 0.0
        var weightedSum = 0.0
        for (index, length) in lengths.enumerated() {
            let weight = Double(index + 1)
            weightedSum += Double(length) * weight
            totalWeight += weight
        }
        return weightedSum / totalWeight
    }

    private func calculateVariance(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        return squaredDiffs.reduce(0, +) / Double(values.count - 1)
    }

    private func calculateVariance(_ values: [Int], mean: Double) -> Double {
        calculateVariance(values.map(Double.init), mean: mean)
    }
}

struct CycleStatistics: Sendable {
    let averageLength: Double
    let shortestLength: Int
    let longestLength: Int
    let standardDeviation: Double
    let totalCycles: Int

    var formattedAverage: String {
        String(format: "%.0f", averageLength)
    }

    var rangeDescription: String {
        "\(shortestLength)-\(longestLength)"
    }
}
