import Foundation

/// Coordinates cycle prediction/statistics derivation for ViewModels.
struct CyclePredictionService: Sendable {
    private let engine: CyclePredictionEngine

    init(engine: CyclePredictionEngine = CyclePredictionEngine()) {
        self.engine = engine
    }

    func prediction(for cycles: [Cycle]) -> CyclePredictionEngine.Prediction? {
        guard let lastCycle = cycles.last else {
            return nil
        }

        return engine.predictNextPeriod(cycles: cycles, lastPeriodStart: lastCycle.startDate)
    }

    func statistics(for cycles: [Cycle]) -> CycleStatistics? {
        engine.cycleStatistics(cycles: cycles)
    }
}
