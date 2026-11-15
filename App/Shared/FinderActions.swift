import AppKit
import Foundation

enum FinderActions {
    @MainActor
    static func reveal(_ url: URL) {
        reveal([url])
    }

    @MainActor
    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
