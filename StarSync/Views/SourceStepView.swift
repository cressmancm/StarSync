import StarSyncCore
import SwiftUI

/// Step one: which Lightroom library, and which photos out of it.
struct SourceStepView: View {
    @Bindable var controller: SyncController
    @State private var search = ""
    @State private var sort: AlbumSort = .name
    @State private var showsAlbumsWithNothingToSync = false

    enum AlbumSort: String, CaseIterable, Identifiable {
        case name, mostRated
        var id: String { rawValue }
        var title: String {
            switch self {
            case .name: return "Name"
            case .mostRated: return "Most rated"
            }
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
                Picker("Sort", selection: $sort) {
                    ForEach(AlbumSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
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
                    .tag(SyncController.Scope.wholeCatalog)
                if !visibleAlbums.isEmpty {
                    Section("Albums") {
                        ForEach(visibleAlbums) { album in
                            albumRow(album)
                                .tag(SyncController.Scope.album(id: album.id))
                        }
                    }
                }
            }
            .listStyle(.inset)

            if hiddenCount > 0 {
                Divider()
                HStack(spacing: 8) {
                    Text("\(hiddenCount.formatted()) album\(hiddenCount == 1 ? "" : "s") with no rated photos hidden")
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

    private var wholeCatalogRow: some View {
        HStack {
            Label("Entire catalog", systemImage: "square.stack.3d.up")
            Spacer()
            if let catalog = controller.catalog {
                Text("\(catalog.ratedCount.formatted()) of \(catalog.assets.count.formatted()) rated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func albumRow(_ album: SyncController.AlbumRow) -> some View {
        HStack {
            Label {
                Text(album.name)
            } icon: {
                Image(systemName: album.isProject ? "rectangle.stack" : "folder")
            }
            Spacer()
            Text("\(album.ratedCount.formatted()) of \(album.photoCount.formatted()) rated")
                .font(.caption)
                .foregroundStyle(album.hasNothingToSync ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .monospacedDigit()
        }
    }

    /// Albums after the search, the nothing-to-sync filter and the sort.
    ///
    /// Half of a real catalog's albums have no rated photos in them, and they
    /// tend to be the biggest — untriaged imports. Showing them by default
    /// buries the ones worth picking.
    private var visibleAlbums: [SyncController.AlbumRow] {
        var rows = controller.albumRows
        if !search.isEmpty {
            rows = rows.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        if !showsAlbumsWithNothingToSync {
            rows = rows.filter { !$0.hasNothingToSync }
        }
        switch sort {
        case .name:
            rows.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .mostRated:
            rows.sort {
                $0.ratedCount != $1.ratedCount
                    ? $0.ratedCount > $1.ratedCount
                    : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
        return rows
    }

    /// How many the search would have matched but the filter is holding back.
    private var hiddenCount: Int {
        guard !showsAlbumsWithNothingToSync else { return 0 }
        let matching = search.isEmpty
            ? controller.albumRows
            : controller.albumRows.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return matching.count(where: \.hasNothingToSync)
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
