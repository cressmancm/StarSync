import StarSyncCore
import SwiftUI

/// Step one: which Lightroom library, and which photos out of it.
struct SourceStepView: View {
    @Bindable var controller: SyncController
    @State private var search = ""
    @State private var showsAlbumsWithNothingToSync = false
    /// Name, A to Z.
    ///
    /// Do not add `order: .forward` here, however explicit it looks: passing
    /// it sorted the table backwards and left the header's arrow on the wrong
    /// column. Leaving it off is what actually gives a forward sort matched to
    /// the Album column.
    @State private var sortOrder = [
        KeyPathComparator(\ScopeRow.name, comparator: .localizedStandard)
    ]

    /// One pickable thing: the whole catalog, or one album.
    ///
    /// Both live in the same table so the catalog can sit in it as a row
    /// rather than floating above it, and `id` is the scope itself so the
    /// table's selection is the controller's scope with nothing in between.
    struct ScopeRow: Identifiable {
        let id: SyncController.Scope
        let name: String
        let symbol: String
        let photoCount: Int
        let ratedCount: Int
        /// The catalog row keeps its place at the top whatever the sort is.
        let isPinned: Bool

        var hasNothingToSync: Bool { ratedCount == 0 }
        var ratedSummary: String {
            "\(ratedCount.formatted()) of \(photoCount.formatted()) rated"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            librarySection
            Divider()
            if controller.catalog != nil {
                scopeSection
            } else {
                Spacer()
            }
        }
    }

    // MARK: Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = controller.libraryURL {
                HStack(spacing: 10) {
                    Image(systemName: "photo.stack")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(url.lastPathComponent).font(.headline)
                        Text(summaryLine).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change…") { chooseLibrary() }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose your Lightroom library")
                        .font(.headline)
                    Text("StarSync reads your star ratings from it. The library is opened read-only — nothing in Lightroom is ever changed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Choose Lightroom Library…") { chooseLibrary() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
    }

    private var summaryLine: String {
        guard let catalog = controller.catalog else { return "Not read yet" }
        var line = "\(catalog.assets.count.formatted()) photos · \(catalog.ratedCount.formatted()) rated"
        if let photos = controller.photos {
            line += " · \(photos.photos.count.formatted()) in Photos"
        }
        return line
    }

    // MARK: Scope

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Which photos?").font(.headline)
                Spacer()
                TextField("Search albums", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Table(rows, selection: Binding(
                get: { controller.scope },
                set: { if let new = $0 { controller.scope = new } }
            ), sortOrder: $sortOrder) {
                TableColumn("Album", value: \.name, comparator: .localizedStandard) { row in
                    Label(row.name, systemImage: row.symbol)
                        .labelStyle(.titleAndIcon)
                }
                .width(min: 200, ideal: 380, max: 460)
                // Left-aligned and narrow, so the heading sits over its own
                // numbers instead of across a gap from them.
                TableColumn("Rated", value: \.ratedCount) { row in
                    Text(row.ratedSummary)
                        .foregroundStyle(row.hasNothingToSync
                                         ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 110, ideal: 150, max: 190)
            }

            if nothingToSyncCount > 0 {
                Divider()
                HStack(spacing: 8) {
                    Text(nothingToSyncSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Button(showsAlbumsWithNothingToSync ? "Hide" : "Show") {
                        showsAlbumsWithNothingToSync.toggle()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
            }
        }
    }

    /// The table's contents: the catalog first, then the albums the search
    /// and the nothing-to-sync filter leave, in whatever order the column
    /// headers ask for.
    ///
    /// Half of a real catalog's albums have no rated photos in them, and they
    /// tend to be the biggest — untriaged imports. Showing them by default
    /// buries the ones worth picking.
    private var rows: [ScopeRow] {
        guard let catalog = controller.catalog else { return [] }

        var albums = controller.albumRows
        if !search.isEmpty {
            albums = albums.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        if !showsAlbumsWithNothingToSync {
            albums = albums.filter { !$0.hasNothingToSync }
        }

        let sorted = albums.map { album in
            ScopeRow(
                id: .album(id: album.id),
                name: album.name,
                symbol: album.isProject ? "rectangle.stack" : "folder",
                photoCount: album.photoCount,
                ratedCount: album.ratedCount,
                isPinned: false
            )
        }
        .sorted(using: sortOrder)

        // Prepended after sorting, so "everything" stays reachable at the top
        // however the table is ordered.
        let wholeCatalog = ScopeRow(
            id: .wholeCatalog,
            name: "Entire catalog",
            symbol: "square.stack.3d.up",
            photoCount: catalog.assets.count,
            ratedCount: catalog.ratedCount,
            isPinned: true
        )
        return [wholeCatalog] + sorted
    }

    /// How many albums the search matches that have nothing to sync.
    ///
    /// Counted whether or not they are currently shown: the footer is the only
    /// way back to hiding them, so it has to stay on screen once they are out.
    private var nothingToSyncCount: Int {
        let matching = search.isEmpty
            ? controller.albumRows
            : controller.albumRows.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return matching.count(where: \.hasNothingToSync)
    }

    private var nothingToSyncSummary: String {
        let albums = "\(nothingToSyncCount.formatted()) album\(nothingToSyncCount == 1 ? "" : "s") with no rated photos"
        return showsAlbumsWithNothingToSync ? "Showing \(albums)" : "\(albums) hidden"
    }

    // MARK: Actions

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.message = "Choose your Lightroom library, usually “Lightroom Library.lrlibrary” in your Pictures folder."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await controller.chooseLibrary(url) }
    }
}
