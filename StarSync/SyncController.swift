import Foundation
import Observation
import Photos
import StarSyncCore

/// Drives the four steps of a sync and holds everything the views display.
@MainActor
@Observable
final class SyncController {

    enum Step: Int, CaseIterable {
        case source, mode, preview, apply

        var title: String {
            switch self {
            case .source: return "Choose photos"
            case .mode: return "Choose what to sync"
            case .preview: return "Review"
            case .apply: return "Done"
            }
        }
    }

    /// Which photos a run covers.
    enum Scope: Hashable {
        case wholeCatalog
        case album(id: String)
    }

    // MARK: Observable state

    var step: Step = .source
    var libraryURL: URL?
    var catalog: LRCatalog?
    var photos: PhotosSnapshot?
    var scope: Scope = .wholeCatalog
    var mode: SyncMode = .reviewConflicts
    var plan: SyncPlan?

    var isWorking = false
    var statusMessage = ""
    var progress: Double?
    var errorMessage: String?

    var applyResult: PhotosWriter.Result?
    var lastRun: SyncRun?
    /// Set after a successful revert, so the Done screen can report it.
    var revertedCount: Int?

    init() {
        libraryURL = CatalogBookmark.restore()
        lastRun = UndoLog.shared.mostRecentRun
    }

    var catalogName: String {
        libraryURL?.deletingPathExtension().lastPathComponent ?? "Lightroom"
    }

    var albums: [LRAlbum] {
        // Collections and projects hold photos; a collection set is only a
        // folder, so it would always come up empty.
        (catalog?.albums ?? []).filter { $0.kind == .collection || $0.kind == .project }
    }

    /// The Lightroom photos the current scope covers.
    var scopedAssets: [LRAsset] {
        guard let catalog else { return [] }
        switch scope {
        case .wholeCatalog:
            return catalog.assets
        case .album(let id):
            guard let album = catalog.albums.first(where: { $0.id == id }) else { return [] }
            let byID = catalog.assetsByID
            return album.assetIDs.compactMap { byID[$0] }
        }
    }

    var scopeDescription: String {
        switch scope {
        case .wholeCatalog:
            return "Entire catalog"
        case .album(let id):
            return catalog?.albums.first(where: { $0.id == id })?.name ?? "Album"
        }
    }

    // MARK: Loading

    /// Reads the Lightroom catalog and the Photos library.
    func load() async {
        guard let libraryURL else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            statusMessage = "Asking for access to Photos…"
            try await PhotosLibrary.requestAccess()

            statusMessage = "Reading the Lightroom catalog…"
            let catalog = try await Task.detached(priority: .userInitiated) {
                try CatalogBookmark.withAccess(to: libraryURL) {
                    try CatalogReader(libraryURL: libraryURL).read()
                }
            }.value

            statusMessage = "Reading your Photos library…"
            let photos = await Task.detached(priority: .userInitiated) {
                PhotosLibrary.fetchPhotos()
            }.value

            self.catalog = catalog
            self.photos = photos
            statusMessage = ""
        } catch {
            errorMessage = describe(error)
        }
    }

    func chooseLibrary(_ url: URL) async {
        do {
            try CatalogBookmark.save(url)
        } catch {
            errorMessage = "Could not keep access to that library: \(error.localizedDescription)"
            return
        }
        libraryURL = url
        catalog = nil
        photos = nil
        plan = nil
        await load()
    }

    // MARK: Planning

    /// Matches the scoped photos and builds the plan for the chosen mode.
    func buildPlan() async {
        guard let photos else { return }
        isWorking = true
        statusMessage = "Matching photos…"
        defer { isWorking = false; statusMessage = "" }

        let assets = scopedAssets
        let mode = mode
        let allPhotos = photos.photos

        let plan = await Task.detached(priority: .userInitiated) {
            let report = Matcher().match(assets: assets, photos: allPhotos)
            return SyncPlanner.plan(from: report, mode: mode)
        }.value

        self.plan = plan
        step = .preview
    }

    // MARK: Applying

    func apply() async {
        guard let plan else { return }
        isWorking = true
        progress = 0
        revertedCount = nil
        statusMessage = "Writing ratings…"
        defer { isWorking = false; progress = nil; statusMessage = "" }

        let written = plan.writes.map(\.photo.id)
        let result = await PhotosWriter.apply(plan: plan, catalogName: catalogName) { done, total in
            self.progress = total > 0 ? Double(done) / Double(total) : nil
            self.statusMessage = "Writing ratings… \(done) of \(total)"
        }

        applyResult = result
        lastRun = result.run ?? UndoLog.shared.mostRecentRun

        // Pick up what was actually written, so going round again compares
        // against what is really in Photos now.
        await refreshRatings(for: written)

        // Clear the working state before showing the Done screen, so Revert
        // is live and no stale progress text is left behind.
        isWorking = false
        progress = nil
        statusMessage = ""
        step = .apply
    }

    func revertLastRun() async {
        guard let run = lastRun else { return }
        isWorking = true
        progress = 0
        statusMessage = "Putting ratings back…"
        defer { isWorking = false; progress = nil; statusMessage = "" }

        let result = await PhotosWriter.revert(run) { done, total in
            self.progress = total > 0 ? Double(done) / Double(total) : nil
        }

        await refreshRatings(for: run.entries.map(\.localIdentifier))

        if result.failed.isEmpty {
            // The run has been undone and removed, so there is nothing left
            // to revert; offering it again would act on an earlier run.
            lastRun = nil
            applyResult = nil
            revertedCount = result.written
        } else {
            errorMessage = result.failed.first?.reason
        }
    }

    /// Updates the in-memory snapshot for a specific set of photos.
    ///
    /// Only these photos changed, so only these are refetched. Refetching the
    /// whole library here is what used to leave the Done screen sitting for
    /// several seconds after the ratings had already landed.
    private func refreshRatings(for identifiers: [String]) async {
        guard !identifiers.isEmpty, photos != nil else { return }
        let ratings = await Task.detached(priority: .userInitiated) {
            PhotosLibrary.ratings(for: identifiers)
        }.value
        photos?.apply(ratings: ratings)
    }

    // MARK: Navigation

    func reset() {
        plan = nil
        applyResult = nil
        revertedCount = nil
        step = .source
    }

    // MARK: Plan editing

    func setRating(_ rating: Int?, for changeID: String) {
        plan?.setRating(rating, for: changeID)
    }

    func takeAllFromLightroom() {
        plan?.resolveAllRemainingFromLightroom()
    }

    func keepAllFromPhotos() {
        plan?.keepAllRemainingFromPhotos()
    }

    private func describe(_ error: Error) -> String {
        if let local = error as? LocalizedError {
            return [local.errorDescription, local.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        return error.localizedDescription
    }
}
