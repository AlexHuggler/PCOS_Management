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
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("InsightEngine: Failed to fetch \(stage.rawValue): \(error.localizedDescription)")
            throw InsightEngineError.fetchFailed(stage: stage, underlying: error)
        }
    }
}
