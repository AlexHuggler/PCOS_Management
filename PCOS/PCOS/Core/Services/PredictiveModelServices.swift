import Foundation
import CoreML

struct SymptomForecastFeatureVector {
    let sleepHours7DayAverage: Double
    let activityMinutes7DayAverage: Double
    let mealGIScore7DayAverage: Double
    let supplementAdherencePercent: Double
    let stressLevelAverage: Double
    let cyclePhase: CyclePhase?
    let bloodSugar7DayAverage: Double?
}

struct SymptomSeverityForecast {
    let dailyPredictions: [Double]
    let featureImportance: [(name: String, weight: Double)]
}

struct CycleLengthRangeForecast {
    let predictedLengthDays: Int
    let earliestLengthDays: Int
    let latestLengthDays: Int
    let confidence: Double
}

protocol SymptomSeverityForecasting {
    func forecast(
        using features: SymptomForecastFeatureVector,
        historicalSymptoms: [SymptomEntry]
    ) -> SymptomSeverityForecast
}

protocol CycleLengthForecasting {
    func forecast(
        cycles: [Cycle],
        weightTrendDelta: Double?,
        activityLevelAverage: Double?,
        supplementAdherencePercent: Double?,
        averageSymptomSeverity: Double?
    ) -> CycleLengthRangeForecast?
}

protocol CoreMLModelLoading {
    func loadSymptomSeverityModel() -> Any?
    func loadCycleLengthModel() -> Any?
}

struct DeferredCoreMLModelLoader: CoreMLModelLoading {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadSymptomSeverityModel() -> Any? {
        loadModel(
            candidates: [
                "SymptomLifestyleCorrelator",
                "SymptomSeverityCorrelator",
                "SymptomSeverityPredictor",
            ]
        )
    }

    func loadCycleLengthModel() -> Any? {
        loadModel(
            candidates: [
                "CycleLengthPredictor",
                "CycleLengthForecaster",
            ]
        )
    }

    private func loadModel(candidates: [String]) -> MLModel? {
        for name in candidates {
            guard let url = bundle.url(forResource: name, withExtension: "mlmodelc") else { continue }
            if let model = try? MLModel(contentsOf: url) {
                return model
            }
        }
        return nil
    }
}

struct BaselineSymptomSeverityForecaster: SymptomSeverityForecasting {
    func forecast(
        using features: SymptomForecastFeatureVector,
        historicalSymptoms: [SymptomEntry]
    ) -> SymptomSeverityForecast {
        let historicalAverage = if historicalSymptoms.isEmpty {
            2.5
        } else {
            Double(historicalSymptoms.map(\.severity).reduce(0, +)) / Double(historicalSymptoms.count)
        }

        let sleepAdjustment = features.sleepHours7DayAverage < 7 ? 0.4 : -0.2
        let stressAdjustment = (features.stressLevelAverage - 3.0) * 0.2
        let giAdjustment = features.mealGIScore7DayAverage > 1.4 ? 0.3 : -0.1
        let adherenceAdjustment = features.supplementAdherencePercent >= 80 ? -0.2 : 0.2
        let glucoseAdjustment = (features.bloodSugar7DayAverage ?? 110) >= 130 ? 0.2 : 0.0

        var base = historicalAverage + sleepAdjustment + stressAdjustment + giAdjustment + adherenceAdjustment + glucoseAdjustment
        if features.cyclePhase == .luteal {
            base += 0.2
        }

        let clamped = min(max(base, 1.0), 5.0)
        let dailyPredictions = Array(repeating: clamped, count: 7)

        return SymptomSeverityForecast(
            dailyPredictions: dailyPredictions,
            featureImportance: [
                ("Sleep", 0.28),
                ("Stress", 0.24),
                ("Meal GI", 0.20),
                ("Supplement adherence", 0.16),
                ("Blood sugar", 0.12),
            ]
        )
    }
}

