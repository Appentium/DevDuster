import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class FullDiskAccessModel {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    private static let probeFolders = ["Library/Safari", "Library/Mail", "Library/Messages"]

    private let home: URL
    private var dismissedForSession = false
    private(set) var hasAccess = true
    var isSheetPresented = false

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func check() {
        let granted = Self.probeAccess(home: home)
        hasAccess = granted
        if granted {
            isSheetPresented = false
        } else if !dismissedForSession {
            isSheetPresented = true
        }
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    func dismissForSession() {
        dismissedForSession = true
        isSheetPresented = false
    }

    private static func probeAccess(home: URL) -> Bool {
        for folder in probeFolders {
            let path = home.appending(path: folder).path(percentEncoded: false)
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: path)
                return true
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                    continue
                }
                if error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
                    continue
                }
                return false
            }
        }
        // None of the probe folders exist on this account, so do not block launch.
        return true
    }
}
