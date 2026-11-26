using DevDuster.Core.Rules;

namespace DevDuster.Core.Scan;

public sealed record ProjectArtifact(string Path, Rule Rule);

public sealed class ProjectWalk(IReadOnlyList<string> roots)
{
    public List<ProjectArtifact> Artifacts { get; } = [];
    public Dictionary<string, DateTime> Activity { get; } = new(PathTools.Comparer);

    public string? OwnerOf(ProjectArtifact artifact)
    {
        // The outermost project below the search root decides, so any edit in a repo keeps all its artifacts.
        if (roots.FirstOrDefault(root => PathTools.IsInside(artifact.Path, root)) is not { } root) return null;
        string? outermost = null;
        var current = Path.GetDirectoryName(artifact.Path);
        while (current is not null && PathTools.IsInside(current, root))
        {
            if (Activity.ContainsKey(current)) outermost = current;
            current = Path.GetDirectoryName(current);
        }
        return outermost;
    }
}

public sealed class ProjectWalker(ProjectArtifactMatcher matcher, IReadOnlyList<string> excluded)
{
    private static readonly HashSet<string> InstalledFolderNames = new(
        ["Program Files", "Program Files (x86)", "WindowsApps", "XboxGames", "SteamLibrary", "steamapps", "phpMyAdmin"], PathTools.Comparer);

    private readonly HashSet<string> _excluded = new(excluded, PathTools.Comparer);

    private sealed class Frame(string path)
    {
        public string Path { get; } = path;
        public DateTime Newest { get; set; } = DateTime.MinValue;
        public bool HasMarker { get; set; }
    }

    public static IReadOnlyList<string> SearchRoots(UserFolders folders, DriveService drives, IReadOnlyList<string>? scope)
    {
        var candidates = scope ?? [folders.Home, .. drives.Drives().Where(drive => !drive.IsSystem).Select(drive => drive.Root), .. SystemDriveFolders(folders)];
        var roots = candidates.Select(PathTools.Real).OfType<string>().Distinct(PathTools.Comparer).ToList();
        return [.. roots.Where(root => !roots.Any(other => PathTools.IsInside(root, other))).Order(PathTools.Comparer)];
    }

    // Folders to walk one by one, which are also the units of progress. A folder that is not a project is split into
    // its subfolders: no project encloses them below the root, so each one alone decides whether its artifacts are stale.
    public IReadOnlyList<string> Plan(IReadOnlyList<string> roots, int splitDepth = 3) =>
        [.. roots.Where(root => !IsToolchain(root)).SelectMany(root => Subfolders(root).SelectMany(child => Split(child, splitDepth - 1)))];

    private IEnumerable<string> Split(string folder, int depth)
    {
        if (depth <= 0 || !CanSplit(folder)) return [folder];
        return Subfolders(folder).SelectMany(child => Split(child, depth - 1));
    }

    private static IEnumerable<string> Subfolders(string folder) => PathTools.Children(folder).OfType<DirectoryInfo>().Select(child => child.FullName);

    // Only a folder Visit would enter, and that no marker makes a project: a marker in the folder itself, or one such as
    // ProjectSettings/ProjectVersion.txt one level down.
    private bool CanSplit(string folder)
    {
        if (_excluded.Contains(folder) || PathTools.IsLink(folder) || PathTools.TryChildren(folder) is not { } children) return false;
        var name = Path.GetFileName(folder);
        if (IsInstalledApp(folder, children) || matcher.RuleForArtifact(folder) is not null || IsToolchain(folder)) return false;
        if (name.StartsWith('.') || name.StartsWith('$') || name == "System Volume Information") return false;
        if (children.OfType<FileInfo>().Any(file => matcher.ProjectLevels(file.FullName).Contains(0))) return false;
        return !children.OfType<DirectoryInfo>().Any(child =>
            PathTools.Children(child.FullName).OfType<FileInfo>().Any(file => matcher.ProjectLevels(file.FullName).Contains(1)));
    }

    public ProjectWalk Walk(IReadOnlyList<string> roots, Action<string> progress, CancellationToken cancellation) =>
        Walk(roots, Plan(roots), progress, cancellation);