struct BaselineCycleLengthForecaster: CycleLengthForecasting {
    func forecast(
        cycles: [Cycle],
        weightTrendDelta: Double?,
        activityLevelAverage: Double?,
        supplementAdherencePercent: Double?,
        averageSymptomSeverity: Double?
    ) -> CycleLengthRangeForecast? {
        let completed = cycles
            .filter { !$0.isPredicted }
            .compactMap { $0.manualCycleLengthOverrideDays ?? $0.lengthDays }

        guard !completed.isEmpty else { return nil }
        let recent = Array(completed.suffix(6))

        let weightedAverage = weightedRecentAverage(recent)
        var adjustment = 0.0

        if let supplementAdherencePercent, supplementAdherencePercent >= 80 {
            adjustment -= 1.5
        }
        if let averageSymptomSeverity, averageSymptomSeverity >= 3.5 {
            adjustment += 1.5
        }
        if let activityLevelAverage, activityLevelAverage >= 40 {
            adjustment -= 0.8
        }
        if let weightTrendDelta, abs(weightTrendDelta) > 1.5 {
            adjustment += 0.8
        }

        let predicted = Int(round(weightedAverage + adjustment))
        let spread = max(3, Int(round(standardDeviation(recent) * 1.2)))
        let confidence = min(0.9, max(0.35, 0.55 + (Double(recent.count) * 0.05) - (Double(spread) * 0.01)))

        return CycleLengthRangeForecast(
            predictedLengthDays: predicted,
            earliestLengthDays: predicted - spread,
            latestLengthDays: predicted + spread,
            confidence: confidence
        )
    }

    private func weightedRecentAverage(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        var weightedSum = 0.0
        var totalWeight = 0.0
        for (index, value) in values.enumerated() {
            let weight = Double(index + 1)
            weightedSum += Double(value) * weight
            totalWeight += weight
        }
        return weightedSum / totalWeight
    }

    private func standardDeviation(_ values: [Int]) -> Double {
        guard values.count > 1 else { return 0 }
        let avg = Double(values.reduce(0, +)) / Double(values.count)
        let variance = values
            .map { pow(Double($0) - avg, 2) }
            .reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }
}

struct CoreMLSymptomSeverityForecaster: SymptomSeverityForecasting {
    private let modelLoader: CoreMLModelLoading
    private let fallback: SymptomSeverityForecasting

    init(
        modelLoader: CoreMLModelLoading = DeferredCoreMLModelLoader(),
        fallback: SymptomSeverityForecasting = BaselineSymptomSeverityForecaster()
    ) {
        self.modelLoader = modelLoader
        self.fallback = fallback
    }

    func forecast(
        using features: SymptomForecastFeatureVector,
        historicalSymptoms: [SymptomEntry]
    ) -> SymptomSeverityForecast {
        guard let model = modelLoader.loadSymptomSeverityModel() as? MLModel else {
            return fallback.forecast(using: features, historicalSymptoms: historicalSymptoms)
        }

        guard let forecast = try? runModel(model: model, features: features) else {
            return fallback.forecast(using: features, historicalSymptoms: historicalSymptoms)
        }

        return forecast
    }

    private func runModel(
        model: MLModel,
        features: SymptomForecastFeatureVector
    ) throws -> SymptomSeverityForecast {
        let payload: [String: Any] = [
            "sleepHours7DayAverage": features.sleepHours7DayAverage,
            "activityMinutes7DayAverage": features.activityMinutes7DayAverage,
            "mealGIScore7DayAverage": features.mealGIScore7DayAverage,
            "supplementAdherencePercent": features.supplementAdherencePercent,
            "stressLevelAverage": features.stressLevelAverage,
            "cyclePhaseRawValue": features.cyclePhase?.rawValue ?? "",
            "bloodSugar7DayAverage": features.bloodSugar7DayAverage ?? 0,
        ]

        let provider = try MLDictionaryFeatureProvider(dictionary: payload)
        let output = try model.prediction(from: provider)
        let parsed = parseDailyPredictions(from: output)
        guard !parsed.isEmpty else {
            throw PredictionParsingError.missingPrediction
        }

        let clipped = parsed
            .prefix(7)
            .map { min(max($0, 1.0), 5.0) }
        let filled = clipped.count == 7 ? clipped : Array(clipped + Array(repeating: clipped.last ?? 2.5, count: 7 - clipped.count))

        return SymptomSeverityForecast(
            dailyPredictions: filled,
            featureImportance: [
                ("Sleep", 0.28),
                ("Stress", 0.24),
                ("Meal GI", 0.20),
                ("Supplement adherence", 0.16),
                ("Blood sugar", 0.12),
            ]
        )
    }

