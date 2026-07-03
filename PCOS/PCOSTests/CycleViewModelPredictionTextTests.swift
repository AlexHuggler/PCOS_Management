import Testing
import Foundation
@testable import PCOS

@Suite("Cycle View Model Prediction Texts", .serialized)
@MainActor
struct CycleViewModelPredictionTextTests {
    private func makeViewModel() throws -> CycleViewModel {
        let container = try TestHelpers.makeModelContainer()
        return CycleViewModel(modelContext: container.mainContext)
    }

    private func makePrediction(
        now: Date,
        earliestOffsetDays: Int,
        latestOffsetDays: Int,
        confidence: Double = 0.85
    ) -> CyclePredictionEngine.Prediction {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let earliest = calendar.date(byAdding: .day, value: earliestOffsetDays, to: today) ?? today
        let latest = calendar.date(byAdding: .day, value: latestOffsetDays, to: today) ?? today
        let center = calendar.date(
            byAdding: .day,
            value: (earliestOffsetDays + latestOffsetDays) / 2,
            to: today
        ) ?? today
        return CyclePredictionEngine.Prediction(
            earliestDate: earliest,
            latestDate: latest,
            centerDate: center,
            confidence: confidence
        )
    }

    @Test("Countdown reads in N days at the window midpoint")
    func countdownMidWindow() throws {
        let now = Date()
        let viewModel = try makeViewModel()
        viewModel.prediction = makePrediction(now: now, earliestOffsetDays: 6, latestOffsetDays: 10)

        #expect(viewModel.predictionCountdownText(now: now) == "in 8 days")
    }

    @Test("Countdown reads today and tomorrow near the midpoint")
    func countdownNearTerm() throws {
        let now = Date()
        let viewModel = try makeViewModel()

        viewModel.prediction = makePrediction(now: now, earliestOffsetDays: -2, latestOffsetDays: 2)
        #expect(viewModel.predictionCountdownText(now: now) == "today")

        viewModel.prediction = makePrediction(now: now, earliestOffsetDays: -1, latestOffsetDays: 3)
        #expect(viewModel.predictionCountdownText(now: now) == "tomorrow")
    }

    @Test("Countdown is nil once the midpoint has passed")
    func countdownNilWhenOverdue() throws {
        let now = Date()
        let viewModel = try makeViewModel()
        viewModel.prediction = makePrediction(now: now, earliestOffsetDays: -8, latestOffsetDays: -4)

        #expect(viewModel.predictionCountdownText(now: now) == nil)
    }

    @Test("Countdown is nil without an actionable prediction")
    func countdownRequiresActionablePrediction() throws {
        let now = Date()
        let viewModel = try makeViewModel()

        #expect(viewModel.predictionCountdownText(now: now) == nil)

        // A wide window downgrades the presentation to uncertain.
        viewModel.prediction = makePrediction(now: now, earliestOffsetDays: 4, latestOffsetDays: 24)
        #expect(viewModel.predictionCountdownText(now: now) == nil)

        // Low confidence does the same.
        viewModel.prediction = makePrediction(now: now, earliestOffsetDays: 6, latestOffsetDays: 10, confidence: 0.4)
        #expect(viewModel.predictionCountdownText(now: now) == nil)
    }

    @Test("Midpoint text includes the spread")
    func midpointTextSpread() throws {
        let now = Date()
        let viewModel = try makeViewModel()
        viewModel.prediction = makePrediction(now: now, earliestOffsetDays: 6, latestOffsetDays: 10)

        let text = try #require(viewModel.predictionMidpointText)
        #expect(text.contains("± 2"))
    }

    @Test("Midpoint text omits the spread for a single-day window")
    func midpointTextSingleDay() throws {
        let now = Date()
        let viewModel = try makeViewModel()
        viewModel.prediction = makePrediction(now: now, earliestOffsetDays: 8, latestOffsetDays: 8)

        let text = try #require(viewModel.predictionMidpointText)
        #expect(!text.contains("±"))
    }
}
