import Foundation

public struct UninstallScanner: Sendable {
    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    @concurrent public func scan(progress: @escaping @Sendable (String) -> Void) async -> [UninstallCandidate] {
        progress("Finding apps…")
        let apps = AppInventory(home: home).apps()
        progress("Matching leftovers…")
        let matches = LeftoverFinder(home: home).matches(for: apps)
        let sizes = SizeCalculator()
        let appCandidates = await apps.concurrentMap { app in
            progress("Measuring \(app.name)…")
            return Self.candidate(for: app, leftovers: matches.byApp[app.id] ?? [], sizes: sizes)
        }
        guard !Task.isCancelled else { return [] }
        progress("Reading Homebrew…")
        let packages = Homebrew().installed().map(Self.candidate)
        return appCandidates
            + matches.orphans.sorted { $0.totalBytes > $1.totalBytes }
            + matches.background.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            + packages
    }

    private static func candidate(for app: InstalledApp, leftovers: [FoundFile], sizes: SizeCalculator) -> UninstallCandidate {
        var seen: Set<String> = [app.url.filePath]
        let extras = leftovers.filter { seen.insert($0.id).inserted }.sorted { $0.bytes > $1.bytes }
        let lastUsed = NSMetadataItem(url: app.url)?.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date
        return UninstallCandidate(
            id: "app:\(app.id)", kind: .app, title: app.name,
            detail: [app.bundleID, app.version].compactMap { $0 }.joined(separator: " · "), bundleURL: app.url,
            note: app.isHidden ? "Hidden app in \(app.url.deletingLastPathComponent().filePath)" : nil, isHidden: app.isHidden, lastUsed: lastUsed,
            files: [FoundFile(url: app.url, match: .exact, sizes: sizes)] + extras, quitBundleIDs: app.allIDs, brewPackage: nil
        )
    }

    private static func candidate(for package: BrewPackage) -> UninstallCandidate {
        let kind = package.kind == .cask ? "Cask" : "Formula"
        let notes = [package.summary, package.isDependency ? "Installed as a dependency of another formula" : nil].compactMap { $0 }
        return UninstallCandidate(
            id: "brew:\(package.id)", kind: .homebrew, title: package.title, detail: "\(kind) · \(package.token) \(package.version)",
            bundleURL: nil, note: notes.isEmpty ? nil : notes.joined(separator: " · "), isHidden: false, lastUsed: nil, files: [],
            quitBundleIDs: [], brewPackage: package
        )
    }
}
