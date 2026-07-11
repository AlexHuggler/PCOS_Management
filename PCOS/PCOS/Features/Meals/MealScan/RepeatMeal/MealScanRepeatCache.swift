import Foundation
import SwiftData
import os

@MainActor
protocol MealScanRepeatCaching {
    func suggestion(
        for fingerprint: MealImageFingerprint,
        now: Date
    ) async -> RepeatMealSuggestion?

    func save(
        snapshot: RepeatMealDraftSnapshot,
        sourceMealID: UUID,
        sourceMealLoggedAt: Date,
        fingerprint: MealImageFingerprint,
        now: Date
    ) throws

    func markMatched(recordID: UUID, now: Date) throws
    func markReused(recordID: UUID, now: Date) throws
    func removeRecords(sourceMealID: UUID) throws
}

enum MealScanRepeatCacheError: Error {
    case unsupportedSnapshotSchema
    case snapshotEncodingFailed
}

@MainActor
final class MealScanRepeatCache: MealScanRepeatCaching {
    static let capacity = 100

    private let modelContext: ModelContext
    private let fingerprinter: any MealImageFingerprinting
    private let similarityPolicy: MealRepeatSimilarityPolicy
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        modelContext: ModelContext,
        fingerprinter: any MealImageFingerprinting,
        similarityPolicy: MealRepeatSimilarityPolicy
    ) {
        self.modelContext = modelContext
        self.fingerprinter = fingerprinter
        self.similarityPolicy = similarityPolicy.approvedOrDisabled
    }

    func suggestion(
        for fingerprint: MealImageFingerprint,
        now: Date = Date()
    ) async -> RepeatMealSuggestion? {
        do {
            var descriptor = FetchDescriptor<MealScanRepeatCacheRecord>(
                sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
            )
            descriptor.fetchLimit = Self.capacity
            let records = try modelContext.fetch(descriptor)

            var validRecords: [(record: MealScanRepeatCacheRecord, snapshot: RepeatMealDraftSnapshot)] = []
            var invalidRecords: [MealScanRepeatCacheRecord] = []

            for record in records {
                guard try sourceMealExists(id: record.sourceMealID),
                      let snapshot = decodeSnapshot(from: record) else {
                    invalidRecords.append(record)
                    continue
                }
                validRecords.append((record, snapshot))
            }

            for record in invalidRecords {
                modelContext.delete(record)
            }

            if let exact = validRecords.first(where: {
                $0.record.sourceImageHash == fingerprint.sourceImageHash
            }) {
                exact.record.lastMatchedAt = now
                try modelContext.save()
                return makeSuggestion(from: exact, matchKind: .exactImage)
            }

            guard similarityPolicy.enabled else {
                if !invalidRecords.isEmpty {
                    try modelContext.save()
                }
                return nil
            }

            var candidates: [(
                distance: Float,
                record: MealScanRepeatCacheRecord,
                snapshot: RepeatMealDraftSnapshot
            )] = []

            for candidate in validRecords {
                guard let archive = candidate.record.featurePrintArchive,
                      candidate.record.visionRevision == fingerprint.visionRevision else {
                    continue
                }

                let storedFingerprint = MealImageFingerprint(
                    sourceImageHash: candidate.record.sourceImageHash,
                    featurePrintArchive: archive,
                    visionRevision: candidate.record.visionRevision
                )

                do {
                    let distance = try await fingerprinter.distance(
                        between: fingerprint,
                        and: storedFingerprint
                    )
                    guard distance.isFinite, distance >= 0 else {
                        throw RepeatMealFingerprintError.distanceCalculationFailed
                    }
                    candidates.append((distance, candidate.record, candidate.snapshot))
                } catch {
                    modelContext.delete(candidate.record)
                    invalidRecords.append(candidate.record)
                }
            }

            candidates.sort {
                if $0.distance == $1.distance {
                    return $0.record.id.uuidString < $1.record.id.uuidString
                }
                return $0.distance < $1.distance
            }

            guard candidates.count >= 2 else {
                if !invalidRecords.isEmpty {
                    try modelContext.save()
                }
                return nil
            }

            let nearest = candidates[0]
            let neighborMargin = candidates[1].distance - nearest.distance
            guard nearest.distance <= similarityPolicy.maximumDistance,
                  neighborMargin >= similarityPolicy.minimumNeighborMargin else {
                if !invalidRecords.isEmpty {
                    try modelContext.save()
                }
                return nil
            }

            nearest.record.lastMatchedAt = now
            try modelContext.save()
            return makeSuggestion(
                from: (nearest.record, nearest.snapshot),
                matchKind: .similarImage
            )
        } catch {
            Logger.meals.error("Repeat meal cache lookup failed; continuing with a fresh scan.")
            return nil
        }
    }

    func save(
        snapshot: RepeatMealDraftSnapshot,
        sourceMealID: UUID,
        sourceMealLoggedAt: Date,
        fingerprint: MealImageFingerprint,
        now: Date = Date()
    ) throws {
        guard snapshot.schemaVersion == RepeatMealDraftSnapshot.currentSchemaVersion else {
            throw MealScanRepeatCacheError.unsupportedSnapshotSchema
        }
        guard let snapshotJSON = String(data: try encoder.encode(snapshot), encoding: .utf8) else {
            throw MealScanRepeatCacheError.snapshotEncodingFailed
        }

        let imageHash = fingerprint.sourceImageHash
        let descriptor = FetchDescriptor<MealScanRepeatCacheRecord>(
            predicate: #Predicate { record in
                record.sourceImageHash == imageHash
            },
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        let existingRecords = try modelContext.fetch(descriptor)
        let record: MealScanRepeatCacheRecord

        if let existing = existingRecords.first {
            record = existing
            for duplicate in existingRecords.dropFirst() {
                modelContext.delete(duplicate)
            }
            record.sourceMealID = sourceMealID
            record.featurePrintArchive = fingerprint.featurePrintArchive
            record.visionRevision = fingerprint.visionRevision
            record.snapshotJSON = snapshotJSON
            record.snapshotSchemaVersion = snapshot.schemaVersion
            record.mealName = snapshot.mealName
            record.mealType = snapshot.mealType
            record.caloriesKcal = snapshot.nutrition.caloriesKcal
            record.proteinGrams = snapshot.nutrition.proteinGrams
            record.carbsGrams = snapshot.nutrition.carbsGrams
            record.fatGrams = snapshot.nutrition.fatGrams
            record.sourceMealLoggedAt = sourceMealLoggedAt
            record.lastUsedAt = now
            record.lastMatchedAt = nil
        } else {
            record = MealScanRepeatCacheRecord(
                sourceMealID: sourceMealID,
                sourceImageHash: imageHash,
                featurePrintArchive: fingerprint.featurePrintArchive,
                visionRevision: fingerprint.visionRevision,
                snapshotJSON: snapshotJSON,
                snapshotSchemaVersion: snapshot.schemaVersion,
                mealName: snapshot.mealName,
                mealType: snapshot.mealType,
                caloriesKcal: snapshot.nutrition.caloriesKcal,
                proteinGrams: snapshot.nutrition.proteinGrams,
                carbsGrams: snapshot.nutrition.carbsGrams,
                fatGrams: snapshot.nutrition.fatGrams,
                sourceMealLoggedAt: sourceMealLoggedAt,
                createdAt: now,
                lastUsedAt: now
            )
            modelContext.insert(record)
        }

        try modelContext.save()
        try evictOverflowRecords()
    }

    func markMatched(recordID: UUID, now: Date = Date()) throws {
        guard let record = try record(id: recordID) else { return }
        record.lastMatchedAt = now
        try modelContext.save()
    }

    func markReused(recordID: UUID, now: Date = Date()) throws {
        guard let record = try record(id: recordID) else { return }
        record.lastUsedAt = now
        record.reuseCount += 1
        try modelContext.save()
    }

    func removeRecords(sourceMealID: UUID) throws {
        let mealID = sourceMealID
        let descriptor = FetchDescriptor<MealScanRepeatCacheRecord>(
            predicate: #Predicate { record in
                record.sourceMealID == mealID
            }
        )
        let records = try modelContext.fetch(descriptor)
        guard !records.isEmpty else { return }
        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    private func makeSuggestion(
        from candidate: (record: MealScanRepeatCacheRecord, snapshot: RepeatMealDraftSnapshot),
        matchKind: RepeatMealSuggestion.MatchKind
    ) -> RepeatMealSuggestion {
        RepeatMealSuggestion(
            recordID: candidate.record.id,
            sourceMealID: candidate.record.sourceMealID,
            snapshot: candidate.snapshot,
            sourceMealLoggedAt: candidate.record.sourceMealLoggedAt,
            matchKind: matchKind
        )
    }

    private func decodeSnapshot(
        from record: MealScanRepeatCacheRecord
    ) -> RepeatMealDraftSnapshot? {
        guard record.snapshotSchemaVersion == RepeatMealDraftSnapshot.currentSchemaVersion,
              let data = record.snapshotJSON.data(using: .utf8),
              let snapshot = try? decoder.decode(RepeatMealDraftSnapshot.self, from: data),
              snapshot.schemaVersion == RepeatMealDraftSnapshot.currentSchemaVersion else {
            return nil
        }
        return snapshot
    }

    private func sourceMealExists(id: UUID) throws -> Bool {
        let sourceID = id
        var descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { meal in
                meal.id == sourceID
            }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func record(id: UUID) throws -> MealScanRepeatCacheRecord? {
        let recordID = id
        var descriptor = FetchDescriptor<MealScanRepeatCacheRecord>(
            predicate: #Predicate { record in
                record.id == recordID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func evictOverflowRecords() throws {
        let descriptor = FetchDescriptor<MealScanRepeatCacheRecord>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .forward)]
        )
        let records = try modelContext.fetch(descriptor)
        let overflowCount = records.count - Self.capacity
        guard overflowCount > 0 else { return }
        for record in records.prefix(overflowCount) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}

extension MealRepeatSimilarityPolicy {
    static func loadApproved(from bundle: Bundle = .main) -> Self {
        guard let url = bundle.url(
            forResource: "MealRepeatSimilarityPolicy",
            withExtension: "json"
        ) else {
            return .disabled
        }
        return loadApproved(fileURL: url)
    }

    static func loadApproved(from directoryURL: URL) -> Self {
        loadApproved(
            fileURL: directoryURL.appendingPathComponent("MealRepeatSimilarityPolicy.json")
        )
    }

    fileprivate var approvedOrDisabled: Self {
        isApproved ? self : .disabled
    }

    private static func loadApproved(fileURL: URL) -> Self {
        guard let data = try? Data(contentsOf: fileURL),
              let policy = try? JSONDecoder().decode(Self.self, from: data),
              policy.isApproved else {
            return .disabled
        }
        return policy
    }

    private var isApproved: Bool {
        enabled
            && version == 1
            && evaluatedImageCount == 100
            && precision.isFinite
            && precision >= 0.95
            && precision <= 1
            && highRiskFalseMatches == 0
            && maximumDistance.isFinite
            && maximumDistance > 0
            && minimumNeighborMargin.isFinite
            && minimumNeighborMargin >= 0
    }
}
