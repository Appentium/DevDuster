import Foundation

struct RunningAppGuard: Sendable {
    private static let nameSeparators = [".", "-", " "]

    let home: URL
    let apps: [RunningApp]

    func owner(of item: ScanItem) -> RunningApp? {
        guard item.rule.skipsRunningApps, case .home(let patterns) = item.rule.target else { return nil }
        let bases = patterns.compactMap { RuleGlob(home: home, pattern: $0).base }
        guard let base = bases.first(where: { item.url.isInside($0) }) else { return nil }
        let components = item.url.realComponents.dropFirst(base.realComponents.count).map { $0.lowercased() }
        return apps.first { Self.owns($0, components) }
    }

    private static func owns(_ app: RunningApp, _ components: [String]) -> Bool {
        guard let folder = components.first else { return false }
        let name = app.name.lowercased()
        let keys = [name] + [app.bundleIdentifier?.lowercased()].compactMap { $0 }
        if keys.contains(where: { key in folder == key || nameSeparators.contains { folder.hasPrefix(key + $0) } }) { return true }
        // Vendor folders: Google/Chrome belongs to "Google Chrome", and Google alone holds it.
        let vendorPaths = components.indices.map { components[...$0].joined(separator: " ") }
        return vendorPaths.contains(name) || vendorPaths.last.map { name.hasPrefix($0 + " ") } == true
    }
}