    private func parseDailyPredictions(from output: MLFeatureProvider) -> [Double] {
        let candidateKeys = [
            "dailyPredictions",
            "prediction",
            "predictions",
            "output",
        ]

        for key in candidateKeys {
            guard let value = output.featureValue(for: key) else { continue }
            if value.type == .multiArray, let array = value.multiArrayValue {
                return extractMultiArray(array)
            }
            if value.type == .double {
                return Array(repeating: value.doubleValue, count: 7)
            }
        }

        for name in output.featureNames.sorted() {
            guard let value = output.featureValue(for: name) else { continue }
            if value.type == .multiArray, let array = value.multiArrayValue {
                let extracted = extractMultiArray(array)
                if !extracted.isEmpty { return extracted }
            }
            if value.type == .double {
                return Array(repeating: value.doubleValue, count: 7)
            }
        }

        return []
    }

    private func extractMultiArray(_ array: MLMultiArray) -> [Double] {
        guard array.count > 0 else { return [] }
        return (0..<array.count).map { index in
            array[index].doubleValue
        }
    }
}

struct CoreMLCycleLengthForecaster: CycleLengthForecasting {
    private let modelLoader: CoreMLModelLoading
    private let fallback: CycleLengthForecasting

    init(
        modelLoader: CoreMLModelLoading = DeferredCoreMLModelLoader(),
        fallback: CycleLengthForecasting = BaselineCycleLengthForecaster()
    ) {
        self.modelLoader = modelLoader
        self.fallback = fallback
    }

    func forecast(
        cycles: [Cycle],
        weightTrendDelta: Double?,
        activityLevelAverage: Double?,
        supplementAdherencePercent: Double?,
        averageSymptomSeverity: Double?
    ) -> CycleLengthRangeForecast? {
        guard let model = modelLoader.loadCycleLengthModel() as? MLModel else {
            return fallback.forecast(
                cycles: cycles,
                weightTrendDelta: weightTrendDelta,
                activityLevelAverage: activityLevelAverage,
                supplementAdherencePercent: supplementAdherencePercent,
                averageSymptomSeverity: averageSymptomSeverity
            )
        }

        guard let forecast = try? runModel(
            model: model,
            cycles: cycles,
            weightTrendDelta: weightTrendDelta,
            activityLevelAverage: activityLevelAverage,
            supplementAdherencePercent: supplementAdherencePercent,
            averageSymptomSeverity: averageSymptomSeverity
        ) else {
            return fallback.forecast(
                cycles: cycles,
                weightTrendDelta: weightTrendDelta,
                activityLevelAverage: activityLevelAverage,
                supplementAdherencePercent: supplementAdherencePercent,
                averageSymptomSeverity: averageSymptomSeverity
            )
        }

        return forecast
    }

