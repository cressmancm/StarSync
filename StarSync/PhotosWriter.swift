import Foundation
import Photos
import StarSyncCore

/// Writes ratings into Apple Photos.
///
/// The rating is the only property StarSync ever changes, and every run is
/// recorded first so it can be put back.
enum PhotosWriter {

    /// Writes are grouped so progress can be reported and so one rejected
    /// asset cannot take a whole run down with it.
    static let batchSize = 200

    struct Result: Sendable {
        var written: Int = 0
        var failed: [(filename: String, reason: String)] = []
        var run: SyncRun?
    }

    /// Applies every row of `plan` that wants to write.
    static func apply(
        plan: SyncPlan,
        catalogName: String,
        progress: @MainActor (Int, Int) -> Void
    ) async -> Result {
        let pending = plan.writes
        var result = Result()
        guard !pending.isEmpty else { return result }

        var run = SyncRun(
            id: UUID(),
            date: Date(),
            mode: plan.mode.title,
            catalogName: catalogName,
            entries: pending.map {
                SyncRun.Entry(
                    localIdentifier: $0.photo.id,
                    filename: $0.photo.originalFilename,
                    oldRating: $0.photo.rating,
                    newRating: $0.newRating ?? $0.photo.rating
                )
            }
        )

        // Recorded before the first write, so an interrupted run is still
        // reversible.
        do {
            try UndoLog.shared.save(run)
        } catch {
            result.failed.append((filename: "—", reason: "Could not save the undo log: \(error.localizedDescription)"))
            return result
        }

        var written = 0
        for batch in pending.chunked(into: batchSize) {
            let targets = Dictionary(
                batch.map { ($0.photo.id, $0.newRating ?? $0.photo.rating) },
                uniquingKeysWith: { first, _ in first }
            )
            let assets = PhotosLibrary.assets(withIdentifiers: Array(targets.keys))

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for (identifier, rating) in targets {
                        guard let asset = assets[identifier],
                              let value = PHAsset.Rating(rawValue: rating),
                              asset.canPerform(.properties)
                        else { continue }
                        let request = PHAssetChangeRequest(for: asset)
                        request.rating = value
                    }
                }
                written += targets.count
            } catch {
                // Fall back to one asset at a time so a single bad asset only
                // costs itself, not the other 199 in the batch.
                for change in batch {
                    guard let asset = assets[change.photo.id],
                          let value = PHAsset.Rating(rawValue: change.newRating ?? change.photo.rating)
                    else {
                        result.failed.append((change.displayName, "Photo is no longer in the library"))
                        continue
                    }
                    do {
                        try await PHPhotoLibrary.shared().performChanges {
                            let request = PHAssetChangeRequest(for: asset)
                            request.rating = value
                        }
                        written += 1
                    } catch {
                        result.failed.append((change.displayName, error.localizedDescription))
                    }
                }
            }
            await progress(written, pending.count)
        }

        // Keep only what actually landed, so a revert cannot try to undo a
        // write that never happened.
        let failedNames = Set(result.failed.map(\.filename))
        run.entries = run.entries.filter { !failedNames.contains($0.filename ?? "—") }
        try? UndoLog.shared.save(run)

        result.written = written
        result.run = run
        return result
    }

    /// Puts a previous run back, restoring each photo's earlier rating.
    static func revert(
        _ run: SyncRun,
        progress: @MainActor (Int, Int) -> Void
    ) async -> Result {
        var result = Result()
        let assets = PhotosLibrary.assets(withIdentifiers: run.entries.map(\.localIdentifier))
        var restored = 0

        for batch in run.entries.chunked(into: batchSize) {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for entry in batch {
                        guard let asset = assets[entry.localIdentifier],
                              let value = PHAsset.Rating(rawValue: entry.oldRating),
                              asset.canPerform(.properties)
                        else { continue }
                        let request = PHAssetChangeRequest(for: asset)
                        request.rating = value
                    }
                }
                restored += batch.count
            } catch {
                result.failed.append((filename: "—", reason: error.localizedDescription))
            }
            await progress(restored, run.entries.count)
        }

        if result.failed.isEmpty {
            UndoLog.shared.delete(run)
        }
        result.written = restored
        return result
    }
}

extension PlannedChange {
    var displayName: String {
        photo.originalFilename ?? asset.fileName
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
