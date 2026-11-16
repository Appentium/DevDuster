import Foundation

enum LeftoverOwner {
    case apps([Int], FoundFile.Match)
    case ambiguous
    case none
}

struct AppIndex {
    private let apps: [InstalledApp]
    private let idOwners: [String: [Int]]
    private let vendorOwners: [String: [Int]]
    private let teamOwners: [String: [Int]]
    private let nameOwners: [String: [Int]]
    private let executableOwners: [String: [Int]]

    init(apps: [InstalledApp]) {
        self.apps = apps
        func owners(_ keys: (InstalledApp) -> [String]) -> [String: [Int]] {
            var result: [String: [Int]] = [:]
            for (index, app) in apps.enumerated() {
                Set(keys(app)).forEach { result[$0, default: []].append(index) }
            }
            return result
        }
        idOwners = Self.preferringVisibleCopies(owners { $0.allIDs.map { $0.lowercased() } }, apps: apps)
        // Every Apple app shares "com.apple", so the vendor says nothing about which one owns a file.
        vendorOwners = owners { Self.vendor(of: $0.bundleID.lowercased()).flatMap { $0 == "com.apple" ? nil : [$0] } ?? [] }
        teamOwners = owners { $0.teamID.map { [$0.uppercased()] } ?? [] }
        nameOwners = Self.preferringVisibleCopies(owners { app in
            let name = Self.normalized(app.name)
            return name.count >= 3 ? [name] : []
        }, apps: apps)
        executableOwners = owners { $0.executableName.map { [$0] } ?? [] }
    }

    func owner(ofID key: String) -> LeftoverOwner {
        var candidate = key
        while true {
            if let owners = idOwners[candidate] { return owners.count == 1 ? .apps(owners, .exact) : .ambiguous }
            guard let dot = candidate.lastIndex(of: ".") else { break }
            candidate = String(candidate[..<dot])
        }
        if let vendor = Self.vendor(of: key), let owners = vendorOwners[vendor] { return .apps(owners, .sharedDeveloper) }
        return .none
    }

    func owner(ofIDPrefix prefix: String) -> LeftoverOwner {
        guard prefix.split(separator: ".").count >= 2 else { return .none }
        let owners = Set(idOwners.filter { $0.key.hasPrefix(prefix + ".") }.flatMap(\.value)).sorted()
        if owners.isEmpty { return .none }
        return .apps(owners, owners.count == 1 ? .developer : .sharedDeveloper)
    }

    func owner(ofTeamPrefixed key: String) -> LeftoverOwner {
        guard let team = Self.teamPrefix(of: key), let owners = teamOwners[team] else { return .none }
        return .apps(owners, owners.count == 1 ? .developer : .sharedDeveloper)
    }

    func owner(ofName key: String) -> LeftoverOwner {
        nameOwners[Self.normalized(key)].map { .apps($0, .name) } ?? .none
    }

    func owner(ofNameInside key: String) -> LeftoverOwner {
        let normalizedKey = Self.normalized(key)
        let owners = nameOwners.filter { $0.key.count >= 5 && normalizedKey.contains($0.key) }.flatMap(\.value)
        return owners.isEmpty ? .none : .apps(owners, .name)
    }

    func owner(ofExecutable fileName: String) -> LeftoverOwner {
        guard let end = fileName.firstIndex(where: { "-_.".contains($0) }), let owners = executableOwners[String(fileName[..<end])] else { return .none }
        return owners.count == 1 ? .apps(owners, .exact) : .ambiguous
    }

    func app(containing path: String) -> Int? {
        apps.firstIndex { path.hasPrefix($0.url.filePath + "/") }
    }

    func hasTeam(_ team: String) -> Bool {
        teamOwners[team] != nil
    }

    func hasVendor(of id: String) -> Bool {
        Self.vendor(of: id).map { vendorOwners[$0] != nil } ?? false
    }

    static func ungrouped(_ key: String) -> String {
        var id = key
        if teamPrefix(of: id) != nil, let dot = id.firstIndex(of: ".") { id = String(id[id.index(after: dot)...]) }
        for prefix in ["group.", "groups."] where id.hasPrefix(prefix) {
            return String(id.dropFirst(prefix.count))
        }
        return id
    }

    static func teamPrefix(of key: String) -> String? {
        guard let first = key.split(separator: ".").first, first.count == 10, first.allSatisfy({ $0.isLetter || $0.isNumber }),
              first.contains(where: \.isNumber) else { return nil }
        return first.uppercased()
    }

    private static func preferringVisibleCopies(_ owners: [String: [Int]], apps: [InstalledApp]) -> [String: [Int]] {
        // A second copy of an app, such as an update being unpacked, must not make its data ambiguous.
        owners.mapValues { indices in
            let visible = indices.filter { !apps[$0].isHidden }
            return visible.count == 1 ? visible : indices
        }
    }

    private static func vendor(of id: String) -> String? {
        let components = id.split(separator: ".")
        return components.count >= 3 ? components.prefix(2).joined(separator: ".") : nil
    }

    private static func normalized(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