    private func runModel(
        model: MLModel,
        cycles: [Cycle],
        weightTrendDelta: Double?,
        activityLevelAverage: Double?,
        supplementAdherencePercent: Double?,
        averageSymptomSeverity: Double?
    ) throws -> CycleLengthRangeForecast {
        let completedLengths = cycles
            .filter { !$0.isPredicted }
            .compactMap { $0.manualCycleLengthOverrideDays ?? $0.lengthDays }
        guard let latestLength = completedLengths.last else {
            throw PredictionParsingError.missingPrediction
        }

        let payload: [String: Any] = [
            "latestCycleLengthDays": latestLength,
            "weightTrendDelta": weightTrendDelta ?? 0,
            "activityLevelAverage": activityLevelAverage ?? 0,
            "supplementAdherencePercent": supplementAdherencePercent ?? 0,
            "averageSymptomSeverity": averageSymptomSeverity ?? 0,
        ]
        let provider = try MLDictionaryFeatureProvider(dictionary: payload)
        let output = try model.prediction(from: provider)

        guard let predictedLength = extractPredictedLength(from: output) else {
            throw PredictionParsingError.missingPrediction
        }

        let confidence = extractDouble(
            from: output,
            keys: ["confidence", "predictionConfidence"],
            fallback: 0.6
        )
        let earliest = extractInt(
            from: output,
            keys: ["earliestLengthDays", "minLengthDays"],
            fallback: predictedLength - 3
        ) ?? (predictedLength - 3)
        let latest = extractInt(
            from: output,
            keys: ["latestLengthDays", "maxLengthDays"],
            fallback: predictedLength + 3
        ) ?? (predictedLength + 3)

        let clampedPrediction = min(max(predictedLength, 15), 120)
        let clampedEarliest = min(max(min(earliest, latest), 15), 120)
        let clampedLatest = min(max(max(earliest, latest), 15), 120)

        return CycleLengthRangeForecast(
            predictedLengthDays: clampedPrediction,
            earliestLengthDays: clampedEarliest,
            latestLengthDays: clampedLatest,
            confidence: min(max(confidence, 0.3), 0.95)
        )
    }

    private func extractPredictedLength(from output: MLFeatureProvider) -> Int? {
        if let explicit = extractInt(from: output, keys: ["predictedLengthDays", "prediction", "output"], fallback: nil) {
            return explicit
        }
        for name in output.featureNames.sorted() {
            guard let value = output.featureValue(for: name) else { continue }
            if value.type == .int64 {
                return Int(value.int64Value)
            }
            if value.type == .double {
                return Int(round(value.doubleValue))
            }
        }
        return nil
    }

    private func extractInt(
        from output: MLFeatureProvider,
        keys: [String],
        fallback: Int?
    ) -> Int? {
        for key in keys {
            guard let value = output.featureValue(for: key) else { continue }
            if value.type == .int64 {
                return Int(value.int64Value)
            }
            if value.type == .double {
                return Int(round(value.doubleValue))
            }
        }
        return fallback
    }

    private func extractDouble(
        from output: MLFeatureProvider,
        keys: [String],
        fallback: Double
    ) -> Double {
        for key in keys {
            guard let value = output.featureValue(for: key) else { continue }
            if value.type == .double {
                return value.doubleValue
            }
            if value.type == .int64 {
                return Double(value.int64Value)
            }
        }
        return fallback
    }
}

struct CycleForecastFeatureInput {
    let weightTrendDelta: Double?
    let activityLevelAverage: Double?
    let supplementAdherencePercent: Double?
    let averageSymptomSeverity: Double?
}

struct PredictiveFeaturePipeline {
    private let calendar = Calendar.current
    private let phaseInferencePolicy = CyclePhaseInferencePolicy()

