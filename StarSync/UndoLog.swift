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
    let mode: String
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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter.filenameSafe().string(from: run.date)
        let url = directory.appendingPathComponent("\(stamp)-\(run.id.uuidString).json")
        try encoder.encode(run).write(to: url, options: .atomic)
        pruneOldRuns()
    }

    /// Runs on disk, newest first.
    func allRuns() -> [SyncRun] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
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
