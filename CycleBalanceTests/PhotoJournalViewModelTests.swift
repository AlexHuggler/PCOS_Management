import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("PhotoJournal ViewModel", .serialized)
@MainActor
struct PhotoJournalViewModelTests {

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
}
