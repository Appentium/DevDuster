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

    public ProjectWalk Walk(IReadOnlyList<string> roots, Action<string> progress, CancellationToken cancellation)
    {
        var walk = new ProjectWalk(roots);
        var gate = new Lock();
        foreach (var root in roots)
        {
            if (IsToolchain(root)) continue;
            var children = PathTools.Children(root).OfType<DirectoryInfo>().ToList();
            Parallel.ForEach(children, new ParallelOptions { MaxDegreeOfParallelism = 8 }, child =>
            {
                if (cancellation.IsCancellationRequested) return;
                var frames = new List<Frame>();
                var found = new List<ProjectArtifact>();
                var projects = new Dictionary<string, DateTime>(PathTools.Comparer);
                Visit(child.FullName, frames, found, projects, progress, cancellation);
                lock (gate)
                {
                    walk.Artifacts.AddRange(found);
                    foreach (var (path, newest) in projects) walk.Activity[path] = newest;
                }
            });
        }
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
