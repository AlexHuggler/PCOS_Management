import Foundation
import SwiftData
import os

/// Keeps a JSON copy of the current data before a replace-all import so a wrong file is recoverable
/// from Settings > Data. Only the newest few snapshots are kept.
@MainActor
struct PreImportSnapshotStore {
    static let maximumSnapshots = 3
    private static let filePrefix = "pre-import-"

    let directory: URL
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
    }

    /// Writes a full JSON backup of `modelContext` and prunes older snapshots.
    func saveSnapshot(of modelContext: ModelContext, now: Date = Date()) throws -> URL {
        let data = try SettingsDataBackupService(modelContext: modelContext).generateJSONBackupData()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(Self.filePrefix)\(Self.stamp(for: now))-\(UUID().uuidString.prefix(6)).json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try prune()
        Logger.database.info("Saved pre-import snapshot with \(data.count) bytes")
        return url
    }

    /// Newest first.
    func snapshotURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(Self.filePrefix) && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    var latestSnapshotURL: URL? {
        (try? snapshotURLs())?.first
    }

    private func prune() throws {
        for url in try snapshotURLs().dropFirst(Self.maximumSnapshots) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func stamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("CycleBalanceStoreBackups/PreImport", isDirectory: true)
    }
}
