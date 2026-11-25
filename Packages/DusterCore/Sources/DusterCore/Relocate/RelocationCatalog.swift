import Foundation

public struct RelocationTarget: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let platform: Rule.Platform
    public let url: URL
    public let blockedReason: String?
}

public struct RelocationCatalog: Sendable {
    static let extraTools: [DevTool] = [
        DevTool(id: "xcode.derived", title: "Xcode DerivedData", platform: .apple, roots: ["Library/Developer/Xcode/DerivedData"]),
        DevTool(id: "xcode.archives", title: "Xcode archives", platform: .apple, roots: ["Library/Developer/Xcode/Archives"]),
        DevTool(id: "xcode.devicesupport", title: "iOS device support", platform: .apple, roots: ["Library/Developer/Xcode/iOS DeviceSupport"]),
        DevTool(id: "simulators", title: "Simulator devices", platform: .apple, roots: ["Library/Developer/CoreSimulator/Devices"]),
    ]

    static let blockedReasons: [String: String] = [
        "docker": "Docker keeps its disk in a sandboxed folder. Move it in Docker Desktop: Settings > Resources > Disk image location.",
        "xcode.data": "Holds Xcode's own settings. Move DerivedData, archives, device support or simulators on their own instead.",
    ]

    private let home: URL
    private let tools: [DevTool]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, tools: DevStorageAnalyzer.builtIn + Self.extraTools)
    }

    init(home: URL, tools: [DevTool]) {
        self.home = home
        self.tools = tools
    }

    public func targets() -> [RelocationTarget] {
        let analyzer = DevStorageAnalyzer(home: home, tools: tools)
        return tools.compactMap { tool in
            analyzer.root(of: tool).map { url in
                RelocationTarget(id: tool.id, title: tool.title, platform: tool.platform, url: url, blockedReason: blockedReason(tool, url))
            }
        }
    }

    private func blockedReason(_ tool: DevTool, _ url: URL) -> String? {
        if let reason = Self.blockedReasons[tool.id] { return reason }
        guard url.isInside(home) else {
            return "Outside your home folder. DevDuster moves your tool data, never apps or system folders."
        }
        let sandboxed = ["Library/Containers", "Library/Group Containers"].map { home.appending(path: $0) }
        if sandboxed.contains(where: url.isSameOrInside) {
            return "A sandboxed app folder. macOS blocks links out of it, so the app would stop working."
        }
        return nil
    }
}
