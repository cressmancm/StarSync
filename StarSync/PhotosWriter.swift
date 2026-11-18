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

    /// A row that was left alone because one of the libraries moved on after
    /// the preview was built.
    struct SkippedChange: Sendable {
        /// Which side moved. The remedy differs, so the Done screen says which.
        enum Reason: Sendable {
            case photosChanged
            case lightroomChanged
        }

        let filename: String
        let reason: Reason
        /// What the library that moved holds now.
        let liveRating: Int
        /// What the preview was going to write.
        let plannedRating: Int

        /// Which side moved and what it says now, without the file name.
        ///
        /// Kept apart from the name rather than being one sentence, so the
        /// Done screen can draw the name as something you can select and copy
        /// — it is the string you would paste into a search field in whichever
        /// app this line is telling you to go and look at.
        var note: String {
            switch reason {
            case .photosChanged:
                return "Photos has \(liveRating)★, Lightroom has \(plannedRating)★"
            case .lightroomChanged:
                return "Lightroom now has \(liveRating)★, the preview had \(plannedRating)★"
            }
        }
    }

    struct Result: Sendable {
        var written: Int = 0
        var failed: [(filename: String, reason: String)] = []
        /// Rows dropped because one of the libraries moved on after the
        /// preview was built. Reported rather than silently overwritten.
        var skipped: [SkippedChange] = []
        var run: SyncRun?
    }

    /// Applies every row of `plan` that wants to write.
    ///
    /// The plan came from a snapshot taken when the app opened, so each row is
    /// checked once more against both libraries immediately before it is
    /// written. This is the only staleness check in the app, which is why it
    /// is also why the undo log records the live rating rather than the one
    /// the preview displayed.
    ///
    /// `lightroomRatings` maps `LRAsset.id` to the rating Lightroom holds now.
    /// It is `nil` when the catalog has not been touched since it was read, in
    /// which case there is nothing to compare and nothing was read.
    static func apply(
        plan: SyncPlan,
        catalogName: String,
        lightroomRatings: [String: Int]?,
        progress: @MainActor (Int, Int) -> Void
    ) async -> Result {
        let pending = plan.writes
        var result = Result()
        guard !pending.isEmpty else { return result }

        var run = SyncRun(
            id: UUID(),
            date: Date(),
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
        // reversible. The live ratings replace these as each batch is reached.
        do {
            try UndoLog.shared.save(run)
        } catch {
            result.failed.append((filename: "—", reason: "Could not save the undo log: \(error.localizedDescription)"))
            return result
        }

        /// Keyed by local identifier so one entry per photo survives, whatever
        /// its file name. Only rows that are really going to be written land
        /// here, and each carries the rating Photos held a moment before.
        var entries: [String: SyncRun.Entry] = [:]
        var written = 0

        for batch in pending.chunked(into: batchSize) {
            let assets = PhotosLibrary.assets(withIdentifiers: batch.map(\.photo.id))
            let names = Dictionary(
                batch.map { ($0.photo.id, $0.displayName) },
                uniquingKeysWith: { first, _ in first }
            )

            var targets: [String: Int] = [:]
            for change in batch {
                guard let asset = assets[change.photo.id] else {
                    result.failed.append((change.displayName, "Photo is no longer in the library"))
                    continue
                }

                let live = asset.rating.rawValue
                let lightroomNow = lightroomRatings.flatMap { $0[change.asset.id] }
                switch SyncPlanner.recheck(
                    change, liveRating: live, lightroomRating: lightroomNow
                ) {
                case .alreadyCorrect:
                    continue
                case .changedInPhotos(let liveRating):
                    result.skipped.append(
                        SkippedChange(
                            filename: change.displayName,
                            reason: .photosChanged,
                            liveRating: liveRating,
                            plannedRating: change.newRating ?? liveRating
                        )
                    )
                case .changedInLightroom(let liveRating):
                    result.skipped.append(
                        SkippedChange(
                            filename: change.displayName,
                            reason: .lightroomChanged,
                            liveRating: liveRating,
                            plannedRating: change.newRating ?? liveRating
                        )
                    )
                case .write(let rating):
                    guard asset.canPerform(.properties) else {
                        result.failed.append((change.displayName, "Photos doesn't allow changes to this photo"))
                        continue
                    }
                    guard PHAsset.Rating(rawValue: rating) != nil else {
                        result.failed.append((change.displayName, "Photos doesn't accept a rating of \(rating)"))
                        continue
                    }
                    targets[change.photo.id] = rating
                    entries[change.photo.id] = SyncRun.Entry(
                        localIdentifier: change.photo.id,
                        filename: change.photo.originalFilename,
                        oldRating: live,
                        newRating: rating
                    )
                }
            }

            guard !targets.isEmpty else {
                await progress(written, pending.count)
                continue
            }

            // Saved with this batch's live ratings before the batch is written.
            // If it cannot be saved, nothing more is written: a batch whose
            // earlier ratings are not on disk is a batch Revert would put
            // back wrong. What already landed is still recorded below.
            run.entries = sortedEntries(entries)
            do {
                try UndoLog.shared.save(run)
            } catch {
                for identifier in targets.keys { entries[identifier] = nil }
                result.failed.append((filename: "—", reason: "Could not save the undo log, so the rest of the run was not written: \(error.localizedDescription)"))
                break
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for (identifier, rating) in targets {
                        guard let asset = assets[identifier],
                              let value = PHAsset.Rating(rawValue: rating)
                        else { continue }
                        let request = PHAssetChangeRequest(for: asset)
                        request.rating = value
                    }
                }
                written += targets.count
            } catch {
                // Fall back to one asset at a time so a single bad asset only
                // costs itself, not the other 199 in the batch.
                for (identifier, rating) in targets {
                    guard let asset = assets[identifier],
                          let value = PHAsset.Rating(rawValue: rating)
                    else {
                        result.failed.append((names[identifier] ?? "—", "Photo is no longer in the library"))
                        entries[identifier] = nil
                        continue
                    }
                    do {
                        try await PHPhotoLibrary.shared().performChanges {
                            let request = PHAssetChangeRequest(for: asset)
                            request.rating = value
                        }
                        written += 1
                    } catch {
                        result.failed.append((names[identifier] ?? "—", error.localizedDescription))
                        // Never offer to put back a write that did not land.
                        entries[identifier] = nil
                    }
                }
            }
            await progress(written, pending.count)
        }

        // Keep only what actually landed, so a revert cannot try to undo a
        // write that never happened.
        run.entries = sortedEntries(entries)
        do {
            try UndoLog.shared.save(run)
        } catch {
            result.failed.append((filename: "—", reason: "Could not update the undo log: \(error.localizedDescription)"))
        }

        result.written = written
        result.run = run
        return result
    }

    /// Stable order, so a run on disk reads the same way twice.
    private static func sortedEntries(_ entries: [String: SyncRun.Entry]) -> [SyncRun.Entry] {
        entries.keys.sorted().compactMap { entries[$0] }
    }

    /// Puts a previous run back, restoring each photo's earlier rating.
    static func revert(
        _ run: SyncRun,
        progress: @MainActor (Int, Int) -> Void
    ) async -> Result {
        var result = Result()
        let assets = PhotosLibrary.assets(withIdentifiers: run.entries.map(\.localIdentifier))
        var restored = 0
        var processed = 0

        for batch in run.entries.chunked(into: batchSize) {
            // Worked out before the change block rather than inside it, so
            // the count reported is the photos actually changed, not every
            // entry the batch held. The old rating comes from a file on disk,
            // so it is checked rather than trusted.
            let changes: [(asset: PHAsset, rating: PHAsset.Rating)] = batch.compactMap { entry in
                guard (0...5).contains(entry.oldRating),
                      let asset = assets[entry.localIdentifier],
                      let value = PHAsset.Rating(rawValue: entry.oldRating),
                      asset.canPerform(.properties)
                else { return nil }
                return (asset, value)
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for change in changes {
                        let request = PHAssetChangeRequest(for: change.asset)
                        request.rating = change.rating
                    }
                }
                restored += changes.count
            } catch {
                result.failed.append((filename: "—", reason: error.localizedDescription))
            }
            processed += batch.count
            await progress(processed, run.entries.count)
        }

        if result.failed.isEmpty {
            UndoLog.shared.delete(run)
        }
        result.written = restored
        return result
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
