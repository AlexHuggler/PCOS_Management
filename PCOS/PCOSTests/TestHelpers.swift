import Testing
import Foundation
import SwiftData
@testable import PCOS

@MainActor
enum TestHelpers {
    /// Creates an in-memory ModelContainer for testing.
    static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
            Insight.self,
            BloodSugarReading.self,
            SupplementLog.self,
            MealEntry.self,
            HairPhotoEntry.self,
            DailyLog.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
