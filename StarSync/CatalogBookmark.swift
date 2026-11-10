import Foundation

/// Remembers which Lightroom library the person chose.
///
/// StarSync is sandboxed, so it has no standing access to `~/Pictures`. The
/// person grants it once by picking the `.lrlibrary` in an open panel, and a
/// security-scoped bookmark keeps that grant across launches.
struct CatalogBookmark {
    private static let key = "lightroomLibraryBookmark"

    static func save(_ url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: key)
    }

    /// The remembered library, if there is one and it still exists.
    ///
    /// The caller is responsible for balancing `startAccessingSecurityScopedResource`
    /// with a matching stop; `withAccess` does that for you.
    static func restore() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        if isStale { try? save(url) }
        return url
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Runs `body` with the sandbox grant open, and always closes it again.
    static func withAccess<T>(to url: URL, _ body: () throws -> T) throws -> T {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}
