import AppKit
import SwiftUI

/// A file name you can select with the cursor, or copy whole from the context
/// menu.
///
/// Both, because selection on its own is not enough here. These names are
/// middle-truncated to fit the row, and dragging across truncated text selects
/// only the glyphs that were drawn — so the long names, the ones you are most
/// likely to want to paste into a search field, come out with their middle
/// missing and find nothing. The menu item copies the real string.
struct FileNameText: View {
    let name: String
    /// What Lightroom calls the same photo, where that is a different name.
    ///
    /// The row shows the name Photos uses, since that is what you see in
    /// Photos.app. For a derived match — an export filed under the raw it came
    /// from — Lightroom knows it by another name, and searching Lightroom for
    /// the Photos one finds nothing. So both are offered, and the second item
    /// only appears when there is actually a difference.
    var lightroomName: String? = nil

    var body: some View {
        Text(name)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            // The whole name, for when the row is too narrow to show it.
            .help(name)
            .contextMenu {
                Button("Copy File Name") { copy(name) }
                if let lightroomName, lightroomName != name {
                    Button("Copy Lightroom File Name") { copy(lightroomName) }
                }
            }
    }

    private func copy(_ string: String) {
        // clearContents() first: the pasteboard keeps whatever types were
        // written last, and setString alone would leave an older flavour of
        // the previous item sitting next to the new text.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
