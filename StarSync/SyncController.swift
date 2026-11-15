import Foundation
import Observation
import Photos
import StarSyncCore

/// Drives the three steps of a sync and holds everything the views display.
@MainActor
@Observable
final class SyncController {

    enum Step: Int, CaseIterable {
        case source, preview, apply

        var title: String {
            switch self {
            case .source: return "Choose photos"
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
    var plan: SyncPlan?

    var isWorking = false
    var statusMessage = ""
    var progress: Double?
    var errorMessage: String?

    var applyResult: PhotosWriter.Result?
    var lastRun: SyncRun?
    /// Set after a successful revert, so the Done screen can report it.
    var revertedCount: Int?

    /// When the catalog file was last written, as of the read in `load()`.
    ///
    /// Compared against the file on disk before a run, so an unchanged catalog
    /// costs nothing to rule out. `CatalogReader` copies the catalog before
    /// opening it, so reading it again to find nothing is not free.
    private var catalogModified: Date?

    init() {
        libraryURL = CatalogBookmark.restore()
        lastRun = UndoLog.shared.mostRecentRun
    }

    var catalogName: String {
        libraryURL?.deletingPathExtension().lastPathComponent ?? "Lightroom"
    }

    var albums: [LRAlbum] {
        // Collections are the albums a person makes in Lightroom. The other
        // kinds are not: a `project` is an Adobe Portfolio gallery, which
        // syncs into the same catalog but is not something anyone thinks of
        // as a Lightroom album — and it duplicates the collection it was
        // published from. A `collection_set` is only a folder of collections,
        // so it holds no photos of its own.
        (catalog?.albums ?? []).filter { $0.kind == .collection }
    }

    /// One album as the chooser needs it, with its counts already worked out.
    ///
    /// The counts drive the filter and the sort as well as the label, so they
    /// are resolved once here rather than per row while the list draws.
    struct AlbumRow: Identifiable, Hashable {
        let id: String
        let name: String
        let photoCount: Int
        let ratedCount: Int

        /// Albums with nothing rated can only ever produce an empty plan.
        var hasNothingToSync: Bool { ratedCount == 0 }
    }

    var albumRows: [AlbumRow] {
        guard let catalog else { return [] }
        let byID = catalog.assetsByID
        return albums.map { album in
            let assets = album.assetIDs.compactMap { byID[$0] }
            return AlbumRow(
                id: album.id,
                name: album.name,
                photoCount: assets.count,
                ratedCount: assets.count(where: \.isRated)
            )
        }
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
            self.catalogModified = Self.catalogModificationDate(for: libraryURL)
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

    /// Matches the scoped photos against the snapshot and builds the plan.
    ///
    /// Reads nothing. Both libraries are read once, in `load()`, and the plan
    /// is drawn from that — so this is a picture of the moment the app opened,
    /// and it is allowed to be. `PhotosWriter` checks every row against both
    /// libraries immediately before writing it, which is the only check that
    /// can actually be relied on: a preview can go stale the instant after it
    /// is drawn, and a run can take minutes.
    func buildPlan() async {
        guard let photos else { return }
        isWorking = true
        statusMessage = "Matching photos…"
        defer { isWorking = false; statusMessage = "" }

        let assets = scopedAssets
        let allPhotos = photos.photos

        // Matching reads file names, dates and dimensions, never ratings, so
        // the snapshot's age cannot affect which photo is paired with which.
        let report = await Task.detached(priority: .userInitiated) {
            Matcher().match(assets: assets, photos: allPhotos)
        }.value

        let plan = await Task.detached(priority: .userInitiated) {
            SyncPlanner.plan(from: report)
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

        let lightroomRatings = await currentLightroomRatings()

        let written = plan.writes.map(\.photo.id)
        let result = await PhotosWriter.apply(
            plan: plan,
            catalogName: catalogName,
            lightroomRatings: lightroomRatings
        ) { done, total in
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

    /// What Lightroom holds right now, for checking against before writing.
    ///
    /// `nil` when the catalog file has not been written since it was read, in
    /// which case no rating in it can have changed and there is nothing to
    /// compare — so nothing is read. This is the usual case, and it matters
    /// because `CatalogReader` copies the catalog before opening it.
    ///
    /// Lightroom touches the file as it syncs, so the date can move without
    /// any rating having changed; the cost of that is one read that finds
    /// nothing, once, at the start of a run.
    private func currentLightroomRatings() async -> [String: Int]? {
        guard let libraryURL,
              let wasModified = catalogModified,
              let nowModified = Self.catalogModificationDate(for: libraryURL),
              nowModified != wasModified
        else { return nil }

        statusMessage = "Checking Lightroom…"
        guard let fresh = try? await Task.detached(priority: .userInitiated, operation: {
            try CatalogBookmark.withAccess(to: libraryURL) {
                try CatalogReader(libraryURL: libraryURL).read()
            }
        }).value else {
            // Unreadable right now — Lightroom may be mid-write. Writing is
            // still safe: every row is checked against Photos regardless, and
            // a row whose Lightroom rating moved will be caught on the next
            // run instead.
            return nil
        }

        catalog = fresh
        catalogModified = nowModified
        return fresh.assets.reduce(into: [:]) { $0[$1.id] = $1.rating }
    }

    /// When the catalog database inside the `.lrlibrary` was last written.
    private static func catalogModificationDate(for libraryURL: URL) -> Date? {
        try? CatalogBookmark.withAccess(to: libraryURL) {
            let file = try CatalogReader.locateCatalog(in: libraryURL)
            return try FileManager.default
                .attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        }
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
