import SwiftData

@MainActor
struct SettingsDataDeletionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func deleteAllData() throws {
        try modelContext.delete(model: CycleEntry.self)
        try modelContext.delete(model: Cycle.self)
        try modelContext.delete(model: SymptomEntry.self)
        try modelContext.delete(model: Insight.self)
        try modelContext.delete(model: BloodSugarReading.self)
        try modelContext.delete(model: SupplementLog.self)
        try modelContext.delete(model: MealEntry.self)
        try modelContext.delete(model: HairPhotoEntry.self)
        try modelContext.delete(model: DailyLog.self)
        try modelContext.save()
    }
}
