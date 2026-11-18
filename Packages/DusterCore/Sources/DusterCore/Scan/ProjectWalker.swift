import Darwin
import Foundation

struct ProjectWalker: Sendable {
    struct Artifact: Sendable {
        let url: URL
        let rule: Rule
    }

    struct Result: Sendable {
        let roots: [URL]
        var artifacts: [Artifact] = []
        var projectActivity: [String: Date] = [:]

        func activity(of artifact: Artifact) -> Date? {
            // The outermost project below the search root decides, so any edit in a repo keeps all its artifacts.
            let parent = artifact.url.deletingLastPathComponent()
            guard let root = roots.first(where: { artifact.url.isInside($0) }) else { return nil }
            var outermost = parent
            var current = parent
            while current.isInside(root) {
                if projectActivity[current.filePath] != nil { outermost = current }
                current = current.deletingLastPathComponent()
            }
            return projectActivity[outermost.filePath]
        }
    }

    private struct Tree: Sendable {
        var artifacts: [Artifact] = []
        var projects: [String: time_t] = [:]
        var newest = time_t.min
    }

    private struct Frame {
        let path: String
        var newest = time_t.min
        var hasMarker = false
    }

    private enum Decision {
        case artifact(Rule)
        case skip
        case enter
    }

    let matcher: ProjectArtifactMatcher
    private let excluded: Set<String>
    private let markerNames: Set<String>

    init(matcher: ProjectArtifactMatcher, excluded: [URL]) {
        self.matcher = matcher
        self.excluded = Set(excluded.map(\.filePath))
        markerNames = matcher.markerNames
    }

    static func searchRoots(home: URL, volumes: [Volume], scope: [URL]?) -> [URL] {
        let candidates = scope ?? [home] + volumes.filter { !$0.isBoot && !$0.isReadOnly }.map(\.url)
        let roots = Set(candidates.compactMap(FilePath.real))
        return roots.filter { root in !roots.contains { root.isInside($0) } }.sorted { $0.filePath < $1.filePath }
    }

    func walk(roots: [URL], progress: @escaping @Sendable (String) -> Void) async -> Result {
        let tops = roots.map(scanTopLevel)
        let starts = tops.flatMap(\.subtrees)
        let trees = await starts.concurrentMap { walkTree($0, progress: progress) }

        var result = Result(roots: roots)
        var newestByRoot = Dictionary(uniqueKeysWithValues: tops.map { ($0.root.filePath, $0.tree.newest) })
        for (start, tree) in zip(starts, trees) {
            let root = start.deletingLastPathComponent().filePath
            newestByRoot[root] = max(newestByRoot[root] ?? .min, tree.newest)
            result.artifacts += tree.artifacts
            for (path, newest) in tree.projects {
                result.projectActivity[path] = Self.date(newest)
            }
        }
        for top in tops {
            result.artifacts += top.tree.artifacts
            if top.hasMarker, let newest = newestByRoot[top.root.filePath] {
                result.projectActivity[top.root.filePath] = Self.date(newest)
            }
        }
        return result
    }

    private func scanTopLevel(_ root: URL) -> (root: URL, tree: Tree, hasMarker: Bool, subtrees: [URL]) {
        var tree = Tree()
        var hasMarker = false
        var subtrees: [URL] = []
        if Self.isToolchain(root) { return (root, tree, hasMarker, subtrees) }
        for child in FilePath.children(of: root) {
            guard let info = FilePath.status(child) else { continue }
            guard FilePath.isDirectory(info) else {
                if !FilePath.isSymlink(info) { tree.newest = max(tree.newest, info.st_mtimespec.tv_sec) }
                hasMarker = hasMarker || markerNames.contains(child.lastPathComponent)
                continue
            }
            switch decide(child) {
            case .artifact(let rule): tree.artifacts.append(Artifact(url: child, rule: rule))
            case .skip: continue
            case .enter: subtrees.append(child)
            }
        }
        return (root, tree, hasMarker, subtrees)
    }

    private func walkTree(_ start: URL, progress: @Sendable (String) -> Void) -> Tree {
        var tree = Tree()
        let startPath = strdup(start.filePath)
        defer { free(startPath) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [startPath, nil]
        guard let fts = fts_open(&arguments, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return tree }
        defer { fts_close(fts) }

        var frames: [Frame] = []
        var directoriesSeen = 0
        while let entry = fts_read(fts), !Task.isCancelled {
            switch Int32(entry.pointee.fts_info) {
            case FTS_D:
                let path = String(cString: entry.pointee.fts_path)
                if entry.pointee.fts_level > 0 {
                    switch decide(URL(filePath: path)) {
                    case .artifact(let rule):
                        tree.artifacts.append(Artifact(url: URL(filePath: path), rule: rule))
                        fts_set(fts, entry, FTS_SKIP)
                        continue
                    case .skip:
                        fts_set(fts, entry, FTS_SKIP)
                        continue
                    case .enter:
                        break
                    }
                }
                frames.append(Frame(path: path))
                directoriesSeen += 1
                if directoriesSeen % 500 == 0 { progress(path) }
            case FTS_DP:
                // fts also reports skipped folders and other-device mount points as FTS_DP, without a frame.
                guard frames.last?.path == String(cString: entry.pointee.fts_path), let frame = frames.popLast() else { continue }
                if frame.hasMarker { tree.projects[frame.path] = frame.newest }
                if frames.isEmpty {
                    tree.newest = frame.newest
                } else {
                    frames[frames.count - 1].newest = max(frames[frames.count - 1].newest, frame.newest)
                }
            case FTS_F, FTS_SL, FTS_SLNONE:
                guard !frames.isEmpty else { continue }
                let entryInfo = entry.pointee
                if Int32(entryInfo.fts_info) == FTS_F {
                    frames[frames.count - 1].newest = max(frames[frames.count - 1].newest, entryInfo.fts_statp.pointee.st_mtimespec.tv_sec)
                }
                let name = String(cString: entryInfo.fts_path + Int(entryInfo.fts_pathlen - entryInfo.fts_namelen))
                if markerNames.contains(name) { frames[frames.count - 1].hasMarker = true }
            case FTS_DNR, FTS_ERR:
                // Unseen files may be fresh, so an unreadable folder counts as activity now.
                guard !frames.isEmpty else { continue }
                frames[frames.count - 1].newest = time(nil)
            default:
                continue
            }
        }
        return tree
    }

    private func decide(_ directory: URL) -> Decision {
        if excluded.contains(directory.filePath) { return .skip }
        if let rule = matcher.rule(forArtifact: directory) { return .artifact(rule) }
        // Hidden folders hold tool state (.git, .gradle homes, .pub-cache, .Trashes, .claude/worktrees), not projects.
        if directory.lastPathComponent.hasPrefix(".") { return .skip }
        return Self.isToolchain(directory) ? .skip : .enter
    }

    private static func isToolchain(_ directory: URL) -> Bool {
        if directory.pathExtension == "app" { return true }
        let exists = { (path: String) in FilePath.status(directory.appending(path: path)) != nil }
        let isFlutterSDK = exists("bin/flutter") && exists("packages/flutter_tools")
        return isFlutterSDK || exists("platform-tools") || exists("build-tools")
    }

    private static func date(_ seconds: time_t) -> Date {
        seconds == .min ? .distantPast : Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}
