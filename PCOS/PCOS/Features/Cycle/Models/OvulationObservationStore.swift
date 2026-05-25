import Foundation
import SwiftData

struct OvulationObservationStore {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    func observation(on date: Date) throws -> OvulationObservation? {
        let interval = dayInterval(for: date)
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<OvulationObservation>(
            predicate: #Predicate<OvulationObservation> { observation in
                observation.date >= start && observation.date < end
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor).first
    }

    func observations(in interval: DateInterval) throws -> [OvulationObservation] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<OvulationObservation>(
            predicate: #Predicate<OvulationObservation> { observation in
                observation.date >= start && observation.date < end
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor)
    }

    @discardableResult
    func upsertObservation(
        date: Date,
        basalBodyTemperatureCelsius: Double?,
        cervicalMucus: CervicalMucusType?,
        lhTestResult: LHTestResult?,
        notes: String?
    ) throws -> OvulationObservation? {
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = trimmedNotes?.isEmpty == false ? trimmedNotes : nil
        let normalizedCervicalMucus = cervicalMucus == .notObserved ? nil : cervicalMucus
        let normalizedLHTestResult = lhTestResult == .notTested ? nil : lhTestResult

        let existingObservation = try observation(on: date)

        if basalBodyTemperatureCelsius == nil,
           normalizedCervicalMucus == nil,
           normalizedLHTestResult == nil,
           normalizedNotes == nil {
            if let existingObservation {
                modelContext.delete(existingObservation)
                try modelContext.save()
            }
            return nil
        }

        let observation = existingObservation ?? OvulationObservation(date: calendar.startOfDay(for: date))
        observation.date = calendar.startOfDay(for: date)
        observation.basalBodyTemperatureCelsius = basalBodyTemperatureCelsius
        observation.cervicalMucus = normalizedCervicalMucus
        observation.lhTestResult = normalizedLHTestResult
        observation.notes = normalizedNotes

        if existingObservation == nil {
            modelContext.insert(observation)
        }

        try modelContext.save()
        return observation
    }
}

private extension OvulationObservationStore {
    func dayInterval(for date: Date) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }
}
