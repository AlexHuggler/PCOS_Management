import Foundation

enum OvulationPredictionSource: String, Sendable {
    case temperatureShift
    case lhPeak
    case cervicalMucus
    case cycleHistory
}

struct OvulationPrediction: Sendable {
    let fertileWindowStart: Date
    let fertileWindowEnd: Date
    let predictedOvulationDate: Date
    let confidence: Double
    let source: OvulationPredictionSource

    var fertileWindow: DateInterval {
        DateInterval(start: fertileWindowStart, end: fertileWindowEnd)
    }
}

struct OvulationPredictionService: Sendable {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func prediction(
        for cycle: Cycle?,
        cycleHistory: [Cycle],
        observations: [OvulationObservation]
    ) -> OvulationPrediction? {
        guard let cycle, cycle.endDate == nil else { return nil }
        guard cycle.ovulationStatus != .anovulatory else { return nil }

        let normalizedObservations = observations
            .sorted { $0.date < $1.date }
            .filter { calendar.startOfDay(for: $0.date) >= calendar.startOfDay(for: cycle.startDate) }

        if let prediction = temperatureShiftPrediction(from: normalizedObservations) {
            return prediction
        }

        if let prediction = lhPrediction(from: normalizedObservations) {
            return prediction
        }

        if let prediction = cervicalMucusPrediction(from: normalizedObservations) {
            return prediction
        }

        return historyPrediction(for: cycle, cycleHistory: cycleHistory)
    }
}

private extension OvulationPredictionService {
    struct TemperatureReading {
        let date: Date
        let temperatureCelsius: Double
    }

    func temperatureShiftPrediction(from observations: [OvulationObservation]) -> OvulationPrediction? {
        let readings = observations.compactMap { observation -> TemperatureReading? in
            guard let temperatureCelsius = observation.basalBodyTemperatureCelsius else { return nil }
            return TemperatureReading(
                date: calendar.startOfDay(for: observation.date),
                temperatureCelsius: temperatureCelsius
            )
        }

        guard readings.count >= 6 else { return nil }

        for index in 2..<readings.count {
            let priorReadings = Array(readings[..<(index - 1)].suffix(6))
            guard priorReadings.count >= 3 else { continue }

            let elevatedReadings = Array(readings[(index - 2)...index])
            let baselineTemperature = priorReadings
                .map(\.temperatureCelsius)
                .reduce(0, +) / Double(priorReadings.count)

            let sustainedRise = elevatedReadings.allSatisfy { reading in
                reading.temperatureCelsius >= baselineTemperature + 0.18
            }

            guard sustainedRise else { continue }

            let highShiftDate = elevatedReadings[0].date
            let ovulationDate = calendar.date(byAdding: .day, value: -1, to: highShiftDate) ?? highShiftDate
            return makePrediction(
                ovulationDate: ovulationDate,
                fertileStartOffset: -5,
                fertileEndOffset: 1,
                confidence: 0.94,
                source: .temperatureShift
            )
        }

        return nil
    }

