import Testing
import Foundation
import SwiftData
@testable import PCOS

/// Reversible test encryptor: a two-byte header carrying a key tag, then bytes XOR the tag.
private struct TaggedEncryptor: PhotoEncrypting {
    let tag: UInt8

    func encrypt(_ data: Data) -> Data? {
        if data.count >= 2, data[0] == 0xFA { return data }
        return Data([0xFA, tag]) + Data(data.map { $0 ^ tag })
    }

    func decrypt(_ data: Data) -> Data? {
        guard data.count >= 2, data[0] == 0xFA else { return data }
        guard data[1] == tag else { return nil }
        return Data(data.dropFirst(2).map { $0 ^ tag })
    }
}

@Suite("Data safety net", .serialized)
@MainActor
struct DataSafetyNetTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DataSafetyNetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Backup schema is v6 and the DailyLog DTO mirrors every stored DailyLog property")
    func dailyLogBackupParity() throws {
        #expect(SettingsDataBackupFile.currentSchemaVersion == 6)

        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let modelSource = try String(contentsOf: projectRoot.appendingPathComponent("PCOS/PCOS/Core/Data/SwiftData/DailyLog.swift"), encoding: .utf8)
        let classBody = modelSource.components(separatedBy: "final class DailyLog {")[1].components(separatedBy: "\n    init(")[0]
        var storedProperties = Set<String>()
        for line in classBody.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("var "), !trimmed.contains("{") else { continue }
            let name = trimmed.dropFirst(4).split(separator: ":").first.map(String.init) ?? ""
            storedProperties.insert(name)
        }
        let record = DailyLogRecord(id: UUID(), date: Date(), weight: nil, sleepHours: nil, activeMinutes: nil, restingHeartRateBPM: nil, stressLevel: nil, energyLevel: nil, waterOz: nil)
        let dtoProperties = Set(Mirror(reflecting: record).children.compactMap(\.label))
        #expect(storedProperties.subtracting(dtoProperties).isEmpty, "DailyLogRecord is missing \(storedProperties.subtracting(dtoProperties))")
    }

    @Test("Backup round trip keeps pain level, private note and positive actions")
    func dailyCheckInSurvivesBackup() throws {
        let sourceContainer = try TestHelpers.makeModelContainer()
        let source = sourceContainer.mainContext
        let log = DailyLog(date: Date(), stressLevel: 2, painLevel0To10: 6, privateNote: "rough night", positiveActionRawValues: "walk|water")
        source.insert(log)
        try source.save()

        let data = try SettingsDataBackupService(modelContext: source, photoEncryptor: TaggedEncryptor(tag: 1)).generateJSONBackupData()
        let destinationContainer = try TestHelpers.makeModelContainer()
        let destination = destinationContainer.mainContext
        _ = try SettingsDataImportService(modelContext: destination, snapshotStore: nil, photoEncryptor: TaggedEncryptor(tag: 2)).importJSONBackup(data: data)

        let imported = try #require(try destination.fetch(FetchDescriptor<DailyLog>()).first)
        #expect(imported.painLevel0To10 == 6)
        #expect(imported.privateNote == "rough night")
        #expect(imported.positiveActionRawValues == "walk|water")
    }

    @Test("Replace-all import writes a pre-import snapshot that restores the previous data, keeping at most three")
    func preImportSnapshot() throws {
        let directory = try temporaryDirectory()
        let store = PreImportSnapshotStore(directory: directory)
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        context.insert(SupplementLog(date: Date(), supplementName: "Inositol", dosageMg: 4000, timeTaken: Date()))
        try context.save()

        let incoming = SettingsDataBackupFile(exportedAt: Date(), appVersion: "test", source: .userExport, records: SettingsDataBackupRecords(
            supplements: [SupplementLogRecord(id: UUID(), date: Date(), supplementName: "Magnesium", dosageMg: 400, timeTaken: Date(), taken: true, brand: nil)]
        ))
        let service = SettingsDataImportService(modelContext: context, snapshotStore: store, photoEncryptor: TaggedEncryptor(tag: 1))
        let summary = try service.replaceAll(with: incoming)
        let snapshotURL = try #require(summary.preImportSnapshotURL)
        #expect(FileManager.default.fileExists(atPath: snapshotURL.path))
        #expect(store.latestSnapshotURL == snapshotURL)
        #expect(try context.fetch(FetchDescriptor<SupplementLog>()).map(\.supplementName) == ["Magnesium"])

        // Restoring the snapshot brings the pre-import data back.
        _ = try service.importJSONBackup(from: snapshotURL)
        #expect(try context.fetch(FetchDescriptor<SupplementLog>()).map(\.supplementName) == ["Inositol"])

        for _ in 0..<4 {
            _ = try service.replaceAll(with: incoming)
        }
        #expect(try store.snapshotURLs().count == PreImportSnapshotStore.maximumSnapshots)
    }

    @Test("Photo Journal images restore on a device with a different encryption key")
    func photosSurviveKeyChange() throws {
        let original = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let deviceA = TaggedEncryptor(tag: 0x11)
        let deviceB = TaggedEncryptor(tag: 0x22)

        let sourceContainer = try TestHelpers.makeModelContainer()
        let source = sourceContainer.mainContext
        source.insert(HairPhotoEntry(date: Date(), photoType: .faceChin, photoData: deviceA.encrypt(original)!, notes: nil, analysisResult: nil))
        try source.save()

        let data = try SettingsDataBackupService(modelContext: source, photoEncryptor: deviceA).generateJSONBackupData()
        let destinationContainer = try TestHelpers.makeModelContainer()
        let destination = destinationContainer.mainContext
        _ = try SettingsDataImportService(modelContext: destination, snapshotStore: nil, photoEncryptor: deviceB).importJSONBackup(data: data)

        let imported = try #require(try destination.fetch(FetchDescriptor<HairPhotoEntry>()).first)
        #expect(deviceB.decrypt(imported.photoData) == original)
        #expect(deviceA.decrypt(imported.photoData) == nil, "stored bytes must be re-encrypted for the new device")
    }

    @Test("Shared export files are recognised for cleanup only inside the temporary directory")
    func temporaryExportDetection() {
        let tmp = URL(fileURLWithPath: "/tmp/app", isDirectory: true)
        #expect(SettingsDataBackupService.isTemporaryExport(tmp.appendingPathComponent("CycleBalance_Backup.json"), temporaryDirectory: tmp))
        #expect(!SettingsDataBackupService.isTemporaryExport(URL(fileURLWithPath: "/Documents/CycleBalance_Backup.json"), temporaryDirectory: tmp))
    }

    @Test("Settings cleans up shared exports, rolls back a failed delete-all, and states the full deletion scope")
    func settingsSafetyWiring() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let settings = try String(contentsOf: projectRoot.appendingPathComponent("PCOS/PCOS/App/SettingsView.swift"), encoding: .utf8)
        #expect(settings.contains(".sheet(item: $activeSheet, onDismiss: removeSharedExportFile)"))
        #expect(settings.contains("SettingsDataBackupService.isTemporaryExport("))
        #expect(!settings.contains("This will permanently delete all your cycle data, symptoms, and insights."))
        #expect(settings.contains("cannot be undone"))
        let deleteFunction = settings.components(separatedBy: "private func deleteAllData() {")[1].components(separatedBy: "\n    }\n")[0]
        #expect(deleteFunction.contains("modelContext.rollback()"))
        #expect(!settings.contains("Importing a backup will replace all existing app data."))
        #expect(settings.contains("PreImportSnapshotStore"))
    }
}
