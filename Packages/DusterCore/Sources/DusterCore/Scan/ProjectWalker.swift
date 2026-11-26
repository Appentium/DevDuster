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
            owner(of: artifact).flatMap { projectActivity[$0] }
        }

        func owner(of artifact: Artifact) -> String? {
            // The outermost project below the search root decides, so any edit in a repo keeps all its artifacts.
            let parent = artifact.url.deletingLastPathComponent()
            guard let root = roots.first(where: { artifact.url.isInside($0) }) else { return nil }
            var outermost: String?
            var current = parent
            while current.isInside(root) {
                if projectActivity[current.filePath] != nil { outermost = current.filePath }
                current = current.deletingLastPathComponent()
            }
            return outermost
        }
    }

    fileprivate struct Tree: Sendable {
        var artifacts: [Artifact] = []
        var projects: [String: time_t] = [:]
        var newest = time_t.min
    }

    fileprivate struct Top: Sendable {
        let root: URL
        var tree = Tree()
        var hasMarker = false
        var subtrees: [URL] = []
    }

    /// Folders to walk one by one, which are also the units of scan progress.
    struct Plan: Sendable {
        fileprivate let tops: [Top]
        let units: [URL]
        fileprivate let splitArtifacts: [Artifact]
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

    init(matcher: ProjectArtifactMatcher, excluded: [URL]) {
        self.matcher = matcher
        self.excluded = Set(excluded.map(\.filePath))
    }

    static func searchRoots(home: URL, volumes: [Volume], scope: [URL]?) -> [URL] {
        let candidates = scope ?? [home] + volumes.filter { !$0.isBoot && !$0.isReadOnly }.map(\.url)
        let roots = Set(candidates.compactMap(FilePath.real))
        return roots.filter { root in !roots.contains { root.isInside($0) } }.sorted { $0.filePath < $1.filePath }
    }

    func walk(roots: [URL], progress: @escaping @Sendable (String) -> Void) async -> Result {
        await walk(roots: roots, plan: plan(roots: roots), progress: progress)
    }

    /// A folder that is not a project is split into its subfolders: no project encloses them below the root,
    /// so each one alone decides whether its artifacts are stale.
    func plan(roots: [URL], splitDepth: Int = 3) -> Plan {
        let tops = roots.map(scanTopLevel)
        var units: [URL] = []
        var artifacts: [Artifact] = []
        for start in tops.flatMap(\.subtrees) {
            split(start, depth: splitDepth - 1, units: &units, artifacts: &artifacts)
        }
        return Plan(tops: tops, units: units, splitArtifacts: artifacts)
    }

    /// Each planned folder holds its projects and every project around them, so its walk alone decides
    /// whether its artifacts are stale. onFolder gets each finished folder and its walk, on a worker task.
    func walk(
        roots: [URL],
        plan: Plan,
        progress: @escaping @Sendable (String) -> Void,
        onFolder: (@Sendable (URL, Result) -> Void)? = nil
    ) async -> Result {
        let trees = await plan.units.concurrentMap { start in
            let tree = walkTree(start, progress: progress)
            // A cut-short folder has incomplete activity, which could make an active project look stale.
            if let onFolder, !Task.isCancelled { onFolder(start, Self.result(roots: roots, tree: tree)) }
            return tree
        }

        var result = Result(roots: roots)
        result.artifacts = plan.splitArtifacts
        // Files in split folders are not counted here; only a root that is itself a project uses this, and it never owns an artifact.
        var newestByRoot = Dictionary(uniqueKeysWithValues: plan.tops.map { ($0.root.filePath, $0.tree.newest) })
        for (start, tree) in zip(plan.units, trees) {
            if let root = roots.first(where: { start.isInside($0) })?.filePath {
                newestByRoot[root] = max(newestByRoot[root] ?? .min, tree.newest)
            }
            result.artifacts += tree.artifacts
            for (path, newest) in tree.projects {
                result.projectActivity[path] = Self.date(newest)
            }
        }
        for top in plan.tops {
            result.artifacts += top.tree.artifacts
            if top.hasMarker, let newest = newestByRoot[top.root.filePath] {
                result.projectActivity[top.root.filePath] = Self.date(newest)
            }
        }
        return result
    }

    private static func result(roots: [URL], tree: Tree) -> Result {
        var result = Result(roots: roots)
        result.artifacts = tree.artifacts
        for (path, newest) in tree.projects {
            result.projectActivity[path] = date(newest)
        }
        return result
    }

    private func split(_ folder: URL, depth: Int, units: inout [URL], artifacts: inout [Artifact]) {
        guard depth > 0, let folderInfo = FilePath.status(folder), canSplit(folder) else {
            units.append(folder)
            return
        }
        for child in FilePath.children(of: folder) {
            // fts stays on one device, so a mount point inside is left out here too.
            guard let info = FilePath.status(child), FilePath.isDirectory(info), info.st_dev == folderInfo.st_dev else { continue }
            switch decide(child) {
            case .artifact(let rule): artifacts.append(Artifact(url: child, rule: rule))
            case .skip: continue
            case .enter: split(child, depth: depth - 1, units: &units, artifacts: &artifacts)
            }
        }
    }

    /// A folder no marker makes a project: none in the folder itself, and none such as
    /// ProjectSettings/ProjectVersion.txt one level down.
    private func canSplit(_ folder: URL) -> Bool {
        var subfolders: [URL] = []
        for child in FilePath.children(of: folder) {
            guard let info = FilePath.status(child) else { continue }
            if FilePath.isDirectory(info) {
                subfolders.append(child)
            } else if matcher.projectLevels(forFile: child.lastPathComponent, at: { child.filePath }).contains(0) {
                return false
            }
        }
        return !subfolders.contains { subfolder in
            FilePath.children(of: subfolder).contains { file in
                guard let info = FilePath.status(file), !FilePath.isDirectory(info) else { return false }
                return matcher.projectLevels(forFile: file.lastPathComponent, at: { file.filePath }).contains(1)
            }
        }
    }

    private func scanTopLevel(_ root: URL) -> Top {
        var top = Top(root: root)
        if Self.isToolchain(root) { return top }
        for child in FilePath.children(of: root) {
            guard let info = FilePath.status(child) else { continue }
            guard FilePath.isDirectory(info) else {
                if !FilePath.isSymlink(info) { top.tree.newest = max(top.tree.newest, info.st_mtimespec.tv_sec) }
                top.hasMarker = top.hasMarker || matcher.projectLevels(forFile: child.lastPathComponent) { child.filePath }.contains(0)
                continue
            }
            switch decide(child) {
            case .artifact(let rule): top.tree.artifacts.append(Artifact(url: child, rule: rule))
            case .skip: continue
            case .enter: top.subtrees.append(child)
            }
        }
        return top
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
                for level in matcher.projectLevels(forFile: name, at: { String(cString: entryInfo.fts_path) }) where level < frames.count {
                    frames[frames.count - 1 - level].hasMarker = true
                }
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
