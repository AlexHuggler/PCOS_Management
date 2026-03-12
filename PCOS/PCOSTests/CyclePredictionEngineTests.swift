import Testing
import Foundation
@testable import PCOS

@Suite("Cycle Prediction Engine")
struct CyclePredictionEngineTests {
    let engine = CyclePredictionEngine()

    @Test("Returns nil with no completed cycles")
    func noPredictionWithoutData() {
        let result = engine.predictNextPeriod(cycles: [], lastPeriodStart: Date())
        #expect(result == nil)
    }

    @Test("Returns nil when cycles have no length data")
    func noPredictionWithoutLengths() {
        let cycles = [Cycle(startDate: Date())]
        let result = engine.predictNextPeriod(cycles: cycles, lastPeriodStart: Date())
        #expect(result == nil)
    }

    @Test("Prediction window is at least 5 days for PCOS")
    func minimumWindowForPCOS() throws {
        // Create cycles with identical lengths (zero variance)
        let cycles = (0..<3).map { i in
            let cycle = Cycle(startDate: Date().addingTimeInterval(TimeInterval(-28 * (3 - i) * 86400)))
            cycle.lengthDays = 28
            cycle.endDate = cycle.startDate.addingTimeInterval(28 * 86400)
            return cycle
        }
        let prediction = engine.predictNextPeriod(cycles: cycles, lastPeriodStart: Date())
        let window = try #require(prediction).windowDays
        #expect(window >= 5, "PCOS minimum window should be 5 days")
    }

    @Test("Confidence never exceeds 0.9")
    func confidenceCapped() throws {
        let cycles = (0..<10).map { i in
            let cycle = Cycle(startDate: Date().addingTimeInterval(TimeInterval(-28 * (10 - i) * 86400)))
            cycle.lengthDays = 28
            cycle.endDate = cycle.startDate.addingTimeInterval(28 * 86400)
            return cycle
        }
        let prediction = engine.predictNextPeriod(cycles: cycles, lastPeriodStart: Date())
        let confidence = try #require(prediction).confidence
        #expect(confidence <= 0.9)
    }

    @Test("Statistics computed correctly")
    func cycleStatistics() throws {
        let lengths = [25, 28, 30]
        let cycles = lengths.enumerated().map { i, len in
            let cycle = Cycle(startDate: Date().addingTimeInterval(TimeInterval(-len * (3 - i) * 86400)))
            cycle.lengthDays = len
            cycle.endDate = cycle.startDate.addingTimeInterval(TimeInterval(len * 86400))
            return cycle
        }
        let stats = try #require(engine.cycleStatistics(cycles: cycles))
        #expect(stats.shortestLength == 25)
        #expect(stats.longestLength == 30)
        #expect(stats.totalCycles == 3)
    }

    @Test("Statistics returns nil with no completed cycles")
    func noStatisticsWithoutData() {
        let result = engine.cycleStatistics(cycles: [])
        #expect(result == nil)
    }

    @Test("Predicted cycles are excluded from statistics")
    func predictedCyclesExcluded() {
        let cycle = Cycle(startDate: Date(), isPredicted: true)
        cycle.lengthDays = 28
        let result = engine.cycleStatistics(cycles: [cycle])
        #expect(result == nil)
    }
}
