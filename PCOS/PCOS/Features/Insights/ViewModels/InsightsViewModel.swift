import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class InsightsViewModel {
    typealias InsightsGenerator = () throws -> [Insight]

    private let modelContext: ModelContext
    private let generateInsights: InsightsGenerator

    var insights: [Insight] = []
    var isGenerating = false
    var errorMessage: String?

    init(
        modelContext: ModelContext,
        insightGenerator: InsightsGenerator? = nil
    ) {
        self.modelContext = modelContext
        if let insightGenerator {
            self.generateInsights = insightGenerator
        } else {
            let engine = InsightEngine(modelContext: modelContext)
            self.generateInsights = { try engine.generateInsights() }
        }
    }

    /// Generate new insights via the engine, persist them, and refresh the local list.
    func refreshInsights() async {
        isGenerating = true
        defer { isGenerating = false }
        errorMessage = nil

        do {
            let newInsights = try generateInsights()
            for insight in newInsights {
                modelContext.insert(insight)
            }
            try modelContext.save()
            Logger.database.info("InsightsViewModel: Saved \(newInsights.count) new insights")
            fetchExistingInsights()
        } catch {
            modelContext.rollback()
            Logger.database.error("InsightsViewModel: Failed to refresh insights: \(error.localizedDescription)")
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    /// Load all persisted insights, sorted by generatedDate descending.
    func fetchExistingInsights() {
        let descriptor = FetchDescriptor<Insight>(
            sortBy: [SortDescriptor(\.generatedDate, order: .reverse)]
        )
        do {
            insights = try modelContext.fetch(descriptor)
            errorMessage = nil
        } catch {
            Logger.database.error("InsightsViewModel: Failed to fetch insights: \(error.localizedDescription)")
            insights = []
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return "Couldn't refresh insights right now. Please try again."
    }
}
