import Foundation
import SwiftData
import os

@MainActor
struct InsightDataFetcher {
    let modelContext: ModelContext

    func fetch<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        stage: InsightEngineStage
    ) throws -> [T] {
        do {
            let records = try modelContext.fetch(descriptor)
            let days: Int
            switch stage {
            case .supplementEfficacy, .supplementEfficacySymptoms, .supplementEfficacyCycles:
                days = InsightAnalysisPolicy.supplementHistoryDays
            case .seasonalPatterns, .seasonalPatternSymptoms: days = 365
            case .symptomCorrelations: days = InsightAnalysisPolicy.symptomDays
            default: days = InsightAnalysisPolicy.lifestyleDays
            }
            return records.filter { record in
                let date: Date?
                switch record {
                case let value as Cycle where stage == .supplementEfficacyCycles: date = value.startDate
                case let value as SymptomEntry: date = value.date
                case let value as DailyLog: date = value.date
                case let value as MealEntry: date = value.timestamp
                case let value as SupplementLog: date = value.date
                case let value as BloodSugarReading: date = value.timestamp
                case let value as HealthKitImportedSampleRecord: date = value.startDate
                default: date = nil // Cycle history and derived snapshot are not truncated.
                }
                return date.map { InsightAnalysisPolicy.includes($0, days: days) } ?? true
            }
        } catch {
            Logger.database.error("InsightEngine: Failed to fetch \(stage.rawValue): \(error.localizedDescription)")
            throw InsightEngineError.fetchFailed(stage: stage, underlying: error)
        }
    }
}
