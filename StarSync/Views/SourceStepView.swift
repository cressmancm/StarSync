import StarSyncCore
import SwiftUI

/// Step one: which Lightroom library, and which photos out of it.
struct SourceStepView: View {
    @Bindable var controller: SyncController
    @State private var search = ""

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
            HStack {
                Text("Which photos?").font(.headline)
                Spacer()
                TextField("Search albums", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List(selection: Binding(
                get: { controller.scope },
                set: { if let new = $0 { controller.scope = new } }
            )) {
                wholeCatalogRow
                if !filteredAlbums.isEmpty {
                    Section("Albums") {
                        ForEach(filteredAlbums) { album in
                            albumRow(album)
                                .tag(SyncController.Scope.album(id: album.id))
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var wholeCatalogRow: some View {
        HStack {
            Label("Entire catalog", systemImage: "square.stack.3d.up")
            Spacer()
            if let catalog = controller.catalog {
                Text("\(catalog.ratedCount.formatted()) rated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(SyncController.Scope.wholeCatalog)
    }

    private func albumRow(_ album: LRAlbum) -> some View {
        let byID = controller.catalog?.assetsByID ?? [:]
        let assets = album.assetIDs.compactMap { byID[$0] }
        let rated = assets.count(where: \.isRated)
        return HStack {
            Label {
                Text(album.name)
            } icon: {
                Image(systemName: album.kind == .project ? "rectangle.stack" : "folder")
            }
            Spacer()
            Text("\(rated.formatted()) of \(assets.count.formatted()) rated")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var filteredAlbums: [LRAlbum] {
        let albums = controller.albums
        guard !search.isEmpty else { return albums }
        return albums.filter { $0.name.localizedCaseInsensitiveContains(search) }
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
