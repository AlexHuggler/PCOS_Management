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
        let completedCycles = cycles.filter { $0.lengthDays != nil && !$0.isPredicted && $0.endReason != .pregnancy }
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

        let centerDays = Int(round(weightedAverage))
        // Confidence decreases with higher variance and fewer data points.
        // Capped at 0.9 — cycle prediction should never claim certainty.
        let dataPointFactor = min(Double(lengths.count) / 6.0, 1.0)
        let varianceFactor = max(0.0, 1.0 - (standardDeviation / 20.0))
        let confidence = min(dataPointFactor * varianceFactor, 0.9)
        return makePrediction(
            centerDays: centerDays,
            windowHalf: windowHalf,
            lastPeriodStart: lastPeriodStart,
            confidence: confidence
        )
    }

    /// Predict next period using a user-provided manual cycle length override.
    /// Manual override takes precedence over statistical prediction.
    func predictNextPeriod(
        manualCycleLengthOverrideDays: Int,
        cycles: [Cycle],
        lastPeriodStart: Date
    ) -> Prediction? {
        guard (15...120).contains(manualCycleLengthOverrideDays) else { return nil }

        let completedCycles = cycles.filter { $0.lengthDays != nil && !$0.isPredicted && $0.endReason != .pregnancy }
        let lengths = completedCycles.compactMap { $0.lengthDays }
        let variance = calculateVariance(lengths, mean: Double(manualCycleLengthOverrideDays))
        let standardDeviation = sqrt(variance)

        // Keep the default minimum window while respecting uncertainty from historical variance.
        let minimumWindowDays = 5.0
        let windowHalf = max(minimumWindowDays / 2.0, standardDeviation * 1.2)
        let confidencePenalty = min(0.35, standardDeviation / 24.0)
        let confidence = max(0.45, 0.88 - confidencePenalty)

        return makePrediction(
            centerDays: manualCycleLengthOverrideDays,
            windowHalf: windowHalf,
            lastPeriodStart: lastPeriodStart,
            confidence: confidence
        )
    }

    /// Calculate cycle statistics for display.
    func cycleStatistics(cycles: [Cycle]) -> CycleStatistics? {
        let completedCycles = cycles.filter { $0.lengthDays != nil && !$0.isPredicted && $0.endReason != .pregnancy }
        let lengths = completedCycles.map { $0.manualCycleLengthOverrideDays ?? $0.lengthDays }.compactMap { $0 }
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

    private func makePrediction(
        centerDays: Int,
        windowHalf: Double,
        lastPeriodStart: Date,
        confidence: Double
    ) -> Prediction? {
        let calendar = Calendar.current
        guard let centerDate = calendar.date(byAdding: .day, value: centerDays, to: lastPeriodStart) else {
            return nil
        }

        let earliestOffset = centerDays - Int(ceil(windowHalf))
        let latestOffset = centerDays + Int(ceil(windowHalf))

        guard let earliestDate = calendar.date(byAdding: .day, value: earliestOffset, to: lastPeriodStart),
              let latestDate = calendar.date(byAdding: .day, value: latestOffset, to: lastPeriodStart) else {
            return nil
        }

        return Prediction(
            earliestDate: earliestDate,
            latestDate: latestDate,
            centerDate: centerDate,
            confidence: confidence
        )
    }

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

    /// Predict next period during postpartum recovery.
    /// Uses only postpartum cycles until blending threshold is reached.
    func predictNextPeriodPostpartum(
        postpartumCycles: [Cycle],
        prePregnancyCycles: [Cycle],
        lastPeriodStart: Date
    ) -> Prediction? {
        let validPostpartum = postpartumCycles.filter { $0.lengthDays != nil && !$0.isPredicted && $0.endReason != .pregnancy }
        guard validPostpartum.count >= 2 else { return nil }

        let postpartumLengths = validPostpartum.compactMap { $0.lengthDays }
        guard !postpartumLengths.isEmpty else { return nil }

        var allLengths = postpartumLengths

        // Blend pre-pregnancy data if 4+ postpartum cycles and averages are close
        if validPostpartum.count >= 4 {
            let prePregnancyValid = prePregnancyCycles.filter { $0.lengthDays != nil && !$0.isPredicted && $0.endReason != .pregnancy }
            let prePregnancyLengths = prePregnancyValid.suffix(6).compactMap { $0.lengthDays }

            if !prePregnancyLengths.isEmpty {
                let postAvg = Double(postpartumLengths.reduce(0, +)) / Double(postpartumLengths.count)
                let preAvg = Double(prePregnancyLengths.reduce(0, +)) / Double(prePregnancyLengths.count)

                if abs(postAvg - preAvg) <= 7.0 {
                    // Blend up to 2 pre-pregnancy cycles with lower weight
                    allLengths.append(contentsOf: prePregnancyLengths.suffix(2))
                }
            }
        }

        let weightedAverage = calculateWeightedAverage(allLengths)
        let variance = calculateVariance(allLengths, mean: weightedAverage)
        let standardDeviation = sqrt(variance)

        let minimumWindowDays = 5.0
        let windowHalf = max(minimumWindowDays / 2.0, standardDeviation * 1.5)
        let centerDays = Int(round(weightedAverage))

        // Cap confidence for early postpartum
        let dataPointFactor = min(Double(postpartumLengths.count) / 6.0, 1.0)
        let varianceFactor = max(0.0, 1.0 - (standardDeviation / 20.0))
        var confidence = min(dataPointFactor * varianceFactor, 0.9)
        if validPostpartum.count < 4 {
            confidence = min(confidence, 0.6)
        }

        return makePrediction(
            centerDays: centerDays,
            windowHalf: windowHalf,
            lastPeriodStart: lastPeriodStart,
            confidence: confidence
        )
    }
}

struct CycleStatistics: Sendable {
    let averageLength: Double
    let shortestLength: Int
    let longestLength: Int
    let standardDeviation: Double
    let totalCycles: Int

    var formattedAverage: String {
        L10n.decimal(averageLength, fractionDigits: 0)
    }

    var rangeDescription: String {
        "\(shortestLength)-\(longestLength)"
    }
}
