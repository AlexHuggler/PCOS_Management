import Testing
import Foundation
@testable import PCOS

@Suite("Cycle Phase Inference Policy")
struct CyclePhaseInferencePolicyTests {
    private let policy = CyclePhaseInferencePolicy()

    private func makeStableOvulatoryHistory(
        cycleLength: Int = 28,
        count: Int = 4
    ) -> [Cycle] {
        (0..<count).map { index in
            Cycle(
                startDate: Date().addingTimeInterval(TimeInterval(-cycleLength * (count - index) * 86400)),
                lengthDays: cycleLength,
                ovulationStatus: .ovulatory
            )
        }
    }

    // MARK: - approximateOngoingPhase

    @Test("Stable ovulatory history yields phase buckets across the cycle")
    func ongoingPhaseBuckets() {
        let history = makeStableOvulatoryHistory()

        #expect(policy.approximateOngoingPhase(dayInCycle: 1, expectedCycleLength: 28, recentCompletedCycles: history) == .menstrual)
        #expect(policy.approximateOngoingPhase(dayInCycle: 5, expectedCycleLength: 28, recentCompletedCycles: history) == .menstrual)
        #expect(policy.approximateOngoingPhase(dayInCycle: 8, expectedCycleLength: 28, recentCompletedCycles: history) == .follicular)
        #expect(policy.approximateOngoingPhase(dayInCycle: 14, expectedCycleLength: 28, recentCompletedCycles: history) == .ovulatory)
        #expect(policy.approximateOngoingPhase(dayInCycle: 20, expectedCycleLength: 28, recentCompletedCycles: history) == .luteal)
    }

    @Test("Refuses phase for unsupported expected lengths")
    func refusesLongCycles() {
        let history = makeStableOvulatoryHistory(cycleLength: 50)

        #expect(policy.approximateOngoingPhase(dayInCycle: 20, expectedCycleLength: 50, recentCompletedCycles: history) == nil)
        #expect(policy.approximateOngoingPhase(dayInCycle: 20, expectedCycleLength: nil, recentCompletedCycles: history) == nil)
        #expect(policy.approximateOngoingPhase(dayInCycle: 20, expectedCycleLength: 0, recentCompletedCycles: history) == nil)
    }

    @Test("Refuses phase when the cycle runs past its expected length")
    func refusesOverdueCycle() {
        let history = makeStableOvulatoryHistory()

        #expect(policy.approximateOngoingPhase(dayInCycle: 29, expectedCycleLength: 28, recentCompletedCycles: history) == nil)
        #expect(policy.approximateOngoingPhase(dayInCycle: 100, expectedCycleLength: 28, recentCompletedCycles: history) == nil)
    }

    @Test("Refuses phase for unstable cycle lengths")
    func refusesUnstableLengths() {
        let lengths = [21, 40, 24, 44, 27, 45]
        let history = lengths.enumerated().map { index, length in
            Cycle(
                startDate: Date().addingTimeInterval(TimeInterval(-35 * (lengths.count - index) * 86400)),
                lengthDays: length,
                ovulationStatus: .ovulatory
            )
        }

        #expect(policy.approximateOngoingPhase(dayInCycle: 10, expectedCycleLength: 33, recentCompletedCycles: history) == nil)
    }

    @Test("Refuses phase without ovulation evidence in the latest completed cycle")
    func refusesAnovulatoryHistory() {
        var history = makeStableOvulatoryHistory()
        history[history.count - 1].ovulationStatus = .anovulatory

        #expect(policy.approximateOngoingPhase(dayInCycle: 10, expectedCycleLength: 28, recentCompletedCycles: history) == nil)
    }

    @Test("Refuses phase with no completed cycles at all")
    func refusesWithoutHistory() {
        #expect(policy.approximateOngoingPhase(dayInCycle: 10, expectedCycleLength: 28, recentCompletedCycles: []) == nil)
    }

    @Test("Ignores predicted cycles when evaluating history")
    func ignoresPredictedCycles() {
        let predictedOnly = [
            Cycle(startDate: Date(), lengthDays: 28, isPredicted: true, ovulationStatus: .ovulatory)
        ]

        #expect(policy.approximateOngoingPhase(dayInCycle: 10, expectedCycleLength: 28, recentCompletedCycles: predictedOnly) == nil)
    }

    // MARK: - approximatePhase (existing completed-cycle path still works)

    @Test("Completed stable ovulatory cycle still resolves a phase")
    func completedCyclePhase() throws {
        let calendar = Calendar.current
        let currentStart = try #require(
            calendar.date(byAdding: .day, value: -10, to: calendar.startOfDay(for: Date()))
        )

        // Older cycles chained back-to-back so none overlaps the current one.
        var history: [Cycle] = try (1...4).map { index in
            Cycle(
                startDate: try #require(calendar.date(byAdding: .day, value: -28 * index, to: currentStart)),
                lengthDays: 28,
                ovulationStatus: .ovulatory
            )
        }
        history.append(
            Cycle(startDate: currentStart, lengthDays: 28, ovulationStatus: .ovulatory)
        )

        let queryDate = try #require(calendar.date(byAdding: .day, value: 2, to: currentStart))
        let phase = policy.approximatePhase(for: queryDate, cycles: history)
        #expect(phase == .menstrual)
    }
}
