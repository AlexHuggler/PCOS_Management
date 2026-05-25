import Foundation
import SwiftData

struct GlucosePrefillContext: Equatable {
    var mealContext: String
    var readingType: GlucoseReadingType
    var readingDate: Date
}

struct PostMealFeedbackSummary: Equatable {
    var severity: Int
    var note: String?
    var recordedAt: Date?
}

struct MealGlucosePairing {
    var meal: MealEntry
    var beforeMealReading: BloodSugarReading?
    var afterMealReadings: [BloodSugarReading]
    var postMealFeedback: PostMealFeedbackSummary?
}

struct RecentMealReuseSuggestion: Equatable, Identifiable {
    var id: String {
        "\(mealType.rawValue)|\(mealDescription.lowercased())|\(glycemicImpact.rawValue)"
    }

    var mealType: MealType
    var mealDescription: String
    var glycemicImpact: GlycemicImpact
    var carbsGrams: Double?
    var proteinGrams: Double?
    var fatGrams: Double?
    var notes: String?
}

struct MealGlucoseReadiness: Equatable {
    enum State: Equatable {
        case notReady
        case building
        case ready
    }

    var state: State
    var mealCount: Int
    var pairedReadingCount: Int
    var postMealFeedbackCount: Int
    var message: String
}

@MainActor
struct MealGlucoseContextService {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    func mealGlucosePairings(days: Int = 14, now: Date = Date()) throws -> [MealGlucosePairing] {
        let meals = try recentMeals(days: days, now: now)
        let readings = try recentReadings(days: days, now: now)

        return meals.map { meal in
            let beforeReading = readings
                .filter { reading in
                    reading.readingType == .beforeMeal
                        && reading.timestamp >= meal.timestamp.addingTimeInterval(-7_200)
                        && reading.timestamp <= meal.timestamp
                        && referencesMeal(reading, meal: meal)
                }
                .max { $0.timestamp < $1.timestamp }

            let afterReadings = readings
                .filter { reading in
                    reading.readingType == .afterMeal
                        && reading.timestamp >= meal.timestamp
                        && reading.timestamp <= meal.timestamp.addingTimeInterval(10_800)
                        && referencesMeal(reading, meal: meal)
                }
                .sorted { $0.timestamp < $1.timestamp }

            return MealGlucosePairing(
                meal: meal,
                beforeMealReading: beforeReading,
                afterMealReadings: afterReadings,
                postMealFeedback: feedbackSummary(for: meal)
            )
        }
    }

