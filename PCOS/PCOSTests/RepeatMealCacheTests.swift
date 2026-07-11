import Foundation
import SwiftData
import Testing
import UIKit
@testable import PCOS

@Suite("Repeat Meal Cache", .serialized)
@MainActor
struct RepeatMealCacheTests {
    private enum ForcedContainerError: Error {
        case completeStoreFailure
    }

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

#if targetEnvironment(simulator)
    @Test(
        "Vision fingerprint archives revision 2 and compares itself",
        .disabled("Vision feature-print requests require a physical device.")
    )
#else
    @Test("Vision fingerprint archives revision 2 and compares itself")
#endif
    func visionFingerprintRoundTripsAndHasZeroSelfDistance() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        }
        let normalized = try MealScanImageNormalizer().normalizeJPEGData(from: image)
        let fingerprinter = VisionRepeatMealImageFingerprinter()
        let fingerprint = try await fingerprinter.makeFingerprint(for: normalized.jpegData)

        #expect(fingerprint.sourceImageHash.count == 64)
        #expect(fingerprint.visionRevision == 2)
        #expect(try await fingerprinter.distance(between: fingerprint, and: fingerprint) < 0.0001)
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

    @Test("primary and complete schemas derive from the canonical primary model list")
    func schemasDeriveFromCanonicalPrimaryModels() {
        let primaryModelNames = Set(
            CycleBalanceApp.primaryModelTypes.map { String(describing: $0) }
        )
        let primarySchemaNames = Set(CycleBalanceApp.primarySchema.entities.map(\.name))
        let completeSchemaNames = Set(CycleBalanceApp.completeSchema.entities.map(\.name))

        #expect(primarySchemaNames == primaryModelNames)
        #expect(
            completeSchemaNames
                == primaryModelNames.union([String(describing: MealScanRepeatCacheRecord.self)])
        )
    }

    @Test("cache recovery preserves a readable primary store and resets only the cache store")
    func cacheRecoveryPreservesPrimaryStore() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepeatMealCacheRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let primaryStoreURL = directoryURL.appendingPathComponent("Primary.sqlite")
        let cacheStoreURL = directoryURL.appendingPathComponent("RepeatCache.sqlite")
        let primaryConfiguration = ModelConfiguration(
            "RepeatMealRecoveryPrimary",
            schema: CycleBalanceApp.primarySchema,
            url: primaryStoreURL,
            cloudKitDatabase: .none
        )
        let cacheConfiguration = ModelConfiguration(
            "RepeatMealRecoveryCache",
            schema: CycleBalanceApp.repeatCacheSchema,
            url: cacheStoreURL,
            cloudKitDatabase: .none
        )

        do {
            let seedContainer = try ModelContainer(
                for: CycleBalanceApp.primarySchema,
                configurations: [primaryConfiguration]
            )
            seedContainer.mainContext.insert(
                MealEntry(
                    timestamp: Date(timeIntervalSince1970: 1_780_000_000),
                    mealType: .lunch,
                    mealDescription: "Preexisting recovery meal",
                    glycemicImpact: .low
                )
            )
            try seedContainer.mainContext.save()
        }

        var containerAttempts = 0
        var attemptedSchemaNames: [Set<String>] = []
        var attemptedConfigurationURLs: [[URL]] = []
        var primaryProbeReadPreexistingMeal = false
        var resetStoreURLs: [URL] = []

        let recoveredContainer = try CycleBalanceApp.makeModelContainerRecoveringCache(
            completeSchema: CycleBalanceApp.completeSchema,
            primarySchema: CycleBalanceApp.primarySchema,
            primaryConfiguration: primaryConfiguration,
            cacheConfiguration: cacheConfiguration,
            containerFactory: { schema, configurations in
                containerAttempts += 1
                attemptedSchemaNames.append(Set(schema.entities.map(\.name)))
                attemptedConfigurationURLs.append(configurations.map(\.url))
                if containerAttempts == 1 {
                    throw ForcedContainerError.completeStoreFailure
                }

                let container = try ModelContainer(
                    for: schema,
                    configurations: configurations
                )
                if containerAttempts == 2 {
                    primaryProbeReadPreexistingMeal = try container.mainContext
                        .fetch(FetchDescriptor<MealEntry>())
                        .contains { $0.mealDescription == "Preexisting recovery meal" }
                }
                return container
            },
            resetStoreFiles: { storeURL in
                resetStoreURLs.append(storeURL)
                try StoreRecovery.backupAndResetStoreFiles(at: storeURL)
            }
        )

        #expect(containerAttempts == 3)
        #expect(
            attemptedSchemaNames == [
                Set(CycleBalanceApp.completeSchema.entities.map(\.name)),
                Set(CycleBalanceApp.primarySchema.entities.map(\.name)),
                Set(CycleBalanceApp.completeSchema.entities.map(\.name)),
            ]
        )
        #expect(
            attemptedConfigurationURLs == [
                [primaryStoreURL, cacheStoreURL],
                [primaryStoreURL],
                [primaryStoreURL, cacheStoreURL],
            ]
        )
        #expect(primaryProbeReadPreexistingMeal)
        #expect(resetStoreURLs == [cacheStoreURL])

        let recoveredMeals = try recoveredContainer.mainContext.fetch(FetchDescriptor<MealEntry>())
        #expect(recoveredMeals.contains { $0.mealDescription == "Preexisting recovery meal" })

        let cacheRecord = MealScanRepeatCacheRecord(
            sourceMealID: UUID(),
            sourceImageHash: "recovered-cache-image",
            featurePrintArchive: nil,
            visionRevision: 2,
            snapshotJSON: "{}",
            snapshotSchemaVersion: 1,
            mealName: "Recovered cache meal",
            mealType: .lunch,
            caloriesKcal: 540,
            proteinGrams: 32,
            carbsGrams: 61,
            fatGrams: 17,
            sourceMealLoggedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        recoveredContainer.mainContext.insert(cacheRecord)
        try recoveredContainer.mainContext.save()

        let recoveredCacheRecords = try recoveredContainer.mainContext.fetch(
            FetchDescriptor<MealScanRepeatCacheRecord>()
        )
        #expect(recoveredCacheRecords.count == 1)
    }
}
