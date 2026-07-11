import Foundation
import SwiftData
import Testing
import UIKit
@testable import PCOS

@Suite("Repeat Meal Cache", .serialized)
@MainActor
struct RepeatMealCacheTests {
    @MainActor
    private final class StubRepeatMealFingerprinter: MealImageFingerprinting {
        var distancesByStoredHash: [String: Float]
        var failingStoredHashes: Set<String>
        private(set) var distanceCalls: [String] = []

        init(
            distancesByStoredHash: [String: Float] = [:],
            failingStoredHashes: Set<String> = []
        ) {
            self.distancesByStoredHash = distancesByStoredHash
            self.failingStoredHashes = failingStoredHashes
        }

        func makeFingerprint(for normalizedJPEGData: Data) async throws -> MealImageFingerprint {
            MealImageFingerprint(
                sourceImageHash: MealScanImageNormalizer.sha256Hex(normalizedJPEGData),
                featurePrintArchive: Data([0x01]),
                visionRevision: 2
            )
        }

        func distance(
            between lhs: MealImageFingerprint,
            and rhs: MealImageFingerprint
        ) async throws -> Float {
            distanceCalls.append(rhs.sourceImageHash)
            if failingStoredHashes.contains(rhs.sourceImageHash) {
                throw RepeatMealFingerprintError.invalidArchive
            }
            return try #require(distancesByStoredHash[rhs.sourceImageHash])
        }
    }

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

    private static let enabledSimilarityPolicy = MealRepeatSimilarityPolicy(
        version: 1,
        enabled: true,
        maximumDistance: 0.25,
        minimumNeighborMargin: 0.10,
        evaluatedImageCount: 100,
        precision: 0.96,
        highRiskFalseMatches: 0
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

    @Test("exact image suggestion bypasses distance and records match then reuse")
    func exactImageSuggestionBypassesDistanceAndTracksUsage() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let sourceMealID = UUID()
        let recordID = UUID()
        let loggedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let matchedAt = loggedAt.addingTimeInterval(3_600)
        let reusedAt = matchedAt.addingTimeInterval(60)
        insertSourceMeal(id: sourceMealID, loggedAt: loggedAt, into: context)
        try insertRepeatRecord(
            id: recordID,
            sourceMealID: sourceMealID,
            sourceImageHash: "same-image-hash",
            sourceMealLoggedAt: loggedAt,
            into: context
        )

        let fingerprinter = StubRepeatMealFingerprinter()
        let cache = MealScanRepeatCache(
            modelContext: context,
            fingerprinter: fingerprinter,
            similarityPolicy: Self.enabledSimilarityPolicy
        )
        let suggestion = await cache.suggestion(
            for: fingerprint(hash: "same-image-hash"),
            now: matchedAt
        )

        #expect(suggestion?.recordID == recordID)
        #expect(suggestion?.matchKind == .exactImage)
        #expect(fingerprinter.distanceCalls.isEmpty)

        let matchedRecord = try #require(fetchRepeatRecords(from: context).first)
        #expect(matchedRecord.lastMatchedAt == matchedAt)
        #expect(matchedRecord.reuseCount == 0)

        try cache.markReused(recordID: recordID, now: reusedAt)
        let reusedRecord = try #require(fetchRepeatRecords(from: context).first)
        #expect(reusedRecord.lastUsedAt == reusedAt)
        #expect(reusedRecord.reuseCount == 1)
    }

    @Test("disabled policy suppresses different-image distance work")
    func disabledPolicySuppressesSimilarMatching() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let sourceMealID = UUID()
        let loggedAt = Date(timeIntervalSince1970: 1_780_000_000)
        insertSourceMeal(id: sourceMealID, loggedAt: loggedAt, into: context)
        try insertRepeatRecord(
            sourceMealID: sourceMealID,
            sourceImageHash: "stored-image",
            sourceMealLoggedAt: loggedAt,
            into: context
        )

        let fingerprinter = StubRepeatMealFingerprinter(distancesByStoredHash: ["stored-image": 0.01])
        let cache = MealScanRepeatCache(
            modelContext: context,
            fingerprinter: fingerprinter,
            similarityPolicy: .disabled
        )

