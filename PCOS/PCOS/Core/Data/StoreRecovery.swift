import Foundation
import os

/// Recovers from an unreadable SwiftData store by moving its files aside so a
/// fresh store can be created on the next attempt. Files are preserved in a
/// timestamped backup folder next to the store rather than deleted, so user
/// data remains available for support-assisted recovery.
enum StoreRecovery {
    static let backupsDirectoryName = "CycleBalanceStoreBackups"

    /// Moves the store file and any sidecar files sharing its base name
    /// (e.g. `default.store-wal`, `default.store-shm`) into a timestamped
    /// backup directory. Returns the backup directory URL, or nil when no
    /// store files existed to move.
    @discardableResult
    static func backupAndResetStoreFiles(
        at storeURL: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL? {
        let directory = storeURL.deletingLastPathComponent()
        let baseName = storeURL.lastPathComponent
        guard !baseName.isEmpty else { return nil }

        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        let storeFiles = contents.filter { $0.lastPathComponent.hasPrefix(baseName) }
        guard !storeFiles.isEmpty else { return nil }

        let backupDirectory = directory
            .appendingPathComponent(backupsDirectoryName, isDirectory: true)
            .appendingPathComponent(backupFolderName(for: now), isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        for file in storeFiles {
            let destination = backupDirectory.appendingPathComponent(file.lastPathComponent)
            try fileManager.moveItem(at: file, to: destination)
            Logger.database.notice(
                "Backed up unreadable store file: \(file.lastPathComponent, privacy: .public)"
            )
        }

        return backupDirectory
    }

    static func backupFolderName(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withTimeZone]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}
