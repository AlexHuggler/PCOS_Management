import SwiftUI
import SwiftData

@main
struct CycleBalanceApp: App {
    var sharedModelContainer: ModelContainer = {
        // Only include models that have active UI. Unused models
        // (BloodSugarReading, SupplementLog, MealEntry, HairPhotoEntry,
        // DailyLog) are kept as source files for future features but
        // excluded from the schema to avoid empty CloudKit tables.
        let schema = Schema([
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
            Insight.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.cyclebalance.app")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