        #expect(await cache.suggestion(for: fingerprint(hash: "new-image"), now: loggedAt) == nil)
        #expect(fingerprinter.distanceCalls.isEmpty)
    }

    @Test("similar image requires distance and neighbor-margin gates")
    func similarImageRequiresDistanceAndMargin() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_780_010_000)
        let nearestID = UUID()
        let nearestMealID = UUID()
        let secondMealID = UUID()
        insertSourceMeal(id: nearestMealID, loggedAt: now, into: context)
        insertSourceMeal(id: secondMealID, loggedAt: now, into: context)
        try insertRepeatRecord(
            id: nearestID,
            sourceMealID: nearestMealID,
            sourceImageHash: "nearest-image",
            sourceMealLoggedAt: now,
            into: context
        )
        try insertRepeatRecord(
            sourceMealID: secondMealID,
            sourceImageHash: "second-image",
            sourceMealLoggedAt: now,
            into: context
        )

        let fingerprinter = StubRepeatMealFingerprinter(
            distancesByStoredHash: ["nearest-image": 0.18, "second-image": 0.40]
        )
        let cache = MealScanRepeatCache(
            modelContext: context,
            fingerprinter: fingerprinter,
            similarityPolicy: Self.enabledSimilarityPolicy
        )
        let suggestion = await cache.suggestion(for: fingerprint(hash: "new-image"), now: now)

        #expect(suggestion?.recordID == nearestID)
        #expect(suggestion?.matchKind == .similarImage)
        #expect(Set(fingerprinter.distanceCalls) == ["nearest-image", "second-image"])
    }

    @Test("ambiguous similar-image tie returns no suggestion")
    func ambiguousSimilarImageTieReturnsNil() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_780_020_000)
        for (index, hash) in ["near-one", "near-two"].enumerated() {
            let mealID = UUID()
            insertSourceMeal(id: mealID, loggedAt: now, into: context)
            try insertRepeatRecord(
                sourceMealID: mealID,
                sourceImageHash: hash,
                sourceMealLoggedAt: now.addingTimeInterval(Double(index)),
                into: context
            )
        }

        let fingerprinter = StubRepeatMealFingerprinter(
            distancesByStoredHash: ["near-one": 0.18, "near-two": 0.21]
        )
        let cache = MealScanRepeatCache(
            modelContext: context,
            fingerprinter: fingerprinter,
            similarityPolicy: Self.enabledSimilarityPolicy
        )

        #expect(await cache.suggestion(for: fingerprint(hash: "new-image"), now: now) == nil)
    }

    @Test("invalid cache records are removed and matching fails open")
    func invalidRecordsAreRemovedAndMatchingFailsOpen() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_780_030_000)
        let malformedMealID = UUID()
        let corruptMealID = UUID()
        insertSourceMeal(id: malformedMealID, loggedAt: now, into: context)
        insertSourceMeal(id: corruptMealID, loggedAt: now, into: context)
        try insertRepeatRecord(
            sourceMealID: malformedMealID,
            sourceImageHash: "malformed-snapshot",
            sourceMealLoggedAt: now,
            snapshotJSON: "not-json",
            into: context
        )
        try insertRepeatRecord(
            sourceMealID: UUID(),
            sourceImageHash: "missing-source",
            sourceMealLoggedAt: now,
            into: context
        )
        try insertRepeatRecord(
            sourceMealID: corruptMealID,
            sourceImageHash: "corrupt-archive",
            sourceMealLoggedAt: now,
            featurePrintArchive: Data([0x00]),
            into: context
        )

        let fingerprinter = StubRepeatMealFingerprinter(
            failingStoredHashes: ["corrupt-archive"]
        )
        let cache = MealScanRepeatCache(
            modelContext: context,
            fingerprinter: fingerprinter,
            similarityPolicy: Self.enabledSimilarityPolicy
        )

        #expect(await cache.suggestion(for: fingerprint(hash: "new-image"), now: now) == nil)
        let remainingRecords = try fetchRepeatRecords(from: context)
        #expect(remainingRecords.isEmpty)
    }

    @Test("saving the same exact hash upserts the reviewed snapshot")
    func savingExactHashUpserts() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let firstMealID = UUID()
        let secondMealID = UUID()
        let firstDate = Date(timeIntervalSince1970: 1_780_040_000)
        let secondDate = firstDate.addingTimeInterval(60)
        insertSourceMeal(id: firstMealID, loggedAt: firstDate, into: context)
        insertSourceMeal(id: secondMealID, loggedAt: secondDate, into: context)
        let cache = MealScanRepeatCache(
            modelContext: context,
            fingerprinter: StubRepeatMealFingerprinter(),
            similarityPolicy: .disabled
        )

        try cache.save(
            snapshot: Self.snapshot,
            sourceMealID: firstMealID,
            sourceMealLoggedAt: firstDate,
            fingerprint: fingerprint(hash: "repeat-hash"),
            now: firstDate
        )
        var updatedSnapshot = Self.snapshot
        updatedSnapshot.mealName = "Updated reviewed bowl"
        try cache.save(
            snapshot: updatedSnapshot,
            sourceMealID: secondMealID,
            sourceMealLoggedAt: secondDate,
            fingerprint: fingerprint(hash: "repeat-hash"),
            now: secondDate
        )

        let records = try fetchRepeatRecords(from: context)
        #expect(records.count == 1)
        #expect(records.first?.sourceMealID == secondMealID)
        #expect(records.first?.mealName == "Updated reviewed bowl")
        #expect(records.first?.sourceMealLoggedAt == secondDate)
    }

    @Test("saving a 101st record evicts the least recently used record")
    func savingBeyondLimitEvictsLeastRecentlyUsed() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let baseDate = Date(timeIntervalSince1970: 1_780_050_000)
        let oldestRecordID = UUID()

        for index in 0..<100 {
            let mealID = UUID()
            let date = baseDate.addingTimeInterval(Double(index))
            insertSourceMeal(id: mealID, loggedAt: date, into: context)
            try insertRepeatRecord(
                id: index == 0 ? oldestRecordID : UUID(),
                sourceMealID: mealID,
                sourceImageHash: "stored-\(index)",
                sourceMealLoggedAt: date,
                lastUsedAt: date,
                save: false,
                into: context
            )
        }
        try context.save()

        let newestMealID = UUID()
        let newestDate = baseDate.addingTimeInterval(1_000)
        insertSourceMeal(id: newestMealID, loggedAt: newestDate, into: context)
        try context.save()
        let cache = MealScanRepeatCache(
            modelContext: context,
            fingerprinter: StubRepeatMealFingerprinter(),
            similarityPolicy: .disabled
        )
        try cache.save(
            snapshot: Self.snapshot,
            sourceMealID: newestMealID,
            sourceMealLoggedAt: newestDate,
            fingerprint: fingerprint(hash: "stored-100"),
            now: newestDate
        )

        let records = try fetchRepeatRecords(from: context)
        #expect(records.count == 100)
        #expect(!records.contains { $0.id == oldestRecordID })
        #expect(records.contains { $0.sourceImageHash == "stored-100" })
    }

    @Test("removing a source meal clears only its repeat records")
    func removeRecordsClearsOnlyMatchingSourceMeal() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let loggedAt = Date(timeIntervalSince1970: 1_780_060_000)
        let removedMealID = UUID()
        let retainedMealID = UUID()
        insertSourceMeal(id: removedMealID, loggedAt: loggedAt, into: context)
        insertSourceMeal(id: retainedMealID, loggedAt: loggedAt, into: context)
        try insertRepeatRecord(
            sourceMealID: removedMealID,
            sourceImageHash: "removed-source",
            sourceMealLoggedAt: loggedAt,
            into: context
        )
        try insertRepeatRecord(
            sourceMealID: retainedMealID,
            sourceImageHash: "retained-source",
            sourceMealLoggedAt: loggedAt,
            into: context
        )
        let cache = MealScanRepeatCache(
            modelContext: context,
            fingerprinter: StubRepeatMealFingerprinter(),
            similarityPolicy: .disabled
        )

        try cache.removeRecords(sourceMealID: removedMealID)

        let records = try fetchRepeatRecords(from: context)
        #expect(records.count == 1)
        #expect(records.first?.sourceMealID == retainedMealID)
    }

    @Test("similarity policy loader rejects missing malformed and unsafe artifacts")
    func similarityPolicyLoaderRequiresApprovedArtifact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RepeatMealPolicyTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let policyURL = directory.appendingPathComponent("MealRepeatSimilarityPolicy.json")

        #expect(MealRepeatSimilarityPolicy.loadApproved(from: directory) == .disabled)
        try Data("not-json".utf8).write(to: policyURL)
        #expect(MealRepeatSimilarityPolicy.loadApproved(from: directory) == .disabled)

        let unsafePolicies = [
            MealRepeatSimilarityPolicy(
                version: 1,
                enabled: true,
                maximumDistance: 0.2,
                minimumNeighborMargin: 0.1,
                evaluatedImageCount: 99,
                precision: 0.99,
                highRiskFalseMatches: 0
            ),
            MealRepeatSimilarityPolicy(
                version: 1,
                enabled: true,
                maximumDistance: 0.2,
                minimumNeighborMargin: 0.1,
                evaluatedImageCount: 100,
                precision: 0.94,
                highRiskFalseMatches: 0
            ),
            MealRepeatSimilarityPolicy(
                version: 1,
                enabled: true,
                maximumDistance: 0.2,
                minimumNeighborMargin: 0.1,
                evaluatedImageCount: 100,
                precision: 0.99,
                highRiskFalseMatches: 1
            ),
        ]
        for policy in unsafePolicies {
            try JSONEncoder().encode(policy).write(to: policyURL, options: .atomic)
            #expect(MealRepeatSimilarityPolicy.loadApproved(from: directory) == .disabled)
        }

        try JSONEncoder().encode(Self.enabledSimilarityPolicy).write(to: policyURL, options: .atomic)
        #expect(MealRepeatSimilarityPolicy.loadApproved(from: directory) == Self.enabledSimilarityPolicy)
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

    private func fingerprint(hash: String) -> MealImageFingerprint {
        MealImageFingerprint(
            sourceImageHash: hash,
            featurePrintArchive: Data([0x01, 0x02]),
            visionRevision: 2
        )
    }

    private func insertSourceMeal(
        id: UUID,
        loggedAt: Date,
        into context: ModelContext
    ) {
        context.insert(
            MealEntry(
                id: id,
                timestamp: loggedAt,
                mealType: .lunch,
                mealDescription: "Reviewed repeat source",
                glycemicImpact: .medium
            )
        )
    }

    @discardableResult
    private func insertRepeatRecord(
        id: UUID = UUID(),
        sourceMealID: UUID,
        sourceImageHash: String,
        sourceMealLoggedAt: Date,
        snapshotJSON: String? = nil,
        featurePrintArchive: Data? = Data([0x01, 0x02]),
        lastUsedAt: Date? = nil,
        save: Bool = true,
        into context: ModelContext
    ) throws -> MealScanRepeatCacheRecord {
        let encodedSnapshot: String
        if let snapshotJSON {
            encodedSnapshot = snapshotJSON
        } else {
            encodedSnapshot = String(
                data: try JSONEncoder().encode(Self.snapshot),
                encoding: .utf8
            )!
        }
        let record = MealScanRepeatCacheRecord(
            id: id,
            sourceMealID: sourceMealID,
            sourceImageHash: sourceImageHash,
            featurePrintArchive: featurePrintArchive,
            visionRevision: 2,
            snapshotJSON: encodedSnapshot,
            snapshotSchemaVersion: RepeatMealDraftSnapshot.currentSchemaVersion,
            mealName: Self.snapshot.mealName,
            mealType: Self.snapshot.mealType,
            caloriesKcal: Self.snapshot.nutrition.caloriesKcal,
            proteinGrams: Self.snapshot.nutrition.proteinGrams,
            carbsGrams: Self.snapshot.nutrition.carbsGrams,
            fatGrams: Self.snapshot.nutrition.fatGrams,
            sourceMealLoggedAt: sourceMealLoggedAt,
            createdAt: sourceMealLoggedAt,
            lastUsedAt: lastUsedAt ?? sourceMealLoggedAt
        )
        context.insert(record)
        if save {
            try context.save()
        }
        return record
    }

    private func fetchRepeatRecords(
        from context: ModelContext
    ) throws -> [MealScanRepeatCacheRecord] {
        try context.fetch(FetchDescriptor<MealScanRepeatCacheRecord>())
    }
}
