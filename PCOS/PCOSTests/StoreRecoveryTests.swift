import Testing
import Foundation
@testable import PCOS

@Suite("Store Recovery")
struct StoreRecoveryTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Moves store and sidecar files into a timestamped backup folder")
    func backsUpStoreAndSidecarFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("default.store")
        let sidecars = ["default.store-wal", "default.store-shm"]
        try Data("store".utf8).write(to: storeURL)
        for name in sidecars {
            try Data("sidecar".utf8).write(to: directory.appendingPathComponent(name))
        }
        let unrelatedURL = directory.appendingPathComponent("other.json")
        try Data("keep".utf8).write(to: unrelatedURL)

        let backupDirectory = try StoreRecovery.backupAndResetStoreFiles(at: storeURL)

        let unwrappedBackup = try #require(backupDirectory)
        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
        for name in sidecars {
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
            #expect(FileManager.default.fileExists(atPath: unwrappedBackup.appendingPathComponent(name).path))
        }
        #expect(FileManager.default.fileExists(atPath: unwrappedBackup.appendingPathComponent("default.store").path))
        #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
        #expect(unwrappedBackup.path.contains(StoreRecovery.backupsDirectoryName))
    }

    @Test("Returns nil when no store files exist")
    func returnsNilWhenStoreMissing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("default.store")
        let backupDirectory = try StoreRecovery.backupAndResetStoreFiles(at: storeURL)

        #expect(backupDirectory == nil)
    }

    @Test("Tolerates missing sidecar files")
    func toleratesMissingSidecars() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("default.store")
        try Data("store".utf8).write(to: storeURL)

        let backupDirectory = try StoreRecovery.backupAndResetStoreFiles(at: storeURL)

        #expect(backupDirectory != nil)
        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
    }

    @Test("Backup folder name is filesystem-safe")
    func backupFolderNameIsSafe() {
        let name = StoreRecovery.backupFolderName(for: Date(timeIntervalSince1970: 0))
        #expect(!name.contains(":"))
        #expect(!name.contains("/"))
        #expect(!name.isEmpty)
    }
}
