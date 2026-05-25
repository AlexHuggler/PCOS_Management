import Testing
import Foundation
@testable import PCOS

@Suite("Ovulation Prediction Service")
struct OvulationPredictionServiceTests {
    private let calendar = Calendar.current

    @Test("LH peak observations narrow the fertile window")
    func lhPeakNarrowsPrediction() {
        let cycleStart = Date(timeIntervalSince1970: 1_715_000_000)
        let currentCycle = Cycle(startDate: cycleStart, ovulationStatus: .ovulatory)
        let history = [
            makeCompletedCycle(startDate: cycleStart.addingTimeInterval(-90 * 86_400), lengthDays: 34),
            makeCompletedCycle(startDate: cycleStart.addingTimeInterval(-55 * 86_400), lengthDays: 33),
            makeCompletedCycle(startDate: cycleStart.addingTimeInterval(-21 * 86_400), lengthDays: 35),
            currentCycle,
        ]
        let observations = [
            OvulationObservation(
                date: calendar.date(byAdding: .day, value: 12, to: cycleStart)!,
                lhTestResult: .peak
            )
        ]

        let prediction = OvulationPredictionService(calendar: calendar).prediction(
            for: currentCycle,
            cycleHistory: history,
            observations: observations
        )

        #expect(prediction?.source == .lhPeak)
        #expect(dayDelta(from: cycleStart, to: prediction?.predictedOvulationDate) == 13)
        #expect(prediction?.confidence ?? 0 > 0.8)
    }

    @Test("Observed temperature shifts can identify ovulation more precisely")
    func temperatureShiftIdentifiesOvulation() {
        let cycleStart = Date(timeIntervalSince1970: 1_715_500_000)
        let currentCycle = Cycle(startDate: cycleStart, ovulationStatus: .ovulatory)
        let observations = [
            makeTemperatureObservation(dayOffset: 6, cycleStart: cycleStart, temperature: 36.30),
            makeTemperatureObservation(dayOffset: 7, cycleStart: cycleStart, temperature: 36.28),
            makeTemperatureObservation(dayOffset: 8, cycleStart: cycleStart, temperature: 36.31),
            makeTemperatureObservation(dayOffset: 9, cycleStart: cycleStart, temperature: 36.33),
            makeTemperatureObservation(dayOffset: 10, cycleStart: cycleStart, temperature: 36.56),
            makeTemperatureObservation(dayOffset: 11, cycleStart: cycleStart, temperature: 36.59),
            makeTemperatureObservation(dayOffset: 12, cycleStart: cycleStart, temperature: 36.62),
        ]

        let prediction = OvulationPredictionService(calendar: calendar).prediction(
            for: currentCycle,
            cycleHistory: [currentCycle],
            observations: observations
        )

        #expect(prediction?.source == .temperatureShift)
        #expect(dayDelta(from: cycleStart, to: prediction?.predictedOvulationDate) == 9)
        #expect(prediction?.confidence ?? 0 > 0.9)
    }

    @Test("Irregular cycle history widens history-based fertile windows")
    func irregularCyclesWidenPredictionWindow() {
        let cycleStart = Date(timeIntervalSince1970: 1_716_000_000)
        let regularCycle = Cycle(startDate: cycleStart, ovulationStatus: .ovulatory)
        regularCycle.manualCycleLengthOverrideDays = 31

        let irregularCycle = Cycle(startDate: cycleStart, ovulationStatus: .unknown)
        irregularCycle.manualCycleLengthOverrideDays = 46

        let regularHistory = [
            makeCompletedCycle(startDate: cycleStart.addingTimeInterval(-93 * 86_400), lengthDays: 30),
            makeCompletedCycle(startDate: cycleStart.addingTimeInterval(-63 * 86_400), lengthDays: 31),
            makeCompletedCycle(startDate: cycleStart.addingTimeInterval(-32 * 86_400), lengthDays: 32),
            regularCycle,
        ]

        let irregularHistory = [
            makeCompletedCycle(startDate: cycleStart.addingTimeInterval(-150 * 86_400), lengthDays: 28),
            makeCompletedCycle(startDate: cycleStart.addingTimeInterval(-104 * 86_400), lengthDays: 46),
            makeCompletedCycle(startDate: cycleStart.addingTimeInterval(-43 * 86_400), lengthDays: 61),
            irregularCycle,
        ]

        let service = OvulationPredictionService(calendar: calendar)
        let regularPrediction = service.prediction(for: regularCycle, cycleHistory: regularHistory, observations: [])
        let irregularPrediction = service.prediction(for: irregularCycle, cycleHistory: irregularHistory, observations: [])

        #expect(windowLength(for: irregularPrediction) > windowLength(for: regularPrediction))
        #expect((irregularPrediction?.confidence ?? 1) < (regularPrediction?.confidence ?? 0))
    }

    @Test("Anovulatory cycles suppress fertile window predictions")
    func anovulatoryCyclesSuppressPrediction() {
        let cycleStart = Date(timeIntervalSince1970: 1_716_500_000)
        let currentCycle = Cycle(startDate: cycleStart, ovulationStatus: .anovulatory)
        let history = [
            makeCompletedCycle(startDate: cycleStart.addingTimeInterval(-90 * 86_400), lengthDays: 38),
            currentCycle,
        ]

        let prediction = OvulationPredictionService(calendar: calendar).prediction(
            for: currentCycle,
            cycleHistory: history,
            observations: []
        )

        #expect(prediction == nil)
    }
}

private extension OvulationPredictionServiceTests {
    func makeCompletedCycle(startDate: Date, lengthDays: Int) -> Cycle {
        Cycle(
            startDate: startDate,
            endDate: calendar.date(byAdding: .day, value: lengthDays, to: startDate),
            lengthDays: lengthDays,
            ovulationStatus: .ovulatory
        )
    }

    func makeTemperatureObservation(dayOffset: Int, cycleStart: Date, temperature: Double) -> OvulationObservation {
        OvulationObservation(
            date: calendar.date(byAdding: .day, value: dayOffset, to: cycleStart)!,
            basalBodyTemperatureCelsius: temperature
        )
    }

    func dayDelta(from startDate: Date, to endDate: Date?) -> Int? {
        guard let endDate else { return nil }
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: startDate),
            to: calendar.startOfDay(for: endDate)
        ).day
    }

    func windowLength(for prediction: OvulationPrediction?) -> Int {
        guard let prediction else { return 0 }
        return calendar.dateComponents([.day], from: prediction.fertileWindowStart, to: prediction.fertileWindowEnd).day ?? 0
    }
}
