import Foundation

public struct DevTool: Sendable, Hashable, Identifiable {
    public struct Essential: Sendable, Hashable {
        public let title: String
        public let path: String
    }

    public let id: String
    public let title: String
    public let platform: Rule.Platform
    public let roots: [String]
    public let essentials: [Essential]

    init(id: String, title: String, platform: Rule.Platform, roots: [String], essentials: [(String, String)] = []) {
        self.id = id
        self.title = title
        self.platform = platform
        self.roots = roots
        self.essentials = essentials.map { Essential(title: $0.0, path: $0.1) }
    }
}

public struct DevStoragePart: Sendable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case essential
        case cleanable(Tier)
        case other
    }

    public let title: String
    public let kind: Kind
    public let bytes: Int64
    public let items: [ScanItem]

    public var id: String { title }
}

public struct DevToolUsage: Sendable, Identifiable {
    public let tool: DevTool
    public let root: URL
    public let totalBytes: Int64
    public let parts: [DevStoragePart]

    public var id: String { tool.id }

    public func bytes(where matches: (DevStoragePart.Kind) -> Bool) -> Int64 {
        parts.filter { matches($0.kind) }.reduce(0) { $0 + $1.bytes }
    }
}

public struct DevStorageAnalyzer: Sendable {
    private let home: URL
    private let tools: [DevTool]
    private let includesMacPaths: Bool
    private let size: @Sendable (URL) -> Int64

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        tools: [DevTool] = DevStorageAnalyzer.builtIn,
        includesMacPaths: Bool = true,
        // A fresh calculator per folder, so a hard link seen in one folder still counts in the next.
        size: @escaping @Sendable (URL) -> Int64 = { SizeCalculator().allocatedSize(of: $0) }
    ) {
        self.home = home
        self.tools = tools
        self.includesMacPaths = includesMacPaths
        self.size = size
    }

    public var foundRoots: [URL] {
        tools.compactMap(root)
    }

    public func run(items: [ScanItem]) async -> [DevToolUsage] {
        let found = tools.compactMap { tool in root(of: tool).map { (tool, $0) } }
        let usages = await found.concurrentMap(limit: 4) { tool, root in
            usage(of: tool, root: root, items: items)
        }
        return usages.filter { $0.totalBytes > 0 }.sorted { $0.totalBytes > $1.totalBytes }
    }

    func root(of tool: DevTool) -> URL? {
        tool.roots
            .filter { includesMacPaths || !$0.hasPrefix("/") }
            .map { $0.hasPrefix("/") ? URL(filePath: $0) : home.appending(path: $0) }
            .first { FilePath.status($0).map(FilePath.isDirectory) == true }
    }

    func usage(of tool: DevTool, root: URL, items: [ScanItem]) -> DevToolUsage {
        let inside = items.filter { $0.url.isSameOrInside(root) }
        var parts = cleanableParts(inside)
        var essentialBytes: [(url: URL, bytes: Int64)] = []
        // Essentials list nested folders first, so a parent subtracts what its children already counted.
        for essential in tool.essentials {
            let url = essential.path.isEmpty ? root : root.appending(path: essential.path)
            let claimedByItems = inside.filter { $0.url.isSameOrInside(url) }.reduce(0) { $0 + $1.bytes }
            let claimedByEssentials = essentialBytes.filter { $0.url.isInside(url) }.reduce(0) { $0 + $1.bytes }
            let bytes = size(url) - claimedByItems - claimedByEssentials
            guard bytes > 0 else { continue }
            essentialBytes.append((url, bytes))
            parts.append(DevStoragePart(title: essential.title, kind: .essential, bytes: bytes, items: []))
        }
        let partsBytes = parts.reduce(0) { $0 + $1.bytes }
        let measured = size(root)
        if measured > partsBytes {
            parts.append(DevStoragePart(title: "Other files", kind: .other, bytes: measured - partsBytes, items: []))
        }
        return DevToolUsage(
            tool: tool,
            root: root,
            totalBytes: max(measured, partsBytes),
            parts: parts.sorted { $0.bytes > $1.bytes }
        )
    }

    private func cleanableParts(_ items: [ScanItem]) -> [DevStoragePart] {
        Dictionary(grouping: items, by: \.rule.id).values.compactMap { group in
            group.first.map { first in
                DevStoragePart(
                    title: first.rule.title,
                    kind: .cleanable(first.rule.tier),
                    bytes: group.reduce(0) { $0 + $1.bytes },
                    items: group
                )
            }
        }
    }
}

