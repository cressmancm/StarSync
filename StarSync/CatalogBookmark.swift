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
            // Read-only, to match the only thing StarSync ever does with the
            // library and the read-only entitlement the grant came through.
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
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
        // Refreshing a stale bookmark reads the file, which the sandbox only
        // allows while the grant is open.
        if isStale { try? withAccess(to: url) { try save(url) } }
        return url
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: Unfinished reads

    private static let readInProgressKey = "lightroomLibraryReadInProgress"

    /// Marks a catalog read as started, and makes sure the mark is on disk.
    ///
    /// The library is read again at every launch. If reading it crashes or
    /// hangs the app, that would happen on every launch, with no way left to
    /// choose a different library. The mark outlives the crash, so the next
    /// launch can tell and not read it again on its own.
    static func beginRead() {
        UserDefaults.standard.set(true, forKey: readInProgressKey)
        // Written now rather than whenever defaults next flush: a crash in
        // the read would otherwise take the mark down with it.
        UserDefaults.standard.synchronize()
    }

    /// Clears the mark once a read has returned, successfully or not.
    static func endRead() {
        UserDefaults.standard.removeObject(forKey: readInProgressKey)
    }

    /// Whether the last read never finished.
    ///
    /// Asking does not clear the mark. Clearing it here meant a library that
    /// stops the app every time alternated between a launch that crashed and
    /// a launch that said so, for as long as nobody pressed anything. It
    /// stays until a read finishes — a retry, or another library — so the
    /// app keeps opening however many times it is quit in between.
    static var hasUnfinishedRead: Bool {
        UserDefaults.standard.bool(forKey: readInProgressKey)
    }

    /// Runs `body` with the sandbox grant open, and always closes it again.
    static func withAccess<T>(to url: URL, _ body: () throws -> T) throws -> T {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}
