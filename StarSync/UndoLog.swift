import Foundation

/// A record of one sync run, written before anything is changed so that a
/// bulk write can always be put back.
struct SyncRun: Codable, Identifiable, Sendable {
    struct Entry: Codable, Sendable {
        let localIdentifier: String
        let filename: String?
        let oldRating: Int
        let newRating: Int
    }

    let id: UUID
    let date: Date
    let catalogName: String
    var entries: [Entry]

    var writeCount: Int { entries.count }
}

/// Stores sync runs on disk so "Revert last sync" survives quitting the app.
///
/// Runs live in Application Support rather than in the app's defaults: a
/// six-hundred-photo run is real data, and losing it to a preferences reset
/// would mean losing the only way back.
struct UndoLog {
    static let shared = UndoLog()

    private let directory: URL
    private let maximumRuns = 20
    /// Far beyond any real run, which is a few hundred bytes per photo. A
    /// file bigger than this was not written by StarSync, and decoding it
    /// would only cost memory.
    private let maximumRunFileSize = 50 * 1024 * 1024

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        directory = support
            .appendingPathComponent("StarSync", isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func save(_ run: SyncRun) throws {
        // A run lists photo file names and identifiers, so it is readable by
        // this user only. The directory is tightened as well as created that
        // way, to cover one made before this was done.
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let stamp = ISO8601DateFormatter.filenameSafe().string(from: run.date)
        let url = directory.appendingPathComponent("\(stamp)-\(run.id.uuidString).json")
        try encoder.encode(run).write(to: url, options: .atomic)
        // Set after the write: an atomic write replaces the file, so any
        // permissions set beforehand would not survive it.
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        pruneOldRuns()
    }

    /// Runs on disk, newest first.
    func allRuns() -> [SyncRun] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys)
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            // Only plain files of a plausible size. A symlink reports itself
            // rather than what it points at, so it is not a regular file and
            // is never followed.
            .filter { url in
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let size = values.fileSize
                else { return false }
                return size <= maximumRunFileSize
            }
            .compactMap { try? decoder.decode(SyncRun.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    var mostRecentRun: SyncRun? { allRuns().first }

    func delete(_ run: SyncRun) {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in urls where url.lastPathComponent.contains(run.id.uuidString) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func pruneOldRuns() {
        let runs = allRuns()
        guard runs.count > maximumRuns else { return }
        for run in runs.dropFirst(maximumRuns) { delete(run) }
    }
}

extension ISO8601DateFormatter {
    /// `2026-11-10T081500Z` — sorts chronologically as a file name.
    ///
    /// Built fresh each time: ISO8601DateFormatter is not Sendable, and a
    /// shared instance would be a data race waiting to happen.
    static func filenameSafe() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate,
                                   .withTime, .withTimeZone]
        return formatter
    }
}