    func buildSymptomFeatureVector(
        now: Date = Date(),
        cycles: [Cycle],
        dailyLogs: [DailyLog],
        meals: [MealEntry],
        supplementLogs: [SupplementLog],
        bloodSugarReadings: [BloodSugarReading]
    ) -> SymptomForecastFeatureVector? {
        guard !cycles.isEmpty
                || !dailyLogs.isEmpty
                || !meals.isEmpty
                || !supplementLogs.isEmpty
                || !bloodSugarReadings.isEmpty else {
            return nil
        }

        let sevenDayStart = startOfDay(daysBack: 6, from: now)

        let recentLogs = dailyLogs.filter { $0.date >= sevenDayStart }
        let recentMeals = meals.filter { $0.timestamp >= sevenDayStart }
        let recentSupplements = supplementLogs.filter { $0.date >= sevenDayStart }
        let recentGlucose = bloodSugarReadings.filter { $0.timestamp >= sevenDayStart }

        let sleepAverage = average(recentLogs.compactMap(\.sleepHours)) ?? 7.0
        let activityAverage = average(recentLogs.compactMap { $0.activeMinutes.map(Double.init) }) ?? 30.0
        let stressAverage = average(recentLogs.compactMap { $0.stressLevel.map(Double.init) }) ?? 3.0

        let mealGIScore = average(recentMeals.map { entry in
            switch entry.glycemicImpact {
            case .low: 1.0
            case .medium: 1.5
            case .high: 2.0
            }
        }) ?? 1.5

        let supplementAdherence = adherencePercent(recentSupplements)
            ?? adherencePercent(supplementLogs)
            ?? 70.0

        let glucoseAverage = average(recentGlucose.map(\.glucoseValue))
        let phase = phaseInferencePolicy.approximatePhase(
            for: now,
            cycles: cycles,
            calendar: calendar
        )

        return SymptomForecastFeatureVector(
            sleepHours7DayAverage: sleepAverage,
            activityMinutes7DayAverage: activityAverage,
            mealGIScore7DayAverage: mealGIScore,
            supplementAdherencePercent: supplementAdherence,
            stressLevelAverage: stressAverage,
            cyclePhase: phase,
            bloodSugar7DayAverage: glucoseAverage
        )
    }

    func buildCycleForecastInput(
        now: Date = Date(),
        cycles: [Cycle],
        dailyLogs: [DailyLog],
        supplementLogs: [SupplementLog],
        symptoms: [SymptomEntry]
    ) -> CycleForecastFeatureInput? {
        let completedCycleCount = cycles.filter { !$0.isPredicted && ($0.manualCycleLengthOverrideDays != nil || $0.lengthDays != nil) }.count
        guard completedCycleCount > 0 else { return nil }

        let thirtyDayStart = startOfDay(daysBack: 29, from: now)
        let logs30d = dailyLogs.filter { $0.date >= thirtyDayStart }
        let supplements30d = supplementLogs.filter { $0.date >= thirtyDayStart }
        let symptoms30d = symptoms.filter { $0.date >= thirtyDayStart }

        let weightedLogs = logs30d
            .compactMap { log -> (date: Date, weight: Double)? in
                guard let weight = log.weight else { return nil }
                return (date: log.date, weight: weight)
            }
            .sorted { $0.date < $1.date }

        let weightTrendDelta: Double? = if let first = weightedLogs.first, let last = weightedLogs.last, weightedLogs.count >= 2 {
            last.weight - first.weight
        } else {
            nil
        }

        let activityAverage = average(logs30d.compactMap { $0.activeMinutes.map(Double.init) })
        let supplementAdherence = adherencePercent(supplements30d)
        let symptomSeverityAverage = average(symptoms30d.map { Double($0.severity) })

        return CycleForecastFeatureInput(
            weightTrendDelta: weightTrendDelta,
            activityLevelAverage: activityAverage,
            supplementAdherencePercent: supplementAdherence,
            averageSymptomSeverity: symptomSeverityAverage
        )
    }

    private func startOfDay(daysBack: Int, from date: Date) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -daysBack, to: dayStart) ?? dayStart
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func adherencePercent(_ logs: [SupplementLog]) -> Double? {
        guard !logs.isEmpty else { return nil }
        let takenCount = logs.filter(\.taken).count
        return (Double(takenCount) / Double(logs.count)) * 100
    }

}

private enum PredictionParsingError: Error {
    case missingPrediction
}
