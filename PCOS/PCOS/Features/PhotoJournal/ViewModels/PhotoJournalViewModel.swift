import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class PhotoJournalViewModel {
    private let modelContext: ModelContext
    private let defaultsStore: UserEntryDefaultsStore

    // MARK: - Form State

    var selectedPhotoType: HairPhotoType = .scalpPart
    var capturedPhotoData: Data? = nil
    var notes: String = ""
    var photoDate: Date = Date()

    // MARK: - Computed

    var hasPhoto: Bool { capturedPhotoData != nil }

    /// Whether the form has any user-entered data worth preserving.
    var hasUnsavedChanges: Bool {
        hasPhoto || !notes.isEmpty
    }

    // MARK: - Init

    init(modelContext: ModelContext, defaultsStore: UserEntryDefaultsStore = .shared) {
        self.modelContext = modelContext
        self.defaultsStore = defaultsStore
        self.selectedPhotoType = defaultsStore.lastPhotoType
    }

    // MARK: - Actions

    /// Save the captured photo as a new HairPhotoEntry using delete-then-insert upsert.
    func savePhoto() throws {
        guard let photoData = capturedPhotoData else {
            return
        }

        // Delete any existing entry for the same date + type (upsert)
        let targetDate = photoDate
        let targetType = selectedPhotoType
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: targetDate)
        guard let endOfDay = calendar.endOfDay(for: targetDate) else { return }

        let descriptor = FetchDescriptor<HairPhotoEntry>(
            predicate: #Predicate<HairPhotoEntry> { entry in
                entry.date >= startOfDay && entry.date < endOfDay
            }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            for entry in existing {
                if entry.photoType == targetType {
                    modelContext.delete(entry)
                }
            }
        } catch {
            Logger.database.error("Failed to fetch existing photos for upsert: \(error.localizedDescription)")
        }

        // Insert fresh entry
        let entry = HairPhotoEntry(
            date: photoDate,
            photoType: selectedPhotoType,
            photoData: photoData,
            notes: notes.isEmpty ? nil : notes
        )

        modelContext.insert(entry)
        try modelContext.save()
        defaultsStore.lastPhotoType = selectedPhotoType
        reset()
    }

    /// Fetch all photos sorted by date descending.
    func fetchAllPhotos() -> [HairPhotoEntry] {
        let descriptor = FetchDescriptor<HairPhotoEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch all photos: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch photos filtered by type, sorted by date descending.
    func fetchPhotos(for type: HairPhotoType) -> [HairPhotoEntry] {
        let descriptor = FetchDescriptor<HairPhotoEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor).filter { $0.photoType == type }
        } catch {
            Logger.database.error("Failed to fetch photos for type \(type.rawValue): \(error.localizedDescription)")
            return []
        }
    }

    /// Delete a single photo entry.
    func deletePhoto(_ photo: HairPhotoEntry) {
        modelContext.delete(photo)
        do {
            try modelContext.save()
        } catch {
            Logger.database.error("Failed to delete photo: \(error.localizedDescription)")
        }
    }

    /// Return the most recent photo for a given type.
    func latestPhoto(for type: HairPhotoType) -> HairPhotoEntry? {
        fetchPhotos(for: type).first
    }

    /// Return the earliest photo for a given type.
    func earliestPhoto(for type: HairPhotoType) -> HairPhotoEntry? {
        fetchPhotos(for: type).last
    }

    /// Group all photos by their type.
    func photosByType() -> [HairPhotoType: [HairPhotoEntry]] {
        let allPhotos = fetchAllPhotos()
        return Dictionary(grouping: allPhotos, by: \.photoType)
    }

    /// Reset form to defaults.
    func reset() {
        selectedPhotoType = defaultsStore.lastPhotoType
        capturedPhotoData = nil
        notes = ""
        photoDate = Date()
    }
}