    func lhPrediction(from observations: [OvulationObservation]) -> OvulationPrediction? {
        if let peakObservation = observations.last(where: { $0.lhTestResult == .peak }) {
            let ovulationDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: peakObservation.date))
                ?? calendar.startOfDay(for: peakObservation.date)
            return makePrediction(
                ovulationDate: ovulationDate,
                fertileStartOffset: -5,
                fertileEndOffset: 1,
                confidence: 0.9,
                source: .lhPeak
            )
        }

        guard let highObservation = observations.last(where: { $0.lhTestResult == .high }) else {
            return nil
        }

        let ovulationDate = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: highObservation.date))
            ?? calendar.startOfDay(for: highObservation.date)
        return makePrediction(
            ovulationDate: ovulationDate,
            fertileStartOffset: -5,
            fertileEndOffset: 2,
            confidence: 0.78,
            source: .lhPeak
        )
    }

    func cervicalMucusPrediction(from observations: [OvulationObservation]) -> OvulationPrediction? {
        if let eggWhiteObservation = observations.last(where: { $0.cervicalMucus == .eggWhite }) {
            let ovulationDate = calendar.startOfDay(for: eggWhiteObservation.date)
            return makePrediction(
                ovulationDate: ovulationDate,
                fertileStartOffset: -4,
                fertileEndOffset: 1,
                confidence: 0.72,
                source: .cervicalMucus
            )
        }

        guard let wateryObservation = observations.last(where: { $0.cervicalMucus == .watery }) else {
            return nil
        }

        let ovulationDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: wateryObservation.date))
            ?? calendar.startOfDay(for: wateryObservation.date)
        return makePrediction(
            ovulationDate: ovulationDate,
            fertileStartOffset: -4,
            fertileEndOffset: 2,
            confidence: 0.64,
            source: .cervicalMucus
        )
    }

    func historyPrediction(for cycle: Cycle, cycleHistory: [Cycle]) -> OvulationPrediction? {
        let cycleLengths = cycleHistory
            .filter {
                $0.id != cycle.id
                    && !$0.isPredicted
                    && $0.endReason != .pregnancy
                    && $0.ovulationStatus != .anovulatory
            }
            .compactMap { $0.manualCycleLengthOverrideDays ?? $0.lengthDays }

        let baselineLength = cycle.manualCycleLengthOverrideDays ?? weightedAverage(cycleLengths)
        guard let baselineLength else { return nil }

        let standardDeviation = cycleLengths.count > 1 ? sqrt(variance(of: cycleLengths.map(Double.init))) : 0
        let irregularityBuffer = max(2, Int(ceil(standardDeviation / 2)))
        let uncertaintyBuffer = irregularityBuffer + (cycle.ovulationStatus == .unknown ? 1 : 0)
        let ovulationOffset = max(10, Int(round(Double(baselineLength) - 14)))

        let baseConfidence = min(0.72, 0.44 + Double(min(cycleLengths.count, 6)) * 0.05)
        let irregularityPenalty = min(0.26, standardDeviation / 30.0)
        let unknownStatusPenalty = cycle.ovulationStatus == .unknown ? 0.08 : 0
        let confidence = max(0.28, baseConfidence - irregularityPenalty - unknownStatusPenalty)

        let ovulationDate = calendar.date(byAdding: .day, value: ovulationOffset, to: calendar.startOfDay(for: cycle.startDate))
            ?? calendar.startOfDay(for: cycle.startDate)

        return makePrediction(
            ovulationDate: ovulationDate,
            fertileStartOffset: -(5 + uncertaintyBuffer),
            fertileEndOffset: 1 + uncertaintyBuffer,
            confidence: confidence,
            source: .cycleHistory
        )
    }

    func makePrediction(
        ovulationDate: Date,
        fertileStartOffset: Int,
        fertileEndOffset: Int,
        confidence: Double,
        source: OvulationPredictionSource
    ) -> OvulationPrediction? {
        guard let fertileWindowStart = calendar.date(byAdding: .day, value: fertileStartOffset, to: ovulationDate),
              let fertileWindowEnd = calendar.date(byAdding: .day, value: fertileEndOffset, to: ovulationDate) else {
            return nil
        }

        return OvulationPrediction(
            fertileWindowStart: fertileWindowStart,
            fertileWindowEnd: fertileWindowEnd,
            predictedOvulationDate: ovulationDate,
            confidence: confidence,
            source: source
        )
    }

    func weightedAverage(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }

        var totalWeight = 0.0
        var weightedSum = 0.0
        for (index, value) in values.enumerated() {
            let weight = Double(index + 1)
            weightedSum += Double(value) * weight
            totalWeight += weight
        }

        return Int(round(weightedSum / totalWeight))
    }

    func variance(of values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        return squaredDiffs.reduce(0, +) / Double(values.count - 1)
    }
}
