import Foundation

struct AppInventory: Sendable {
    private static let mdfind = URL(filePath: "/usr/bin/mdfind")
    private static let bundleExtensions: Set<String> = [
        "app", "framework", "bundle", "plugin", "appex", "xpc", "kext", "systemextension", "xcarchive",
    ]
    private static let excludedPrefixes = ["/System/", "/Library/Apple/", "/Library/Developer/", "/usr/", "/opt/", "/private/"]
    private static let excludedFolders: Set<String> = [
        ".Trash", ".Trashes", "DerivedData", "Build", "build", "node_modules", "Pods", ".git", "CoreSimulator", "Caches",
    ]
    private static let ownBundlePrefix = "com.appentium.devduster"

    let home: URL

    func apps() -> [InstalledApp] {
        let roots = [URL(filePath: "/Applications"), home.appending(path: "Applications")]
        let paths = roots.flatMap { applications(in: $0, depth: 0) } + spotlightApplications()
        var seen: Set<String> = []
        return paths.compactMap { url -> InstalledApp? in
            guard let real = FilePath.real(url), seen.insert(real.filePath).inserted,
                  Self.isListable(real.filePath), !isOnReadOnlyVolume(real),
                  let app = InstalledApp(url: real, isHidden: !isInApplicationsFolder(real.filePath)),
                  !app.bundleID.hasPrefix(Self.ownBundlePrefix), !(app.isHidden && app.bundleID.hasPrefix("com.apple.")) else { return nil }
            return app
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func isListable(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard path.hasSuffix(".app"), !excludedPrefixes.contains(where: path.hasPrefix) else { return false }
        if components.dropLast().contains(where: { bundleExtensions.contains(URL(filePath: $0).pathExtension) || excludedFolders.contains($0) }) {
            return false
        }
        // Other volumes hold project build outputs; only their Applications folder counts.
        if components.first == "Volumes" { return components.count == 4 && components[2] == "Applications" }
        return true
    }

    private func isInApplicationsFolder(_ path: String) -> Bool {
        ["/Applications/", home.filePath + "/Applications/"].contains(where: path.hasPrefix)
            || (path.hasPrefix("/Volumes/") && path.contains("/Applications/"))
    }

    private func applications(in folder: URL, depth: Int) -> [URL] {
        FilePath.children(of: folder).flatMap { child -> [URL] in
            if child.pathExtension == "app" { return [child] }
            guard depth < 2, let info = FilePath.status(child), FilePath.isDirectory(info) else { return [] }
            return applications(in: child, depth: depth + 1)
        }
    }

    private func spotlightApplications() -> [URL] {
        guard let output = Command.run(Self.mdfind, ["-0", "kMDItemContentType == 'com.apple.application-bundle'"], timeoutSeconds: 60) else { return [] }
        return output.split(separator: "\0").map { URL(filePath: String($0)) }
    }

    private func isOnReadOnlyVolume(_ url: URL) -> Bool {
        // Apple's own apps live on the sealed system volume, which nothing can delete from.
        (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? true
    }
}
