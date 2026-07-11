import Foundation
import SwiftData
import Testing
@testable import PCOS

@Suite("Repeat Meal Cache", .serialized)
@MainActor
struct RepeatMealCacheTests {
    private static let riceDraft = MealFoodItemDraft(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        displayName: "White rice",
        canonicalFoodId: "rice-white-cooked",
        nutritionSource: .usda,
        estimatedGrams: 150,
        estimatedVolumeMl: 180,
        servingDescription: "1 cup cooked",
        nutrition: NutritionSnapshot(
            caloriesKcal: 195,
            proteinGrams: 4.1,
            carbsGrams: 42.3,
            fatGrams: 0.5
        ),
        confidence: .medium,
        warning: "Review portion.",
        detectionSource: "gemini",
        portionEstimationMethod: .servingSizeHeuristic,
        wasUserEdited: true,
        isMixedDish: false
    )

    private static let snapshot = RepeatMealDraftSnapshot(
        mealName: "Chicken rice bowl",
        mealType: .lunch,
        items: [riceDraft],
        nutrition: NutritionSnapshot(
            caloriesKcal: 540,
            proteinGrams: 32,
            carbsGrams: 61,
            fatGrams: 17
        ),
        confidence: .medium,
        warnings: ["Review the sauce amount."],
        hiddenIngredientEstimate: .aLittle,
        source: RepeatMealSourceMetadata(
            modelVersion: "gemini-2.5-flash-lite",
            pipelineVersion: "meal-scan-v2"
        )
    )

    @Test("versioned repeat draft snapshot round trips reviewed state")
    func snapshotRoundTrips() throws {
        let data = try JSONEncoder().encode(Self.snapshot)
        let decoded = try JSONDecoder().decode(RepeatMealDraftSnapshot.self, from: data)

        #expect(decoded == Self.snapshot)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.items.first?.nutritionSource == .usda)
        #expect(decoded.items.first?.detectionSource == "gemini")
        #expect(decoded.items.first?.portionEstimationMethod == .servingSizeHeuristic)
    }

    @Test("reuse drafts preserve provenance and receive fresh IDs")
    func reuseDraftsHaveFreshIDs() throws {
        let reusedItems = Self.snapshot.makeDraftItemsForReuse()
        let reused = try #require(reusedItems.first)

        #expect(reused.id != Self.riceDraft.id)
        #expect(reused.nutritionSource == Self.riceDraft.nutritionSource)
        #expect(reused.detectionSource == Self.riceDraft.detectionSource)
        #expect(reused.portionEstimationMethod == Self.riceDraft.portionEstimationMethod)
        #expect(reused.canonicalFoodId == Self.riceDraft.canonicalFoodId)
    }

    @Test("repeat cache record inserts and fetches through the test container")
    func cacheRecordPersists() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let snapshotJSON = String(data: try JSONEncoder().encode(Self.snapshot), encoding: .utf8)!
        let sourceMealID = UUID()
        let record = MealScanRepeatCacheRecord(
            sourceMealID: sourceMealID,
            sourceImageHash: "sha256-image",
            featurePrintArchive: Data([0x01, 0x02]),
            visionRevision: 2,
            snapshotJSON: snapshotJSON,
            snapshotSchemaVersion: 1,
            mealName: "Chicken rice bowl",
            mealType: .lunch,
            caloriesKcal: 540,
            proteinGrams: 32,
            carbsGrams: 61,
            fatGrams: 17,
            sourceMealLoggedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )

        context.insert(record)
        try context.save()

        let fetched = try #require(context.fetch(FetchDescriptor<MealScanRepeatCacheRecord>()).first)
        #expect(fetched.sourceMealID == sourceMealID)
        #expect(fetched.snapshotSchemaVersion == RepeatMealDraftSnapshot.currentSchemaVersion)
        #expect(fetched.mealType == .lunch)
        #expect(fetched.reuseCount == 0)
        #expect(fetched.lastMatchedAt == nil)
    }

    @Test("optional CloudKit configuration excludes the local repeat cache schema")
    func cloudKitSchemaExcludesRepeatCache() throws {
        let configuration = CycleBalanceApp.makeCloudKitConfiguration(
            schema: CycleBalanceApp.primarySchema
        )
        let configurationSchema = try #require(configuration.schema)
        let entityNames = Set(configurationSchema.entities.map(\.name))

        #expect(entityNames.contains(String(describing: MealEntry.self)))
        #expect(!entityNames.contains(String(describing: MealScanRepeatCacheRecord.self)))
    }
}
