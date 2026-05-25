import Foundation

enum CyclePredictionUncertaintyReason: Sendable, Equatable {
    case wideWindow
    case lowConfidence
    case wideWindowAndLowConfidence
}

enum CyclePredictionPresentationState: Sendable {
    case actionable(CyclePredictionEngine.Prediction)
    case uncertain(CyclePredictionEngine.Prediction, reason: CyclePredictionUncertaintyReason)
    case postpartumReEntry
}

/// Coordinates cycle prediction/statistics derivation for ViewModels.
struct CyclePredictionService: Sendable {
    static let minimumActionableConfidence = 0.70
    static let maximumActionableWindowDays = 14

    private let engine: CyclePredictionEngine

    init(engine: CyclePredictionEngine = CyclePredictionEngine()) {
        self.engine = engine
    }

    func prediction(for cycles: [Cycle]) -> CyclePredictionEngine.Prediction? {
        guard let lastCycle = cycles.last else {
            return nil
        }

        if let overrideDays = lastCycle.manualCycleLengthOverrideDays {
            return engine.predictNextPeriod(
                manualCycleLengthOverrideDays: overrideDays,
                cycles: cycles,
                lastPeriodStart: lastCycle.startDate
            )
        }

        return engine.predictNextPeriod(cycles: cycles, lastPeriodStart: lastCycle.startDate)
    }

    func statistics(for cycles: [Cycle]) -> CycleStatistics? {
        engine.cycleStatistics(cycles: cycles)
    }

    func presentation(for prediction: CyclePredictionEngine.Prediction?) -> CyclePredictionPresentationState? {
        guard let prediction else { return nil }

        let hasWideWindow = prediction.windowDays > Self.maximumActionableWindowDays
        let hasLowConfidence = prediction.confidence < Self.minimumActionableConfidence

        guard hasWideWindow || hasLowConfidence else {
            return .actionable(prediction)
        }

        let reason: CyclePredictionUncertaintyReason
        switch (hasWideWindow, hasLowConfidence) {
        case (true, true):
            reason = .wideWindowAndLowConfidence
        case (true, false):
            reason = .wideWindow
        case (false, true):
            reason = .lowConfidence
        case (false, false):
            return .actionable(prediction)
        }

        return .uncertain(prediction, reason: reason)
    }
}
