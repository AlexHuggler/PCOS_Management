import Testing
import SwiftData
@testable import CycleBalance

@MainActor
enum TestHelpers {
    /// Creates an in-memory ModelContainer for testing.
    static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
            Insight.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