    func recentMealReuseSuggestions(limit: Int = 5) throws -> [RecentMealReuseSuggestion] {
        let descriptor = FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        let meals = try modelContext.fetch(descriptor)

        var seen = Set<String>()
        var suggestions: [RecentMealReuseSuggestion] = []
        for meal in meals {
            let key = "\(meal.mealType.rawValue)|\(normalized(meal.mealDescription))|\(meal.glycemicImpact.rawValue)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            suggestions.append(
                RecentMealReuseSuggestion(
                    mealType: meal.mealType,
                    mealDescription: meal.mealDescription,
                    glycemicImpact: meal.glycemicImpact,
                    carbsGrams: meal.carbsGrams,
                    proteinGrams: meal.proteinGrams,
                    fatGrams: meal.fatGrams,
                    notes: meal.notes
                )
            )
            if suggestions.count == limit { break }
        }
        return suggestions
    }

    func glucosePrefillContext(
        for meal: MealEntry,
        readingType: GlucoseReadingType = .afterMeal,
        now: Date = Date()
    ) -> GlucosePrefillContext {
        let prefix: String
        switch readingType {
        case .beforeMeal:
            prefix = "Before"
        case .afterMeal:
            prefix = "After"
        case .fasting:
            prefix = "Fasting near"
        case .random:
            prefix = "Near"
        }

        return GlucosePrefillContext(
            mealContext: "\(prefix) \(meal.mealDescription)",
            readingType: readingType,
            readingDate: now
        )
    }

    func readiness(days: Int = 14, now: Date = Date()) throws -> MealGlucoseReadiness {
        let pairings = try mealGlucosePairings(days: days, now: now)
        let pairedReadingCount = pairings.reduce(0) { total, pairing in
            total + (pairing.beforeMealReading == nil ? 0 : 1) + pairing.afterMealReadings.count
        }
        let feedbackCount = pairings.filter { $0.postMealFeedback != nil }.count

        let state: MealGlucoseReadiness.State
        let message: String
        if pairings.isEmpty {
            state = .notReady
            message = "Add a few meals and glucose readings to start seeing meal and glucose context."
        } else if pairings.count >= 3 && pairedReadingCount >= 3 && feedbackCount >= 2 {
            state = .ready
            message = "Your meal and glucose context is ready for reflection. Keep pairing before or after readings with meals to improve confidence."
        } else {
            state = .building
            message = "Your meal and glucose context is building. A few more paired readings and post-meal notes will make patterns clearer."
        }

        return MealGlucoseReadiness(
            state: state,
            mealCount: pairings.count,
            pairedReadingCount: pairedReadingCount,
            postMealFeedbackCount: feedbackCount,
            message: message
        )
    }

    private func recentMeals(days: Int, now: Date) throws -> [MealEntry] {
        let startDate = windowStart(days: days, now: now)
        let descriptor = FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return try modelContext.fetch(descriptor).filter { $0.timestamp >= startDate && $0.timestamp <= now }
    }

    private func recentReadings(days: Int, now: Date) throws -> [BloodSugarReading] {
        let startDate = windowStart(days: days, now: now)
        let descriptor = FetchDescriptor<BloodSugarReading>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return try modelContext.fetch(descriptor).filter { $0.timestamp >= startDate && $0.timestamp <= now }
    }

    private func windowStart(days: Int, now: Date) -> Date {
        calendar.date(byAdding: .day, value: -max(days, 1), to: calendar.startOfDay(for: now)) ?? .distantPast
    }

    private func feedbackSummary(for meal: MealEntry) -> PostMealFeedbackSummary? {
        guard meal.postMealSymptomSeverity != nil || meal.postMealSymptomNote != nil else {
            return nil
        }
        return PostMealFeedbackSummary(
            severity: meal.postMealSymptomSeverity ?? 0,
            note: meal.postMealSymptomNote,
            recordedAt: meal.postMealFeedbackTimestamp
        )
    }

    private func referencesMeal(_ reading: BloodSugarReading, meal: MealEntry) -> Bool {
        guard let mealContext = reading.mealContext, !mealContext.isEmpty else {
            return true
        }

        let context = normalized(mealContext)
        let description = normalized(meal.mealDescription)
        return context.contains(description) || description.contains(context)
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct HealthKitContributionSummary: Equatable, Identifiable {
    enum Kind: String, CaseIterable {
        case bodyMass
        case sleepAnalysis
        case activeMinutes
        case restingHeartRate
        case bloodGlucose
    }

    var id: Kind { kind }
    var kind: Kind
    var title: String
    var sampleCount: Int
    var sourceLabel: String

    var displayText: String {
        sampleCount == 1 ? "1 Apple Health contribution" : "\(sampleCount) Apple Health contributions"
    }
}

@MainActor
struct HealthKitContributionSummaryService {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    func summaries(days: Int = 30, now: Date = Date()) throws -> [HealthKitContributionSummary] {
        let startDate = calendar.date(byAdding: .day, value: -max(days, 1), to: calendar.startOfDay(for: now)) ?? .distantPast
        let dailyLogs = try modelContext.fetch(FetchDescriptor<DailyLog>())
            .filter { $0.date >= startDate && $0.date <= now }
        let glucoseReadings = try modelContext.fetch(FetchDescriptor<BloodSugarReading>())
            .filter { $0.timestamp >= startDate && $0.timestamp <= now && $0.fromHealthKit }

        return [
            HealthKitContributionSummary(
                kind: .bodyMass,
                title: "Weight",
                sampleCount: dailyLogs.filter { $0.weight != nil }.count,
                sourceLabel: "Apple Health"
            ),
            HealthKitContributionSummary(
                kind: .sleepAnalysis,
                title: "Sleep",
                sampleCount: dailyLogs.filter { $0.sleepHours != nil }.count,
                sourceLabel: "Apple Health"
            ),
            HealthKitContributionSummary(
                kind: .activeMinutes,
                title: "Activity",
                sampleCount: dailyLogs.filter { $0.activeMinutes != nil }.count,
                sourceLabel: "Apple Health"
            ),
            HealthKitContributionSummary(
                kind: .restingHeartRate,
                title: "Resting heart rate",
                sampleCount: dailyLogs.filter { $0.restingHeartRateBPM != nil }.count,
                sourceLabel: "Apple Health"
            ),
            HealthKitContributionSummary(
                kind: .bloodGlucose,
                title: "Blood glucose",
                sampleCount: glucoseReadings.count,
                sourceLabel: "Apple Health"
            ),
        ]
    }
}

struct LocalProfilePhotoStore {
    private let baseDirectory: URL
    private let fileManager: FileManager

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileManager = fileManager
    }

    var photoURL: URL {
        baseDirectory
            .appendingPathComponent("Profile", isDirectory: true)
            .appendingPathComponent("profile-photo.dat")
    }

    @discardableResult
    func saveProfilePhoto(_ data: Data) throws -> URL {
        let directory = photoURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: photoURL, options: .atomic)
        return photoURL
    }

    func loadProfilePhoto() throws -> Data? {
        guard fileManager.fileExists(atPath: photoURL.path) else {
            return nil
        }
        return try Data(contentsOf: photoURL)
    }

    func deleteProfilePhoto() throws {
        guard fileManager.fileExists(atPath: photoURL.path) else {
            return
        }
        try fileManager.removeItem(at: photoURL)
    }

    func shouldMaskProfilePhoto(isAppLockEnabled: Bool, isContentMasked: Bool) -> Bool {
        isAppLockEnabled && isContentMasked
    }
}
