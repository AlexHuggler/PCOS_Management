import CryptoKit
import Foundation
import SwiftData

@MainActor
protocol MealScanResultCaching: AnyObject {
    func cachedResponseJSON(for cacheKey: String, now: Date) throws -> String?

    func saveResponseJSON(
        _ responseJSON: String,
        cacheKey: String,
        modelID: String,
        schemaVersion: String,
        promptVersion: String,
        confidenceScore: Double,
        sourceImageHash: String,
        now: Date
    ) throws
}

@MainActor
final class MealScanResultCache: MealScanResultCaching {
    private let modelContext: ModelContext
    private let ttl: TimeInterval

    init(modelContext: ModelContext, ttl: TimeInterval = 86_400) {
        self.modelContext = modelContext
        self.ttl = ttl
    }

    static func cacheKey(
        modelID: String,
        schemaVersion: String,
        promptVersion: String,
        normalizedImageData: Data,
        mealType: MealType,
        localeIdentifier: String,
        appBuild: String?
    ) -> String {
        let imageHash = SHA256.hash(data: normalizedImageData).map { String(format: "%02x", $0) }.joined()
        let material = [
            modelID,
            schemaVersion,
            promptVersion,
            imageHash,
            mealType.rawValue,
            localeIdentifier,
            appBuild ?? "unknown",
        ].joined(separator: "|")
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func cachedResponseJSON(for cacheKey: String, now: Date = Date()) throws -> String? {
        guard let record = try record(for: cacheKey) else { return nil }
        guard record.expiresAt > now else {
            modelContext.delete(record)
            try modelContext.save()
            return nil
        }

        record.lastAccessedAt = now
        try modelContext.save()
        return record.responseJSON
    }

    func saveResponseJSON(
        _ responseJSON: String,
        cacheKey: String,
        modelID: String,
        schemaVersion: String,
        promptVersion: String,
        confidenceScore: Double,
        sourceImageHash: String,
        now: Date = Date()
    ) throws {
        let record = try record(for: cacheKey) ?? MealScanResultCacheRecord(
            cacheKey: cacheKey,
            modelID: modelID,
            schemaVersion: schemaVersion,
            promptVersion: promptVersion,
            responseJSON: responseJSON,
            confidenceScore: confidenceScore,
            sourceImageHash: sourceImageHash,
            createdAt: now,
            lastAccessedAt: now,
            expiresAt: now.addingTimeInterval(ttl)
        )

        record.modelID = modelID
        record.schemaVersion = schemaVersion
        record.promptVersion = promptVersion
        record.responseJSON = responseJSON
        record.confidenceScore = confidenceScore
        record.sourceImageHash = sourceImageHash
        record.lastAccessedAt = now
        record.expiresAt = now.addingTimeInterval(ttl)

        if record.modelContext == nil {
            modelContext.insert(record)
        }
        try modelContext.save()
    }

    private func record(for cacheKey: String) throws -> MealScanResultCacheRecord? {
        let descriptor = FetchDescriptor<MealScanResultCacheRecord>(
            predicate: #Predicate { $0.cacheKey == cacheKey }
        )
        return try modelContext.fetch(descriptor).first
    }
}
