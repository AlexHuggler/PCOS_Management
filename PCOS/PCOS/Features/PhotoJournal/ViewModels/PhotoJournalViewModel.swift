import SwiftUI
import SwiftData
import os
import UIKit

@Observable
@MainActor
final class PhotoJournalViewModel {
    private let modelContext: ModelContext
    private let defaultsStore: UserEntryDefaultsStore
    private let suggestionProvider: SuggestionProvider
    private let photoDensityAnalyzer: PhotoDensityAnalyzing
    private let photoEncryptor: PhotoEncrypting

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

    var photoNoteSuggestions: [String] {
        let baseSuggestions = suggestionProvider.photoNoteSuggestions(
            photoType: selectedPhotoType,
            query: "",
            limit: 20
        )
        let filteredSuggestions = suggestionProvider.photoNoteSuggestions(
            photoType: selectedPhotoType,
            query: QuickNoteComposer.suggestionQuery(in: notes, availableSuggestions: baseSuggestions),
            limit: 8
        )

        return QuickNoteComposer.visibleSuggestions(
            from: filteredSuggestions,
            selectedIn: notes,
            availableSuggestions: baseSuggestions
        )
    }

    // MARK: - Init

    init(
        modelContext: ModelContext,
        defaultsStore: UserEntryDefaultsStore = .shared,
        suggestionProvider: SuggestionProvider? = nil,
        photoDensityAnalyzer: PhotoDensityAnalyzing = PhotoDensityAnalysisService(),
        photoEncryptor: PhotoEncrypting = PhotoEncryptionService()
    ) {
        self.modelContext = modelContext
        self.defaultsStore = defaultsStore
        self.suggestionProvider = suggestionProvider ?? SuggestionProvider(defaultsStore: defaultsStore)
        self.photoDensityAnalyzer = photoDensityAnalyzer
        self.photoEncryptor = photoEncryptor
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
        let analysisResult = photoDensityAnalyzer.analyze(photoData: photoData, photoType: selectedPhotoType)
        let encryptedPhotoData = photoEncryptor.encrypt(photoData) ?? photoData
        let entry = HairPhotoEntry(
            date: photoDate,
            photoType: selectedPhotoType,
            photoData: encryptedPhotoData,
            notes: notes.isEmpty ? nil : notes,
            analysisResult: analysisResult
        )

        modelContext.insert(entry)
        try modelContext.save()
        defaultsStore.lastPhotoType = selectedPhotoType
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            let noteTokens = QuickNoteComposer.tokens(from: trimmedNotes)
            if noteTokens.count > 1 {
                for token in noteTokens {
                    suggestionProvider.recordPhotoNote(token, photoType: selectedPhotoType)
                }
            } else {
                suggestionProvider.recordPhotoNote(trimmedNotes, photoType: selectedPhotoType)
            }
        }
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

    func decryptedPhotoData(for entry: HairPhotoEntry) -> Data? {
        photoEncryptor.decrypt(entry.photoData)
    }

    func image(for entry: HairPhotoEntry) -> UIImage? {
        guard let data = decryptedPhotoData(for: entry) else { return nil }
        return UIImage(data: data)
    }

    /// Reset form to defaults.
    func reset() {
        selectedPhotoType = defaultsStore.lastPhotoType
        capturedPhotoData = nil
        notes = ""
        photoDate = Date()
    }

    func isPhotoNoteSelected(_ suggestion: String) -> Bool {
        QuickNoteComposer.isSelected(suggestion, in: notes)
    }

    func togglePhotoNoteSuggestion(_ suggestion: String) {
        notes = QuickNoteComposer.toggled(suggestion, in: notes)
    }
}
