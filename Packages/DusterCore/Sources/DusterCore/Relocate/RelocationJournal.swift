import Foundation

public struct Relocation: Codable, Sendable, Hashable, Identifiable {
    public enum Phase: String, Codable, Sendable {
        case copying, switching, moved, copyingBack, switchingBack
    }

    public let targetID: String
    public let title: String
    public let original: URL
    public let destination: URL
    public let bytes: Int64
    public let date: Date
    public var phase: Phase

    public var id: URL { original }

    public var isDestinationConnected: Bool {
        FilePath.status(destination).map(FilePath.isDirectory) == true
    }
}

struct RelocationJournal: Sendable {
    let url: URL

    init(home: URL) {
        url = home.appending(path: "Library/Application Support/DevDuster/relocations.json")
    }

    func load() -> [Relocation] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Relocation].self, from: data)) ?? []
    }

    func save(_ relocations: [Relocation]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(relocations).write(to: url, options: .atomic)
    }

    func upsert(_ relocation: Relocation) throws {
        try save(load().filter { $0.id != relocation.id } + [relocation])
    }

    func remove(_ relocation: Relocation) throws {
        try save(load().filter { $0.id != relocation.id })
    }
}
