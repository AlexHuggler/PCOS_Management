import Testing
import Foundation
@testable import PCOS

@Suite("Policy and Analytics Services")
struct PolicyAndAnalyticsServiceTests {
    private struct NilModelLoader: CoreMLModelLoading {
        func loadSymptomSeverityModel() -> Any? { nil }
        func loadCycleLengthModel() -> Any? { nil }
    }

    private struct InvalidModelLoader: CoreMLModelLoading {
        func loadSymptomSeverityModel() -> Any? { "invalid-model-object" }
        func loadCycleLengthModel() -> Any? { "invalid-model-object" }
    }

    @Test("Symptom saves are unlimited for free users")
    func freeTierSymptomCap() {
        let policy = FreeTierPolicyService(
            symptomDailyLimit: nil,
            cycleHistoryDays: 30,
            symptomHistoryDays: nil
        )

        #expect(policy.isSymptomSaveAllowed(selectedCount: 5, isPremium: false))
        #expect(policy.isSymptomSaveAllowed(selectedCount: 50, isPremium: false))
        #expect(policy.isSymptomSaveAllowed(selectedCount: 12, isPremium: true))
    }

    @Test("Free tier keeps cycle history limited while symptom history stays open")
    func freeTierHistoryWindow() throws {
        let policy = FreeTierPolicyService(
            symptomDailyLimit: nil,
            cycleHistoryDays: 30,
            symptomHistoryDays: nil
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let earliest = try #require(policy.earliestAccessibleCycleHistoryDate(now: now, isPremium: false))
        let expected = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: now))
        #expect(earliest == expected)
        #expect(policy.earliestAccessibleCycleHistoryDate(now: now, isPremium: true) == nil)
        #expect(policy.earliestAccessibleSymptomHistoryDate(now: now, isPremium: false) == nil)
        #expect(policy.earliestAccessibleSymptomHistoryDate(now: now, isPremium: true) == nil)
        #expect(policy.isCycleDateAccessible(expected ?? now, now: now, isPremium: false))
        #expect(!policy.isCycleDateAccessible((expected ?? now).addingTimeInterval(-86_400), now: now, isPremium: false))
    }

    @Test("Insulin resistance service pairs before and after meal spikes")
    func postMealSpikePairing() throws {
        let service = InsulinResistanceMetricService()
        let now = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 3, day: 19, hour: 12, minute: 0)
            )
        )

        let before = BloodSugarReading(
            timestamp: now,
            glucoseValue: 100,
            readingType: .beforeMeal,
            mealContext: "Lunch"
        )
        let after = BloodSugarReading(
            timestamp: now.addingTimeInterval(60 * 60),
            glucoseValue: 148,
            readingType: .afterMeal,
            mealContext: "Lunch"
        )

        let spikes = service.postMealSpikeSamples(readings: [before, after])
        #expect(spikes.count == 1)
        let firstSpike = try #require(spikes.first)
        #expect(Int(firstSpike.spike.rounded()) == 48)
    }

    @Test("Baseline symptom forecaster returns 7-day output")
    func baselineSymptomForecastShape() {
        let forecaster = BaselineSymptomSeverityForecaster()
        let forecast = forecaster.forecast(
            using: SymptomForecastFeatureVector(
                sleepHours7DayAverage: 6.5,
                activityMinutes7DayAverage: 32,
                mealGIScore7DayAverage: 1.6,
                supplementAdherencePercent: 75,
                stressLevelAverage: 3.2,
                cyclePhase: .luteal,
                bloodSugar7DayAverage: 132
            ),
            historicalSymptoms: []
        )

        #expect(forecast.dailyPredictions.count == 7)
        #expect(forecast.dailyPredictions.allSatisfy { (1...5).contains(Int($0.rounded())) })
    }

    @Test("Baseline cycle-length forecaster uses override-aware cycle lengths")
    func baselineCycleLengthForecast() {
        let forecaster = BaselineCycleLengthForecaster()
        let cycles = [
            Cycle(startDate: Date().addingTimeInterval(-90 * 86_400), endDate: Date().addingTimeInterval(-60 * 86_400), lengthDays: 30, isPredicted: false),
            Cycle(startDate: Date().addingTimeInterval(-60 * 86_400), endDate: Date().addingTimeInterval(-32 * 86_400), lengthDays: 28, isPredicted: false, manualCycleLengthOverrideDays: 27),
            Cycle(startDate: Date().addingTimeInterval(-32 * 86_400), endDate: Date().addingTimeInterval(-3 * 86_400), lengthDays: 29, isPredicted: false),
        ]

        let forecast = forecaster.forecast(
            cycles: cycles,
            weightTrendDelta: nil,
            activityLevelAverage: 35,
            supplementAdherencePercent: 82,
            averageSymptomSeverity: 2.4
        )

        #expect(forecast != nil)
        #expect((forecast?.earliestLengthDays ?? 0) <= (forecast?.predictedLengthDays ?? 0))
        #expect((forecast?.latestLengthDays ?? 0) >= (forecast?.predictedLengthDays ?? 0))
    }

    @Test("Predictive feature pipeline builds deterministic symptom and cycle inputs")
    func predictiveFeaturePipelineOutputs() throws {
        let pipeline = PredictiveFeaturePipeline()
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let calendar = Calendar.current

        let cycles = [
            Cycle(
                startDate: calendar.date(byAdding: .day, value: -40, to: now) ?? now,
                endDate: calendar.date(byAdding: .day, value: -10, to: now) ?? now,
                lengthDays: 30,
                isPredicted: false
            ),
        ]

        let dailyLogs: [DailyLog] = (0..<7).compactMap { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            return DailyLog(
                date: date,
                weight: 70.0 + Double(offset) * 0.1,
                sleepHours: 7.0,
                activeMinutes: 35,
                restingHeartRateBPM: 62,
                stressLevel: 3
            )
        }

        let meals: [MealEntry] = (0..<7).compactMap { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            return MealEntry(
                timestamp: date,
                mealType: .lunch,
                mealDescription: "Test",
                glycemicImpact: offset.isMultiple(of: 2) ? .high : .low
            )
        }

        let supplements: [SupplementLog] = (0..<7).compactMap { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            return SupplementLog(
                date: date,
                supplementName: "Inositol",
                timeTaken: date,
                taken: !offset.isMultiple(of: 3)
            )
        }

        let readings: [BloodSugarReading] = (0..<4).compactMap { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            return BloodSugarReading(
                timestamp: date,
                glucoseValue: 110 + Double(offset * 5),
                readingType: .random
            )
        }

        let symptoms: [SymptomEntry] = (0..<10).compactMap { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            return SymptomEntry(date: date, type: .fatigue, severity: 2 + (offset % 3))
        }

        let symptomFeatures = try #require(
            pipeline.buildSymptomFeatureVector(
                now: now,
                cycles: cycles,
                dailyLogs: dailyLogs,
                meals: meals,
                supplementLogs: supplements,
                bloodSugarReadings: readings
            )
        )
        #expect((1...2).contains(Int(symptomFeatures.mealGIScore7DayAverage.rounded())))
        #expect(symptomFeatures.supplementAdherencePercent > 0)

        let cycleFeatures = try #require(
            pipeline.buildCycleForecastInput(
                now: now,
                cycles: cycles,
                dailyLogs: dailyLogs,
                supplementLogs: supplements,
                symptoms: symptoms
            )
        )
        #expect(cycleFeatures.activityLevelAverage != nil)
        #expect(cycleFeatures.supplementAdherencePercent != nil)
    }

    @Test("Predictive feature pipeline suppresses phase features for long unknown cycles")
    func predictiveFeaturePipelineSuppressesUnsafePhaseInference() throws {
        let pipeline = PredictiveFeaturePipeline()
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let calendar = Calendar.current

        let cycles = [
            Cycle(
                startDate: calendar.date(byAdding: .day, value: -60, to: now) ?? now,
                endDate: calendar.date(byAdding: .day, value: -10, to: now) ?? now,
                lengthDays: 50,
                isPredicted: false,
                ovulationStatus: .unknown
            ),
        ]

        let features = try #require(
            pipeline.buildSymptomFeatureVector(
                now: now,
                cycles: cycles,
                dailyLogs: [],
                meals: [],
                supplementLogs: [],
                bloodSugarReadings: []
            )
        )

        #expect(features.cyclePhase == nil)
    }

    @Test("Core ML symptom forecaster falls back when model is missing or invalid")
    func coreMLSymptomFallbackBehavior() {
        let features = SymptomForecastFeatureVector(
            sleepHours7DayAverage: 6.8,
            activityMinutes7DayAverage: 30,
            mealGIScore7DayAverage: 1.6,
            supplementAdherencePercent: 78,
            stressLevelAverage: 3.4,
            cyclePhase: .luteal,
            bloodSugar7DayAverage: 128
        )
        let symptoms = [SymptomEntry(date: Date(), type: .fatigue, severity: 3)]

        let missingModelForecaster = CoreMLSymptomSeverityForecaster(modelLoader: NilModelLoader())
        let missingForecast = missingModelForecaster.forecast(using: features, historicalSymptoms: symptoms)
        #expect(missingForecast.dailyPredictions.count == 7)

        let invalidModelForecaster = CoreMLSymptomSeverityForecaster(modelLoader: InvalidModelLoader())
        let invalidForecast = invalidModelForecaster.forecast(using: features, historicalSymptoms: symptoms)
        #expect(invalidForecast.dailyPredictions.count == 7)
    }

    @Test("Core ML cycle forecaster falls back when model is missing or invalid")
    func coreMLCycleFallbackBehavior() {
        let cycles = [
            Cycle(
                startDate: Date().addingTimeInterval(-90 * 86_400),
                endDate: Date().addingTimeInterval(-60 * 86_400),
                lengthDays: 30,
                isPredicted: false
            ),
            Cycle(
                startDate: Date().addingTimeInterval(-60 * 86_400),
                endDate: Date().addingTimeInterval(-31 * 86_400),
                lengthDays: 29,
                isPredicted: false
            ),
        ]

        let missingModelForecaster = CoreMLCycleLengthForecaster(modelLoader: NilModelLoader())
        let missingForecast = missingModelForecaster.forecast(
            cycles: cycles,
            weightTrendDelta: 0.5,
            activityLevelAverage: 40,
            supplementAdherencePercent: 85,
            averageSymptomSeverity: 2.5
        )
        #expect(missingForecast != nil)

        let invalidModelForecaster = CoreMLCycleLengthForecaster(modelLoader: InvalidModelLoader())
        let invalidForecast = invalidModelForecaster.forecast(
            cycles: cycles,
            weightTrendDelta: 0.5,
            activityLevelAverage: 40,
            supplementAdherencePercent: 85,
            averageSymptomSeverity: 2.5
        )
        #expect(invalidForecast != nil)
    }
}