    // Each planned folder holds its projects and every project around them, so that folder's walk alone decides
    // whether its artifacts are stale. onFolder gets each finished folder and its walk, on a worker thread.
    public ProjectWalk Walk(
        IReadOnlyList<string> roots, IReadOnlyList<string> plan, Action<string> progress, CancellationToken cancellation,
        Action<string, ProjectWalk>? onFolder = null)
    {
        var walk = new ProjectWalk(roots);
        var gate = new Lock();
        Parallel.ForEach(plan, new ParallelOptions { MaxDegreeOfParallelism = 8 }, start =>
        {
            if (cancellation.IsCancellationRequested) return;
            var frames = new List<Frame>();
            var folder = new ProjectWalk(roots);
            Visit(start, frames, folder.Artifacts, folder.Activity, progress, cancellation);
            // A cut-short folder has incomplete activity, which could make an active project look stale.
            if (cancellation.IsCancellationRequested) return;
            onFolder?.Invoke(start, folder);
            lock (gate)
            {
                walk.Artifacts.AddRange(folder.Artifacts);
                foreach (var (path, newest) in folder.Activity) walk.Activity[path] = newest;
            }
        });
        return walk;
    }

    private void Visit(
        string folder, List<Frame> frames, List<ProjectArtifact> found, Dictionary<string, DateTime> projects,
        Action<string> progress, CancellationToken cancellation)
    {
        if (cancellation.IsCancellationRequested || _excluded.Contains(folder) || PathTools.IsLink(folder)) return;
        var children = PathTools.TryChildren(folder);
        if (children is not null && IsInstalledApp(folder, children)) return;
        if (matcher.RuleForArtifact(folder) is { } rule)
        {
            found.Add(new ProjectArtifact(folder, rule));
            return;
        }
        // Dot folders hold tool state (.git, .gradle, .cache); $ folders are Windows system data.
        var name = Path.GetFileName(folder);
        if (name.StartsWith('.') || name.StartsWith('$') || name == "System Volume Information" || IsToolchain(folder)) return;

        var frame = new Frame(folder);
        frames.Add(frame);
        progress(folder);
        if (children is null)
        {
            // Unseen files may be fresh, so an unreadable folder counts as activity now.
            frame.Newest = DateTime.UtcNow;
        }
        else
        {
            foreach (var file in children.OfType<FileInfo>())
            {
                if (file.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                if (file.LastWriteTimeUtc > frame.Newest) frame.Newest = file.LastWriteTimeUtc;
                foreach (var level in matcher.ProjectLevels(file.FullName).Where(level => level < frames.Count))
                {
                    frames[^(level + 1)].HasMarker = true;
                }
            }
            foreach (var child in children.OfType<DirectoryInfo>())
            {
                Visit(child.FullName, frames, found, projects, progress, cancellation);
            }
        }
        frames.RemoveAt(frames.Count - 1);
        if (frame.HasMarker) projects[folder] = frame.Newest;
        if (frames.Count > 0 && frame.Newest > frames[^1].Newest) frames[^1].Newest = frame.Newest;
    }

    private static IEnumerable<string> SystemDriveFolders(UserFolders folders)
    {
        if (folders.SystemDrive is not { } drive) return [];
        // Developers often keep code in C:\dev or C:\src, so plain top-level folders are searched too.
        var users = Path.Combine(drive, "Users");
        return PathTools.Children(drive).OfType<DirectoryInfo>()
            .Where(folder => !folder.Attributes.HasFlag(FileAttributes.System) && !folder.Attributes.HasFlag(FileAttributes.Hidden))
            .Select(folder => folder.FullName)
            .Where(path => !PathTools.IsSame(path, users) && !folders.SystemFolders.Any(system => PathTools.IsSameOrInside(system, path)));
    }

    private static bool IsToolchain(string folder)
    {
        bool Has(params string[] parts) => PathTools.Exists(Path.Combine([folder, .. parts]));
        return Has("bin", "flutter.bat") && Has("packages", "flutter_tools") || Has("platform-tools") || Has("build-tools");
    }

    // Installed apps ship node_modules and vendor folders that nothing on this PC can rebuild.
    private static bool IsInstalledApp(string folder, IReadOnlyList<FileSystemInfo> children) =>
        InstalledFolderNames.Contains(Path.GetFileName(folder))
        || PathTools.Exists(Path.Combine(folder, "resources", "app"))
        || PathTools.Exists(Path.Combine(folder, "resources", "app.asar"))
        || children.Any(child => child is FileInfo && child.Name.StartsWith("unins", PathTools.Comparison) && child.Extension.Equals(".exe", PathTools.Comparison));
}
