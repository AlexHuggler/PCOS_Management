import Testing
import Foundation
import SwiftData
import UIKit
@testable import PCOS

@Suite("PhotoJournal ViewModel", .serialized)
@MainActor
struct PhotoJournalViewModelTests {
    private struct MockCoreMLPredictor: PhotoDensityCoreMLPredicting {
        let score: Double?

        func predictDensityScore(photoData: Data, photoType: HairPhotoType) -> Double? {
            score
        }
    }

    /// Creates an in-memory ModelContainer that includes HairPhotoEntry.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([HairPhotoEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
            UIColor.white.setFill()
            context.fill(CGRect(x: 6, y: 6, width: 12, height: 12))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }

    // MARK: - Save

    @Test("Save photo creates entry")
    func savePhotoCreatesEntry() throws {
        let container = try makeContainer()
        let vm = PhotoJournalViewModel(modelContext: container.mainContext)

        vm.selectedPhotoType = .hairline
        vm.capturedPhotoData = Data([0x00, 0x01, 0x02])
        vm.notes = "Test note"
        vm.photoDate = Date()

        try vm.savePhoto()

        let all = vm.fetchAllPhotos()
        #expect(all.count == 1)
        #expect(all.first?.photoType == .hairline)
        #expect(all.first?.notes == "Test note")
    }

    @Test("Save photo populates density analysis result when image data is valid")
    func savePhotoPopulatesAnalysisResult() throws {
        let container = try makeContainer()
        let vm = PhotoJournalViewModel(modelContext: container.mainContext)

        vm.selectedPhotoType = .scalpPart
        vm.capturedPhotoData = makeImageData()
        vm.photoDate = Date()

        try vm.savePhoto()

        let saved = try #require(vm.fetchAllPhotos().first)
        #expect(saved.analysisResult?.isEmpty == false)
    }

    @Test("Photo density service labels Core ML output source when model score is available")
    func photoDensityCoreMLSourceLabel() {
        let service = PhotoDensityAnalysisService(
            coreMLPredictor: MockCoreMLPredictor(score: 72)
        )
        let analysis = service.analyze(photoData: makeImageData(), photoType: .hairline)
        #expect(analysis?.localizedCaseInsensitiveContains("Core ML") == true)
    }

    @Test("Photo density service falls back to heuristic label when Core ML score is unavailable")
    func photoDensityHeuristicFallbackLabel() {
        let service = PhotoDensityAnalysisService(
            coreMLPredictor: MockCoreMLPredictor(score: nil)
        )
        let analysis = service.analyze(photoData: makeImageData(), photoType: .hairline)
        #expect(analysis?.localizedCaseInsensitiveContains("heuristic") == true)
    }

    @Test("Saved photo data is encrypted and decryptable")
    func savedPhotoDataEncrypted() throws {
        let container = try makeContainer()
        let vm = PhotoJournalViewModel(modelContext: container.mainContext)

        let original = makeImageData()
        vm.selectedPhotoType = .hairline
        vm.capturedPhotoData = original
        vm.photoDate = Date()

        try vm.savePhoto()

        let saved = try #require(vm.fetchAllPhotos().first)
        #expect(saved.photoData != original)

        let decrypted = PhotoEncryptionService().decrypt(saved.photoData)
        #expect(decrypted == original)
    }

    @Test("Save persists photo note suggestions for the selected type")
    func savePersistsPhotoNoteSuggestions() throws {
        let container = try makeContainer()
        let suiteName = "PhotoJournalViewModelTests.suggestions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        let vm = PhotoJournalViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)

        vm.selectedPhotoType = .hairline
        vm.capturedPhotoData = Data([0x00, 0x01, 0x02])
        vm.notes = "Baby hairs, Same angle"

        try vm.savePhoto()

        #expect(defaultsStore.recentPhotoNotes(photoType: .hairline, limit: 2) == ["Same angle", "Baby hairs"])
        #expect(defaultsStore.recentPhotoNotes(photoType: .body, limit: 2).isEmpty)
    }

    // MARK: - Fetch All

    @Test("Fetch all photos returns entries")
    func fetchAllPhotosReturnsEntries() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let vm = PhotoJournalViewModel(modelContext: ctx)

        // Insert two entries directly
        let entry1 = HairPhotoEntry(
            date: Date(),
            photoType: .scalpPart,
            photoData: Data([0x01])
        )
        let entry2 = HairPhotoEntry(
            date: Date().addingTimeInterval(-3600),
            photoType: .body,
            photoData: Data([0x02])
        )
        ctx.insert(entry1)
        ctx.insert(entry2)
        try ctx.save()

        let all = vm.fetchAllPhotos()
        #expect(all.count == 2)
    }

    // MARK: - Fetch by Type

    @Test("Fetch by type filters correctly")
    func fetchByTypeFiltersCorrectly() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let vm = PhotoJournalViewModel(modelContext: ctx)

        let entry1 = HairPhotoEntry(
            date: Date(),
            photoType: .faceChin,
            photoData: Data([0x01])
        )
        let entry2 = HairPhotoEntry(
            date: Date(),
            photoType: .faceUpperLip,
            photoData: Data([0x02])
        )
        let entry3 = HairPhotoEntry(
            date: Date().addingTimeInterval(-100),
            photoType: .faceChin,
            photoData: Data([0x03])
        )
        ctx.insert(entry1)
        ctx.insert(entry2)
        ctx.insert(entry3)
        try ctx.save()

        let chinPhotos = vm.fetchPhotos(for: .faceChin)
        #expect(chinPhotos.count == 2)
        for photo in chinPhotos {
            #expect(photo.photoType == .faceChin)
        }

        let lipPhotos = vm.fetchPhotos(for: .faceUpperLip)
        #expect(lipPhotos.count == 1)
    }

    // MARK: - Latest / Earliest

    @Test("Latest photo returns correct entry")
    func latestPhotoReturnsCorrectEntry() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let vm = PhotoJournalViewModel(modelContext: ctx)

        let older = HairPhotoEntry(
            date: Date().addingTimeInterval(-86400),
            photoType: .hairline,
            photoData: Data([0x01])
        )
        let newer = HairPhotoEntry(
            date: Date(),
            photoType: .hairline,
            photoData: Data([0x02])
        )
        ctx.insert(older)
        ctx.insert(newer)
        try ctx.save()

        let latest = vm.latestPhoto(for: .hairline)
        #expect(latest != nil)
        #expect(latest?.id == newer.id)
    }

    @Test("Earliest photo returns correct entry")
    func earliestPhotoReturnsCorrectEntry() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let vm = PhotoJournalViewModel(modelContext: ctx)

        let older = HairPhotoEntry(
            date: Date().addingTimeInterval(-86400),
            photoType: .hairline,
            photoData: Data([0x01])
        )
        let newer = HairPhotoEntry(
            date: Date(),
            photoType: .hairline,
            photoData: Data([0x02])
        )
        ctx.insert(older)
        ctx.insert(newer)
        try ctx.save()

        let earliest = vm.earliestPhoto(for: .hairline)
        #expect(earliest != nil)
        #expect(earliest?.id == older.id)
    }

    // MARK: - Photos by Type

    @Test("Photos by type groups correctly")
    func photosByTypeGroupsCorrectly() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let vm = PhotoJournalViewModel(modelContext: ctx)

        let entry1 = HairPhotoEntry(
            date: Date(),
            photoType: .scalpPart,
            photoData: Data([0x01])
        )
        let entry2 = HairPhotoEntry(
            date: Date(),
            photoType: .body,
            photoData: Data([0x02])
        )
        let entry3 = HairPhotoEntry(
            date: Date().addingTimeInterval(-100),
            photoType: .scalpPart,
            photoData: Data([0x03])
        )
        ctx.insert(entry1)
        ctx.insert(entry2)
        ctx.insert(entry3)
        try ctx.save()

        let grouped = vm.photosByType()
        #expect(grouped[.scalpPart]?.count == 2)
        #expect(grouped[.body]?.count == 1)
        #expect(grouped[.hairline] == nil)
    }

    // MARK: - Delete

    @Test("Delete removes photo")
    func deleteRemovesPhoto() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let vm = PhotoJournalViewModel(modelContext: ctx)

        let entry = HairPhotoEntry(
            date: Date(),
            photoType: .faceChin,
            photoData: Data([0x01])
        )
        ctx.insert(entry)
        try ctx.save()

        #expect(vm.fetchAllPhotos().count == 1)

        vm.deletePhoto(entry)
        #expect(vm.fetchAllPhotos().count == 0)
    }

    // MARK: - Reset

    @Test("Reset clears state")
    func resetClearsState() throws {
        let container = try makeContainer()
        let suiteName = "PhotoJournalViewModelTests.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        defaultsStore.lastPhotoType = .hairline
        let vm = PhotoJournalViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)

        vm.selectedPhotoType = .body
        vm.capturedPhotoData = Data([0x01, 0x02])
        vm.notes = "Some notes"

        vm.reset()

        #expect(vm.selectedPhotoType == .hairline)
        #expect(vm.capturedPhotoData == nil)
        #expect(vm.notes == "")
        #expect(!vm.hasPhoto)
    }

    @Test("Photo note suggestions are scoped by selected photo type")
    func photoNoteSuggestionsScopedByType() throws {
        let container = try makeContainer()
        let suiteName = "PhotoJournalViewModelTests.noteScope.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        defaultsStore.recordRecentPhotoNote("Temple thinning", photoType: .hairline)
        let vm = PhotoJournalViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)

        vm.selectedPhotoType = .hairline
        #expect(vm.photoNoteSuggestions.contains("Temple thinning"))
        #expect(vm.photoNoteSuggestions.contains("Same angle"))

        vm.selectedPhotoType = .body
        #expect(!vm.photoNoteSuggestions.contains("Temple thinning"))
        #expect(vm.photoNoteSuggestions.contains("Area tracked today"))
    }
}