extension DevStorageAnalyzer {
    public static let builtIn: [DevTool] = [
        DevTool(
            id: "xcode.app", title: "Xcode", platform: .apple,
            roots: ["/Applications/Xcode.app", "/Applications/Xcode-beta.app"],
            essentials: [("Xcode app", "")]
        ),
        DevTool(
            id: "xcode.data", title: "Xcode and simulators", platform: .apple,
            roots: ["Library/Developer"],
            essentials: [("Simulator devices", "CoreSimulator/Devices"), ("Xcode settings", "Xcode/UserData")]
        ),
        DevTool(
            id: "android.sdk", title: "Android SDK", platform: .android,
            roots: ["Library/Android/sdk", "Android/sdk", "android-sdk"],
            essentials: [
                ("SDK platforms", "platforms"),
                ("System images", "system-images"),
                ("Build tools", "build-tools"),
                ("Platform tools", "platform-tools"),
                ("Command-line tools", "cmdline-tools"),
                ("NDK", "ndk"),
                ("Emulator", "emulator"),
                ("Sources", "sources"),
            ]
        ),
        DevTool(
            id: "android.studio", title: "Android Studio", platform: .android,
            roots: ["/Applications/Android Studio.app"],
            essentials: [("Android Studio app", "")]
        ),
        DevTool(id: "android.home", title: "Android emulators", platform: .android, roots: [".android"]),
        DevTool(id: "gradle", title: "Gradle", platform: .android, roots: [".gradle"]),
        DevTool(
            id: "flutter.sdk", title: "Flutter SDK", platform: .flutter,
            roots: [
                "flutter", "development/flutter", "dev/flutter", "src/flutter", "sdk/flutter", "Developer/flutter",
                "Documents/flutter",
            ],
            essentials: [("Engine and tools", "bin/cache"), ("Framework packages", "packages"), ("Other SDK files", "")]
        ),
        DevTool(
            id: "fvm", title: "Flutter versions (FVM)", platform: .flutter,
            roots: ["fvm/versions", "Library/Application Support/fvm/versions"],
            essentials: [("Installed Flutter versions", "")]
        ),
        DevTool(
            id: "pub.cache", title: "Dart pub cache", platform: .flutter,
            roots: [".pub-cache"],
            essentials: [("Global tools", "global_packages"), ("Tool launchers", "bin")]
        ),
        DevTool(
            id: "cocoapods", title: "CocoaPods", platform: .apple,
            roots: [".cocoapods"],
            essentials: [("Spec repositories", "repos")]
        ),
        DevTool(
            id: "homebrew", title: "Homebrew", platform: .devTools,
            roots: ["/opt/homebrew", "/usr/local/Homebrew"],
            essentials: [("Installed formulae", "Cellar"), ("Installed casks", "Caskroom"), ("Service data and databases", "var")]
        ),
        DevTool(
            id: "docker", title: "Docker Desktop", platform: .devTools,
            roots: ["Library/Containers/com.docker.docker"],
            essentials: [("Docker disk image", "Data/vms")]
        ),
        DevTool(id: "npm", title: "npm", platform: .javascript, roots: [".npm", "npm-cache"]),
        DevTool(id: "pnpm", title: "pnpm", platform: .javascript, roots: ["Library/pnpm"]),
        DevTool(
            id: "nvm", title: "Node versions (nvm)", platform: .javascript,
            roots: [".nvm"],
            essentials: [("Installed Node versions", "versions")]
        ),
        DevTool(
            id: "rustup", title: "Rust toolchains", platform: .rust,
            roots: [".rustup"],
            essentials: [("Toolchains", "toolchains")]
        ),
        DevTool(
            id: "cargo", title: "Cargo", platform: .rust,
            roots: [".cargo"],
            essentials: [("Installed tools", "bin")]
        ),
        DevTool(
            id: "go", title: "Go workspace", platform: .go,
            roots: ["go"],
            essentials: [("Installed tools", "bin")]
        ),
        DevTool(
            id: "pyenv", title: "Python versions (pyenv)", platform: .python,
            roots: [".pyenv"],
            essentials: [("Installed Python versions", "versions")]
        ),
        DevTool(
            id: "conda", title: "Conda", platform: .python,
            roots: ["miniconda3", "anaconda3", "miniforge3", "opt/miniconda3", "opt/anaconda3"],
            essentials: [("Environments", "envs")]
        ),
        DevTool(id: "maven", title: "Maven", platform: .jvm, roots: [".m2"]),
        DevTool(
            id: "sdkman", title: "SDKMAN", platform: .jvm,
            roots: [".sdkman"],
            essentials: [("Installed SDKs", "candidates")]
        ),
        DevTool(
            id: "jetbrains", title: "JetBrains IDEs", platform: .editors,
            roots: ["Library/Application Support/JetBrains"],
            essentials: [("Settings and plugins", "")]
        ),
        DevTool(id: "android.studio.data", title: "Android Studio settings and caches", platform: .android, roots: ["Library/Application Support/Google"]),
        DevTool(
            id: "java.jdks", title: "Java JDKs", platform: .jvm,
            roots: ["/Library/Java/JavaVirtualMachines"],
            essentials: [("Installed JDKs", "")]
        ),
        DevTool(id: "kotlin.native", title: "Kotlin/Native", platform: .jvm, roots: [".konan"]),
        DevTool(
            id: "composer", title: "Composer", platform: .php,
            roots: [".composer", ".config/composer"],
            essentials: [("Global packages", "vendor")]
        ),
        DevTool(id: "composer.cache", title: "Composer cache", platform: .php, roots: ["Library/Caches/composer", "composer-cache"]),
        DevTool(
            id: "herd", title: "Laravel Herd", platform: .php,
            roots: ["Library/Application Support/Herd"],
            essentials: [("PHP, Node and services", "bin"), ("Site settings", "config")]
        ),
        DevTool(id: "valet", title: "Laravel Valet", platform: .php, roots: [".config/valet"], essentials: [("Valet settings", "")]),
        DevTool(
            id: "xampp", title: "XAMPP", platform: .php,
            roots: ["/Applications/XAMPP"],
            essentials: [("Databases", "xamppfiles/var/mysql"), ("Web sites", "xamppfiles/htdocs"), ("Servers and PHP", "xamppfiles")]
        ),
        DevTool(
            id: "mamp", title: "MAMP", platform: .php,
            roots: ["/Applications/MAMP"],
            essentials: [("Databases", "db"), ("Web sites", "htdocs"), ("Servers and PHP", "")]
        ),
        DevTool(
            id: "postgres.app", title: "Postgres.app", platform: .devTools,
            roots: ["Library/Application Support/Postgres"],
            essentials: [("Databases", "")]
        ),
        DevTool(
            id: "dbngin", title: "DBngin", platform: .devTools,
            roots: ["Library/Application Support/com.tinyapp.DBngin"],
            essentials: [("Database engines and data", "")]
        ),
        DevTool(
            id: "rbenv", title: "Ruby versions (rbenv)", platform: .ruby,
            roots: [".rbenv"],
            essentials: [("Installed Ruby versions", "versions")]
        ),
        DevTool(
            id: "rvm", title: "Ruby versions (RVM)", platform: .ruby,
            roots: [".rvm"],
            essentials: [("Installed Ruby versions", "rubies"), ("Gem sets", "gems")]
        ),
        DevTool(id: "gems", title: "RubyGems", platform: .ruby, roots: [".gem"]),
        DevTool(id: "bundler", title: "Bundler", platform: .ruby, roots: [".bundle"]),
        DevTool(
            id: "dotnet", title: ".NET SDKs", platform: .dotnet,
            roots: [".dotnet", "/usr/local/share/dotnet"],
            essentials: [("Installed SDKs", "sdk"), ("Runtimes", "shared")]
        ),
        DevTool(id: "nuget", title: "NuGet packages", platform: .dotnet, roots: [".nuget"]),
        DevTool(
            id: "asdf", title: "asdf versions", platform: .devTools,
            roots: [".asdf"],
            essentials: [("Installed versions", "installs")]
        ),
        DevTool(
            id: "mise", title: "mise versions", platform: .devTools,
            roots: [".local/share/mise"],
            essentials: [("Installed versions", "installs")]
        ),
        DevTool(
            id: "volta", title: "Node versions (Volta)", platform: .javascript,
            roots: [".volta"],
            essentials: [("Installed tools", "tools/image")]
        ),
        DevTool(
            id: "fnm", title: "Node versions (fnm)", platform: .javascript,
            roots: [".local/share/fnm", "Library/Application Support/fnm"],
            essentials: [("Installed Node versions", "node-versions")]
        ),
        DevTool(id: "yarn", title: "Yarn", platform: .javascript, roots: ["Library/Caches/Yarn"]),
        DevTool(id: "bun", title: "Bun", platform: .javascript, roots: [".bun"], essentials: [("Bun and global tools", "bin")]),
        DevTool(id: "deno", title: "Deno", platform: .javascript, roots: ["Library/Caches/deno"]),
        DevTool(id: "playwright", title: "Playwright browsers", platform: .javascript, roots: ["Library/Caches/ms-playwright"]),
        DevTool(id: "pip", title: "pip cache", platform: .python, roots: ["Library/Caches/pip"]),
        DevTool(id: "uv", title: "uv", platform: .python, roots: [".cache/uv", ".local/share/uv"]),
        DevTool(id: "poetry", title: "Poetry", platform: .python, roots: ["Library/Caches/pypoetry"]),
        DevTool(id: "ghcup", title: "Haskell (GHCup)", platform: .otherLanguages, roots: [".ghcup"], essentials: [("Compilers and tools", "ghc")]),
        DevTool(id: "stack", title: "Haskell Stack", platform: .otherLanguages, roots: [".stack"], essentials: [("Compilers", "programs")]),
        DevTool(id: "elixir", title: "Elixir (Hex and Mix)", platform: .otherLanguages, roots: [".hex"]),
        DevTool(id: "julia", title: "Julia", platform: .otherLanguages, roots: [".julia"], essentials: [("Packages", "packages")]),
        DevTool(id: "zig", title: "Zig cache", platform: .otherLanguages, roots: [".cache/zig"]),
        DevTool(
            id: "vscode", title: "VS Code", platform: .editors,
            roots: ["Library/Application Support/Code"],
            essentials: [("Settings and workspaces", "User")]
        ),
        DevTool(id: "vscode.extensions", title: "VS Code extensions", platform: .editors, roots: [".vscode/extensions"], essentials: [("Installed extensions", "")]),
        DevTool(
            id: "cursor", title: "Cursor", platform: .editors,
            roots: ["Library/Application Support/Cursor"],
            essentials: [("Settings and workspaces", "User")]
        ),
        DevTool(id: "cursor.extensions", title: "Cursor extensions", platform: .editors, roots: [".cursor/extensions"], essentials: [("Installed extensions", "")]),
        DevTool(id: "jetbrains.caches", title: "JetBrains caches", platform: .editors, roots: ["Library/Caches/JetBrains"]),
        DevTool(
            id: "unity", title: "Unity editors", platform: .gameEngines,
            roots: ["/Applications/Unity/Hub/Editor", "/Applications/Unity"],
            essentials: [("Installed editors", "")]
        ),
        DevTool(id: "unity.data", title: "Unity caches", platform: .gameEngines, roots: ["Library/Unity"]),
        DevTool(
            id: "unreal", title: "Unreal Engine", platform: .gameEngines,
            roots: ["/Users/Shared/Epic Games"],
            essentials: [("Installed engines", "")]
        ),
        DevTool(
            id: "orbstack", title: "OrbStack", platform: .devTools,
            roots: [".orbstack"],
            essentials: [("Container and VM data", "data")]
        ),
        DevTool(id: "colima", title: "Colima", platform: .devTools, roots: [".colima"], essentials: [("VM disks", "_lima")]),
        DevTool(id: "podman", title: "Podman", platform: .devTools, roots: [".local/share/containers"], essentials: [("Machines and images", "")]),
        DevTool(id: "minikube", title: "minikube", platform: .devTools, roots: [".minikube"], essentials: [("Cluster machines", "machines")]),
        DevTool(id: "vagrant", title: "Vagrant", platform: .devTools, roots: [".vagrant.d"]),
        DevTool(id: "terraform", title: "Terraform", platform: .devTools, roots: [".terraform.d"]),
        DevTool(id: "homebrew.cache", title: "Homebrew downloads", platform: .devTools, roots: ["Library/Caches/Homebrew"]),
        DevTool(
            id: "arduino", title: "Arduino", platform: .devTools,
            roots: ["Library/Arduino15"],
            essentials: [("Boards and tools", "packages")]
        ),
        DevTool(id: "platformio", title: "PlatformIO", platform: .devTools, roots: [".platformio"], essentials: [("Platforms and toolchains", "packages")]),
        DevTool(id: "claude.code", title: "Claude Code", platform: .aiTools, roots: [".claude"], essentials: [("Settings and history", "")]),
        DevTool(id: "codex", title: "Codex", platform: .aiTools, roots: [".codex"], essentials: [("Settings and history", "")]),
        DevTool(id: "ollama", title: "Ollama", platform: .aiModels, roots: [".ollama"]),
        DevTool(id: "lmstudio", title: "LM Studio", platform: .aiModels, roots: [".lmstudio"]),
        DevTool(id: "huggingface", title: "Hugging Face", platform: .aiModels, roots: [".cache/huggingface"]),
    ]
}
